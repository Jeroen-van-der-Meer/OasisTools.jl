function parse_cell_bytes(bytes)
    state = CellParserState(bytes)
    nbytes = length(bytes)
    while state.pos <= nbytes
        record_type = OasisTools.read_byte(state)
        OasisTools.read_record(record_type, state)
    end
    return state
end

@testset "Parse OASIS files" begin
    @testset "Polygon" begin
        # Contains: Polygon with four vertices.
        filename = "polygon.oas" # 130.900 μs (86 allocations: 4.84 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 1
        @test cell_names(oas) == [:TOP]
        top_cell = oas[:TOP]
        @test top_cell.name == :TOP
        subcells = placements(top_cell)
        @test isempty(subcells)
        shps = shapes(top_cell)
        @test length(shps) == 1
        polygon = shps[1].shape
        @test polygon isa Polygon
        @test polygon.exterior == [
            Point{2, Int64}(-1000, -1000), Point{2, Int64}(-1000, 0),
            Point{2, Int64}(0, 1000), Point{2, Int64}(0, 0)
        ]
    end
    @testset "Boxes" begin
        # Contains: Two layers, cell placement with repetition, rectangles.
        filename = "boxes.oas" # 146.900 μs (146 allocations: 149.76 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 2
        bottom_cell = oas[:BOTTOM]
        @test bottom_cell.name == :BOTTOM
        @test length(bottom_cell.shapes) == 1
        rectangle = bottom_cell.shapes[1]
        lyr = layer(oas, rectangle)
        layername = lyr.name
        @test layername == :TOP
        rectangle_shape = rectangle.shape
        @test rectangle_shape isa Rect{2, Int64}
        @test rectangle_shape == Rect{2, Int64}(
            Point{2, Int64}(-190, 2870),
            Point{2, Int64}(10, 10)
        )
        @test roots(oas) == [:TOP]
        top_cell = oas[:TOP]
        @test top_cell.name == :TOP
        top_shape = shapes(top_cell)[1]
        @test top_shape isa Shape{Rect{2, Int64}}
        s = Suppressor.@capture_out Base.show(top_shape)
        # Note that the coordinates do not account for the repetition.
        @test s == "Rectangle in layer (1/1) at (-160, -710) (4×)"
        p = placements(top_cell)
        @test length(p) == 2
        # There are two placements in the top cell rather than one. Underneath the 6x5 grid of
        # rectangles, there's another rectangle.
        bottom_cell_placement = p[1]
        s = Suppressor.@capture_out Base.show(bottom_cell_placement)
        @test s == "Placement of cell BOTTOM at (-520, 2200) (30×)"
        @test bottom_cell_placement.location == Point{2, Int64}(-520, 2200)
        # FIXME: Check the placement is correct, esp. the rotation
        @test bottom_cell_placement.rotation == 180
        @test bottom_cell_placement.repetition == PointGridRange((0, 0), 6, 5, (0, 30), (50, -30))
    end
    @testset "Circle" begin
        # Contains: Circle (which klayout doesn't save as a circle), text.
        filename = "circle.oas" # 156.600 μs (169 allocations: 223.48 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 2
        circle_cell = oas["CIRCLE\$1"]
        circle = circle_cell.shapes[1]
        @test circle isa Shape{Polygon{2, Int64}}
        text_cell = oas["TOP"]
        text = text_cell.shapes[1]
        text_string = text.shape.text
        @test text_string == Symbol("This is not a circle")
    end
    @testset "Paths" begin
        # Contains: Some paths. It includes one with rounded ends. Weirdly enough, klayout
        # chooses to save these ends as CIRCLE records, unlike actual circles.
        filename = "paths.oas" # 143.800 μs (120 allocations: 77.43 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 1
        top_cell = oas["TOP"]
        nplacement = length(top_cell.placements)
        @test nplacement == 0
        # Shapes are stored grouped by kind, so reach for the groups rather than an index.
        paths = [s.shape for s in top_cell.shapes.paths]
        circles = [s.shape for s in top_cell.shapes.circles]
        @test length(top_cell.shapes) == 6 # Four paths and two circles for the rounded path
        @test length(paths) == 4
        @test length(circles) == 2
        path_1 = paths[1]
        @test path_1.points == Point{2, Int64}[(-508, 268), (-253, 22), (-342, 190), (-157, 176)]
        @test path_1.width == 100
        path_2 = paths[2]
        @test path_2.points == Point{2, Int64}[(-263, 431), (-116, 420), (-228, 315), (-182, 482)]
        @test path_2.width == 50
        # Third path is a rounded path which klayout saves using CIRCLE records at both ends.
        path_3 = paths[3]
        @test path_3.points == Point{2, Int64}[(-343, 273), (-386, 294), (-351, 303)]
        @test path_3.width == 10
        start_circle = circles[1]
        @test start_circle.center == Point{2, Int64}(-343, 273)
        @test start_circle.r == 5
        end_circle = circles[2]
        @test end_circle.center == Point{2, Int64}(-351, 303)
        @test end_circle.r == 5
        # Fourth path is subject to change; due to the nonzero starting offset, its starting
        # point is actually a fraction of the database unit. As it stands, a rounding takes
        # place.
        path_4 = paths[4]
        @test path_4.points == Point{2, Int64}[(-257, 236), (-255, 238), (-254, 237)]
        @test path_4.width == 2
    end
    @testset "Nested" begin
        # Contains: A bunch of cells with random shapes nested in each other with varying
        # rotations and magnifications.
        filename = "nested.oas" # 161.300 μs (232 allocations: 225.47 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        s = Suppressor.@capture_out Base.show(oas)
        @test s == """
OASIS file with the following cell hierarchy:
TOP
├─ BOTTOM2
│  └─ ROCKBOTTOM
├─ MIDDLE
│  ├─ BOTTOM2
│  │  └─ ⋯
│  └─ BOTTOM
└─ MIDDLE2
   └─ BOTTOM"""
        s = Suppressor.@capture_out Base.show(oas["ROCKBOTTOM"].shapes[1])
        @test s == "Polygon in layer (1/0) at (1, 0)"
        s = Suppressor.@capture_out Base.show(oas["BOTTOM2"].placements[1])
        @test s == "Placement of cell ROCKBOTTOM at (1, 0)"
        s = Suppressor.@capture_out Base.show(oas["MIDDLE2"].placements[1])
        @test s == "Placement of cell BOTTOM at (-5, -3) (2×)"
        bottom = oas["BOTTOM"]
        @test length(bottom.shapes) == 1
        bottom2 = oas["BOTTOM2"]
        @test length(bottom2.placements) == 1
        @test length(bottom2.shapes) == 1
        placement = bottom2.placements[1]
        @test placement.rotation == 90
        @test placement.magnification == 0.5
        @test placement.location == Point{2, Int64}(1, 0)
        shape = bottom2.shapes[1].shape
        @test shape == Rect{2, Int64}([0, 0], [1, 1])
        middle2 = oas["MIDDLE2"]
        @test length(middle2.placements) == 2
        placement1 = middle2.placements[1]
        @test placement1.location == Point{2, Int64}(-5, -3)
        @test placement1.magnification == 1
        @test placement1.rotation == 0
        @test placement1.repetition == Point{2, Int64}[(0, 0), (2, 0)]
        placement2 = middle2.placements[2]
        @test placement2.location == Point{2, Int64}(-3, -1)
        @test placement2.magnification == 2
        @test placement2.rotation == 180
        @test placement2.repetition == Point{2, Int64}[(0, 0), (2, 0), (4, 0)]
    end
    @testset "Trapezoids" begin
        # Contains: Trapezoids and ctrapezoids. Made with LayoutEditor because klayout doesn't
        # use TRAPEZOID and CTRAPEZOID records.
        # Some interesting quirks specific to LayoutEditor's way of saving files:
        #  - It does not seem to use references for strings (at least not when used only once).
        #  - It contains the following stingy message, which they actually insert into the layout:
        #    "Generated with the LayoutEditor (This message will NOT be added by any commercial
        #     version of the LayoutEditor.)"
        #    Surely they know you can just manually delete the text record from the file...?
        filename = "trapezoids.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        cell = oas["noname"] # This is what LayoutEditor calls your cell if you don't name it.
        @test length(cell.shapes) == 7 # Six polygons and the free-version disclaimer.
        @test length(cell.shapes.texts) == 1
        polys = cell.shapes.polygons
        @test length(polys) == 6
        polygon1 = polys[1]
        @test polygon1.shape.exterior == [
            Point{2, Int64}(28810, -17702), Point{2, Int64}(28813, -17703),
            Point{2, Int64}(28813, -17698), Point{2, Int64}(28810, -17696)
        ]
        polygon2 = polys[2]
        @test polygon2.shape.exterior == [
            Point{2, Int64}(28796, -17701), Point{2, Int64}(28796, -17705),
            Point{2, Int64}(28800, -17705), Point{2, Int64}(28803, -17701)
        ]
        polygon3 = polys[3]
        @test polygon3.shape.exterior == [
            Point{2, Int64}(28805, -17705), Point{2, Int64}(28807, -17703),
            Point{2, Int64}(28807, -17698), Point{2, Int64}(28805, -17700)
        ]
        polygon4 = polys[4]
        @test polygon4.shape.exterior == [
            Point{2, Int64}(28800, -17707), Point{2, Int64}(28799, -17710),
            Point{2, Int64}(28806, -17710), Point{2, Int64}(28805, -17707)
        ]
        polygon5 = polys[5]
        @test polygon5.shape.exterior == [
            Point{2, Int64}(28809, -17704), Point{2, Int64}(28810, -17706),
            Point{2, Int64}(28814, -17706), Point{2, Int64}(28813, -17704)
        ]
        polygon6 = polys[6]
        @test polygon6.shape.exterior == [
            Point{2, Int64}(28794, -17696), Point{2, Int64}(28797, -17699),
            Point{2, Int64}(28801, -17699), Point{2, Int64}(28802, -17696)
        ]
    end
    @testset "Two top cells" begin
        # Contains: A file containing two cells that aren't contained in each other.
        filename = "topcells.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        @test oas isa Oasis
        s = Suppressor.@capture_out Base.show(oas)
        @test s == """
OASIS file with the following cell hierarchy:
OTHERTOP
TOP"""
        s = Suppressor.@capture_out Base.show(oas[:TOP])
        @test s == "Cell TOP with 0 placements and 1 shape"
    end
    @testset "Flipped" begin
        # Contains: A cell placement which is flipped around the x-axis.
        filename = "flipped.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath)
        @test oas isa Oasis
        cell = oas["TOP"]
        placement1 = placements(cell)[1]
        @test placement1.rotation == 10
        @test placement1.flipped == false
        placement2 = placements(cell)[2]
        @test placement2.rotation == 10
        @test placement2.flipped == true
    end
end

@testset "Lazy OASIS files" begin
    @testset "Polygon" begin
        filename = "polygon.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
        cell = oas["TOP"]
        @test !isloaded(cell)
        @test cell.source.bytes[1] == 21 # Byte corresponding to start of POLYGON record
        load!(oas["TOP"])
        cell = oas["TOP"]
        @test isloaded(cell)
    end
    @testset "Boxes" begin
        filename = "boxes.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
        s = Suppressor.@capture_out Base.show(oas)
        # Nothing is decoded just to show the file.
        @test s == "OASIS file with 2 cells, whose hierarchy is known once they are indexed (see `index!`)"
        top_cell = oas["TOP"]
        @test top_cell.source.bytes[1] == 17 # First byte of a PLACEMENT record
        bottom_cell = oas["BOTTOM"]
        @test bottom_cell.source.bytes[1] == 20 # RECTANGLE
    end
    @testset "Circle" begin
        filename = "circle.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
    end
    @testset "Paths" begin
        filename = "paths.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
    end
    @testset "Nested" begin
        filename = "nested.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
        load!(oas["BOTTOM"])
        @test isloaded(oas["BOTTOM"])
        @test length(oas["BOTTOM"].shapes) == 1
    end
    @testset "Trapezoids" begin
        filename = "trapezoids.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
    end
    @testset "Two top cells" begin
        filename = "topcells.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
        s = Suppressor.@capture_out Base.show(oas)
        # Nothing is decoded just to show the file.
        @test s == "OASIS file with 2 cells, whose hierarchy is known once they are indexed (see `index!`)"
        @test !isloaded(oas["TOP"])
        @test !isloaded(oas["OTHERTOP"])
    end
    @testset "Flipped" begin
        filename = "flipped.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        @test oas isa Oasis
    end
end

@testset "Modal point lists" begin
    # A record that omits its point list reuses the modal one. The modal point list holds
    # deltas, so it must survive the conversion to absolute coordinates unscathed.
    @testset "Polygon" begin
        state = parse_cell_bytes(UInt8[
            0x15, 0x3b,             # POLYGON; layer, datatype, point list, x and y explicit
            0x01, 0x00,             # layer 1, datatype 0
            0x04, 0x03,             # g-delta point list with three deltas
            0xc0, 0x0c,             # east 100
            0xc2, 0x0c,             # north 100
            0xc4, 0x0c,             # west 100
            0x00, 0x00,             # x = 0, y = 0
            0x15, 0x18,             # POLYGON; only x and y explicit, so point list is modal
            0xd0, 0x0f, 0x00        # x = 1000, y = 0
        ])
        @test length(state.sink.shapes) == 2
        @test state.sink.shapes[1].shape.exterior == Point{2, Int64}[
            (0, 0), (100, 0), (100, 100), (0, 100)
        ]
        @test state.sink.shapes[2].shape.exterior == Point{2, Int64}[
            (1000, 0), (1100, 0), (1100, 100), (1000, 100)
        ]
    end

    @testset "Path" begin
        state = parse_cell_bytes(UInt8[
            0x16, 0x7b,             # PATH; layer, datatype, halfwidth, point list, x, y
            0x02, 0x00,             # layer 2, datatype 0
            0x05,                   # halfwidth 5
            0x04, 0x02,             # g-delta point list with two deltas
            0xc0, 0x0c,             # east 100
            0xc2, 0x0c,             # north 100
            0x00, 0x00,             # x = 0, y = 0
            0x16, 0x18,             # PATH; only x and y explicit, so point list is modal
            0xd0, 0x0f, 0x00        # x = 1000, y = 0
        ])
        @test length(state.sink.shapes) == 2
        @test state.sink.shapes[1].shape.points == Point{2, Int64}[(0, 0), (100, 0), (100, 100)]
        @test state.sink.shapes[2].shape.points == Point{2, Int64}[
            (1000, 0), (1100, 0), (1100, 100)
        ]
        @test state.sink.shapes[1].shape.width == 10
        @test state.sink.shapes[2].shape.width == 10
    end
end

# Writes a file with the given file-level records, followed by cells given by their name number
# and their records.
function raw_file(records::Vector{UInt8}, cells::Pair{Int, Vector{UInt8}}...)
    path = tempname()
    state = OasisTools.WriterState(path, 1 << 16)
    OasisTools.write_bytes(state, OasisTools.MAGIC_BYTES)
    OasisTools.write_start(state, 1000.0)
    OasisTools.write_bytes(state, records)
    for (number, contents) in cells
        OasisTools.write_byte(state, 13) # CELL
        OasisTools.wui(state, number)
        OasisTools.write_bytes(state, contents)
    end
    OasisTools.write_end(state)
    write(state.io, view(state.buf, 1:(state.pos - 1)))
    close(state.io)
    return path
end

@testset "Malformed input" begin
    # Every one of these used to run off the end of the buffer and read unrelated memory,
    # because the low-level readers were annotated @inbounds.
    @testset "Truncated records" begin
        # RECTANGLE claiming a layer, datatype, width, height, x and y, but the record stops
        # after the layer.
        @test_throws OasisParseError parse_cell_bytes(UInt8[0x14, 0x7b, 0x01])

        # Unterminated variable-length integer: every byte has its continuation bit set.
        @test_throws OasisParseError OasisTools.rui(CellParserState(UInt8[0x80, 0x80, 0x80]))

        # A string whose declared length runs past the end of the buffer.
        @test_throws OasisParseError OasisTools.read_string(
            CellParserState(UInt8[0x7f, 0x61, 0x62])
        )
        @test_throws OasisParseError OasisTools.skip_string(
            CellParserState(UInt8[0x7f, 0x61, 0x62])
        )

        # A point list declaring more vertices than there are bytes left.
        @test_throws OasisParseError OasisTools.read_point_list(
            CellParserState(UInt8[0x04, 0x7f, 0x02])
        )
    end
    @testset "Unknown type tags" begin
        @test_throws OasisParseError OasisTools.read_real(CellParserState(UInt8[0x08]))
        @test_throws OasisParseError OasisTools.read_interval(CellParserState(UInt8[0x05]))
        @test_throws OasisParseError OasisTools.read_point_list(CellParserState(UInt8[0x06, 0x01]))
        @test_throws OasisParseError OasisTools.read_repetition(CellParserState(UInt8[0x0c]))
        @test_throws OasisParseError parse_cell_bytes(UInt8[0x63])
    end
    @testset "Not an OASIS file" begin
        path = tempname()
        write(path, zeros(UInt8, 64))
        @test_throws OasisParseError oasisread(path)
    end
    @testset "Undefined references" begin
        # These used to fail with a bare KeyError, rather than saying what was wrong.
        # A placement of cell name number 7, and a text with text string number 3.
        @test_throws OasisParseError parse_cell_bytes(UInt8[0x11, 0xf0, 0x07, 0x00, 0x00])
        @test_throws OasisParseError parse_cell_bytes(UInt8[0x13, 0x7b, 0x03, 0x01, 0x00, 0x00, 0x00])
        # A cell whose name number no CELLNAME record defines.
        path = raw_file(
            UInt8[0x04, 0x03, codeunits("TOP")..., 0x00],             # CELLNAME TOP, number 0
            0 => UInt8[0x11, 0xf0, 0x07, 0x00, 0x00],                 # Places cell number 7
            7 => UInt8[0x14, 0x7b, 0x01, 0x00, 0x0a, 0x0a, 0x00, 0x00] # Which has no name
        )
        @test_throws OasisParseError oasisread(path)
        @test_throws OasisParseError oasisread(path; lazy = true)
    end
    @testset "CBLOCKs that don't decompress properly" begin
        # A CBLOCK holding a single rectangle, declaring a given uncompressed size.
        rectangle = UInt8[0x14, 0x7b, 0x01, 0x00, 0x0a, 0x0a, 0x00, 0x00]
        compressed = transcode(OasisTools.CodecZlib.DeflateCompressor, rectangle)
        cblock(declared) = vcat(UInt8[0x22, 0x00, declared, length(compressed)], compressed)
        @test length(parse_cell_bytes(cblock(length(rectangle))).sink.shapes) == 1
        # The spec treats CBLOCKs decompressing to more or fewer bytes than declared as errors.
        @test_throws OasisParseError parse_cell_bytes(cblock(length(rectangle) + 1))
        @test_throws OasisParseError parse_cell_bytes(cblock(length(rectangle) - 1))
        # Data that isn't compressed at all.
        @test_throws OasisParseError parse_cell_bytes(UInt8[0x22, 0x00, 0x08, 0x04, 0xff, 0xff, 0xff, 0xff])
    end
    @testset "Error carries a byte offset" begin
        err = try
            parse_cell_bytes(UInt8[0x14, 0x7b, 0x01])
            nothing
        catch e
            e
        end
        @test err isa OasisParseError
        @test err.position > 0
        s = sprint(showerror, err)
        @test occursin("OasisParseError", s)
        @test occursin("at byte", s)
    end
end

@testset "Extension records" begin
    # XNAME, XELEMENT and XGEOMETRY records used to stop the reader. They are now skipped, but an
    # XGEOMETRY record still sets the modal variables that the records after it may rely on.
    path = raw_file(
        UInt8[
            0x04, 0x03, codeunits("TOP")..., 0x00, # CELLNAME TOP, number 0
            30, 0x07, 0x03, codeunits("abc")...    # XNAME
        ],
        0 => UInt8[
            32, 0x02, 0x02, codeunits("xy")...,    # XELEMENT
            # XGEOMETRY on layer 5, datatype 2, at (300, 400).
            33, 0x1b, 0x01, 0x05, 0x02, 0x03, codeunits("geo")..., 0xd8, 0x04, 0xa0, 0x06,
            0x14, 0x60, 0x0a, 0x14                 # RECTANGLE of 10 by 20; everything else modal
        ]
    )
    expected = Rect{2, Int64}(Point{2, Int64}(300, 400), Point{2, Int64}(10, 20))
    for lazy in (false, true)
        shape = only(shapes(oasisread(path; lazy = lazy)[:TOP]))
        @test (shape.layer, shape.datatype) == (5, 2)
        @test shape.shape == expected
    end
    # Copying the cell keeps its extension records, so the rectangle comes out the same.
    copied = tempname()
    oasiswrite(copied, oasisread(path; lazy = true))
    @test only(shapes(oasisread(copied)[:TOP])).shape == expected
end
