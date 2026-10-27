# Tests against KLayout, which serves as an independent reference: files are written by KLayout
# and read by OasisTools, or the other way round, and KLayout compares the outcome with what it
# should be. See `klayout_helper.py`. These tests only run if the environment variable
# `KLAYOUT_PYTHON` points at a Python with the `klayout` package installed.

const KLAYOUT_PYTHON = ENV["KLAYOUT_PYTHON"]
const KLAYOUT_HELPER = joinpath(@__DIR__, "klayout_helper.py")

# Runs helper commands (see `klayout_helper.py`) in a single Python process, as starting one
# takes much longer than most commands do. Returns the problems reported by each command.
function run_klayout_batch(jobs::Vector{Vector{String}})
    isempty(jobs) && return Vector{String}[]
    jobfile = tempname()
    write(jobfile, join((join(job, '\t') for job in jobs), '\n'))
    output = read(`$KLAYOUT_PYTHON -I $KLAYOUT_HELPER batch $jobfile`, String)
    problems = [String[] for _ in jobs]
    finished = 0
    for line in eachsplit(output, '\n')
        if startswith(line, "PROBLEM: ") && finished < length(jobs)
            push!(problems[finished + 1], chop(line; head = 9, tail = 0))
        elseif startswith(line, "END ")
            finished += 1
        end
    end
    finished == length(jobs) || error("The KLayout helper stopped early:\n$output")
    return problems
end

# All test layouts written by KLayout, generated in one go up front.
const KLAYOUT_OPTION_SETS = [
    String[], ["cblocks=0"], ["strict=0"], ["compression=0"], ["compression=10"],
    ["std_properties=2"]
]
const KLAYOUT_FILES = Dict(
    (case, options) => tempname() * ".oas"
    for (case, options) in vcat(
        [(case, options) for case in ("shapes", "hierarchy") for options in KLAYOUT_OPTION_SETS],
        [(case, String[]) for case in ("empty", "large", "reticle", "properties")]
    )
)
let jobs = [vcat("generate", case, path, options) for ((case, options), path) in KLAYOUT_FILES]
    problems = run_klayout_batch(jobs)
    all(isempty, problems) || error("KLayout failed to generate test layouts: $problems")
end

klayout_file(case::String, options::String...) = KLAYOUT_FILES[(case, collect(options))]

# Checks by KLayout, queued up to run together at the end, in "KLayout's verdicts". Each is a
# helper command, described by a label in case of failure.
const KLAYOUT_COMPARISONS = Tuple{String, Vector{String}}[]

queue_klayout_check(label::String, command::String...) =
    push!(KLAYOUT_COMPARISONS, (label, collect(command)))

# Queues a comparison of `candidate` with `reference`.
compare_with_klayout(label::String, reference::String, candidate::String, options::String...) =
    queue_klayout_check(label, "compare", reference, candidate, options...)

function written(oas::Oasis; compress::Bool = true)
    path = tempname() * ".oas"
    oasiswrite(path, oas; compress = compress)
    return path
end

interop_box(x0, y0, x1, y1) = Rect{2, Int64}(Point{2, Int64}(x0, y0), Point{2, Int64}(x1 - x0, y1 - y0))

# Reads `file` lazily and eagerly, writes it with and without compression, and has KLayout
# compare the outcome with `file`.
function test_round_trips(label::String, file::String)
    for lazy in (false, true), compress in (true, false)
        out = written(oasisread(file; lazy = lazy); compress = compress)
        compare_with_klayout("$label, lazy = $lazy, compress = $compress", file, out)
    end
    # An edit makes the writer decode and re-encode every cell instead of copying it.
    oas = oasisread(file; lazy = true)
    for cell in cells(oas)
        add_shape!(cell, interop_box(0, 0, 1, 1), 99, 0)
    end
    compare_with_klayout("$label, cells with edits", file, written(oas), "--ignore", "99/0")
end

@testset "KLayout reads what OasisTools writes" begin
    for case in ("shapes", "hierarchy"), options in KLAYOUT_OPTION_SETS
        test_round_trips("$case $(join(options, ' '))", klayout_file(case, options...))
    end
    test_round_trips("empty", klayout_file("empty"))
    # Copying cells with properties used to produce files that KLayout couldn't read, as the
    # properties referred to names that weren't written.
    test_round_trips("properties", klayout_file("properties"))
    # Large enough to be written in several CBLOCKs.
    file = klayout_file("large")
    compare_with_klayout("large, eager", file, written(oasisread(file)))
    compare_with_klayout("large, lazy", file, written(oasisread(file; lazy = true)))
    # Indexed cells are still copied faithfully.
    file = klayout_file("hierarchy")
    oas = oasisread(file; lazy = true)
    index!(oas)
    compare_with_klayout("hierarchy, indexed", file, written(oas))
end

@testset "Edits agree with KLayout" begin
    file = klayout_file("hierarchy")
    for lazy in (false, true)
        oas = oasisread(file; lazy = lazy)
        filter_shapes!(s -> !(s.layer == 2 && s.datatype == 0), oas)
        compare_with_klayout("Removing a layer, lazy = $lazy", file, written(oas), "--drop", "2/0")

        oas = oasisread(file; lazy = lazy)
        remove_cell!(oas, :EMPTY)
        compare_with_klayout("Removing an empty cell, lazy = $lazy", file, written(oas), "--no-structure")
    end
    # Edits to cells that aren't loaded match edits to loaded cells.
    results = map((false, true)) do lazy
        oas = oasisread(file; lazy = lazy)
        add_shape!(oas[:LEAF], interop_box(0, 0, 50, 70), 7, 0)
        add_placement!(oas[:TOP], :LEAF, Point{2, Int64}(-9000, 300); rotation = 270, flipped = true)
        remove_cell!(oas, :ONLY_PLACEMENTS)
        written(oas)
    end
    compare_with_klayout("Edits with and without loading", results...)
end

@testset "Cropping agrees with KLayout" begin
    file = klayout_file("reticle")
    windows = [
        (-10000, -10000, 200000, 200000), # Everything
        (20000, 10000, 60000, 40000),     # Across the array of dies
        (100, 100, 2500, 2500),           # Within a single die, across the array of leaves
        (29500, 1000, 31000, 22000),      # Across leaves in all eight orientations
        (33000, 500, 33600, 1300),        # Across a leaf at magnification 2
        (25000, 0, 26000, 2000),          # Across the array of vias
        (500000, 500000, 600000, 600000)  # Nothing
    ]
    for lazy in (false, true), window in windows
        cropped = crop(oasisread(file; lazy = lazy), :TOP, interop_box(window...))
        # Paths crossing the edge of the window are kept whole, so their layer is left out.
        compare_with_klayout(
            "Cropping, lazy = $lazy, window = $window", file, written(cropped),
            "--window", string.(window)..., "--ignore", "3/0", "--no-structure"
        )
    end
end

@testset "Flattening agrees with KLayout" begin
    # Flattening must leave the geometry exactly as it was, including that of cells placed at odd
    # angles, magnified, or mirrored.
    for (case, depths) in (("reticle", (1, 2, 3)), ("hierarchy", (1, 2)))
        file = klayout_file(case)
        for lazy in (false, true), depth in (depths..., typemax(Int))
            flat = flatten(oasisread(file; lazy = lazy), :TOP; depth = depth)
            compare_with_klayout(
                "Flattening $case, lazy = $lazy, depth = $depth", file, written(flat),
                "--top", "TOP", "--no-structure"
            )
        end
    end
end

@testset "Rotations in any range" begin
    # Rotations outside of [0, 360) used to corrupt the output or fail to write.
    function placed(rotation, flipped, magnification)
        oas = Oasis()
        add_cell!(oas, :TOP)
        add_cell!(oas, :SUB)
        add_shape!(oas[:SUB], Polygon(Point{2, Int64}[(0, 0), (60, 0), (60, 20), (20, 20), (20, 80), (0, 80)]), 1, 0)
        add_placement!(oas[:TOP], :SUB, Point{2, Int64}(5, 7);
            rotation = rotation, flipped = flipped, magnification = magnification)
        add_placement!(oas[:TOP], :SUB, Point{2, Int64}(500, 7);
            rotation = rotation, flipped = flipped, magnification = magnification,
            repetition = PointGridRange((0, 0), 2, 1, (200, 0), (0, 0)))
        return written(oas)
    end
    # Magnification 2 makes for the other kind of PLACEMENT record.
    for rotation in (-450, -360, -270, -180, -90, 360, 450, 540, 630, 720, 1080),
            flipped in (false, true), magnification in (1, 2)
        compare_with_klayout(
            "Rotation $rotation, flipped = $flipped, magnification = $magnification",
            placed(mod(rotation, 360), flipped, magnification),
            placed(rotation, flipped, magnification)
        )
    end
end

@testset "Finding instances agrees with KLayout" begin
    for (case, targets) in (("hierarchy", ["LEAF", "MID", "EMPTY", "ONLY_PLACEMENTS"]), ("reticle", ["LEAF", "VIA", "DIE"]))
        file = klayout_file(case)
        oas = oasisread(file; lazy = true)
        csv = tempname() * ".csv"
        open(csv, "w") do io
            for target in targets, p in find_instances(oas, Symbol(target); top = :TOP)
                println(io, join((p.cell, p.location..., mod(p.rotation, 360), p.magnification, p.flipped), ","))
            end
        end
        queue_klayout_check("Instances in $case", "check_instances", file, "TOP", csv, targets...)
    end
end

# Hand-assembled files, for records that KLayout never writes. KLayout's reading of each file is
# the reference that OasisTools' reading of it is held against.

function uint(x::Integer)
    x = UInt64(x)
    out = UInt8[]
    while true
        b = UInt8(x & 0x7f)
        x >>= 7
        iszero(x) && return push!(out, b)
        push!(out, b | 0x80)
    end
end
sint(x::Integer) = uint(x < 0 ? (UInt64(-x) << 1) | 1 : UInt64(x) << 1)
real_number(x::Real) = isinteger(x) ? (x >= 0 ? vcat(0x00, uint(Int(x))) : vcat(0x01, uint(Int(-x)))) :
    vcat(0x07, reinterpret(UInt8, [Float64(x)]))
astring(s::String) = vcat(uint(ncodeunits(s)), codeunits(s))

# Deltas, with directions 0: east, 1: north, 2: west, 3: south, 4: north-east, 5: north-west,
# 6: south-west, 7: south-east.
delta2(dir, mag) = uint((UInt64(mag) << 2) | dir)
delta3(dir, mag) = uint((UInt64(mag) << 3) | dir)
gdelta(dir::Integer, mag::Integer) = uint(((UInt64(mag) << 3) | dir) << 1) # Single-integer form
gdelta((dx, dy)) = vcat(uint((UInt64(abs(dx)) << 2) | (dx < 0 ? 0x02 : 0x00) | 0x01), sint(dy))

# Point lists.
points0(deltas...) = vcat(0x00, uint(length(deltas)), sint.(deltas)...) # Horizontal first
points1(deltas...) = vcat(0x01, uint(length(deltas)), sint.(deltas)...) # Vertical first
points2(deltas...) = vcat(0x02, uint(length(deltas)), (delta2(d...) for d in deltas)...)
points3(deltas...) = vcat(0x03, uint(length(deltas)), (delta3(d...) for d in deltas)...)
points4(deltas...) = vcat(0x04, uint(length(deltas)), (gdelta(d) for d in deltas)...)
points5(deltas...) = vcat(0x05, uint(length(deltas)), (gdelta(d) for d in deltas)...)

# Records, with every field present. Each record's info byte comes first.
rectangle_record(l, d, x, y, w, h; rep = UInt8[]) =
    vcat(0x14, 0x7b | (isempty(rep) ? 0x00 : 0x04), uint(l), uint(d), uint(w), uint(h), sint(x), sint(y), rep)
polygon_record(l, d, x, y, points) = vcat(0x15, 0x3b, uint(l), uint(d), points, sint(x), sint(y))
path_record(l, d, x, y, halfwidth, points; scheme = 0b0101, extensions = Int[]) =
    vcat(0x16, 0xfb, uint(l), uint(d), uint(halfwidth), uint(scheme), sint.(extensions)..., points, sint(x), sint(y))
circle_record(l, d, x, y, r; rep = UInt8[]) =
    vcat(0x1b, 0x3b | (isempty(rep) ? 0x00 : 0x04), uint(l), uint(d), uint(r), sint(x), sint(y), rep)
text_record(s, l, t, x, y; rep = UInt8[]) =
    vcat(0x13, 0x5b | (isempty(rep) ? 0x00 : 0x04), astring(s), uint(l), uint(t), sint(x), sint(y), rep)
placement_record(ref, x, y; quarter_turns = 0, flipped = false, rep = UInt8[]) = vcat(
    0x11, 0xf0 | (isempty(rep) ? 0x00 : 0x08) | UInt8(quarter_turns << 1) | UInt8(flipped),
    uint(ref), sint(x), sint(y), rep
)
placement_mag_angle_record(ref, x, y, magnification, angle; flipped = false) = vcat(
    0x12, 0xf6 | UInt8(flipped), uint(ref), magnification, real_number(angle), sint(x), sint(y)
)
const XYRELATIVE = UInt8[0x10]
const XYABSOLUTE = UInt8[0x0f]

# Writes a file with the given cells, numbering cell names and text strings implicitly in the
# order given.
function raw_oasis_file(cells::Pair{Symbol, Vector{UInt8}}...; textstrings::Vector{String} = String[])
    path = tempname() * ".oas"
    state = OasisTools.WriterState(path, 1 << 20)
    OasisTools.write_bytes(state, OasisTools.MAGIC_BYTES)
    OasisTools.write_start(state, 1000.0)
    for (cell_name, _) in cells
        OasisTools.write_cellname(state, cell_name)
    end
    for s in textstrings
        OasisTools.write_byte(state, 5) # TEXTSTRING
        OasisTools.write_a_string(state, s)
    end
    for (i, (_, contents)) in enumerate(cells)
        OasisTools.write_byte(state, 13) # CELL
        OasisTools.wui(state, i - 1)
        OasisTools.write_bytes(state, contents)
    end
    OasisTools.write_end(state)
    write(state.io, view(state.buf, 1:(state.pos - 1)))
    close(state.io)
    return path
end

@testset "OasisTools reads what KLayout reads" begin
    @testset "CTRAPEZOID" begin
        # Types 2, 8, 9, 11, 24 and 25 used to come out wrong.
        records = UInt8[]
        for t in 0:25
            x = 1000t
            if t in (16, 17, 18, 19, 22, 23, 25) # Height absent
                append!(records, vcat(0x1a, 0xdb, uint(1), uint(0), uint(t), uint(100), sint(x), sint(0)))
            elseif t in (20, 21) # Width absent
                append!(records, vcat(0x1a, 0xbb, uint(1), uint(0), uint(t), uint(100), sint(x), sint(0)))
            else
                w, h = 8 <= t <= 15 ? (100, 300) : (300, 100)
                append!(records, vcat(0x1a, 0xfb, uint(1), uint(0), uint(t), uint(w), uint(h), sint(x), sint(0)))
            end
            # A rectangle taking its width and height from the CTRAPEZOID's bounding box.
            append!(records, vcat(0x14, 0x18, sint(x), sint(2000)))
        end
        # Repeated, and with the type taken from the previous record.
        append!(records, vcat(0x1a, 0xff, uint(2), uint(0), uint(4), uint(300), uint(100), sint(0), sint(5000), 0x02, uint(1), uint(500)))
        append!(records, vcat(0x1a, 0x7b, uint(2), uint(0), uint(300), uint(100), sint(0), sint(6000)))
        test_round_trips("CTRAPEZOID", raw_oasis_file(:TOP => records))
    end
    @testset "TRAPEZOID" begin
        records = UInt8[]
        x = 0
        for (vertical, w, h) in ((false, 400, 200), (true, 200, 400)), (a, b) in ((50, -30), (-50, 30), (0, 70), (-60, 0))
            info = vertical ? 0xfb : 0x7b
            common = vcat(info, uint(1), uint(0), uint(w), uint(h))
            append!(records, vcat(0x17, common, sint(a), sint(b), sint(x), sint(0)))
            append!(records, vcat(0x18, common, sint(a), sint(x), sint(1000)))
            append!(records, vcat(0x19, common, sint(b), sint(x), sint(2000)))
            x += 1000
        end
        test_round_trips("TRAPEZOID", raw_oasis_file(:TOP => records))
    end
    @testset "Point lists" begin
        # Polygons with point lists of type 0 and 1 used to lose a vertex.
        records = vcat(
            polygon_record(1, 0, 0, 0, points0(600, 200, -400, 600)),
            polygon_record(1, 0, 1000, 0, points1(800, 200, -600, 400)),
            polygon_record(1, 0, 2000, 0, points0(300, 100, 300, 100, -100, 100)),
            polygon_record(1, 0, 3000, 0, points2((0, 300), (1, 200), (2, 100), (1, 100), (2, 200))),
            polygon_record(1, 0, 4000, 0, points3((0, 400), (4, 200), (1, 200), (2, 600))),
            polygon_record(1, 0, 5000, 0, points3((7, 100), (0, 300), (5, 100), (2, 200))),
            polygon_record(1, 0, 6000, 0, points4((370, 130), (80, 780), (-470, -390))),
            polygon_record(1, 0, 7000, 0, vcat(0x04, uint(3), gdelta(0, 200), gdelta(4, 100), gdelta((-150, 333)))),
            polygon_record(1, 0, 8000, 0, points5((100, 0), (0, 100), (-200, 0))),
            # A polygon reusing the previous point list.
            vcat(0x15, 0x18, sint(9000), sint(0)),
            path_record(2, 0, 0, 2000, 20, points0(500, 300, -200)),
            path_record(2, 0, 1000, 2000, 20, points1(500, 300, -200)),
            path_record(2, 0, 2000, 2000, 20, points2((0, 300), (1, 200), (2, 100))),
            path_record(2, 0, 3000, 2000, 20, points3((4, 200), (0, 100), (7, 50))),
            path_record(2, 0, 4000, 2000, 20, points4((300, 0), (0, 400))),
            path_record(2, 0, 5000, 2000, 20, points5((100, 0), (0, 100), (-100, 0)))
        )
        test_round_trips("Point lists", raw_oasis_file(:TOP => records))
    end
    @testset "Path extensions" begin
        # Explicit extensions used to be forgotten by the next path relying on them.
        route = points4((400, 0), (0, 300))
        records = vcat(
            path_record(1, 0, 0, 0, 20, route; scheme = 0b1111, extensions = [30, -10]),
            vcat(0x16, 0x7b, uint(1), uint(0), uint(20), route, sint(1000), sint(0)),  # Extensions from before
            path_record(1, 0, 2000, 0, 20, route; scheme = 0b1000),                           # Half-width start, previous end
            vcat(0x16, 0x7b, uint(1), uint(0), uint(50), route, sint(3000), sint(0)),  # Extensions from before, wider
            path_record(1, 0, 4000, 0, 20, route; scheme = 0b0110),                           # Flush start, half-width end
            path_record(1, 0, 5000, 0, 20, route; scheme = 0b1101, extensions = [-15])        # Explicit start, flush end
        )
        test_round_trips("Path extensions", raw_oasis_file(:TOP => records))
    end
    @testset "Repetitions" begin
        # A repeated CIRCLE used to throw off the parser for the rest of the file.
        repetitions = [
            vcat(0x01, uint(1), uint(0), uint(500), uint(400)),
            vcat(0x02, uint(2), uint(300)),
            vcat(0x03, uint(2), uint(300)),
            vcat(0x04, uint(2), uint(100), uint(250), uint(400)),
            vcat(0x05, uint(2), uint(10), uint(10), uint(25), uint(40)),
            vcat(0x06, uint(2), uint(100), uint(250), uint(400)),
            vcat(0x07, uint(2), uint(10), uint(10), uint(25), uint(40)),
            vcat(0x08, uint(1), uint(0), gdelta((300, 100)), gdelta((-100, 400))),
            vcat(0x09, uint(2), gdelta((200, -150))),
            vcat(0x0a, uint(2), gdelta((100, 0)), gdelta((300, 50)), gdelta((-50, 400))),
            vcat(0x0b, uint(2), uint(5), gdelta((20, 0)), gdelta((60, 10)), gdelta((-10, 80))),
            UInt8[0x00] # The previous repetition once more
        ]
        records = UInt8[]
        for (i, rep) in enumerate(repetitions)
            append!(records, rectangle_record(1, 0, 0, 3000i, 50, 30; rep = rep))
        end
        append!(records, vcat(
            # A placement using the repetition of the previous shape.
            vcat(0x11, 0xf8, uint(1), sint(50000), sint(0), 0x00),
            circle_record(2, 0, 0, -5000, 40; rep = vcat(0x02, uint(1), uint(500))),
            rectangle_record(2, 0, 0, -6000, 10, 10),
            circle_record(2, 0, 0, -7000, 25; rep = vcat(0x0a, uint(0), gdelta((90, 90)))),
            text_record("repeated", 3, 0, 100, -8000; rep = vcat(0x01, uint(0), uint(0), uint(400), uint(300))),
            placement_record(1, 60000, 0; rep = vcat(0x08, uint(0), uint(1), gdelta((300, 0)), gdelta((0, 300))))
        ))
        sub = rectangle_record(1, 0, 0, 0, 20, 20)
        test_round_trips("Repetitions", raw_oasis_file(:TOP => records, :SUB => sub))
    end
    @testset "Relative coordinates" begin
        route = points4((400, 0), (0, 300))
        records = vcat(
            XYRELATIVE,
            rectangle_record(1, 0, 100, 100, 50, 50),
            rectangle_record(1, 0, 100, 0, 50, 50),       # 100 to the right of the previous one
            vcat(0x14, 0x08, sint(200)),           # Same x, 200 up; width and height as before
            polygon_record(1, 0, 300, 300, points4((200, 0), (0, 200), (-100, 50))),
            path_record(1, 0, 500, -200, 10, route),
            text_record("relative", 2, 0, 1000, 1000),
            text_record("relative too", 2, 0, 50, 0),
            circle_record(1, 0, 400, 400, 30),
            placement_record(1, 2000, 0),
            placement_record(1, 500, 500),
            XYABSOLUTE,
            rectangle_record(1, 0, 10, 10, 5, 5)
        )
        test_round_trips("Relative coordinates", raw_oasis_file(:TOP => records, :SUB => rectangle_record(1, 0, 0, 0, 20, 20)))
    end
    @testset "Placements" begin
        # Placing an asymmetric cell reveals mistakes in its orientation.
        sub = polygon_record(1, 0, 0, 0, points0(600, 200, -400, 600))
        records = UInt8[]
        for quarter_turns in 0:3, flipped in (false, true)
            append!(records, placement_record(1, 2000quarter_turns, flipped ? 2000 : 0; quarter_turns = quarter_turns, flipped = flipped))
        end
        append!(records, vcat(
            placement_mag_angle_record(1, 0, 6000, real_number(2), 0),
            placement_mag_angle_record(1, 2000, 6000, vcat(0x02, uint(2)), 90; flipped = true), # Magnification 1/2
            placement_mag_angle_record(1, 4000, 6000, vcat(0x04, uint(3), uint(2)), -270),       # Magnification 3/2
            placement_mag_angle_record(1, 6000, 6000, real_number(1), -90),
            placement_mag_angle_record(1, 8000, 6000, real_number(1), 30; flipped = true),
            vcat(0x11, 0xb0, astring("SUB"), sint(0), sint(9000)), # Cell named explicitly
            vcat(0x11, 0x30, sint(2000), sint(9000))               # Cell taken from the previous record
        ))
        test_round_trips("Placements", raw_oasis_file(:TOP => records, :SUB => sub))
    end
    @testset "Texts" begin
        records = vcat(
            vcat(0x13, 0x7b, uint(0), uint(1), uint(0), sint(0), sint(0)),   # Reference to "alpha"
            vcat(0x13, 0x7b, uint(1), uint(1), uint(2), sint(100), sint(0)), # Reference to "beta"
            vcat(0x13, 0x18, sint(200), sint(0)),                            # "beta" once more
            text_record("explicit", 4, 0, 300, 0),
            vcat(0x13, 0x1b, uint(5), uint(1), sint(400), sint(0))           # "explicit" on another layer
        )
        test_round_trips("Texts", raw_oasis_file(:TOP => records; textstrings = ["alpha", "beta"]))
    end
end

@testset "KLayout's verdicts" begin
    problems = run_klayout_batch(last.(KLAYOUT_COMPARISONS))
    for ((label, _), found) in zip(KLAYOUT_COMPARISONS, problems)
        # Pairing the problems with the label makes failures say which comparison they're from.
        @test (label => found) == (label => String[])
    end
end
