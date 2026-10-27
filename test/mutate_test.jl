@testset "Manipulate OASIS objects" begin
    @testset "Add cells" begin
        oas = Oasis()
        add_cell!(oas, :NEW)
        @test oas[:NEW] isa Cell
        @test OasisTools.unit(oas) == OasisTools.DEFAULT_UNIT
        @test_throws Exception add_cell!(oas, :NEW)
    end
    @testset "Add layers" begin
        oas = Oasis()
        add_layer!(oas, :M0, 1, 0)
        add_layer!(oas, Layer("V0", 1, 1))
        add_layer!(oas, Layer("V0", OasisTools.Interval(2, 3), 2))
        @test_throws Exception add_layer!(oas, :M0, OasisTools.Interval(1, 2), OasisTools.Interval(0, 1))
    end
    @testset "Add shapes" begin
        oas = Oasis()
        add_cell!(oas, :TOP)
        cell = oas[:TOP]
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))

        # Direct Shape argument
        s = Shape(rect, UInt64(1), UInt64(0), nothing)
        add_shape!(cell, s)
        @test length(shapes(cell)) == 1
        @test shapes(cell)[1] === s

        # Convenience overload
        rect2 = Rect{2, Int64}(Point{2, Int64}(20, 20), Point{2, Int64}(30, 30))
        add_shape!(cell, rect2, 2, 0)
        @test length(shapes(cell)) == 2
        @test shapes(cell)[2].layer == UInt64(2)
        @test shapes(cell)[2].datatype == UInt64(0)

        # With repetition
        rect3 = Rect{2, Int64}(Point{2, Int64}(40, 40), Point{2, Int64}(50, 50))
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(100, 0)]
        add_shape!(cell, rect3, 1, 0; repetition=rep)
        @test length(shapes(cell)) == 3
        @test shapes(cell)[3].repetition == rep
    end
    @testset "Polygons with holes" begin
        # OASIS polygons can't have holes; they used to be dropped silently when writing.
        holed = Polygon(
            Point{2, Int64}[(0, 0), (10, 0), (10, 10), (0, 10)], [Point{2, Int64}[(2, 2), (4, 2), (4, 4)]]
        )
        oas = Oasis()
        add_cell!(oas, :A)
        @test_throws ArgumentError add_shape!(oas[:A], holed, 1, 0)
        # Shapes added by other means are caught when writing.
        push!(oas[:A].shapes, Shape(holed, UInt64(1), UInt64(0), nothing))
        @test_throws ArgumentError oasiswrite(tempname(), oas)
    end
    @testset "Looking up cells" begin
        oas = Oasis()
        add_cell!(oas, :A)
        @test name(oas[:A]) == :A
        @test name(oas["A"]) == :A
        @test_throws KeyError oas[:B]
        @test haskey(oas, :A)
        @test !haskey(oas, :B)
        @test isnothing(get(oas, :B, nothing))
        @test name(get(oas, "A", nothing)) == :A
    end
    @testset "Add placements" begin
        oas = Oasis()
        add_cell!(oas, :TOP)
        add_cell!(oas, :BOT)
        cell = oas[:TOP]

        # Direct CellPlacement argument
        p = CellPlacement(:BOT, Point{2, Int64}(100, 200), 0.0, 1.0, false, nothing)
        add_placement!(cell, p)
        @test length(placements(cell)) == 1
        @test placements(cell)[1] === p

        # Convenience overload
        add_placement!(cell, :BOT, Point{2, Int64}(300, 400); rotation=90.0)
        @test length(placements(cell)) == 2
        @test placements(cell)[2].rotation == 90.0
        @test placements(cell)[2].cell == :BOT
    end
    @testset "Remove cells" begin
        oas = Oasis()
        add_cell!(oas, :A)
        add_cell!(oas, :B)
        add_cell!(oas, :C)
        @test length(cell_names(oas)) == 3

        remove_cell!(oas, :B)
        @test length(cell_names(oas)) == 2
        @test :B ∉ cell_names(oas)
        @test :A ∈ cell_names(oas)
        @test :C ∈ cell_names(oas)

        @test_throws Exception remove_cell!(oas, :NONEXISTENT)
    end
    @testset "Removing a cell removes its placements" begin
        oas = Oasis()
        add_cell!(oas, :TOP)
        add_cell!(oas, :BOT)
        add_placement!(oas[:TOP], :BOT, Point{2, Int64}(0, 0))
        add_placement!(oas[:TOP], :BOT, Point{2, Int64}(100, 0))
        @test length(placements(oas[:TOP])) == 2

        remove_cell!(oas, :BOT)
        @test :BOT ∉ cell_names(oas)
        @test isempty(placements(oas[:TOP]))
    end
    @testset "Filter shapes" begin
        oas = Oasis()
        add_cell!(oas, :TOP)
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        add_shape!(oas[:TOP], rect, 1, 0)
        add_shape!(oas[:TOP], rect, 2, 0)
        add_shape!(oas[:TOP], rect, 1, 0)
        @test length(shapes(oas[:TOP])) == 3

        filter_shapes!(s -> s.layer != 1, oas)
        @test length(shapes(oas[:TOP])) == 1
        @test shapes(oas[:TOP])[1].layer == UInt64(2)
    end
    @testset "Merge files" begin
        oas = Oasis()
        add_cell!(oas, :TOP1)
        add_layer!(oas, :M0, 1, 0)
        add_layer!(oas, :V0, 2, 0)
        oas2 = Oasis()
        add_cell!(oas2, :TOP1)
        add_cell!(oas2, :TOP2)
        add_placement!(oas2[:TOP2], :TOP1, Point{2, Int64}(0, 0))
        add_layer!(oas2, :Metal0, 1, 0)
        add_layer!(oas2, :V0, 2, 0)

        # Clashing cell names are an error, and leave everything untouched.
        @test_throws ErrorException merge_oases!(oas, oas2)
        @test cell_names(oas) == [:TOP1]

        # Renaming resolves the clash, placements included.
        rename_cell!(oas2, :TOP1, :TOP1_B)
        @test only(placements(oas2[:TOP2])).cell == :TOP1_B
        merged = merge_oases(oas, oas2)
        @test cell_names(merged) == [:TOP1, :TOP1_B, :TOP2]
        @test roots(merged) == [:TOP1, :TOP2]
        # Layers from both sides are kept, without duplicates.
        @test name.(layers(merged)) == [:M0, :V0, :Metal0]

        # The originals are left untouched.
        add_shape!(merged[:TOP2], Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(1, 1)), 1, 0)
        @test isempty(shapes(oas2[:TOP2]))
        @test cell_names(oas) == [:TOP1]

        # Different database units are an error.
        @test_throws ErrorException merge_oases(oas, Oasis(; unit = 2000))
    end
end
