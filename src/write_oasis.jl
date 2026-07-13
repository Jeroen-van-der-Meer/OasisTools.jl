"""
    oasiswrite(filename, oas; bufsize)

Write an [`Oasis`](@ref) object to an OASIS file.

# Arguments

- `filename::AbstractString`: Path of the output file.
- `oas::Oasis`: The OASIS object to write.

# Keyword Arguments

- `bufsize::Integer = 16 * 1024 * 1024`: Size of the output buffer in bytes.
"""
function oasiswrite(filename::AbstractString, oas::Oasis; bufsize = 16 * 1024 * 1024)
    units = unique(cell.unit for cell in cells(oas))
    @assert length(units) == 1 "Writing of cells with incompatible unit length not supported yet"
    unit = first(units)

    state = WriterState(oas, filename, bufsize)

    write_bytes(state, MAGIC_BYTES)
    write_start(state, unit)
    write_roots(state)
    write_cblock(state) do cblock_state
        write_propname(cblock_state, :S_TOP_CELL)
        construct_and_write_cellname_references(cblock_state)
        write_layers(cblock_state)
    end
    write_cells(state)
    write_end(state)

    # Write remaining bytes in buffer.
    write(state.io, @view state.buf[1:(state.pos - 1)])
    close(state.io)
end

function write_roots(state::WriterState)
    for root in roots(state.cells)
        write_property(state, 0, root) # 'S_TOP_CELL' to be numerically stored as 0
    end
end

function construct_and_write_cellname_references(state::WriterState)
    for (i, cell) in enumerate(state.cells)
        cellname = name(cell)
        state.cellnameReferences[cellname] = i - 1
        write_cellname(state, cellname)
    end
end

function write_layers(state::WriterState)
    for layer in state.layers
        write_layername(state, layer)
        write_textlayername(state, layer)
    end
end

function write_cells(state)
    for cell in state.cells
        write_cell(state, cell)
    end
end
