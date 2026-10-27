function read_and_reset(state, nbytes::Integer)
    l = state.buf[1:nbytes]
    state.pos = 1
    return l
end

function write_and_read(write_function, read_function, value; reader_type = FileParserState)
    writer_state = OasisTools.WriterState(tempname(), 1024)
    write_function(writer_state, value)
    reader_state = reader_type(writer_state.buf)
    @test read_function(reader_state) == value
end

@testset "Write data" begin
    @testset "Write bytes" begin
        state = OasisTools.WriterState(tempname(), 16)
        bytes = rand(UInt8, 16)
        OasisTools.write_bytes(state, bytes)
        @test state.pos == 1
        bytes = rand(UInt8, 17)
        OasisTools.write_bytes(state, bytes)
        @test state.pos == 2
        bytes = rand(UInt8, 174)
        OasisTools.write_bytes(state, bytes)
        @test state.pos == 16
    end
    @testset "Write unsigned integers" begin
        write_and_read(OasisTools.wui, OasisTools.rui, 0)
        write_and_read(OasisTools.wui, OasisTools.rui, 127)
        write_and_read(OasisTools.wui, OasisTools.rui, 128)
        write_and_read(OasisTools.wui, OasisTools.rui, 16383)
        write_and_read(OasisTools.wui, OasisTools.rui, 16384)
    end
    @testset "Write signed integers" begin
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, 0)
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, 1)
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, -1)
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, 63)
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, -64)
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, 8191)
        write_and_read(OasisTools.write_signed_integer, OasisTools.read_signed_integer, -8192)
    end
    @testset "Write reals" begin
        write_and_read(OasisTools.write_real, OasisTools.read_real, 0.0)
        write_and_read(OasisTools.write_real, OasisTools.read_real, 1.0)
        write_and_read(OasisTools.write_real, OasisTools.read_real, -1.0)
        write_and_read(OasisTools.write_real, OasisTools.read_real, -2/13)
    end
    @testset "Write strings" begin
        write_and_read(OasisTools.write_bn_string, OasisTools.read_string, "abc")
        write_and_read(OasisTools.write_bn_string, OasisTools.read_string, "")
        @test_logs (
            :warn,
            "Non-printable ASCII characters detected. Other software may not be able to read your output file."
        ) OasisTools.write_bn_string(OasisTools.WriterState(tempname(), 1024), "↑")
    end
    @testset "Write g-deltas" begin
        write_and_read(OasisTools.write_g_delta, OasisTools.read_g_delta, Point{2, Int64}(122, 61))
        write_and_read(OasisTools.write_g_delta, OasisTools.read_g_delta, Point{2, Int64}(-46, -46))
        write_and_read(OasisTools.write_g_delta, OasisTools.read_g_delta, Point{2, Int64}(-46, -987))
    end
    @testset "Write repetitions" begin
        # A repetition covers at least two instances; absence is expressed with `nothing`.
        @test_throws ArgumentError OasisTools.write_repetition(
            OasisTools.WriterState(tempname(), 1024), Point{2, Int64}[]
        )
        # Writing the same repetition twice falls back on the modal variable the second time.
        let rep = Point{2, Int64}[(0, 0), (10, 0), (20, 0)]
            state = OasisTools.WriterState(tempname(), 1024)
            OasisTools.write_repetition(state, rep)
            nbytes = state.pos - 1
            OasisTools.write_repetition(state, rep)
            @test state.pos - 1 == nbytes + 1
            @test state.buf[nbytes + 1] == 0x00
        end
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, PointGridRange((0, 0), 130, 129, (1, 0), (0, 1)); reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, PointGridRange((0, 0), 130, 1, (127, 0), (1, 1)); reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, Point{2, Int64}[(0, 0), (127, 0), (128, 0), (255, 0)]; reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, Point{2, Int64}[(0, 0), (254, 0), (256, 0), (510, 0)]; reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, Point{2, Int64}[(0, 0), (0, 127), (0, 128), (0, 255)]; reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, Point{2, Int64}[(0, 0), (0, 254), (0, 256), (0, 510)]; reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, PointGridRange((0, 0), 130, 129, (122, 61), (10, 0)); reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, PointGridRange((0, 0), 3, 1, (122, 61), (1, 1)); reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, Point{2, Int64}[(0, 0), (122, 61), (244, 122)]; reader_type = CellParserState)
        write_and_read(OasisTools.write_repetition, OasisTools.read_repetition, Point{2, Int64}[(0, 0), (244, 122), (488, 244)]; reader_type = CellParserState)
    end
    @testset "Write intervals" begin
        write_and_read(OasisTools.write_interval, OasisTools.read_interval, OasisTools.Interval(128, 128))
        write_and_read(OasisTools.write_interval, OasisTools.read_interval, OasisTools.Interval(128, typemax(UInt64)))
        write_and_read(OasisTools.write_interval, OasisTools.read_interval, OasisTools.Interval(128, 256))
    end
end
