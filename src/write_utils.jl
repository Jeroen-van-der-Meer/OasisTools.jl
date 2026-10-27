function write_cellname_reference(
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState,
    info_byte::UInt8
)
    cellname_explicit = bit_is_one(info_byte, 1)
    if cellname_explicit
        cellname_as_ref = bit_is_one(info_byte, 2)
        if cellname_as_ref
            cellname_number = rui(cell_parser_state)
            cellname = lookup_reference(
                cell_parser_state, source.cellnameReferences, cellname_number, "cell name", "CELLNAME"
            )
        else
            cellname = read_symbol(cell_parser_state)
            # Change the bit indicating that the reference was a string, because we choose to
            # store a number instead.
            info_byte = set_bit_to_one(info_byte, 2)
        end
        new_cellname_number = state.cellnameReferences[cellname]
        write_byte(state, info_byte)
        wui(state, new_cellname_number)
    else
        # If cellname is implicit, then a modal variable is used to refer to the right cellname.
        # Since copying happens sequentially, we can be sure that the value of this
        # modal variable will be correct by the time it reaches this record, and hence we can
        # simply copy the info byte.
        write_byte(state, info_byte)
    end
end

function write_text(
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState,
    info_byte::UInt8
)
    # We explicitly store text strings rather than using references.
    textstring_explicit = bit_is_one(info_byte, 2)
    if textstring_explicit
        textstring_as_ref = bit_is_one(info_byte, 3)
        if textstring_as_ref
            textstring_number = rui(cell_parser_state)
            textstring = lookup_reference(
                cell_parser_state, source.textstringReferences, textstring_number, "text string", "TEXTSTRING"
            )
            # Change the bit indicating that the reference was a string, because we choose to
            # store a number instead.
            info_byte = set_bit_to_zero(info_byte, 3)
        else
            textstring = read_symbol(cell_parser_state)
        end
        write_byte(state, info_byte)
        write_a_string(state, textstring)
    else
        # If textstring is implicit, then a modal variable is used to refer to the right
        # textstring. Since copying happens sequentially, we can be sure that the
        # value of this modal variable will be correct by the time it reaches this record, and
        # hence we can simply copy the info byte.
        write_byte(state, info_byte)
    end
end

function set_bit_to_zero(byte::UInt8, position::Integer)
    byte &= ~(0x01 << (8 - position))
end

function set_bit_to_one(byte::UInt8, position::Integer)
    byte |= (0x01 << (8 - position))
end