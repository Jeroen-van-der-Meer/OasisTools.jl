@testset "Validate placements" begin
    oas = Oasis()
    add_cell!(oas, :TOP)
    cell = oas[:TOP]

    # Add a dangling placement
    add_placement!(cell, :MISSING, Point{2, Int64}(0, 0))

    warnings = validate_placements(oas)
    @test length(warnings) == 1
    @test contains(warnings[1], "MISSING")

    # Fix by adding the missing cell
    add_cell!(oas, :MISSING)
    @test isempty(validate_placements(oas))
end
