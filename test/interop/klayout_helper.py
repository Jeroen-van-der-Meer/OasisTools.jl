"""
KLayout as an independent reference for the OasisTools test suite.

    generate CASE OUT [OPTION=VALUE ...]
        Write the test layout CASE to OUT with KLayout. Options: cblocks, strict, compression,
        std_properties (all integers).

    compare REFERENCE CANDIDATE [--window X0 Y0 X1 Y1] [--ignore L/D ...] [--drop L/D ...]
                                [--no-structure]
        Read both files with KLayout and compare them: per layer, the flattened geometry (by XOR)
        and the texts, and unless --no-structure, the cells and how often each cell places each
        other cell. With --window, REFERENCE is clipped to the window first. Layers given with
        --ignore are skipped; layers given with --drop are expected to be absent from CANDIDATE.
        Warnings from KLayout's reader count as problems.

    batch FILE
        Run the commands in FILE, one per line with tab-separated arguments, in this process.

Prints one `PROBLEM: ...` line per problem found, and `DONE` at the end.
"""

import os
import random
import sys
import tempfile

import klayout.db as db


def problem(message):
    print("PROBLEM:", message)


def read_layout(path):
    """Reads a layout, returning it along with the warnings KLayout printed while reading."""
    # KLayout prints warnings to standard output, and errors possibly to standard error.
    with tempfile.TemporaryFile() as captured:
        sys.stdout.flush()
        sys.stderr.flush()
        saved = {fd: os.dup(fd) for fd in (1, 2)}
        for fd in saved:
            os.dup2(captured.fileno(), fd)
        try:
            layout = db.Layout()
            layout.read(path)
        finally:
            for fd, original in saved.items():
                os.dup2(original, fd)
                os.close(original)
        captured.seek(0)
        output = captured.read().decode(errors="replace")
    warnings = [line for line in output.splitlines() if "Warning" in line or "Error" in line]
    return layout, warnings


def layer_key(text):
    layer, datatype = text.split("/")
    return int(layer), int(datatype)


def flattened(layout):
    """Per (layer, datatype): the flattened geometry and texts of all top cells."""
    result = {}
    for index in layout.layer_indexes():
        info = layout.get_info(index)
        region, texts = db.Region(), []
        for top in layout.top_cells():
            # Texts are compared on their own; as part of a region they'd become polygons of
            # zero area.
            shapes = top.begin_shapes_rec(index)
            shapes.shape_flags = db.Shapes.SAll & ~db.Shapes.STexts
            region += db.Region(shapes)
            texts += [(t.string, t.x, t.y) for t in db.Texts(top.begin_shapes_rec(index)).each()]
        result[(info.layer, info.datatype)] = (region, sorted(texts))
    return result


def structure(layout):
    """Per cell: how many instances of each other cell it holds, with arrays expanded."""
    result = {}
    for cell in layout.each_cell():
        counts = {}
        for inst in cell.each_inst():
            child = layout.cell(inst.cell_index).name
            counts[child] = counts.get(child, 0) + inst.cell_inst.size()
        result[cell.name] = counts
    return result


def compare(args):
    reference_path, candidate_path = args[0], args[1]
    window, ignored, dropped, check_structure = None, set(), set(), True
    rest = args[2:]
    while rest:
        flag = rest.pop(0)
        if flag == "--window":
            x0, y0, x1, y1 = (int(rest.pop(0)) for _ in range(4))
            window = db.Box(x0, y0, x1, y1)
        elif flag == "--ignore":
            ignored.add(layer_key(rest.pop(0)))
        elif flag == "--drop":
            dropped.add(layer_key(rest.pop(0)))
        elif flag == "--no-structure":
            check_structure = False
        else:
            raise ValueError(f"Unknown option {flag}")

    layouts = []
    for label, path in (("reference", reference_path), ("candidate", candidate_path)):
        try:
            layout, warnings = read_layout(path)
        except Exception as e:
            problem(f"KLayout cannot read the {label}: {e}")
            return
        for warning in warnings:
            problem(f"{label}: {warning}")
        layouts.append(layout)
    reference, candidate = layouts

    if reference.dbu != candidate.dbu:
        problem(f"Database units differ: {reference.dbu} vs {candidate.dbu}")

    ref_layers, cand_layers = flattened(reference), flattened(candidate)
    empty = (db.Region(), [])
    for key in sorted(set(ref_layers) | set(cand_layers)):
        if key in ignored:
            continue
        ref_region, ref_texts = empty if key in dropped else ref_layers.get(key, empty)
        cand_region, cand_texts = cand_layers.get(key, empty)
        if window is not None:
            ref_region = ref_region & db.Region(window)
            ref_texts = [t for t in ref_texts if window.contains(db.Point(t[1], t[2]))]
        difference = ref_region ^ cand_region
        if not difference.is_empty():
            problem(f"Layer {key[0]}/{key[1]}: geometry differs (XOR area {difference.area()}, "
                    f"reference area {ref_region.area()}, candidate area {cand_region.area()})")
        if ref_texts != cand_texts:
            missing = [t for t in ref_texts if t not in cand_texts][:3]
            extra = [t for t in cand_texts if t not in ref_texts][:3]
            problem(f"Layer {key[0]}/{key[1]}: texts differ (missing {missing}, extra {extra})")

    if check_structure:
        ref_tops = sorted(c.name for c in reference.top_cells())
        cand_tops = sorted(c.name for c in candidate.top_cells())
        if ref_tops != cand_tops:
            problem(f"Top cells differ: {ref_tops} vs {cand_tops}")
        ref_structure, cand_structure = structure(reference), structure(candidate)
        if sorted(ref_structure) != sorted(cand_structure):
            problem(f"Cells differ: {sorted(ref_structure)} vs {sorted(cand_structure)}")
        for name in sorted(set(ref_structure) & set(cand_structure)):
            if ref_structure[name] != cand_structure[name]:
                problem(f"Instances in {name} differ: {ref_structure[name]} vs {cand_structure[name]}")


# Test layouts. Coordinates are in database units of 1 nm.

def make_shapes(layout):
    """All kinds of shapes in a single cell."""
    top = layout.create_cell("TOP")
    layer = lambda l, d = 0: layout.layer(l, d)
    # The very first shape uses layer 0, datatype 0, at the origin: nothing may be left implicit.
    top.shapes(layer(0)).insert(db.Box(0, 0, 100, 100))
    top.shapes(layer(1)).insert(db.Box(-500, -300, 200, 700))
    top.shapes(layer(1, 5)).insert(db.Box(1000, 1000, 1001, 1001))
    # Extreme coordinates.
    top.shapes(layer(1)).insert(db.Box(-2**30, -2**30, -2**30 + 10, -2**30 + 10))
    top.shapes(layer(1)).insert(db.Box(2**30 - 10, 2**30 - 10, 2**30, 2**30))
    # Manhattan polygons, which KLayout writes with compact point lists.
    l_shape = [(0, 0), (600, 0), (600, 200), (200, 200), (200, 800), (0, 800)]
    u_shape = [(0, 0), (900, 0), (900, 900), (600, 900), (600, 300), (300, 300), (300, 900), (0, 900)]
    for i, points in enumerate((l_shape, u_shape)):
        polygon = db.Polygon([db.Point(x + 3000 * i, y + 5000) for x, y in points])
        top.shapes(layer(2)).insert(polygon)
    # Octangular and all-angle polygons.
    top.shapes(layer(2)).insert(db.Polygon([db.Point(x, y) for x, y in
        [(0, 0), (400, 0), (600, 200), (600, 600), (400, 800), (0, 800), (-200, 600)]]))
    top.shapes(layer(2)).insert(db.Polygon([db.Point(x, y) for x, y in
        [(10000, 0), (10370, 130), (10450, 910), (9980, 520)]]))
    top.shapes(layer(2)).insert(db.SimplePolygon([db.Point(20000, 0), db.Point(20500, 0), db.Point(20000, 700)]))
    # Paths: flush, square-ended, explicit (including negative) extensions, and round-ended.
    path = [db.Point(0, 10000), db.Point(2000, 10000), db.Point(2000, 12000)]
    shifted = lambda dy: [db.Point(p.x, p.y + dy) for p in path]
    top.shapes(layer(3)).insert(db.Path(shifted(0), 100))
    top.shapes(layer(3)).insert(db.Path(shifted(3000), 100, 50, 50))
    top.shapes(layer(3)).insert(db.Path(shifted(6000), 80, 120, -20))
    top.shapes(layer(3)).insert(db.Path(shifted(9000), 60, 0, 0, True))
    # Texts, with repeated strings and on several layers.
    for i, string in enumerate(["A", "B", "A", "longer label", "A"]):
        top.shapes(layer(10 + i % 2)).insert(db.Text(string, db.Trans(i * 700, -4000)))
    # Many identical shapes on a grid, and some at irregular offsets, which KLayout's writer
    # turns into repetitions.
    for i in range(12):
        for j in range(7):
            top.shapes(layer(4)).insert(db.Box(30000 + 250 * i, 300 * j, 30100 + 250 * i, 300 * j + 150))
    rng = random.Random(1)
    for _ in range(40):
        x, y = rng.randrange(0, 20000), rng.randrange(40000, 60000)
        top.shapes(layer(5)).insert(db.Box(x, y, x + 77, y + 33))


def make_hierarchy(layout):
    """Arrays, all orientations, magnifications and odd angles, several top cells."""
    leaf = layout.create_cell("LEAF")
    leaf.shapes(layout.layer(1, 0)).insert(db.Box(0, 0, 400, 200))
    leaf.shapes(layout.layer(2, 0)).insert(db.Polygon([db.Point(x, y) for x, y in
        [(0, 0), (300, 0), (300, 100), (100, 100), (100, 400), (0, 400)]]))
    leaf.shapes(layout.layer(10, 0)).insert(db.Text("leaf", db.Trans(50, 50)))
    empty = layout.create_cell("EMPTY")
    mid = layout.create_cell("MID")
    for i, rotation in enumerate(range(8)):
        mid.insert(db.CellInstArray(leaf.cell_index(), db.Trans(rotation % 4, rotation >= 4, db.Vector(1000 * i, 0))))
    mid.insert(db.CellInstArray(empty.cell_index(), db.Trans(db.Vector(-500, -500))))
    only_placements = layout.create_cell("ONLY_PLACEMENTS")
    only_placements.insert(db.CellInstArray(mid.cell_index(), db.Trans(db.Vector(0, 0))))
    top = layout.create_cell("TOP")
    # Regular arrays: two-dimensional, one-dimensional, and with skewed vectors.
    top.insert(db.CellInstArray(mid.cell_index(), db.Trans(), db.Vector(0, 2000), db.Vector(9000, 0), 4, 3))
    top.insert(db.CellInstArray(leaf.cell_index(), db.Trans(db.Vector(0, -3000)), db.Vector(600, 0), db.Vector(0, 0), 10, 1))
    top.insert(db.CellInstArray(leaf.cell_index(), db.Trans(1, False, db.Vector(0, -6000)), db.Vector(700, 100), db.Vector(-100, 900), 3, 4))
    # The same cell placed at irregular offsets, which KLayout's writer may turn into an
    # irregular repetition.
    for x, y in [(50000, 0), (50300, 0), (50800, 0), (51800, 0)]:
        top.insert(db.CellInstArray(leaf.cell_index(), db.Trans(db.Vector(x, y))))
    # Magnifications and an angle that isn't a multiple of 90 degrees.
    top.insert(db.CellInstArray(leaf.cell_index(), db.ICplxTrans(2.0, 0, False, 60000, 0)))
    top.insert(db.CellInstArray(leaf.cell_index(), db.ICplxTrans(0.5, 90, True, 62000, 0)))
    top.insert(db.CellInstArray(leaf.cell_index(), db.ICplxTrans(1.0, 30, False, 64000, 0)))
    top.insert(db.CellInstArray(only_placements.cell_index(), db.Trans(db.Vector(0, 20000))))
    # A second top cell.
    other = layout.create_cell("OTHER_TOP")
    other.shapes(layout.layer(1, 0)).insert(db.Box(0, 0, 10, 10))
    other.insert(db.CellInstArray(leaf.cell_index(), db.Trans(2, True, db.Vector(5, 5))))


def make_reticle(layout):
    """Dies in an array on a reticle, for cropping. Only rotations by multiples of 90 degrees."""
    leaf = layout.create_cell("LEAF")
    leaf.shapes(layout.layer(1, 0)).insert(db.Box(0, 0, 400, 200))
    leaf.shapes(layout.layer(2, 0)).insert(db.Polygon([db.Point(x, y) for x, y in
        [(0, 0), (300, 0), (300, 100), (100, 100), (100, 400), (0, 400)]]))
    leaf.shapes(layout.layer(2, 0)).insert(db.Polygon([db.Point(x, y) for x, y in
        [(500, 0), (700, 0), (900, 200), (900, 400), (500, 400)]]))
    leaf.shapes(layout.layer(3, 0)).insert(db.Path([db.Point(0, 500), db.Point(600, 500), db.Point(600, 900)], 40))
    leaf.shapes(layout.layer(10, 0)).insert(db.Text("leaf", db.Trans(50, 50)))
    via = layout.create_cell("VIA")
    via.shapes(layout.layer(2, 0)).insert(db.Box(0, 0, 50, 50))
    die = layout.create_cell("DIE")
    die.insert(db.CellInstArray(leaf.cell_index(), db.Trans(db.Vector(0, 0)), db.Vector(1000, 0), db.Vector(0, 1200), 20, 15))
    for rotation in range(8):
        die.insert(db.CellInstArray(leaf.cell_index(), db.Trans(rotation % 4, rotation >= 4, db.Vector(30000, 3000 * rotation))))
    die.insert(db.CellInstArray(leaf.cell_index(), db.ICplxTrans(2.0, 90, False, 34000, 0)))
    die.insert(db.CellInstArray(via.cell_index(), db.Trans(db.Vector(25000, 0)), db.Vector(100, 0), db.Vector(0, 100), 30, 30))
    die.shapes(layout.layer(1, 0)).insert(db.Box(-100, -100, 36000, 0))
    top = layout.create_cell("TOP")
    top.insert(db.CellInstArray(die.cell_index(), db.Trans(db.Vector(0, 0)), db.Vector(40000, 0), db.Vector(0, 25000), 3, 4))
    top.shapes(layout.layer(99, 0)).insert(db.Box(-5000, -5000, 125000, 105000))


def make_large(layout):
    """A cell too large to fit in a single CBLOCK."""
    rng = random.Random(2)
    top = layout.create_cell("TOP")
    for _ in range(200000):
        x, y = rng.randrange(0, 1000000), rng.randrange(0, 1000000)
        top.shapes(layout.layer(1, 0)).insert(db.Box(x, y, x + rng.randrange(10, 300), y + rng.randrange(10, 300)))


def make_properties(layout):
    """Properties on shapes and placements."""
    sub = layout.create_cell("SUB")
    sub.shapes(layout.layer(1, 0)).insert(db.Box(0, 0, 10, 10), layout.properties_id({"kind": "sub"}))
    top = layout.create_cell("TOP")
    top.shapes(layout.layer(1, 0)).insert(db.Box(0, 0, 100, 100), layout.properties_id({1: "net_a", "name": "label"}))
    top.shapes(layout.layer(2, 0)).insert(db.Box(200, 0, 300, 100), layout.properties_id({"kind": "via"}))
    top.insert(db.CellInstArray(sub.cell_index(), db.Trans(db.Vector(500, 0))), layout.properties_id({"instance": "X1"}))


def make_empty(layout):
    """A single cell without anything in it."""
    layout.create_cell("TOP")


CASES = {
    "shapes": make_shapes, "hierarchy": make_hierarchy, "reticle": make_reticle,
    "large": make_large, "empty": make_empty, "properties": make_properties,
}


def generate(args):
    case, out = args[0], args[1]
    options = {key: int(value) for key, value in (arg.split("=") for arg in args[2:])}
    layout = db.Layout()
    layout.dbu = 0.001
    CASES[case](layout)
    save = db.SaveLayoutOptions()
    save.format = "OASIS"
    save.oasis_write_cblocks = bool(options.get("cblocks", 1))
    save.oasis_strict_mode = bool(options.get("strict", 1))
    save.oasis_compression_level = options.get("compression", 2)
    save.oasis_write_std_properties = options.get("std_properties", 1)
    layout.write(out, save)


def check_instances(args):
    """check_instances FILE TOP CSV CELL...: compares the instances of the given cells below TOP
    listed in CSV (one `cell,x,y,rotation,magnification,flipped` row per instance, in TOP's
    coordinates) with those KLayout finds."""
    path, top, csv_path, targets = args[0], args[1], args[2], set(args[3:])
    layout, warnings = read_layout(path)
    for warning in warnings:
        problem(warning)
    expected = []

    def visit(cell, trans):
        for inst in cell.each_inst():
            child = layout.cell(inst.cell_index)
            for t in inst.cell_inst.each_cplx_trans():
                placed = trans * t
                if child.name in targets:
                    expected.append((child.name, round(placed.disp.x), round(placed.disp.y),
                                     round(placed.angle % 360, 6), round(placed.mag, 6), placed.is_mirror()))
                visit(child, placed)

    visit(layout.cell(top), db.ICplxTrans())
    found = []
    with open(csv_path) as f:
        for line in f:
            cell, x, y, rotation, magnification, flipped = line.strip().split(",")
            found.append((cell, int(x), int(y), round(float(rotation), 6), round(float(magnification), 6),
                          flipped == "true"))
    if sorted(expected) != sorted(found):
        missing = [r for r in expected if r not in found][:3]
        extra = [r for r in found if r not in expected][:3]
        problem(f"Instances differ: {len(expected)} expected, {len(found)} found; "
                f"missing {missing}, extra {extra}")


def batch(args):
    """Runs the commands in a file, one per line with tab-separated arguments, printing
    `END i` after the output of the i-th command."""
    with open(args[0]) as f:
        jobs = [line.rstrip("\n").split("\t") for line in f if line.strip()]
    for i, job in enumerate(jobs):
        try:
            COMMANDS[job[0]](job[1:])
        except Exception as e:
            problem(f"{type(e).__name__}: {e}")
        print(f"END {i}", flush=True)


COMMANDS = {"generate": generate, "compare": compare, "check_instances": check_instances, "batch": batch}


if __name__ == "__main__":
    COMMANDS[sys.argv[1]](sys.argv[2:])
    print("DONE")
