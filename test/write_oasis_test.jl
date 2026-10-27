@testset "Write cells that aren't loaded" begin
    @testset "Polygon" begin
        filename = "polygon.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        
        state = OasisTools.WriterState(oas, tempname(), 1024 * 1024)
        state.cellnameReferences[:TOP] = 123
        cell = oas["TOP"]
        OasisTools.write_cell(state, cell)

        @test read_and_reset(state, state.pos - 1) == [
            0x0d, # CELL record
            0x7b, # 123; the reference we set
            0x15, # POLYGON record
            0x3b, 0x01, 0x00, 0x04, 0x03, # General polygon stuff
            0x82, 0x7d, 0x88, 0x7d, 0x86,
            0x7d, 0xd1, 0x0f, 0xd1, 0x0f
        ]
    end
    @testset "Boxes" begin
        filename = "boxes.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        
        state = OasisTools.WriterState(oas, tempname(), 1024 * 1024)
        state.cellnameReferences[:TOP] = 123
        state.cellnameReferences[:BOTTOM] = 124
        cell = oas["TOP"]
        OasisTools.write_cell(state, cell)

        @test read_and_reset(state, state.pos - 1) == [
            0x0d, # CELL record
            0x7b, # 123; reference to TOP
            0x11, # PLACEMENT record
            0xfc, 0x7c, 0x91, 0x08, 0xb0, # General placement stuff, the 0x7c being 124 (BOTTOM)
            0x22, 0x08, 0x04, 0x03, 0xe2,
            0x03, 0xc9, 0x01, 0x3d,
            0x11, # Another PLACEMENT record
            0x44, # 0b01000100; modal variables used for all information
            0x14, # RECTANGLE record
            0x7f, 0x01, 0x01, 0x00, 0x8c, # General rectangle stuff
            0x01, 0xc1, 0x02, 0x99, 0x0c,
            0x0b, 0x02, 0x0a, 0x17, 0x06,
            0x17, 0x06, 0x17, 0x06
        ]
        
        state = OasisTools.WriterState(oas, tempname(), 1024 * 1024)
        state.cellnameReferences[:BOTTOM] = 124
        cell = oas["BOTTOM"]
        OasisTools.write_cell(state, cell)

        @test read_and_reset(state, state.pos - 1) == [
            0x0d, # CELL record
            0x7c, # 124; reference to BOTTOM
            0x14, # RECTANGLE record
            0xdb, 0x01, 0x00, 0x0a, 0xfd, # General rectangle stuff
            0x02, 0xec, 0x2c
        ]
    end
    @testset "Trailing single-byte record" begin
        # The last record of a cell may be a single byte, which puts it right at the edge of the
        # cell's byte range.
        bytes = UInt8[
            0x14, 0x7b,             # RECTANGLE; layer, datatype, width, height, x, y explicit
            0x01, 0x00,             # layer 1, datatype 0
            0x0a, 0x14,             # width 10, height 20
            0x00, 0x00,             # x = 0, y = 0
            0x00                    # PAD
        ]
        source = OasisTools.CellSource(
            view(bytes, 1:length(bytes)), Dict{UInt64, Symbol}(), Dict{UInt64, Symbol}()
        )
        cell = Cell(:TOP, source, true)

        state = OasisTools.WriterState(tempname(), 1024)
        state.cellnameReferences[:TOP] = 123
        OasisTools.write_cell(state, cell)
        @test read_and_reset(state, state.pos - 1) == vcat(UInt8[0x0d, 0x7b], bytes)
        close(state.io)

        @test length(OasisTools.load_cell(cell).shapes) == 1
    end
end

@testset "Write lazy OASIS files" begin
    # Strategy: Lazily load each OASIS file as provided in `testdata`, then save it to a
    # temporary file and load it again. The resulting object should have essentially the same
    # contents.
    @testset "Polygon" begin
        filename = "polygon.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 1
        top_cell = oas["TOP"]
        subcells = top_cell.placements
        @test isempty(subcells)
        shapes = top_cell.shapes
        @test length(shapes) == 1
        polygon = top_cell.shapes[1].shape
        @test polygon isa Polygon
        @test polygon.exterior == [
            Point{2, Int64}(-1000, -1000), Point{2, Int64}(-1000, 0),
            Point{2, Int64}(0, 1000), Point{2, Int64}(0, 0)
        ]
    end
    @testset "Boxes" begin
        # Contains: Two layers, cell placement with repetition, rectangles.
        filename = "boxes.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 2
        bottom_cell = oas["BOTTOM"]
        @test bottom_cell.name == :BOTTOM
        @test length(bottom_cell.shapes) == 1
        rectangle = bottom_cell.shapes[1]
        layer_number = rectangle.layerNumber
        datatype_number = rectangle.datatypeNumber
        layername = name(layer(oas, layer_number, datatype_number))
        @test layername == :TOP
        rectangle_shape = rectangle.shape
        @test rectangle_shape isa Rect{2, Int64}
        @test rectangle_shape == Rect{2, Int64}(
            Point{2, Int64}(-190, 2870),
            Point{2, Int64}(10, 10)
        )
        top_shape = shapes(oas["TOP"])[1]
        @test top_shape isa Shape{Rect{2, Int64}}
        s = Suppressor.@capture_out Base.show(top_shape)
        @test s == "Rectangle in layer (1/1) at (-160, -710) (4×)"
    end
    @testset "Circle" begin
        filename = "circle.oas" # 156.600 μs (169 allocations: 223.48 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
        @test oas isa Oasis
        circle_cell = oas["CIRCLE\$1"]
        circle = circle_cell.shapes[1]
        @test circle isa Shape{Polygon{2, Int64}}
        text_cell = oas["TOP"]
        text = text_cell.shapes[1]
        @test String(text.shape.text) == "This is not a circle"
    end
    @testset "Paths" begin
        filename = "paths.oas" # 143.800 μs (120 allocations: 77.43 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 1
        top_cell = oas["TOP"]
        nplacement = length(top_cell.placements)
        @test nplacement == 0
        paths = [s.shape for s in top_cell.shapes.paths]
        circles = [s.shape for s in top_cell.shapes.circles]
        @test length(top_cell.shapes) == 6 # Four paths and two circles for the rounded path
        path_1 = paths[1]
        @test path_1.points == Point{2, Int64}[(-508, 268), (-253, 22), (-342, 190), (-157, 176)]
        @test path_1.width == 100
        path_2 = paths[2]
        @test path_2.points == Point{2, Int64}[(-263, 431), (-116, 420), (-228, 315), (-182, 482)]
        @test path_2.width == 50
        path_3 = paths[3]
        @test path_3.points == Point{2, Int64}[(-343, 273), (-386, 294), (-351, 303)]
        @test path_3.width == 10
        start_circle = circles[1]
        @test start_circle.center == Point{2, Int64}(-343, 273)
        @test start_circle.r == 5
        end_circle = circles[2]
        @test end_circle.center == Point{2, Int64}(-351, 303)
        @test end_circle.r == 5
        path_4 = paths[4]
        @test path_4.points == Point{2, Int64}[(-257, 236), (-255, 238), (-254, 237)]
        @test path_4.width == 2
    end
    @testset "Nested" begin
        filename = "nested.oas" # 161.300 μs (232 allocations: 225.47 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
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
        filename = "trapezoids.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
        cell = oas["noname"]
        @test length(cell.shapes) == 7
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
        filename = "topcells.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
        @test oas isa Oasis
        s = Suppressor.@capture_out Base.show(oas)
        @test s == """
OASIS file with the following cell hierarchy:
OTHERTOP
TOP"""
        s = Suppressor.@capture_out Base.show(oas["TOP"])
        @test s == "Cell TOP with 0 placements and 1 shape"
    end
    @testset "Flipped" begin
        filename = "flipped.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        path = tempname()
        oasiswrite(path, oas)
        oas = oasisread(path)
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

@testset "CBLOCK writing" begin
    @testset "Metadata is wrapped in a CBLOCK" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        shape = Shape(rect, UInt64(1), UInt64(0), nothing)
        cell = Cell(:CBLOCK_TEST, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        add_layer!(oas, Layer(:M1, 1, 0))
        path = tempname()
        oasiswrite(path, oas)

        # Verify the file contains a CBLOCK record (record type 34)
        raw = read(path)
        @test UInt8(34) in raw

        # Verify round-trip works through the CBLOCK
        oas2 = oasisread(path)
        @test oas2 isa Oasis
        cell2 = oas2["CBLOCK_TEST"]
        @test length(shapes(cell2)) == 1
        @test shapes(cell2)[1].shape isa Rect{2, Int64}
        @test length(oas2.layers) == 1
        @test name(oas2.layers[1]) == :M1
    end
    @testset "Multiple cells and layers through CBLOCK" begin
        oas = Oasis()
        rect1 = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(5, 5))
        rect2 = Rect{2, Int64}(Point{2, Int64}(10, 10), Point{2, Int64}(20, 20))
        s1 = Shape(rect1, UInt64(1), UInt64(0), nothing)
        s2 = Shape(rect2, UInt64(2), UInt64(1), nothing)
        cell1 = Cell(:CELL_A, [s1], CellPlacement[], true)
        placement = CellPlacement(:CELL_A, Point{2, Int64}(100, 200), 0.0, 1.0, false, nothing)
        cell2 = Cell(:CELL_B, [s2], [placement], true)
        add_cell!(oas, cell1)
        add_cell!(oas, cell2)
        add_layer!(oas, Layer(:L1, 1, 0))
        add_layer!(oas, Layer(:L2, 2, 1))
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        @test length(oas2.cells) == 2
        @test length(oas2.layers) == 2
        @test name(oas2.layers[1]) == :L1
        @test name(oas2.layers[2]) == :L2
        @test shapes(oas2["CELL_A"])[1].shape isa Rect{2, Int64}
        @test placements(oas2["CELL_B"])[1].cellName == :CELL_A
    end
end

@testset "Write Cells with shapes" begin
    @testset "Polygon" begin
        oas = Oasis()
        pts = [
            Point{2, Int64}(0, 0), Point{2, Int64}(100, 0),
            Point{2, Int64}(100, 200), Point{2, Int64}(0, 200)
        ]
        polygon = Polygon(pts)
        shape = Shape(polygon, UInt64(1), UInt64(0), nothing)
        cell = Cell(:POLY, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        add_layer!(oas, Layer(:M1, 1, 0))
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        cell2 = oas2["POLY"]
        @test length(shapes(cell2)) == 1
        s = shapes(cell2)[1]
        @test s.shape isa Polygon{2, Int64}
        @test s.layerNumber == 1
        @test s.datatypeNumber == 0
        @test s.shape.exterior == pts
        @test isnothing(s.repetition)
    end
    @testset "Rectangle" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(10, 20), Point{2, Int64}(30, 40))
        shape = Shape(rect, UInt64(2), UInt64(1), nothing)
        cell = Cell(:RECT, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        cell2 = oas2["RECT"]
        @test length(shapes(cell2)) == 1
        s = shapes(cell2)[1]
        @test s.shape isa Rect{2, Int64}
        @test s.shape.origin == Point{2, Int64}(10, 20)
        @test s.shape.widths == Point{2, Int64}(30, 40)
    end
    @testset "Square rectangle" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(5, 5), Point{2, Int64}(50, 50))
        shape = Shape(rect, UInt64(1), UInt64(0), nothing)
        cell = Cell(:SQR, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        s = shapes(oas2["SQR"])[1]
        @test s.shape isa Rect{2, Int64}
        @test s.shape.widths == Point{2, Int64}(50, 50)
    end
    @testset "Circle" begin
        oas = Oasis()
        circle = HyperSphere{2, Int64}(Point{2, Int64}(100, 200), 50)
        shape = Shape(circle, UInt64(3), UInt64(0), nothing)
        cell = Cell(:CIRC, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        s = shapes(oas2["CIRC"])[1]
        @test s.shape isa HyperSphere{2, Int64}
        @test s.shape.center == Point{2, Int64}(100, 200)
        @test s.shape.r == 50
    end
    @testset "Path" begin
        oas = Oasis()
        pts = [
            Point{2, Int64}(0, 0), Point{2, Int64}(100, 0),
            Point{2, Int64}(100, 100)
        ]
        path = OasisTools.Path(pts, Int64(20))
        shape = Shape(path, UInt64(1), UInt64(0), nothing)
        cell = Cell(:PATH, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        s = shapes(oas2["PATH"])[1]
        @test s.shape isa OasisTools.Path{2, Int64}
        @test s.shape.points == pts
        @test s.shape.width == 20
    end
    @testset "Text" begin
        oas = Oasis()
        text = OasisTools.Text(:hello, Point{2, Int64}(50, 60), nothing)
        shape = Shape(text, UInt64(10), UInt64(0), nothing)
        cell = Cell(:TXT, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        s = shapes(oas2["TXT"])[1]
        @test s.shape isa OasisTools.Text
        @test s.shape.text == :hello
        @test s.shape.location == Point{2, Int64}(50, 60)
    end
    @testset "Multiple shapes on different layers" begin
        oas = Oasis()
        rect1 = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        rect2 = Rect{2, Int64}(Point{2, Int64}(20, 20), Point{2, Int64}(30, 30))
        s1 = Shape(rect1, UInt64(1), UInt64(0), nothing)
        s2 = Shape(rect2, UInt64(2), UInt64(1), nothing)
        cell = Cell(:MULTI, [s1, s2], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        cell2 = oas2["MULTI"]
        @test length(shapes(cell2)) == 2
        @test shapes(cell2)[1].layerNumber == 1
        @test shapes(cell2)[2].layerNumber == 2
        @test shapes(cell2)[2].datatypeNumber == 1
    end
    @testset "Shape with repetition" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(5, 5))
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(10, 0), Point{2, Int64}(20, 0)]
        shape = Shape(rect, UInt64(1), UInt64(0), rep)
        cell = Cell(:REP, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        s = shapes(oas2["REP"])[1]
        @test s.repetition == rep
    end
    @testset "Mixed placements and shapes" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        shape = Shape(rect, UInt64(1), UInt64(0), nothing)
        inner = Cell(:INNER, Shape[], CellPlacement[], false)
        placement = CellPlacement(:INNER, Point{2, Int64}(50, 50), 0.0, 1.0, false, nothing)
        outer = Cell(:OUTER, [shape], [placement], true)
        add_cell!(oas, inner)
        add_cell!(oas, outer)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        cell2 = oas2["OUTER"]
        @test length(placements(cell2)) == 1
        @test placements(cell2)[1].cellName == :INNER
        @test length(shapes(cell2)) == 1
        @test shapes(cell2)[1].shape isa Rect{2, Int64}
    end
    @testset "Negative coordinates" begin
        oas = Oasis()
        pts = [
            Point{2, Int64}(-100, -200), Point{2, Int64}(100, -200),
            Point{2, Int64}(100, 200), Point{2, Int64}(-100, 200)
        ]
        polygon = Polygon(pts)
        shape = Shape(polygon, UInt64(1), UInt64(0), nothing)
        cell = Cell(:NEG, [shape], CellPlacement[], true)
        add_cell!(oas, cell)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        s = shapes(oas2["NEG"])[1]
        @test s.shape.exterior == pts
    end
end

@testset "Modal variables when writing" begin
    @testset "Reset at every cell" begin
        # Readers reset the modal variables at every CELL record, so the second cell must not
        # rely on values that were set in the first.
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(5, 5), Point{2, Int64}(10, 20))
        for cell_name in (:A, :B)
            add_cell!(oas, cell_name)
            add_shape!(oas[cell_name], rect, 3, 2)
            add_placement!(oas[cell_name], :C, Point{2, Int64}(7, 8))
        end
        add_cell!(oas, :C)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path)
        for cell_name in (:A, :B)
            s = only(shapes(oas2[cell_name]))
            @test s.shape == rect
            @test s.layerNumber == 3
            @test s.datatypeNumber == 2
            p = only(placements(oas2[cell_name]))
            @test p.cellName == :C
            @test p.location == Point{2, Int64}(7, 8)
        end
    end
    @testset "Undefined modal variables are written explicitly" begin
        # A square on layer 0, datatype 0 at the origin. Layer, datatype and width start out
        # undefined and must be present; x and y start out at 0 and may be omitted.
        oas = Oasis()
        add_cell!(oas, :A)
        add_shape!(oas[:A], Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10)), 0, 0)
        path = tempname()
        oasiswrite(path, oas)
        oas2 = oasisread(path; lazy = true)
        bytes = oas2[:A].source.bytes
        @test bytes[1] == 20 # RECTANGLE
        @test bytes[2] == 0b11000011 # S, W, D and L set; X and Y omitted
        @test bytes[3:5] == [0x00, 0x00, 0x0a] # layer, datatype, width
    end
end

@testset "Replace files rather than overwrite them" begin
    contents(oas) = [(name(c), length(shapes(c)), length(placements(c))) for c in cells(oas)]
    source = joinpath(@__DIR__, "testdata", "nested.oas")
    expected = contents(oasisread(source))

    @testset "Source of lazy cells" begin
        # Overwriting the file in place used to truncate the memory map that the lazy cells read
        # from, which crashed Julia with a bus error and left the file destroyed.
        dir = mktempdir()
        path = joinpath(dir, "nested.oas")
        cp(source, path)
        oas = oasisread(path; lazy = true)
        oasiswrite(path, oas)
        @test contents(oasisread(path)) == expected
        # The lazy cells keep reading the original contents.
        load_all_cells!(oas)
        @test contents(oas) == expected
    end
    if !Sys.iswindows()
        @testset "Symlinks and permissions" begin
            dir = mktempdir()
            path = joinpath(dir, "nested.oas")
            cp(source, path)
            chmod(path, 0o640)
            link = joinpath(dir, "link.oas")
            symlink(path, link)
            oasiswrite(link, oasisread(path; lazy = true))
            @test islink(link)
            @test filemode(path) & 0o777 == 0o640
            @test contents(oasisread(path)) == expected
        end
    end
    @testset "Failed write leaves the file untouched" begin
        dir = mktempdir()
        path = joinpath(dir, "nested.oas")
        cp(source, path)
        original = read(path)
        oas = Oasis()
        add_cell!(oas, :TOP)
        add_placement!(oas[:TOP], :MISSING, Point{2, Int64}(0, 0)) # Fails to write
        @test_throws KeyError oasiswrite(path, oas)
        @test read(path) == original
        @test readdir(dir) == ["nested.oas"] # No temporary file left behind
    end
end
