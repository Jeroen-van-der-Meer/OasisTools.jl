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
- Properties are read (see [`properties`](@ref)), but not yet written.
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

    # Properties may refer to PROPNAME and PROPSTRING records anywhere in the file, so they can
    # only be resolved now.
    resolve(raw) = resolve_property(state, raw, state.propnameReferences, state.propstringReferences)
    file_properties = map(resolve, state.metadata.fileProperties)
    oas = Oasis(process_cells(state, resolve), state.layers; unit = state.metadata.unit, properties = file_properties)
    lazy || load!(oas)

    return oas
end

function process_cells(state::FileParserState, resolve)
    cs = Vector{Cell}(undef, length(state.cells))
    # Properties following CELLNAME records, by cell name.
    cellname_properties = Dict(
        lookup_reference(state, state.cellnameReferences, number, "cell name", "CELLNAME") => map(resolve, raws)
        for (number, raws) in state.metadata.cellnameProperties
    )

    for (i, preprocessed_cell) in enumerate(state.cells)
        if preprocessed_cell.nameOrNumber isa UInt64
            cell_name = lookup_reference(
                state, state.cellnameReferences, preprocessed_cell.nameOrNumber, "cell name", "CELLNAME"
            )
        else
            cell_name = preprocessed_cell.nameOrNumber
        end

        source = CellSource(
            preprocessed_cell.bytes, state.cellnameReferences, state.textstringReferences,
            state.propnameReferences, state.propstringReferences
        )
        cs[i] = Cell(cell_name, source, get(cellname_properties, cell_name, Property[]))
    end

    return cs
end
