@testset "Write LazyCells" begin
    @testset "Polygon" begin
        filename = "polygon.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        
        state = OasisTools.WriterState(oas, "temp", 1024 * 1024)
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
        
        state = OasisTools.WriterState(oas, "temp", 1024 * 1024)
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
        
        state = OasisTools.WriterState(oas, "temp", 1024 * 1024)
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
end

@testset "Write lazy OASIS files" begin
    # Strategy: Lazily load each OASIS file as provided in `testdata`, then save it to a
    # temporary file `"temp"` and load it again. The resulting object should have essentially
    # the same contents.
    # Note: Between each subsequent @testset, we run GC.gc(). This is needed because
    # `oas = oasisread("temp")` implicitly casts an mmap onto the file `"temp"`, which causes
    # the OS to lock the file until `oas` is garbage-collected.
    @testset "Polygon" begin
        filename = "polygon.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
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
    GC.gc()
    @testset "Boxes" begin
        # Contains: Two layers, cell placement with repetition, rectangles.
        filename = "boxes.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
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
    GC.gc()
    @testset "Circle" begin
        filename = "circle.oas" # 156.600 μs (169 allocations: 223.48 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
        @test oas isa Oasis
        circle_cell = oas["CIRCLE\$1"]
        circle = circle_cell.shapes[1]
        @test circle isa Shape{Polygon{2, Int64}}
        text_cell = oas["TOP"]
        text = text_cell.shapes[1]
        @test String(text.shape.text) == "This is not a circle"
    end
    GC.gc()
    @testset "Paths" begin
        filename = "paths.oas" # 143.800 μs (120 allocations: 77.43 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
        @test oas isa Oasis
        ncell = length(oas.cells)
        @test ncell == 1
        top_cell = oas["TOP"]
        nplacement = length(top_cell.placements)
        @test nplacement == 0
        shapes = [s.shape for s in top_cell.shapes]
        @test length(shapes) == 6 # Four paths and two circles for the rounded path
        path_1 = shapes[1]
        @test path_1.points == Point{2, Int64}[(-508, 268), (-253, 22), (-342, 190), (-157, 176)]
        @test path_1.width == 100
        path_2 = shapes[2]
        @test path_2.points == Point{2, Int64}[(-263, 431), (-116, 420), (-228, 315), (-182, 482)]
        @test path_2.width == 50
        path_3 = shapes[3]
        @test path_3.points == Point{2, Int64}[(-343, 273), (-386, 294), (-351, 303)]
        @test path_3.width == 10
        start_circle = shapes[4]
        @test start_circle.center == Point{2, Int64}(-343, 273)
        @test start_circle.r == 5
        end_circle = shapes[5]
        @test end_circle.center == Point{2, Int64}(-351, 303)
        @test end_circle.r == 5
        path_4 = shapes[6]
        @test path_4.points == Point{2, Int64}[(-257, 236), (-255, 238), (-254, 237)]
        @test path_4.width == 2
    end
    GC.gc()
    @testset "Nested" begin
        filename = "nested.oas" # 161.300 μs (232 allocations: 225.47 KiB)
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
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
    GC.gc()
    @testset "Trapezoids" begin
        filename = "trapezoids.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
        cell = oas["noname"]
        @test length(cell.shapes) == 7
        @test cell.shapes[1] isa Shape{OasisTools.Text}
        polygon1 = cell.shapes[2]
        @test polygon1.shape.exterior == [
            Point{2, Int64}(28810, -17702), Point{2, Int64}(28813, -17703),
            Point{2, Int64}(28813, -17698), Point{2, Int64}(28810, -17696)
        ]
        polygon2 = cell.shapes[3]
        @test polygon2.shape.exterior == [
            Point{2, Int64}(28796, -17701), Point{2, Int64}(28796, -17705),
            Point{2, Int64}(28800, -17705), Point{2, Int64}(28803, -17701)
        ]
        polygon3 = cell.shapes[4]
        @test polygon3.shape.exterior == [
            Point{2, Int64}(28805, -17705), Point{2, Int64}(28807, -17703),
            Point{2, Int64}(28807, -17698), Point{2, Int64}(28805, -17700)
        ]
        polygon4 = cell.shapes[5]
        @test polygon4.shape.exterior == [
            Point{2, Int64}(28800, -17707), Point{2, Int64}(28799, -17710),
            Point{2, Int64}(28806, -17710), Point{2, Int64}(28805, -17707)
        ]
        polygon5 = cell.shapes[6]
        @test polygon5.shape.exterior == [
            Point{2, Int64}(28809, -17704), Point{2, Int64}(28810, -17706),
            Point{2, Int64}(28814, -17706), Point{2, Int64}(28813, -17704)
        ]
        polygon6 = cell.shapes[7]
        @test polygon6.shape.exterior == [
            Point{2, Int64}(28794, -17696), Point{2, Int64}(28797, -17699),
            Point{2, Int64}(28801, -17699), Point{2, Int64}(28802, -17696)
        ]
    end
    GC.gc()
    @testset "Two top cells" begin
        filename = "topcells.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
        @test oas isa Oasis
        s = Suppressor.@capture_out Base.show(oas)
        @test s == """
OASIS file with the following cell hierarchy:
OTHERTOP
TOP"""
        s = Suppressor.@capture_out Base.show(oas["TOP"])
        @test s == "Cell TOP with 0 placements and 1 shape"
    end
    GC.gc()
    @testset "Flipped" begin
        filename = "flipped.oas"
        filepath = joinpath(@__DIR__, "testdata", filename)
        oas = oasisread(filepath; lazy = true)
        oasiswrite("temp", oas)
        oas = oasisread("temp")
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

@testset "Write Cells with shapes" begin
    @testset "Polygon" begin
        oas = Oasis()
        pts = [
            Point{2, Int64}(0, 0), Point{2, Int64}(100, 0),
            Point{2, Int64}(100, 200), Point{2, Int64}(0, 200)
        ]
        polygon = Polygon(pts)
        shape = Shape(polygon, UInt64(1), UInt64(0), nothing)
        cell = Cell(:POLY, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        add_layer!(oas, Layer(:M1, 1, 0))
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        cell2 = oas2["POLY"]
        @test length(shapes(cell2)) == 1
        s = shapes(cell2)[1]
        @test s.shape isa Polygon{2, Int64}
        @test s.layerNumber == 1
        @test s.datatypeNumber == 0
        @test s.shape.exterior == pts
        @test isnothing(s.repetition)
    end
    GC.gc()
    @testset "Rectangle" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(10, 20), Point{2, Int64}(30, 40))
        shape = Shape(rect, UInt64(2), UInt64(1), nothing)
        cell = Cell(:RECT, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        cell2 = oas2["RECT"]
        @test length(shapes(cell2)) == 1
        s = shapes(cell2)[1]
        @test s.shape isa Rect{2, Int64}
        @test s.shape.origin == Point{2, Int64}(10, 20)
        @test s.shape.widths == Point{2, Int64}(30, 40)
    end
    GC.gc()
    @testset "Square rectangle" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(5, 5), Point{2, Int64}(50, 50))
        shape = Shape(rect, UInt64(1), UInt64(0), nothing)
        cell = Cell(:SQR, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        s = shapes(oas2["SQR"])[1]
        @test s.shape isa Rect{2, Int64}
        @test s.shape.widths == Point{2, Int64}(50, 50)
    end
    GC.gc()
    @testset "Circle" begin
        oas = Oasis()
        circle = HyperSphere{2, Int64}(Point{2, Int64}(100, 200), 50)
        shape = Shape(circle, UInt64(3), UInt64(0), nothing)
        cell = Cell(:CIRC, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        s = shapes(oas2["CIRC"])[1]
        @test s.shape isa HyperSphere{2, Int64}
        @test s.shape.center == Point{2, Int64}(100, 200)
        @test s.shape.r == 50
    end
    GC.gc()
    @testset "Path" begin
        oas = Oasis()
        pts = [
            Point{2, Int64}(0, 0), Point{2, Int64}(100, 0),
            Point{2, Int64}(100, 100)
        ]
        path = OasisTools.Path(pts, Int64(20))
        shape = Shape(path, UInt64(1), UInt64(0), nothing)
        cell = Cell(:PATH, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        s = shapes(oas2["PATH"])[1]
        @test s.shape isa OasisTools.Path{2, Int64}
        @test s.shape.points == pts
        @test s.shape.width == 20
    end
    GC.gc()
    @testset "Text" begin
        oas = Oasis()
        text = OasisTools.Text(:hello, Point{2, Int64}(50, 60), nothing)
        shape = Shape(text, UInt64(10), UInt64(0), nothing)
        cell = Cell(:TXT, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        s = shapes(oas2["TXT"])[1]
        @test s.shape isa OasisTools.Text
        @test s.shape.text == :hello
        @test s.shape.location == Point{2, Int64}(50, 60)
    end
    GC.gc()
    @testset "Multiple shapes on different layers" begin
        oas = Oasis()
        rect1 = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        rect2 = Rect{2, Int64}(Point{2, Int64}(20, 20), Point{2, Int64}(30, 30))
        s1 = Shape(rect1, UInt64(1), UInt64(0), nothing)
        s2 = Shape(rect2, UInt64(2), UInt64(1), nothing)
        cell = Cell(:MULTI, [s1, s2], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        cell2 = oas2["MULTI"]
        @test length(shapes(cell2)) == 2
        @test shapes(cell2)[1].layerNumber == 1
        @test shapes(cell2)[2].layerNumber == 2
        @test shapes(cell2)[2].datatypeNumber == 1
    end
    GC.gc()
    @testset "Shape with repetition" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(5, 5))
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(10, 0), Point{2, Int64}(20, 0)]
        shape = Shape(rect, UInt64(1), UInt64(0), rep)
        cell = Cell(:REP, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        s = shapes(oas2["REP"])[1]
        @test s.repetition == rep
    end
    GC.gc()
    @testset "Mixed placements and shapes" begin
        oas = Oasis()
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        shape = Shape(rect, UInt64(1), UInt64(0), nothing)
        inner = Cell(:INNER, Shape[], CellPlacement[], 1000.0, false)
        placement = CellPlacement(:INNER, Point{2, Int64}(50, 50), 0.0, 1.0, false, nothing)
        outer = Cell(:OUTER, [shape], [placement], 1000.0, true)
        add_cell!(oas, inner)
        add_cell!(oas, outer)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        cell2 = oas2["OUTER"]
        @test length(placements(cell2)) == 1
        @test placements(cell2)[1].cellName == :INNER
        @test length(shapes(cell2)) == 1
        @test shapes(cell2)[1].shape isa Rect{2, Int64}
    end
    GC.gc()
    @testset "Negative coordinates" begin
        oas = Oasis()
        pts = [
            Point{2, Int64}(-100, -200), Point{2, Int64}(100, -200),
            Point{2, Int64}(100, 200), Point{2, Int64}(-100, 200)
        ]
        polygon = Polygon(pts)
        shape = Shape(polygon, UInt64(1), UInt64(0), nothing)
        cell = Cell(:NEG, [shape], CellPlacement[], 1000.0, true)
        add_cell!(oas, cell)
        oasiswrite("temp", oas)
        oas2 = oasisread("temp")
        s = shapes(oas2["NEG"])[1]
        @test s.shape.exterior == pts
    end
end
