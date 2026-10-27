skip_record(state::AbstractParserState) = return

function skip_start(state::FileParserState)
    skip_string(state)
    skip_real(state)
    offset_flag = rui(state)
    if iszero(offset_flag)
        # We ignore the 12 integers corresponding to the table offset structure.
        for _ in 1:12
            skip_integer(state)
        end
    end
end

function skip_propname_impl(state::FileParserState)
    skip_string(state)
end

function skip_propname_ref(state::FileParserState)
    skip_string(state)
    skip_integer(state)
end

function skip_propstring_impl(state::FileParserState)
    skip_string(state)
end

function skip_propstring_ref(state::FileParserState)
    skip_string(state)
    skip_integer(state)
end

function skip_placement(state::SkipParserState)
    info_byte = read_byte(state)
    if bit_is_one(info_byte, 1)
        if bit_is_one(info_byte, 2)
            skip_integer(state)
        else
            skip_string(state)
        end
    end
    bit_is_one(info_byte, 3) && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_repetition(state)
end

function skip_placement_mag_angle(state::SkipParserState)
    info_byte = read_byte(state)
    if bit_is_one(info_byte, 1)
        if bit_is_one(info_byte, 2)
            skip_integer(state)
        else
            skip_string(state)
        end
    end
    bit_is_one(info_byte, 6) && skip_real(state)
    bit_is_one(info_byte, 7) && skip_real(state)
    bit_is_one(info_byte, 3) && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_repetition(state)
end

function skip_text(state::SkipParserState)
    info_byte = read_byte(state)
    if bit_is_one(info_byte, 2)
        if bit_is_one(info_byte, 3)
            skip_integer(state)
        else
            skip_string(state)
        end
    end
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_rectangle(state::SkipParserState)
    info_byte = read_byte(state)
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 2) && skip_integer(state)
    bit_is_one(info_byte, 3) && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_polygon(state::SkipParserState)
    info_byte = read_byte(state)
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 3) && skip_point_list(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_path(state::SkipParserState)
    info_byte = read_byte(state)
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 2) && skip_integer(state)
    if bit_is_one(info_byte, 1)
        extension_scheme = read_byte(state)
        if bit_is_one(extension_scheme, 5) && bit_is_one(extension_scheme, 6)
            skip_integer(state)
        end
        if bit_is_one(extension_scheme, 7) && bit_is_one(extension_scheme, 8)
            skip_integer(state)
        end
    end
    bit_is_one(info_byte, 3) && skip_point_list(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_trapezoid(state::SkipParserState, delta_a_explicit::Bool, delta_b_explicit::Bool)
    info_byte = read_byte(state)
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 2) && skip_integer(state)
    bit_is_one(info_byte, 3) && skip_integer(state)
    delta_a_explicit && skip_integer(state)
    delta_b_explicit && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_ctrapezoid(state::SkipParserState)
    info_byte = read_byte(state)
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 1) && skip_integer(state)
    bit_is_one(info_byte, 2) && skip_integer(state)
    bit_is_one(info_byte, 3) && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_circle(state::SkipParserState)
    info_byte = read_byte(state)
    bit_is_one(info_byte, 8) && skip_integer(state)
    bit_is_one(info_byte, 7) && skip_integer(state)
    bit_is_one(info_byte, 3) && skip_integer(state)
    bit_is_one(info_byte, 4) && skip_integer(state)
    bit_is_one(info_byte, 5) && skip_integer(state)
    bit_is_one(info_byte, 6) && skip_repetition(state)
end

function skip_property(state::AbstractParserState)
    info_byte = read_byte(state)
    if bit_is_one(info_byte, 6)
        if bit_is_one(info_byte, 7)
            skip_integer(state)
        else
            skip_string(state)
        end
    end
    if !bit_is_one(info_byte, 5)
        number_of_values = info_byte >> 4
        if number_of_values == 0x0f
            number_of_values = rui(state)
        end
        for _ in 1:number_of_values
            skip_property_value(state)
        end
    end
end

function skip_cblock(state::SkipParserState)
    skip_integer(state)
    skip_integer(state)
    comp_byte_count = rui(state)
    skip_bytes(state, comp_byte_count)
end
