"""
    load_all_cells!(oas)

Load all [`LazyCell`](@ref) objects in `oas` into memory, replacing them with [`Cell`](@ref)
objects. Equivalent to calling [`load_cell!`](@ref) on every cell.
"""
function load_all_cells!(oas::Oasis)
    for (i, cell) in enumerate(cells(oas))
        load_cell!(oas, cell, i)
    end
end

load_cell!(oas, cell_name::AbstractString) = load_cell!(oas, Symbol(cell_name))

"""
    load_cell!(oas, cell_name)

Load a `LazyCell` into memory and replace the `LazyCell` with a corresponding `Cell` in the
input OASIS file.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> oas[:TOP]
Lazy cell TOP

julia> load_cell!(oas, :TOP);

julia> oas[:TOP]
Cell TOP with 5 placements and 0 shapes
```

See also [`load_cell`](@ref).
"""
function load_cell!(oas::Oasis, cell_name::Symbol)
    cell = get_cell(oas, cell_name)
    cell_index = find_cell(oas, cell_name)
    isnothing(cell_index) && error("Could not find cell with name $cell_name")
    cell = oas.cells[cell_index]
    load_cell!(oas, cell, cell_index)
end

load_cell!(::Oasis, ::Cell, ::Int64) = return

function load_cell!(oas::Oasis, lazy_cell::LazyCell, cell_index::Int64)
    cell = load_cell(lazy_cell)
    oas.cells[cell_index] = cell
    return oas
end

load_cell(cell::Cell) = cell

"""
    load_cell(lazy_cell)

Load a `LazyCell` into memory.

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "polygon.oas");

julia> oas = oasisread(filename; lazy = true);

julia> lazy_cell = oas[:TOP]
Lazy cell TOP

julia> loaded_cell = load_cell(lazy_cell)
Cell TOP with 0 placements and 1 shape
```

See also [`load_cell!`](@ref).
"""
function load_cell(lazy_cell::LazyCell)
    state = CellParserState(lazy_cell)
    nbytes = length(lazy_cell.bytes)
    while state.pos < nbytes
        record_type = read_byte(state)
        read_record(record_type, state)
    end
    cell = Cell(lazy_cell.name, state.shapes, state.placements, lazy_cell.unit, lazy_cell._root)
    return cell
end
