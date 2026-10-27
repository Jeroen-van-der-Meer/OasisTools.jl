function rui(state) # read_unsigned_integer; using shorthand since this function is used often
    output = UInt64(0)
    shift = 0
    while true
        b = read_byte(state)
        output |= UInt64(b & 0x7F) << shift
        b & 0x80 == 0 && break
        shift += 7
    end
    return output
end

function unsigned_to_signed(x::UInt64)
    sign = x & one(UInt64)
    output = signed(x >> 1)
    iszero(sign) ? output : -output
end

function read_signed_integer(state)
    unsigned_output = rui(state)
    return unsigned_to_signed(unsigned_output)
end

# Every branch returns Float64 so that `read_real` is type stable.
read_positive_whole_number(state) = Float64(rui(state))
read_negative_whole_number(state) = -Float64(rui(state))
read_positive_reciprocal(state) = 1 / rui(state)
read_negative_reciprocal(state) = -1 / rui(state)
read_positive_ratio(state) = read_positive_whole_number(state) / read_positive_whole_number(state)
read_negative_ratio(state) = read_negative_whole_number(state) / read_positive_whole_number(state)
read_four_byte_float(state) = Float64(read(IOBuffer(read_bytes(state, 4)), Float32))
read_eight_byte_float(state) = read(IOBuffer(read_bytes(state, 8)), Float64)

function read_real(state, format::UInt8)
    format == 0 && return read_positive_whole_number(state)
    format == 1 && return read_negative_whole_number(state)
    format == 2 && return read_positive_reciprocal(state)
    format == 3 && return read_negative_reciprocal(state)
    format == 4 && return read_positive_ratio(state)
    format == 5 && return read_negative_ratio(state)
    format == 6 && return read_four_byte_float(state)
    format == 7 && return read_eight_byte_float(state)
    parse_error(state, "Unknown real format $format")
end

function read_real(state)
    format = read_byte(state)
    return read_real(state, format)
end

function read_string(state)
    length = rui(state)
    s = read_bytes(state, length)
    return String(s)
end

function read_symbol(state)
    length = rui(state)
    s = read_bytes(state, length)
    return Symbol(s)
end

function read_1_delta(state, dir)
    # dir 0: east/west; dir 1: north/south
    mag = read_signed_integer(state)
    return iszero(dir) ? Point{2, Int64}(mag, 0) : Point{2, Int64}(0, mag)
end

east_integer(mag::UInt64) = Point{2, Int64}(signed(mag), 0)
north_integer(mag::UInt64) = Point{2, Int64}(0, signed(mag))
west_integer(mag::UInt64) = Point{2, Int64}(-signed(mag), 0)
south_integer(mag::UInt64) = Point{2, Int64}(0, -signed(mag))
northeast_integer(mag::UInt64) = Point{2, Int64}(signed(mag), signed(mag))
northwest_integer(mag::UInt64) = Point{2, Int64}(-signed(mag), signed(mag))
southwest_integer(mag::UInt64) = Point{2, Int64}(-signed(mag), -signed(mag))
southeast_integer(mag::UInt64) = Point{2, Int64}(signed(mag), -signed(mag))

function read_delta(dir::UInt64, magnitude::UInt64)
    dir == 0 && return east_integer(magnitude)
    dir == 1 && return north_integer(magnitude)
    dir == 2 && return west_integer(magnitude)
    dir == 3 && return south_integer(magnitude)
    dir == 4 && return northeast_integer(magnitude)
    dir == 5 && return northwest_integer(magnitude)
    dir == 6 && return southwest_integer(magnitude)
    dir == 7 && return southeast_integer(magnitude)
    throw(OasisParseError("Unknown delta direction $dir", 0))
end

function read_2_delta(Δ::UInt64)
    dir = Δ & 0x03 # Last 2 bits
    magnitude = Δ >> 2 # Remaining bits
    return read_delta(dir, magnitude)
end

read_2_delta(state) = read_2_delta(rui(state))

function read_3_delta(Δ::UInt64)
    dir = Δ & 0x07 # Last 3 bits
    magnitude = Δ >> 3 # Remaining bits
    return read_delta(dir, magnitude)
end

read_3_delta(state) = read_3_delta(rui(state))

function read_g_delta(state)
    Δ = rui(state)
    form = Δ & 0x01 # Last bit
    Δ >>= 1
    # g-delta comes in two forms
    if form == 0x00
        return read_3_delta(Δ) # Remaining bits to be read out as 3-delta
    else
        Δ2 = rui(state)
        return Point{2, Int64}(unsigned_to_signed(Δ), unsigned_to_signed(Δ2))
    end
end

function collect_repetitions_x(state, nrep; grid::Int64 = 1)
    l = Vector{Point{2, Int64}}(undef, nrep)
    l[1] = Point{2, Int64}(0, 0)
    @inbounds for i = 2:nrep
        l[i] = Point{2, Int64}(rui(state), 0) + l[i - 1]
    end
    l .*= grid
    return l
end

function collect_repetitions_y(state, nrep; grid::Int64 = 1)
    l = Vector{Point{2, Int64}}(undef, nrep)
    l[1] = Point{2, Int64}(0, 0)
    @inbounds for i = 2:nrep
        l[i] = Point{2, Int64}(0, rui(state)) + l[i - 1]
    end
    l .*= grid
    return l
end

function collect_repetitions_g(state, nrep; grid::Int64 = 1)
    l = Vector{Point{2, Int64}}(undef, nrep)
    l[1] = Point{2, Int64}(0, 0)
    @inbounds for i = 2:nrep
        l[i] = read_g_delta(state) + l[i - 1]
    end
    l .*= grid
    return l
end

read_repetition_type_0(state) = state.mod.repetition
read_repetition_type_1(state) = PointGridRange((0, 0), rui(state) + 2, rui(state) + 2, (rui(state), 0), (0, rui(state)))
read_repetition_type_2(state) = PointGridRange((0, 0), rui(state) + 2, 1, (rui(state), 0), (1, 1))
read_repetition_type_3(state) = PointGridRange((0, 0), rui(state) + 2, 1, (0, rui(state)), (1, 1))
read_repetition_type_4(state) = collect_repetitions_x(state, rui(state) + 2)
read_repetition_type_5(state) = collect_repetitions_x(state, rui(state) + 2; grid = signed(rui(state)))
read_repetition_type_6(state) = collect_repetitions_y(state, rui(state) + 2)
read_repetition_type_7(state) = collect_repetitions_y(state, rui(state) + 2; grid = signed(rui(state)))
read_repetition_type_8(state) = PointGridRange((0, 0), rui(state) + 2, rui(state) + 2, read_g_delta(state), read_g_delta(state))
read_repetition_type_9(state) = PointGridRange((0, 0), rui(state) + 2, 1, read_g_delta(state), (1, 1))
read_repetition_type_10(state) = collect_repetitions_g(state, rui(state) + 2)
read_repetition_type_11(state) = collect_repetitions_g(state, rui(state) + 2; grid = signed(rui(state)))

function read_repetition(state::CellParserState)
    type = read_byte(state)
    # Ordering is changed based on what appears to be used most often in practice.
    type == 0  && return read_repetition_type_0(state)
    type == 1  && return read_repetition_type_1(state)
    type == 8  && return read_repetition_type_8(state)
    type == 2  && return read_repetition_type_2(state)
    type == 3  && return read_repetition_type_3(state)
    type == 11 && return read_repetition_type_11(state)
    type == 10 && return read_repetition_type_10(state)
    type == 9  && return read_repetition_type_9(state)
    type == 4  && return read_repetition_type_4(state)
    type == 5  && return read_repetition_type_5(state)
    type == 6  && return read_repetition_type_6(state)
    type == 7  && return read_repetition_type_7(state)
    parse_error(state, "Unknown repetition type $type")
end

function read_1_delta_list_horizontal_first(state, vc::UInt64)
    l = Vector{Point{2, Int64}}(undef, vc + 1)
    l[1] = Point{2, Int64}(0, 0)
    for i in 1:vc
        l[i + 1] = read_1_delta(state, (i + 1) % 2)
    end
    return l
end

function read_1_delta_list_vertical_first(state, vc::UInt64)
    l = Vector{Point{2, Int64}}(undef, vc + 1)
    l[1] = Point{2, Int64}(0, 0)
    for i in 1:vc
        l[i + 1] = read_1_delta(state, i % 2)
    end
    return l
end

function read_2_delta_list(state, vc::UInt64)
    l = Vector{Point{2, Int64}}(undef, vc + 1)
    l[1] = Point{2, Int64}(0, 0)
    for i in 1:vc
        l[i + 1] = read_2_delta(state)
    end
    return l
end

function read_3_delta_list(state, vc::UInt64)
    l = Vector{Point{2, Int64}}(undef, vc + 1)
    l[1] = Point{2, Int64}(0, 0)
    for i in 1:vc
        l[i + 1] = read_3_delta(state)
    end
    return l
end

function read_g_delta_list(state, vc::UInt64)
    l = Vector{Point{2, Int64}}(undef, vc + 1)
    l[1] = Point{2, Int64}(0, 0)
    for i in 1:vc
        l[i + 1] = read_g_delta(state)
    end
    return l
end

function read_point_list(state)
    # Warning: read_point_list artificially adds a Point{2, Int64}(0, 0) to the beginning of the list.
    # In the OASIS specification, this first point is implied because an offset is provided
    # alongside the point list.
    type = read_byte(state)
    return read_point_list(state, type)
end

function read_point_list(state, type::UInt8)
    vertex_count = rui(state)
    # Ordering is changed based on what appears to be used most often in practice.
    type == 0x01 && return read_1_delta_list_vertical_first(state, vertex_count)
    type == 0x04 && return read_g_delta_list(state, vertex_count)
    type == 0x00 && return read_1_delta_list_horizontal_first(state, vertex_count)
    type == 0x02 && return read_2_delta_list(state, vertex_count)
    type == 0x03 && return read_3_delta_list(state, vertex_count)
    type == 0x05 && return cumsum(read_g_delta_list(state, vertex_count))
    parse_error(state, "Unknown point list type $type")
end

function read_polygon_point_list(state)
    type = read_byte(state)
    l = read_point_list(state, type)
    type <= 0x01 && push_implicit_manhattan_delta!(l, type)
    return l
end

# For polygons, point lists of type 0 and 1 omit their last two displacements. The second of
# these is implied by the polygon closing itself, but the first has to be added back: it moves
# us level with the starting point, along whichever direction is next in the alternation.
function push_implicit_manhattan_delta!(l::Vector{Point{2, Int64}}, type::UInt8)
    vertex_count = length(l) - 1
    # Type 0 starts with a horizontal displacement and type 1 with a vertical one.
    next_is_horizontal = iseven(vertex_count) == (type == 0x00)
    offset = sum(l)
    delta = next_is_horizontal ? Point{2, Int64}(-offset[1], 0) : Point{2, Int64}(0, -offset[2])
    iszero(delta) || push!(l, delta)
    return l
end

function read_property_value(state)
    type = read_byte(state)
    if type <= 0x07
        return read_real(state, type)
    elseif type == 0x09
        return read_signed_integer(state)
    elseif 0x0a <= type <= 0x0c
        return read_symbol(state)
    else
        return rui(state)
    end
end

read_interval_type_0(state) = Interval(0, typemax(UInt64))
read_interval_type_1(state) = Interval(0, rui(state))
read_interval_type_2(state) = Interval(rui(state), typemax(UInt64))
read_interval_type_3(state) = (x = rui(state); Interval(x, x))
read_interval_type_4(state) = Interval(rui(state), rui(state))

function read_interval(state)
    type = read_byte(state)
    # Ordering is changed based on what appears to be used most often in practice.
    type == 3 && return read_interval_type_3(state)
    type == 0 && return read_interval_type_0(state)
    type == 1 && return read_interval_type_1(state)
    type == 2 && return read_interval_type_2(state)
    type == 4 && return read_interval_type_4(state)
    parse_error(state, "Unknown interval type $type")
end

function read_byte(state)
    state.pos > length(state.buf) && parse_error(state, "Unexpected end of input")
    @inbounds b = state.buf[state.pos]
    state.pos += 1
    return b
end

# Comparing against the bytes that remain rather than against `pos + nbytes` keeps the check
# correct when a corrupt file yields an absurdly large `nbytes`.
function check_remaining(state, nbytes::Integer)
    nbytes > length(state.buf) - state.pos + 1 &&
        parse_error(state, "Unexpected end of input; expected $nbytes more byte(s)")
end

function read_bytes(state, nbytes::Integer)
    check_remaining(state, nbytes)
    @inbounds b = state.buf[state.pos:(state.pos + nbytes - 1)]
    state.pos += nbytes
    return b
end

function view_bytes(state, nbytes::Integer)
    check_remaining(state, nbytes)
    @inbounds b = @view state.buf[state.pos:(state.pos + nbytes - 1)]
    state.pos += nbytes
    return b
end
