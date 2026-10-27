@testset "Read data" begin
    @testset "Read unsigned integers" begin
        @test OasisTools.rui(FileParserState([0x00])) == 0
        @test OasisTools.rui(FileParserState([0x7f])) == 127
        @test OasisTools.rui(FileParserState([0x80, 0x01])) == 128
        @test OasisTools.rui(FileParserState([0xff, 0x7f])) == 16383
        @test OasisTools.rui(FileParserState([0x80, 0x80, 0x01])) == 16384
        @test @inferred(OasisTools.rui(FileParserState([0x80, 0x01]))) === UInt64(128)
    end
    @testset "Read signed integers" begin
        @test OasisTools.read_signed_integer(FileParserState([0x00])) == 0
        @test OasisTools.read_signed_integer(FileParserState([0x02])) == 1
        @test OasisTools.read_signed_integer(FileParserState([0x03])) == -1
        @test OasisTools.read_signed_integer(FileParserState([0x7e])) == 63
        @test OasisTools.read_signed_integer(FileParserState([0x81, 0x01])) == -64
        @test OasisTools.read_signed_integer(FileParserState([0xfe, 0x7f])) == 8191
        @test OasisTools.read_signed_integer(FileParserState([0x81, 0x80, 0x01])) == -8192
    end
    @testset "Read reals" begin
        @test OasisTools.read_real(FileParserState([0x00, 0x00])) == 0.0
        @test OasisTools.read_real(FileParserState([0x00, 0x01])) == 1.0
        @test OasisTools.read_real(FileParserState([0x03, 0x02])) == -0.5
        @test OasisTools.read_real(FileParserState([0x04, 0x05, 0x10])) == 0.3125
        @test OasisTools.read_real(FileParserState([0x02, 0x03])) == 1/3
        @test OasisTools.read_real(FileParserState([0x05, 0x02, 0x0d])) == -2/13
        # In line below, LHS outputs Float64. Conversion to Float32 needed due to inherently
        # limited precision.
        @test OasisTools.read_real(FileParserState([0x06, 0xd9, 0x89, 0x1d, 0xbe])) == Float32(-2/13)
        @test OasisTools.read_real(FileParserState([0x07, 0x14, 0x3b, 0xb1, 0x13, 0x3b, 0xb1, 0xc3, 0xbf])) == -2/13
        # Every format must produce a Float64, otherwise read_real is type unstable.
        @test OasisTools.read_real(FileParserState([0x00, 0x01])) isa Float64
        @test OasisTools.read_real(FileParserState([0x01, 0x01])) isa Float64
        @test OasisTools.read_real(FileParserState([0x02, 0x03])) isa Float64
        @test OasisTools.read_real(FileParserState([0x03, 0x02])) isa Float64
        @test OasisTools.read_real(FileParserState([0x04, 0x05, 0x10])) isa Float64
        @test OasisTools.read_real(FileParserState([0x05, 0x02, 0x0d])) isa Float64
        @test OasisTools.read_real(FileParserState([0x06, 0xd9, 0x89, 0x1d, 0xbe])) isa Float64
        @test OasisTools.read_real(
            FileParserState([0x07, 0x14, 0x3b, 0xb1, 0x13, 0x3b, 0xb1, 0xc3, 0xbf])
        ) isa Float64
    end
    @testset "Read strings" begin
        @test OasisTools.read_string(FileParserState([0x03, 0x61, 0x62, 0x63, 0x64])) == "abc"
        @test OasisTools.read_string(FileParserState([0x00, 0xff])) == ""
    end
    @testset "Read 2-deltas" begin
        @test OasisTools.read_2_delta(FileParserState([0x98, 0x2a])) == Point{2, Int64}(1350, 0)
        @test OasisTools.read_2_delta(FileParserState([0x9b, 0x2a])) == Point{2, Int64}(0, -1350)
    end
    @testset "Read 3-deltas" begin
        @test OasisTools.read_3_delta(FileParserState([0xcd, 0x01])) == Point{2, Int64}(-25, 25)
        @test OasisTools.read_3_delta(FileParserState([0xd7, 0x07])) == Point{2, Int64}(122, -122)
    end
    @testset "Read g-deltas" begin
        @test OasisTools.read_g_delta(FileParserState([0xe9, 0x03, 0x7a])) == Point{2, Int64}(122, 61)
        @test OasisTools.read_g_delta(FileParserState([0xec, 0x05])) == Point{2, Int64}(-46, -46)
        @test OasisTools.read_g_delta(FileParserState([0xbb, 0x01, 0xb7, 0x0f])) == Point{2, Int64}(-46, -987)
    end
    @testset "Read point lists" begin
        @test OasisTools.read_point_list(FileParserState([0x00, 0x04, 0x0c, 0x08, 0x11, 0x05])) ==
            Point{2, Int64}[(0, 0), (6, 0), (0, 4), (-8, 0), (0, -2)]
        @test OasisTools.read_point_list(FileParserState([0x01, 0x04, 0x11, 0x04, 0x04, 0x04])) ==
            Point{2, Int64}[(0, 0), (0, -8), (2, 0), (0, 2), (2, 0)]
        @test OasisTools.read_point_list(FileParserState([0x02, 0x05, 0x20, 0x19, 0x12, 0x0b, 0x12])) ==
            Point{2, Int64}[(0, 0), (8, 0), (0, 6), (-4, 0), (0, -2), (-4, 0)]
        @test OasisTools.read_point_list(FileParserState([0x03, 0x04, 0x15, 0x21, 0x30, 0x13])) ==
            Point{2, Int64}[(0, 0), (-2, 2), (0, 4), (6, 0), (0, -2)]
        @test OasisTools.read_point_list(FileParserState([0x04, 0x02, 0x44, 0x09, 0x0d])) ==
            Point{2, Int64}[(0, 0), (-4, 0), (2, -6)]
        @test OasisTools.read_point_list(FileParserState([
            0x05, 0x09, 0x01, 0x03, 0x29,
            0x00, 0x01, 0x04, 0x01, 0x03,
            0x01, 0x03, 0x2b, 0x04, 0x2b,
            0x00, 0x01, 0x03, 0x01, 0x03
        ])) == Point{2, Int64}[
            (0, 0), (0, -1), (10, -1), (10, 1), (10, 0),
            (10, -1), (0, 1), (-10, 1), (-10, 0), (-10, -1)
        ]
    end
    @testset "Read repetitions" begin
        # Type 0 reuses the modal repetition, which starts out unset.
        @test isnothing(OasisTools.read_repetition(CellParserState([0x00])))
        @test OasisTools.read_repetition(CellParserState([0x01, 0x80, 0x01, 0x7f, 0x01, 0x01])) ==
            PointGridRange((0, 0), 130, 129, (1, 0), (0, 1))
        @test OasisTools.read_repetition(CellParserState([0x02, 0x80, 0x01, 0x7f, 0x01, 0x01])) ==
            PointGridRange((0, 0), 130, 1, (127, 0), (1, 1))
        @test OasisTools.read_repetition(CellParserState([0x03, 0x80, 0x01, 0x7f, 0x01, 0x01])) ==
            PointGridRange((0, 0), 130, 1, (0, 127), (1, 1))
        @test OasisTools.read_repetition(CellParserState([0x04, 0x02, 0x7f, 0x01, 0x7f, 0x01])) ==
            Point{2, Int64}[(0, 0), (127, 0), (128, 0), (255, 0)]
        @test OasisTools.read_repetition(CellParserState([0x05, 0x02, 0x02, 0x7f, 0x01, 0x7f, 0x01])) ==
            Point{2, Int64}[(0, 0), (254, 0), (256, 0), (510, 0)]
        @test OasisTools.read_repetition(CellParserState([0x06, 0x02, 0x7f, 0x01, 0x7f, 0x01])) ==
            Point{2, Int64}[(0, 0), (0, 127), (0, 128), (0, 255)]
        @test OasisTools.read_repetition(CellParserState([0x07, 0x02, 0x02, 0x7f, 0x01, 0x7f, 0x01])) ==
            Point{2, Int64}[(0, 0), (0, 254), (0, 256), (0, 510)]
        @test OasisTools.read_repetition(CellParserState([0x08, 0x80, 0x01, 0x7f, 0xe9, 0x03, 0x7a, 0xa0, 0x01])) ==
            PointGridRange((0, 0), 130, 129, (122, 61), (10, 0))
        @test OasisTools.read_repetition(CellParserState([0x09, 0x01, 0xe9, 0x03, 0x7a])) ==
            PointGridRange((0, 0), 3, 1, (122, 61), (1, 1))
        @test OasisTools.read_repetition(CellParserState([0x0a, 0x01, 0xe9, 0x03, 0x7a, 0xe9, 0x03, 0x7a])) ==
            Point{2, Int64}[(0, 0), (122, 61), (244, 122)]
        @test OasisTools.read_repetition(CellParserState([0x0b, 0x01, 0x02, 0xe9, 0x03, 0x7a, 0xe9, 0x03, 0x7a])) ==
            Point{2, Int64}[(0, 0), (244, 122), (488, 244)]
    end
    @testset "Read intervals" begin
        @test OasisTools.read_interval(FileParserState([0x00, 0x80, 0x01, 0x80, 0x02])) == OasisTools.Interval(0, typemax(UInt64))
        @test OasisTools.read_interval(FileParserState([0x01, 0x80, 0x01, 0x80, 0x02])) == OasisTools.Interval(0, 128)
        @test OasisTools.read_interval(FileParserState([0x02, 0x80, 0x01, 0x80, 0x02])) == OasisTools.Interval(128, typemax(UInt64))
        @test OasisTools.read_interval(FileParserState([0x03, 0x80, 0x01, 0x80, 0x02])) == OasisTools.Interval(128, 128)
        @test OasisTools.read_interval(FileParserState([0x04, 0x80, 0x01, 0x80, 0x02])) == OasisTools.Interval(128, 256)
    end
end

@testset "Point grid range" begin
    p = PointGridRange((1, 1), 3, 2, (1, 1), (0, 2))
    @test length(p) == 6
    @test first(p) == Point{2, Int64}(1, 1)
    @test last(p) == Point{2, Int64}(3, 5)
    @test size(p) == (3, 2)
    @test_throws BoundsError p[0]
    @test p[1] == p[1, 1] == Point{2, Int64}(1, 1)
    @test p[2] == p[2, 1] == Point{2, Int64}(2, 2)
    @test p[3] == p[3, 1] == Point{2, Int64}(3, 3)
    @test p[4] == p[1, 2] == Point{2, Int64}(1, 3)
    @test_throws BoundsError p[7]
    @test_throws BoundsError p[4, 1]
    @test_throws BoundsError p[1, 3]
    @test_throws BoundsError p[0]
    @test collect(p) == [p[1], p[2], p[3], p[4], p[5], p[6]]
end
