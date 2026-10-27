"""
    struct CellHierarchy

Encodes the cell hierarchy of an OASIS file.

# Properties

- `hierarchy::Dict{Symbol, Vector{Symbol}}`. The keys are the cell names, and their values are
  the (unique) names of the cells that have been placed within them.
"""
struct CellHierarchy
    hierarchy::Dict{Symbol, Vector{Symbol}}
end

function roots(ch::CellHierarchy)
    all_nodes = keys(ch.hierarchy)
    child_nodes = unique(k for children in values(ch.hierarchy) for k in children)
    return setdiff(all_nodes, child_nodes)
end

roots(oas::Oasis) = roots(cells(oas))
roots(cells::AbstractVector{Cell}) = [c.name for c in cells if c._root]

"""
    cell_hierarchy(oas)

Find the cell hierarchy of your OASIS object. Cells that aren't loaded are brought to
[`tier`](@ref) 1 to find their placements.
"""
function cell_hierarchy(oas::Oasis)
    index_all_cells!(oas)
    ch = CellHierarchy(Dict())
    for cell in cells(oas)
        ch.hierarchy[cell.name] = unique(p.cellName for p in placements(cell))
    end
    return ch
end

"""
    update_roots!(oas)

Go through the cell hierarchy to figure out which cells are root cells, i.e. aren't placed in
any other cell. Cells that aren't loaded are brought to [`tier`](@ref) 1 to find their
placements.
"""
function update_roots!(oas::Oasis)
    rts = Set(roots(cell_hierarchy(oas)))
    for cell in cells(oas)
        should_be_root = cell.name in rts
        cell._root = should_be_root
    end
    return oas
end

"""
    validate_placements(oas)

Check for dangling cell placements, i.e. placements that reference cells not present in `oas`.
Returns a list of warning strings; an empty list means no issues were found. Cells that aren't
loaded are brought to [`tier`](@ref) 1 to find their placements.
"""
function validate_placements(oas::Oasis)
    index_all_cells!(oas)
    warnings = String[]
    known_cells = Set(cell_names(oas))
    for cell in cells(oas)
        for p in placements(cell)
            if p.cellName ∉ known_cells
                push!(warnings, "Cell $(cell.name) places unknown cell $(p.cellName)")
            end
        end
    end
    return warnings
end
