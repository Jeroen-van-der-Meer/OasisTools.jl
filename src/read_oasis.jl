"""
    oasisread(filename; kw...)

Read your OASIS file in Julia.

# Keyword Arguments

- `lazy::Bool = false`: If set to `true`, `oasisread` will use an experimental lazy loader
  which does not load the contents of the cells into memory until a cell explicitly gets
  prompted.

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
        # In case of lazy loading, make a best-effort attempt at finding the root cells by
        # looking for the S_TOP_CELL property. (In case of non-lazy loading, we are guaranteed
        # to find the root cells by using the placement information.)
        find_root_cells!(state)
    end

    lazy_cells = process_cells(state)
    oas = Oasis(lazy_cells, state.layers; unit = state.metadata.unit)
    
    if !lazy
        # In case of non-lazy loading, parse each of the lazy-loaded cells and replace them with
        # ordinary cells.
        load_all_cells!(oas)
        # Use the recorded cell placements to find the root cells.
        update_roots!(oas)
    end
    
    return oas
end

function process_cells(state::FileParserState)
    lazy_cells = Vector{LazyCell}(undef, length(state.cells))

    for (i, preprocessed_cell) in enumerate(state.cells)
        if preprocessed_cell.nameOrNumber isa UInt64
            cell_name = state.cellnameReferences[preprocessed_cell.nameOrNumber]
        else
            cell_name = preprocessed_cell.nameOrNumber
        end

        is_root = cell_name in state.metadata.roots
        lazy_cells[i] = LazyCell(
            cell_name,
            preprocessed_cell.bytes,
            state.cellnameReferences,
            state.textstringReferences,
            is_root
        )
    end

    return lazy_cells
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
