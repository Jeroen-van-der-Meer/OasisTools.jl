function skip_integer(state)
    while true
        b = read_byte(state)
        b & 0x80 == 0 && return
    end
end

function skip_integers(state, nintegers::Integer)
    for _ in 1:nintegers
        skip_integer(state)
    end
end

skip_ratio(state) = skip_integers(state, 2)

skip_four_byte_float(state) = skip_bytes(state, 4)

skip_eight_byte_float(state) = skip_bytes(state, 8)

function skip_real(state, format::UInt8)
    if format <= 0x03
        skip_integer(state)
    elseif format <= 0x05
        skip_ratio(state)
    elseif format == 0x06
        skip_four_byte_float(state)
    else
        skip_eight_byte_float(state)
    end
end

skip_real(state) = skip_real(state, read_byte(state))

function skip_string(state)
    length = rui(state)
    skip_bytes(state, length)
end

function skip_g_delta(state)
    Δ = rui(state)
    isone(Δ & 0x01) && skip_integer(state)
end

function skip_g_deltas(state, n::Integer)
    for _ in 1:n
        skip_g_delta(state)
    end
end

function skip_property_value(state)
    type = read_byte(state)
    if type <= 0x07
        skip_real(state, type)
    elseif 0x0a <= type <= 0x0c
        skip_string(state)
    else
        skip_integer(state)
    end
end

skip_repetition_type_1(state) = skip_integers(state, 4)
skip_repetition_type_2(state) = skip_integers(state, 2)
skip_repetition_type_3(state) = skip_integers(state, 2)
skip_repetition_type_4(state) = skip_integers(state, rui(state) + 1)
function skip_repetition_type_5(state)
    n = rui(state) + 1
    skip_integer(state)
    skip_integers(state, n)
end
skip_repetition_type_6(state) = skip_integers(state, rui(state) + 1)
skip_repetition_type_7(state) = skip_repetition_type_5(state)
skip_repetition_type_8(state) = (skip_integers(state, 2); skip_g_deltas(state, 2))
skip_repetition_type_9(state) = (skip_integer(state); skip_g_delta(state))
skip_repetition_type_10(state) = skip_g_deltas(state, rui(state) + 1)
function skip_repetition_type_11(state)
    n = rui(state) + 1
    skip_integer(state)
    skip_g_deltas(state, n)
end

function skip_repetition(state)
    type = read_byte(state)
    # Ordering is changed based on what appears to be used most often in practice.
    type == 0  && return
    type == 1  && return skip_repetition_type_1(state)
    type == 8  && return skip_repetition_type_8(state)
    type == 2  && return skip_repetition_type_2(state)
    type == 3  && return skip_repetition_type_3(state)
    type == 11 && return skip_repetition_type_11(state)
    type == 10 && return skip_repetition_type_10(state)
    type == 9  && return skip_repetition_type_9(state)
    type == 4  && return skip_repetition_type_4(state)
    type == 5  && return skip_repetition_type_5(state)
    type == 6  && return skip_repetition_type_6(state)
    type == 7  && return skip_repetition_type_7(state)
    parse_error(state, "Unknown repetition type $type")
end

function skip_point_list(state)
    type = read_byte(state)
    v = rui(state)
    if type < 4
        skip_integers(state, v)
    else
        skip_g_deltas(state, v)
    end
end

function skip_byte(state)
    skip_bytes(state, 1)
end

function skip_bytes(state, nbytes::Integer)
    check_remaining(state, nbytes)
    state.pos += nbytes
end