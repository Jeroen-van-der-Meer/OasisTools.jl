function wui(state, int::Unsigned) # write_unsigned_integer; using shorthand since this function is used often
    more_bytes_needed = true
    while more_bytes_needed
        b = UInt8(int & 0x7f)
        int >>= 7
        if iszero(int)
            more_bytes_needed = false
        else
            b |= 0x80 # Use first bit to mark that there are more bytes to come
        end
        write_byte(state, b)
    end
end

function wui(state, int::Integer)
    @assert int >= 0
    wui(state, unsigned(int))
end

function write_signed_integer(state, int::Integer)
    is_neg = int < 0
    uint = is_neg ? unsigned(-int) : unsigned(int)
    b = UInt8((uint & 0x3f) << 1)
    b |= is_neg # Use the last bit to indicate whether the represented number is negative
    uint >>= 6
    if iszero(uint)
        write_byte(state, b)
        return
    else
        b |= 0x80 # Use first bit to mark that there are more bytes to come
        write_byte(state, b)
        wui(state, uint)
    end
end

function write_real(state, real::Real)
    real_rounded = round(Int64, real)
    if real_rounded == real
        if real >= 0
            # Write positive whole number
            write_byte(state, 0x00)
            wui(state, real_rounded)
        else
            # Write negative whole number
            write_byte(state, 0x01)
            wui(state, -real_rounded)
        end
    else
        # Write Float64
        write_byte(state, 0x07)
        write_bytes(state, reinterpret(UInt64, real))
    end
end

write_a_string(state, symbol::Symbol) = write_a_string(state, String(symbol))
function write_a_string(state, string::AbstractString) # a-string
    bytes = codeunits(string)
    nbytes = length(bytes)
    if !all(0x20 .<= bytes .<= 0x7e)
        @warn "Non-printable ASCII characters detected. Other software may not be able to read your output file."
    end
    wui(state, nbytes)
    write_bytes(state, bytes, nbytes)
end

write_bn_string(state, symbol::Symbol) = write_bn_string(state, String(symbol))
function write_bn_string(state, string::AbstractString) # b-string and n-string
    bytes = codeunits(string)
    nbytes = length(bytes)
    if !all(0x21 .<= bytes .<= 0x7e)
        @warn "Non-printable ASCII characters detected. Other software may not be able to read your output file."
    end
    wui(state, nbytes)
    write_bytes(state, bytes, nbytes)
end

function write_g_delta(state, value::Point{2, Int64})
    # The last bit of the first byte of a g-delta indicates that it will consist of a pair of
    # unsigned integers. We encode this bit by shifting the first value of the g-delta to the
    # left. This is why we store 2x + 1.
    x = value[1]
    x >= 0 ? wui(state, 4x + 1) : wui(state, -4x + 3)
    y = value[2]
    y >= 0 ? wui(state, 2y) : wui(state, -2y + 1)
end

function write_repetition_type_0(state)
    write_byte(state, 0)
end

function write_repetition_type_8(state, value::PointGridRange)
    write_byte(state, 8)
    wui(state, value.nstepx - 2)
    wui(state, value.nstepy - 2)
    write_g_delta(state, value.stepx)
    write_g_delta(state, value.stepy)
end

function write_repetition_type_9(state, value::PointGridRange)
    write_byte(state, 9)
    if value.nstepx == 1
        wui(state, value.nstepy - 2)
        write_g_delta(state, value.stepy)
    elseif value.nstepy == 1
        wui(state, value.nstepx - 2)
        write_g_delta(state, value.stepx)
    else
        error("Cannot store PointGridRange as repetition of specified type")
    end
end

function write_repetition_type_10(state, value::Vector{Point{2, Int64}})
    write_byte(state, 10)
    nrep = length(value)
    wui(state, nrep - 2)
    @inbounds for i = 2:nrep
        write_g_delta(state, value[i] - value[i - 1])
    end
end

function write_repetition(state, value::PointGridRange)
    if value == state.mod.repetition
        write_repetition_type_0(state)
    elseif (value.nstepx == 1) || (value.nstepy == 1)
        write_repetition_type_9(state, value)
        state.mod.repetition = value
    else
        write_repetition_type_8(state, value)
        state.mod.repetition = value
    end
end

function write_repetition(state, value::Vector{Point{2, Int64}})
    if value == state.mod.repetition
        write_repetition_type_0(state)
    else
        write_repetition_type_10(state, value)
        state.mod.repetition = value
    end
end

function write_point_list(state, points::Vector{Point{2, Int64}})
    # Write as g-delta list (type 4). Points are absolute coordinates; we delta-encode them.
    # The first element is the implicit origin (0,0) added by read_point_list, so vertex_count
    # excludes it.
    write_byte(state, 0x04)
    wui(state, length(points) - 1)
    @inbounds for i in 2:length(points)
        write_g_delta(state, points[i] - points[i - 1])
    end
end

function write_property_value(state, value::Symbol)
    # Warning: We're storing the property value as an n-string because that's what S_TOP_CELL
    # expects. That said, other properties may require an a-string or b-string instead.
    write_byte(state, 0x0c)
    write_bn_string(state, value)
end

function write_interval_type_3(state, interval)
    write_byte(state, 3)
    wui(state, interval.low)
end

function write_interval_type_2(state, interval)
    write_byte(state, 2)
    wui(state, interval.low)
end

function write_interval_type_4(state, interval)
    write_byte(state, 4)
    wui(state, interval.low)
    wui(state, interval.high)
end

function write_interval(state, interval::Interval)
    if interval.low == interval.high
        write_interval_type_3(state, interval)
    elseif interval.high == typemax(UInt64)
        write_interval_type_2(state, interval)
    else
        write_interval_type_4(state, interval)
    end
end

function write_cblock(write_fn::Function, state::WriterState)
    io_temp = IOBuffer()
    temp_state = WriterState(io_temp, state)

    write_fn(temp_state)

    # Flush remaining bytes in temp buffer to the IOBuffer
    if temp_state.pos > 1
        write(io_temp, @view temp_state.buf[1:(temp_state.pos - 1)])
    end

    uncomp_bytes = take!(io_temp)
    comp_bytes = transcode(DeflateCompressor, uncomp_bytes)

    write_byte(state, 34)                       # CBLOCK record type
    wui(state, UInt64(0))                       # comp_type = DEFLATE
    wui(state, UInt64(length(uncomp_bytes)))    # uncompressed byte count
    wui(state, UInt64(length(comp_bytes)))      # compressed byte count
    write_bytes(state, comp_bytes, length(comp_bytes))
end

function write_bytes(state, bytes::AbstractVector{UInt8}, nbytes::Integer = length(bytes))
    count = 0
    while true
        writeable = state.bufsize - state.pos + 1
        # If there's enough space, simply write out all bytes into the buffer.
        if writeable > nbytes - count
            @inbounds state.buf[state.pos:(state.pos + nbytes - count - 1)] .=
                bytes[(count + 1):end]
            state.pos += nbytes - count
            return
        # If not, write out until the end of the buffer, flush the buffer, then continue.
        else
            @inbounds state.buf[state.pos:(state.pos + writeable - 1)] .=
                bytes[(count + 1):(count + writeable)]
            write_buffer(state)
            count += writeable
        end
    end
end

function write_bytes(state, uint::UInt64)
    b = UInt8(uint & 0xff)
    write_byte(state, b)
    for _ in 1:7
        uint >>= 8
        b = UInt8(uint & 0xff)
        write_byte(state, b)
    end
end

write_byte(state, byte::Integer) = write_byte(state, UInt8(byte))

function write_byte(state, byte::UInt8)
    @inbounds state.buf[state.pos] = byte
    if state.pos == state.bufsize
        write_buffer(state)
    else
        state.pos += 1
    end
end

function write_buffer(state)
    write(state.io, state.buf)
    state.pos = 1
end
