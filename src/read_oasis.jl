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
- Backwards-compatible extensions are not supported. You will get an error if your file contains
  any.
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

    if lazy
        # Without decoding the cells, the best we can do to find the root cells is to look for
        # the S_TOP_CELL property. (`update_roots!` finds them reliably, by decoding the cells'
        # placements.)
        find_root_cells!(state)
    end

    oas = Oasis(process_cells(state), state.layers; unit = state.metadata.unit)

    if !lazy
        load_all_cells!(oas)
        # Use the recorded cell placements to find the root cells.
        update_roots!(oas)
    end

    return oas
end

function process_cells(state::FileParserState)
    cs = Vector{Cell}(undef, length(state.cells))

    for (i, preprocessed_cell) in enumerate(state.cells)
        if preprocessed_cell.nameOrNumber isa UInt64
            cell_name = state.cellnameReferences[preprocessed_cell.nameOrNumber]
        else
            cell_name = preprocessed_cell.nameOrNumber
        end

        source = CellSource(
            preprocessed_cell.bytes, state.cellnameReferences, state.textstringReferences
        )
        cs[i] = Cell(cell_name, source, cell_name in state.metadata.roots)
    end

    return cs
end

function find_root_cells!(state::FileParserState)
    # Look for S_TOP_CELL property and store top cell in parser metadata. We can only do this
    # after parsing the entire file because both the the value of S_TOP_CELL as well as the word
    # 'S_TOP_CELL' itself can be stored numerically, and the record that tells you what the
    # corresponding string should be can occur anywhere in the entire file.
    for file_property in state.metadata.fileProperties
        propname_or_number = file_property.nameOrNumber
        if propname_or_number isa UInt64
            propname = state.propnameReferences[propname_or_number]
        else
            propname = propname_or_number
        end
        if propname == :S_TOP_CELL
            cellname_or_number = first(file_property.valueList)
            if cellname_or_number isa UInt64
                cellname = state.propstringReferences[cellname_or_number]
            else
                cellname = cellname_or_number
            end
            push!(state.metadata.roots, cellname)
        end
    end
end
