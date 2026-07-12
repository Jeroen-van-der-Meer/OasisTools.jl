function read_or_modal(
    state,
    reader::Function,
    ::Val{modal}, # Seems to help performance because modal variables have different types.
    info_byte::UInt8,
    position::Int64
) where modal
    if bit_is_one(info_byte, position)
        v = reader(state)
        setproperty!(state.mod, modal, v)
        return v
    else
        return getproperty(state.mod, modal)
    end
end

# If an x or y value is parsed, we require logic to deal with the current value of xy-mode.
function read_or_modal_xy(
    state,
    ::Val{modalX},
    ::Val{modalY},
    info_byte::UInt8,
    position::Int64 # Position of bit determining x-value; the y-value is always the next bit.
) where {modalX, modalY}
    if state.mod.xyAbsolute
        x = read_or_modal(state, read_signed_integer, Val(modalX), info_byte, position)
        y = read_or_modal(state, read_signed_integer, Val(modalY), info_byte, position + 1)
    else
        if bit_is_one(info_byte, position)
            x = read_signed_integer(state) + getproperty(state.mod, modalX)
            setproperty!(state.mod, modalX, x)
        else
            x = getproperty(state.mod, modalX)
        end
        if bit_is_one(info_byte, position + 1)
            y = read_signed_integer(state) + getproperty(state.mod, modalY)
            setproperty!(state.mod, modalY, y)
        else
            y = getproperty(state.mod, modalY)
        end
    end
    return x, y
end

function read_repetition(
    state,
    info_byte::UInt8,
    position::Int64
)
    if bit_is_one(info_byte, position)
        v = read_repetition(state)
        state.mod.repetition = v
        return v
    else
        return nothing
    end
end

function read_nrep(
    state,
    info_byte::UInt8,
    position::Int64
)
    if bit_is_one(info_byte, position)
        v = read_nrep(state)
        state.mod.nrep = v
        return v
    else
        return 1
    end
end

function bit_is_one(byte::UInt8, position::Integer)
    return isone(byte >> (8 - position) & 0x01)
end

function is_end_of_cell(state, next_record::UInt8)
    # The end of a cell is implied when the upcoming record is any of the following:
    # END, CELLNAME, TEXTSTRING, PROPNAME, PROPSTRING, LAYERNAME, CELL, XNAME
    if (0x02 <= next_record <= 0x0e) || (next_record == 0x1e) || (next_record == 0x1f)
        return true
    elseif next_record == 34
        # If a CBLOCK is encountered, the first record within the CBLOCK implies whether or
        # not the CBLOCK belongs to the cell or not.
        comp_type = read_byte(state)
        @assert comp_type == 0x00 "Unknown compression type encountered"
        skip_integer(state) # uncomp_byte_count
        comp_byte_count = rui(state)
        comp_bytes = @view state.buf[state.pos:(state.pos + comp_byte_count - 1)]
        z = DeflateDecompressorStream(IOBuffer(comp_bytes))
        first_record_in_cblock = read(z, UInt8)
        return is_end_of_cell(state, first_record_in_cblock)
    else
        return false
    end
end
