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
roots(cells::AbstractVector{Union{LazyCell, Cell}}) = [c.name for c in cells if c._root]

# FIXME: Eventually I want CellHierarchy to properly deal with lazy-loaded objects.
"""
    cell_hierarchy(oas)

Find the cell hierarchy of your OASIS object. Note that lazy-loaded cells will be listed as
having no cell placements.
"""
function cell_hierarchy(oas::Oasis)
    ch = CellHierarchy(Dict())
    for cell in cells(oas)
        update_cell_hierarchy!(ch, cell)
    end
    return ch
end

function update_cell_hierarchy!(ch::CellHierarchy, cell::Cell)
    ch.hierarchy[cell.name] = unique(p.cellName for p in placements(cell))
end

function update_cell_hierarchy!(ch::CellHierarchy, cell::LazyCell)
    ch.hierarchy[cell.name] = Symbol[]
end

"""
    update_roots!(oas)

Go through the cell hierarchy to figure out what cells are likely to be root cells. May be
inaccurate if your OASIS file contains any `LazyCell` objects, as their placements are
unknown.
"""
function update_roots!(oas::Oasis)
    rts = roots(cell_hierarchy(oas))
    for cell in cells(oas)
        should_be_root = cell.name in rts
        cell._root = should_be_root
    end
    return oas
end

"""
    validate_placements(oas)

Check for dangling cell placements, i.e. placements that reference cells not present in `oas`.
Returns a list of warning strings; an empty list means no issues were found. Beware that
lazy-loaded cells are skipped in the validation.
"""
function validate_placements(oas::Oasis)
    warnings = String[]
    known_cells = Set(cell_names(oas))
    for cell in cells(oas)
        cell isa LazyCell && continue
        for p in placements(cell)
            if p.cellName ∉ known_cells
                push!(warnings, "Cell $(cell.name) places unknown cell $(p.cellName)")
            end
        end
    end
    return warnings
end
