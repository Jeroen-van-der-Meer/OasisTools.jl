"""
    oasisread(filename; kw...)

Read your OASIS file in Julia.

# Keyword Arguments

- `lazy::Bool = false`: If set to `true`, the contents of the cells are not loaded into memory,
  but decoded from the file as and when they are needed. Opening a file this way only involves
  finding where each cell is stored. See [`tier`](@ref) for what can be learned about a cell
  without loading it.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "polygon.oas");

julia> oas = oasisread(filename)
OASIS file with the following cell hierarchy:
TOP
```

# Caveats

- There *will* be bugs.
- Properties are not stored.
- Extension records (XNAME, XELEMENT and XGEOMETRY) are skipped, with a warning.
- Curvilinear features are not yet supported.
"""
function oasisread(filename::AbstractString; lazy::Bool = false)
    buf = mmap(filename)
    state = FileParserState(buf)
    header = read_bytes(state, 13)
    all(header .== MAGIC_BYTES) || parse_error(state, "Wrong header bytes; likely not an OASIS file")

    while true
        record_type = read_byte(state)
        record_type == 0x02 && break # Stop when encountering END record. Ignoring checksum.
        read_record(record_type, state)
    end

    oas = Oasis(process_cells(state), state.layers; unit = state.metadata.unit)
    lazy || load!(oas)

    return oas
end

function process_cells(state::FileParserState)
    cs = Vector{Cell}(undef, length(state.cells))

    for (i, preprocessed_cell) in enumerate(state.cells)
        if preprocessed_cell.nameOrNumber isa UInt64
            cell_name = lookup_reference(
                state, state.cellnameReferences, preprocessed_cell.nameOrNumber, "cell name", "CELLNAME"
            )
        else
            cell_name = preprocessed_cell.nameOrNumber
        end

        source = CellSource(
            preprocessed_cell.bytes, state.cellnameReferences, state.textstringReferences
        )
        cs[i] = Cell(cell_name, source)
    end

    return cs
end
