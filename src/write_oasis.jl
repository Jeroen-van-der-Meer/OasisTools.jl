"""
    oasiswrite(filename, oas; bufsize, compress)

Write an [`Oasis`](@ref) object to an OASIS file.

# Arguments

- `filename::AbstractString`: Path of the output file.
- `oas::Oasis`: The OASIS object to write.

# Keyword Arguments

- `bufsize::Integer = 16 * 1024 * 1024`: Size of the output buffer in bytes.
- `compress::Bool = true`: Whether to compress the file's name tables and the contents of its
  cells with CBLOCK records. Writing without compression is faster, but makes for larger
  files.

The output is first written to a temporary file in the same directory, which then replaces
`filename`. As a result, a failed write leaves an existing file untouched, and `filename` may
be a file that cells which aren't loaded are read from: on Linux and macOS, those cells keep
seeing the original contents. (Windows refuses to replace a file that is still in use.)
"""
function oasiswrite(
    filename::AbstractString, oas::Oasis;
    bufsize = 16 * 1024 * 1024, compress::Bool = true
)
    # Resolving symlinks makes us replace the file a link points to rather than the link itself.
    target = ispath(filename) ? realpath(filename) : abspath(filename)
    temp = tempname(dirname(target); cleanup = false)
    try
        state = WriterState(oas, temp, bufsize)
        try
            write_oasis(state, oas; compress = compress)
        finally
            finish_compression!(state)
            close(state.io)
        end
        # Keep the permissions of the file we're replacing.
        isfile(target) && chmod(temp, filemode(target) & 0o7777)
        mv(temp, target; force = true)
    catch
        rm(temp; force = true)
        rethrow()
    end
    return nothing
end

function write_oasis(state::WriterState, oas::Oasis; compress::Bool = true)
    write_bytes(state, MAGIC_BYTES)
    write_start(state, unit(oas))
    write_roots(state)
    write_tables = function (table_state)
        write_propname(table_state, :S_TOP_CELL)
        construct_and_write_cellname_references(table_state)
        write_layers(table_state)
    end
    compress ? write_cblock(write_tables, state) : write_tables(state)
    write_cells(state; compress = compress)
    write_end(state)

    # Write remaining bytes in buffer.
    write(state.io, @view state.buf[1:(state.pos - 1)])
end

# The root cells are only recorded if they are known without decoding anything, as the
# S_TOP_CELL property is optional.
function write_roots(state::WriterState)
    rts = known_roots(state.cells)
    isnothing(rts) && return
    for root in rts
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

function write_cells(state; compress::Bool = true)
    for cell in state.cells
        write_cell(state, cell; compress = compress)
    end
end
