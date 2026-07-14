@testset "Manipulate OASIS objects" begin
    @testset "Add cells" begin
        oas = Oasis()
        add_cell!(oas, :NEW)
        @test oas[:NEW] isa Cell
        @test OasisTools.unit(oas[:NEW]) == OasisTools.DEFAULT_UNIT
        @test_throws Exception add_cell!(oas, :NEW)
    end
    @testset "Add layers" begin
        oas = Oasis()
        add_layer!(oas, :M0, 1, 0)
        add_layer!(oas, Layer("V0", 1, 1))
        add_layer!(oas, Layer("V0", OasisTools.Interval(2, 3), 2))
        @test_throws Exception add_layer!(oas, :M0, OasisTools.Interval(1, 2), OasisTools.Interval(0, 1))
    end
    @testset "Merge files" begin
        oas = Oasis()
        add_cell!(oas, :TOP1)
        add_layer!(oas, :M0, 1, 0)
        add_layer!(oas, :V0, 2, 0)
        oas2 = Oasis()
        add_cell!(oas2, :TOP1)
        add_cell!(oas2, :TOP2)
        add_layer!(oas2, :Metal0, 1, 0)
        add_layer!(oas2, :V0, 2, OasisTools.Interval(0, 1))
        merge_oases!(oas, oas2)
        @test length(cell_names(oas)) == 2
        @test name(layer(oas, 1, 0)) == Symbol("M0, Metal0")
        @test name(layer(oas, 2, 1)) == :V0
    end
end

@testset "Compose cell placements" begin
    @testset "Translation only" begin
        outer = CellPlacement(:B, Point{2, Int64}(100, 200), 0.0, 1.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(10, 20), 0.0, 1.0, false, nothing)
        r = outer * inner
        @test r.cellName == :C
        @test r.location == Point{2, Int64}(110, 220)
        @test r.rotation == 0.0
        @test r.magnification == 1.0
        @test r.flipped == false
        @test isnothing(r.repetition)
    end
    @testset "90° rotation" begin
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 90.0, 1.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(100, 0), 0.0, 1.0, false, nothing)
        r = outer * inner
        @test r.location == Point{2, Int64}(0, 100)
        @test r.rotation == 90.0
    end
    @testset "180° rotation" begin
        outer = CellPlacement(:B, Point{2, Int64}(5, 10), 180.0, 1.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(3, 7), 0.0, 1.0, false, nothing)
        r = outer * inner
        @test r.location == Point{2, Int64}(5 - 3, 10 - 7)
        @test r.rotation == 180.0
    end
    @testset "Magnification" begin
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 2.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(10, 20), 0.0, 3.0, false, nothing)
        r = outer * inner
        @test r.magnification == 6.0
        @test r.location == Point{2, Int64}(20, 40)
    end
    @testset "Flip" begin
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, true, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(100, 50), 0.0, 1.0, false, nothing)
        r = outer * inner
        @test r.location == Point{2, Int64}(100, -50)
        @test r.flipped == true
    end
    @testset "Double flip cancels" begin
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, true, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 0.0, 1.0, true, nothing)
        r = outer * inner
        @test r.flipped == false
    end
    @testset "Flip reverses inner rotation" begin
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, true, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 45.0, 1.0, false, nothing)
        r = outer * inner
        @test r.flipped == true
        @test r.rotation == mod(-45.0, 360.0)
    end
    @testset "Rotation + magnification + translation" begin
        # 90° rotation with 2× magnification, then offset
        outer = CellPlacement(:B, Point{2, Int64}(10, 20), 90.0, 2.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(3, 4), 0.0, 1.0, false, nothing)
        r = outer * inner
        @test r.magnification == 2.0
        @test r.rotation == 90.0
        # Transform (3, 4) by rot=90, mag=2: 2*(-4, 3) = (-8, 6), then + (10, 20) = (2, 26)
        @test r.location == Point{2, Int64}(2, 26)
    end
    @testset "Repetition: outer only" begin
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(10, 0), Point{2, Int64}(20, 0)]
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, false, rep)
        inner = CellPlacement(:C, Point{2, Int64}(5, 5), 0.0, 1.0, false, nothing)
        r = outer * inner
        @test r.repetition == rep
    end
    @testset "Repetition: inner only" begin
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(10, 0)]
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 0.0, 1.0, false, rep)
        r = outer * inner
        @test r.repetition == rep
    end
    @testset "Repetition: inner transformed by outer rotation" begin
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(10, 0)]
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 90.0, 1.0, false, nothing)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 0.0, 1.0, false, rep)
        r = outer * inner
        @test r.repetition == [Point{2, Int64}(0, 0), Point{2, Int64}(0, 10)]
    end
    @testset "Repetition: Minkowski sum of two Vectors" begin
        rep1 = [Point{2, Int64}(0, 0), Point{2, Int64}(10, 0)]
        rep2 = [Point{2, Int64}(0, 0), Point{2, Int64}(0, 20)]
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, false, rep1)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 0.0, 1.0, false, rep2)
        r = outer * inner
        expected = sort([
            Point{2, Int64}(0, 0), Point{2, Int64}(10, 0),
            Point{2, Int64}(0, 20), Point{2, Int64}(10, 20)
        ])
        @test r.repetition == expected
    end
    @testset "Repetition: two 1D PointGridRanges → 2D PointGridRange" begin
        pgr1 = OasisTools.PointGridRange(
            Point{2, Int64}(0, 0), 3, 1,
            Point{2, Int64}(10, 0), Point{2, Int64}(0, 0)
        )
        pgr2 = OasisTools.PointGridRange(
            Point{2, Int64}(0, 0), 1, 4,
            Point{2, Int64}(0, 0), Point{2, Int64}(0, 20)
        )
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, false, pgr1)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 0.0, 1.0, false, pgr2)
        r = outer * inner
        @test r.repetition isa OasisTools.PointGridRange
        pgr = r.repetition
        @test pgr.nstepx == 3
        @test pgr.nstepy == 4
        @test pgr.stepx == Point{2, Int64}(10, 0)
        @test pgr.stepy == Point{2, Int64}(0, 20)
    end
    @testset "Repetition: 2D PointGridRange + 1D PointGridRange → Vector fallback" begin
        pgr_2d = OasisTools.PointGridRange(
            Point{2, Int64}(0, 0), 2, 2,
            Point{2, Int64}(10, 0), Point{2, Int64}(0, 10)
        )
        pgr_1d = OasisTools.PointGridRange(
            Point{2, Int64}(0, 0), 3, 1,
            Point{2, Int64}(5, 0), Point{2, Int64}(0, 0)
        )
        outer = CellPlacement(:B, Point{2, Int64}(0, 0), 0.0, 1.0, false, pgr_2d)
        inner = CellPlacement(:C, Point{2, Int64}(0, 0), 0.0, 1.0, false, pgr_1d)
        r = outer * inner
        @test r.repetition isa Vector{Point{2, Int64}}
        # 2×2 grid × 3 points = up to 12 combinations; verify some key points
        @test Point{2, Int64}(0, 0) in r.repetition
        @test Point{2, Int64}(10, 0) in r.repetition   # from pgr_2d
        @test Point{2, Int64}(5, 0) in r.repetition    # from pgr_1d
        @test Point{2, Int64}(15, 10) in r.repetition  # (10,0)+(5,0)+(0,10)
    end
end

@testset "Expand cell placements" begin
    @testset "No repetition" begin
        p = CellPlacement(:A, Point{2, Int64}(10, 20), 45.0, 2.0, true, nothing)
        result = collect(expand(p))
        @test length(result) == 1
        @test result[1].cellName == :A
        @test result[1].location == Point{2, Int64}(10, 20)
        @test result[1].rotation == 45.0
        @test result[1].magnification == 2.0
        @test result[1].flipped == true
        @test isnothing(result[1].repetition)
    end
    @testset "Vector repetition" begin
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(100, 0), Point{2, Int64}(200, 0)]
        p = CellPlacement(:B, Point{2, Int64}(5, 10), 90.0, 1.0, false, rep)
        result = collect(expand(p))
        @test length(result) == 3
        @test result[1].location == Point{2, Int64}(5, 10)
        @test result[2].location == Point{2, Int64}(105, 10)
        @test result[3].location == Point{2, Int64}(205, 10)
        for r in result
            @test r.cellName == :B
            @test r.rotation == 90.0
            @test r.magnification == 1.0
            @test r.flipped == false
            @test isnothing(r.repetition)
        end
    end
    @testset "PointGridRange repetition" begin
        pgr = OasisTools.PointGridRange(
            Point{2, Int64}(0, 0), 2, 3,
            Point{2, Int64}(10, 0), Point{2, Int64}(0, 20)
        )
        p = CellPlacement(:C, Point{2, Int64}(1, 2), 0.0, 1.0, false, pgr)
        result = collect(expand(p))
        @test length(result) == 6  # 2 × 3
        locations = [r.location for r in result]
        @test Point{2, Int64}(1, 2) in locations       # (0, 0) offset
        @test Point{2, Int64}(11, 2) in locations      # (10, 0) offset
        @test Point{2, Int64}(1, 22) in locations      # (0, 20) offset
        @test Point{2, Int64}(11, 22) in locations     # (10, 20) offset
        @test Point{2, Int64}(1, 42) in locations      # (0, 40) offset
        @test Point{2, Int64}(11, 42) in locations     # (10, 40) offset
        for r in result
            @test isnothing(r.repetition)
        end
    end
    @testset "Lazy iteration" begin
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(50, 0)]
        p = CellPlacement(:D, Point{2, Int64}(0, 0), 0.0, 1.0, false, rep)
        gen = expand(p)
        # Verify it's a generator, not a materialized vector
        @test gen isa Base.Generator
        # Verify we can iterate it
        count = 0
        for _ in gen
            count += 1
        end
        @test count == 2
    end
end

@testset "Filter shapes by layer" begin
    rect1 = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
    rect2 = Rect{2, Int64}(Point{2, Int64}(20, 20), Point{2, Int64}(30, 30))
    rect3 = Rect{2, Int64}(Point{2, Int64}(40, 40), Point{2, Int64}(50, 50))
    s1 = Shape(rect1, UInt64(1), UInt64(0), nothing)  # layer 1/0
    s2 = Shape(rect2, UInt64(1), UInt64(1), nothing)  # layer 1/1
    s3 = Shape(rect3, UInt64(2), UInt64(0), nothing)  # layer 2/0
    cell = Cell(:TEST, [s1, s2, s3], CellPlacement[], 1000.0, true)

    @testset "No filter returns all shapes" begin
        @test length(shapes(cell)) == 3
    end
    @testset "Filter by Layer object" begin
        l = Layer(:M0, OasisTools.Interval(1, 1), OasisTools.Interval(0, 0))
        @test length(shapes(cell, l)) == 1
        @test shapes(cell, l)[1] === s1
    end
    @testset "Filter by Layer with interval range" begin
        l = Layer(:M, OasisTools.Interval(1, 2), OasisTools.Interval(0, 0))
        result = shapes(cell, l)
        @test length(result) == 2
        @test s1 in result
        @test s3 in result
    end
    @testset "Filter by layer number only" begin
        result = shapes(cell, 1)
        @test length(result) == 2
        @test s1 in result
        @test s2 in result
    end
    @testset "Filter by layer and datatype numbers" begin
        result = shapes(cell, 1, 0)
        @test length(result) == 1
        @test result[1] === s1
    end
    @testset "Filter with no matches" begin
        @test isempty(shapes(cell, 99))
        @test isempty(shapes(cell, Layer(:X, 99, 99)))
    end
end

@testset "Layer lookup by name" begin
    oas = Oasis()
    add_layer!(oas, :M0, 1, 0)
    add_layer!(oas, :V0, 2, 0)
    @test name(layer(oas, :M0)) == :M0
    @test name(layer(oas, :V0)) == :V0
    @test isnothing(layer(oas, :NONEXISTENT))
end
