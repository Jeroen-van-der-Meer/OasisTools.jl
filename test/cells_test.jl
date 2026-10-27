box(x0, y0, x1, y1) = Rect{2, Int64}(Point{2, Int64}(x0, y0), Point{2, Int64}(x1 - x0, y1 - y0))

# Fields of a placement, with the repetition expanded, so that placements can be compared.
placement_fields(p) = (
    p.cell, p.location, p.rotation, p.magnification, p.flipped,
    isnothing(p.repetition) ? nothing : collect(p.repetition)
)

# Everything below `cell_name` as polygons in its coordinates, with all repetitions and
# placements expanded. Only handles rectangles and polygons.
function flatten(oas, cell_name, transform = nothing, out = Vector{Point{2, Int64}}[])
    transform = something(transform, CellPlacement(cell_name, Point{2, Int64}(0, 0), 0.0, 1.0, false, nothing))
    to_top(p) = OasisTools._transform_point(
        p, transform.rotation, transform.magnification, transform.flipped
    ) + transform.location
    foreach_shape(oas[cell_name]) do s
        g = s.shape
        if g isa Rect
            lo, hi = OasisTools.box_lo(g), OasisTools.box_hi(g)
            points = [lo, Point{2, Int64}(hi[1], lo[2]), hi, Point{2, Int64}(lo[1], hi[2])]
        else
            points = collect(g.exterior)
        end
        offsets = isnothing(s.repetition) ? [Point{2, Int64}(0, 0)] : collect(s.repetition)
        for o in offsets
            push!(out, [to_top(p + o) for p in points])
        end
    end
    for p in placements(oas[cell_name]), q in expand(p)
        flatten(oas, q.cell, transform * q, out)
    end
    return out
end

total_area(polygons) = sum(p -> abs(OasisTools.twice_area(p)), polygons; init = Int128(0))

# LEAF has a rectangle and a repeated L-shaped polygon. MID places LEAF in all eight
# orientations, one of them repeated. TOP places MID twice, once as an array, and has a
# rectangle of its own.
function build_layout()
    oas = Oasis()
    for cell_name in (:TOP, :MID, :LEAF)
        add_cell!(oas, cell_name)
    end
    add_shape!(oas[:LEAF], box(0, 0, 10, 4), 1, 0)
    l_shape = Polygon(Point{2, Int64}[(0, 0), (6, 0), (6, 2), (2, 2), (2, 8), (0, 8)])
    add_shape!(oas[:LEAF], l_shape, 2, 0; repetition = PointGridRange((0, 0), 3, 1, (20, 0), (0, 0)))
    i = 0
    for rotation in (0, 90, 180, 270), flipped in (false, true)
        i += 1
        repetition = i == 3 ? Point{2, Int64}[(0, 0), (0, 70), (0, 140)] : nothing
        add_placement!(
            oas[:MID], :LEAF, Point{2, Int64}(100i, 50);
            rotation = rotation, flipped = flipped, repetition = repetition
        )
    end
    add_placement!(oas[:TOP], :MID, Point{2, Int64}(0, 0))
    add_placement!(
        oas[:TOP], :MID, Point{2, Int64}(-37, 400); rotation = 90,
        repetition = PointGridRange((0, 0), 2, 2, (0, 900), (-300, 0))
    )
    add_shape!(oas[:TOP], box(-50, -50, 950, 10), 3, 0)
    add_layer!(oas, Layer(:L2, 2, 0))
    return oas
end

# The same layout, written to a file and read back without loading anything.
function lazy_layout()
    path = tempname()
    oasiswrite(path, build_layout())
    return oasisread(path; lazy = true)
end

@testset "Tiers" begin
    oas = oasisread(joinpath(@__DIR__, "testdata", "nested.oas"); lazy = true)
    cell = oas[:MIDDLE2]
    @test tier(cell) == 0
    @test sprint(show, cell) == "Cell MIDDLE2 (tier 0)"
    index!(cell)
    @test tier(cell) == 1
    @test sprint(show, cell) == "Cell MIDDLE2 with 2 placements and 0 shapes (tier 1)"
    @test isnothing(extent(cell)) # No shapes of its own
    @test tier(cell) == 2
    load!(cell)
    @test tier(cell) == 3
    @test isloaded(cell)

    # Asking for placements, shapes or layers of a cell doesn't load it.
    bottom = oas[:BOTTOM]
    @test length(shapes(bottom)) == 1
    @test length(placements(bottom)) == 0
    @test sum(c -> c.records, values(layer_counts(bottom))) == 1
    count = Ref(0)
    foreach_shape(_ -> count[] += 1, bottom)
    @test count[] == 1
    @test !isloaded(bottom)

    # Roots are found exactly, even without loading anything.
    lazy = oasisread(joinpath(@__DIR__, "testdata", "nested.oas"); lazy = true)
    @test roots(lazy) == [:TOP]
    @test !any(isloaded, cells(lazy))
end

@testset "Indexes agree with loaded cells" begin
    for filename in readdir(joinpath(@__DIR__, "testdata"))
        filepath = joinpath(@__DIR__, "testdata", filename)
        loaded = oasisread(filepath)
        lazy = oasisread(filepath; lazy = true)
        index!(lazy; extent = true)
        for cell in cells(loaded)
            other = lazy[name(cell)]
            @test tier(other) == 2
            @test placement_fields.(placements(other)) == placement_fields.(placements(cell))
            @test layer_counts(other) == layer_counts(cell)
            @test extent(other) == extent(cell)
        end
    end
end

@testset "Extents" begin
    oas = build_layout()
    @test extent(oas[:LEAF]) == box(0, 0, 46, 8)
    @test extent(oas[:TOP]) == box(-50, -50, 950, 10)
    # The hierarchical extent covers all flattened geometry, and nothing more.
    polygons = flatten(oas, :TOP)
    @test extent(oas, :TOP) == OasisTools.points_box(Iterators.flatten(polygons))
    @test extent(lazy_layout(), :TOP) == extent(oas, :TOP)
end

@testset "Edits to cells that aren't loaded" begin
    oas = lazy_layout()
    filter_shapes!(s -> s.layer != 2, oas)
    add_shape!(oas[:LEAF], box(0, 0, 1, 1), 7, 0)
    remove_cell!(oas, :MID)
    add_placement!(oas[:TOP], :LEAF, Point{2, Int64}(5, 5))
    @test !any(isloaded, cells(oas))
    # MID was removed altogether, so only the other two cells have edits.
    @test sort([(name(c), length(c.edits)) for c in cells(oas)]) == [(:LEAF, 3), (:TOP, 3)]

    # The edits show up in everything decoded from the cells…
    @test sort(collect(keys(layer_counts(oas[:LEAF])))) == [(1, 0), (7, 0)]
    @test [p.cell for p in placements(oas[:TOP])] == [:LEAF]

    # …and are carried out when writing.
    path = tempname()
    oasiswrite(path, oas)
    written = oasisread(path)
    @test cell_names(written) == [:TOP, :LEAF]
    @test sort(collect(keys(layer_counts(written[:LEAF])))) == [(1, 0), (7, 0)]
    @test [p.cell for p in placements(written[:TOP])] == [:LEAF]

    # Loading a cell applies its edits.
    load!(oas[:LEAF])
    @test isempty(oas[:LEAF].edits)
    @test length(oas[:LEAF].shapes) == 2
end

@testset "Clipping shapes" begin
    clip(shape, window) = (out = Shape[]; OasisTools.clip_shape(s -> push!(out, s), shape, window); out)
    window = box(0, 0, 10, 10)

    rect = Shape(box(5, 5, 20, 8), UInt64(1), UInt64(0), nothing)
    @test [s.shape for s in clip(rect, window)] == [box(5, 5, 10, 8)]
    @test isempty(clip(Shape(box(11, 0, 12, 1), UInt64(1), UInt64(0), nothing), window))

    # An L-shape whose corner sticks out.
    l_shape = Polygon(Point{2, Int64}[(5, 5), (15, 5), (15, 7), (7, 7), (7, 15), (5, 15)])
    clipped = only(clip(Shape(l_shape, UInt64(1), UInt64(0), nothing), window))
    @test abs(OasisTools.twice_area(clipped.shape.exterior)) == 2 * (5 * 2 + 2 * 3)

    # Repetitions are split into the instances inside, regrouped, and those crossing the edge.
    repeated = Shape(box(0, 0, 2, 2), UInt64(1), UInt64(0), PointGridRange((0, 0), 4, 1, (3, 0), (0, 0)))
    pieces = clip(repeated, box(0, 0, 10, 2))
    @test length(pieces) == 2
    @test collect(pieces[2].repetition) == Point{2, Int64}[(0, 0), (3, 0), (6, 0)]
    @test pieces[1].shape == box(9, 0, 10, 2)

    # Paths are kept whole; texts are kept if they lie inside.
    path = Shape(OasisTools.Path(Point{2, Int64}[(5, 5), (50, 5)], 2), UInt64(1), UInt64(0), nothing)
    @test clip(path, window) == [path]
    text_in = Shape(OasisTools.Text(:a, Point{2, Int64}(1, 1), nothing), UInt64(1), UInt64(0), nothing)
    text_out = Shape(OasisTools.Text(:a, Point{2, Int64}(11, 1), nothing), UInt64(1), UInt64(0), nothing)
    @test clip(text_in, window) == [text_in]
    @test isempty(clip(text_out, window))
end

@testset "Cropping" begin
    original = build_layout()
    lazy = lazy_layout()
    windows = [
        box(-1000, -1000, 3000, 3000), # Everything
        box(150, 0, 420, 140),
        box(-400, 300, 0, 1500),       # Crosses the rotated array of MID
        box(0, 0, 900, 120),
        box(5000, 5000, 6000, 6000)    # Nothing
    ]
    for window in windows
        expected = total_area(
            filter(p -> length(p) >= 3, [OasisTools.clip_polygon(p, window) for p in flatten(original, :TOP)])
        )
        cropped = crop(original, :TOP, window)
        @test total_area(flatten(cropped, :TOP)) == expected
        @test roots(cropped) == [:TOP]
        cropped_extent = extent(cropped, :TOP)
        @test isnothing(cropped_extent) || OasisTools.contains_box(window, cropped_extent)

        # Cropping cells that aren't loaded only records what to clip, until they're written.
        cropped_lazy = crop(lazy, :TOP, window)
        @test !any(isloaded, cells(cropped_lazy))
        path = tempname()
        oasiswrite(path, cropped_lazy)
        @test total_area(flatten(oasisread(path), :TOP)) == expected
    end
    # The original layout is left untouched.
    @test total_area(flatten(original, :TOP)) == total_area(flatten(build_layout(), :TOP))
    @test cell_names(crop(original, :TOP, box(-1000, -1000, 3000, 3000))) == [:LEAF, :MID, :TOP]
end
