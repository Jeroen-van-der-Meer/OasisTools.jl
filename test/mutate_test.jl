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
        @test shapes(cell)[2].layerNumber == UInt64(2)
        @test shapes(cell)[2].datatypeNumber == UInt64(0)

        # With repetition
        rect3 = Rect{2, Int64}(Point{2, Int64}(40, 40), Point{2, Int64}(50, 50))
        rep = [Point{2, Int64}(0, 0), Point{2, Int64}(100, 0)]
        add_shape!(cell, rect3, 1, 0; repetition=rep)
        @test length(shapes(cell)) == 3
        @test shapes(cell)[3].repetition == rep
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
        @test placements(cell)[2].cellName == :BOT
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
    @testset "Remove cells with cascade" begin
        oas = Oasis()
        add_cell!(oas, :TOP)
        add_cell!(oas, :BOT)
        add_placement!(oas[:TOP], :BOT, Point{2, Int64}(0, 0))
        add_placement!(oas[:TOP], :BOT, Point{2, Int64}(100, 0))
        @test length(placements(oas[:TOP])) == 2

        remove_cell!(oas, :BOT; cascade=true)
        @test :BOT ∉ cell_names(oas)
        @test isempty(placements(oas[:TOP]))
    end
    @testset "Remove layers" begin
        oas = Oasis()
        add_layer!(oas, :M0, 1, 0)
        add_layer!(oas, :V0, 2, 0)
        add_layer!(oas, :M1, 3, 0)
        @test length(layers(oas)) == 3

        # Remove by name
        remove_layer!(oas, :V0)
        @test length(layers(oas)) == 2
        @test isnothing(layer(oas, :V0))

        # Remove by numbers
        remove_layer!(oas, 3, 0)
        @test length(layers(oas)) == 1
        @test name(layer(oas, 1, 0)) == :M0

        @test_throws Exception remove_layer!(oas, :NONEXISTENT)
        @test_throws Exception remove_layer!(oas, 99, 99)
    end
    @testset "Remove layers with cascade" begin
        oas = Oasis()
        add_cell!(oas, :TOP)
        add_layer!(oas, :M0, 1, 0)
        add_layer!(oas, :V0, 2, 0)
        rect = Rect{2, Int64}(Point{2, Int64}(0, 0), Point{2, Int64}(10, 10))
        add_shape!(oas[:TOP], rect, 1, 0)
        add_shape!(oas[:TOP], rect, 2, 0)
        add_shape!(oas[:TOP], rect, 1, 0)
        @test length(shapes(oas[:TOP])) == 3

        remove_layer!(oas, :M0; cascade=true)
        @test length(shapes(oas[:TOP])) == 1
        @test shapes(oas[:TOP])[1].layerNumber == UInt64(2)
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
