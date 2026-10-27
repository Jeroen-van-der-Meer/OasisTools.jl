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

"""
    find_instances(oas, pattern; top)

Every instance of a cell whose name matches `pattern` anywhere below the cell `top`, as a list
of [`CellPlacement`](@ref)s in the coordinates of `top`, with all repetitions expanded.

`pattern` can be a cell name, a `Regex`, or a function that takes a cell name (as a `Symbol`) and
returns whether it matches. `top` defaults to the root cell of `oas`, if there is only one.

Instances of matching cells placed within other matching cells are included. Only cells that
have matches below them are looked into, so large arrays without matches aren't expanded. Cells
that aren't loaded are brought to [`tier`](@ref) 1.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> find_instances(oas, :BOTTOM; top = :MIDDLE2)
5-element Vector{CellPlacement}:
 Placement of cell BOTTOM at (-5, -3)
 Placement of cell BOTTOM at (-3, -3)
 Placement of cell BOTTOM at (-3, -1)
 Placement of cell BOTTOM at (-1, -1)
 Placement of cell BOTTOM at (1, -1)
```

To store the instances in a CSV file:

```julia
instances = find_instances(oas, r"^NAND2_"; top = :TOP)
open("instances.csv", "w") do io
    println(io, "cell,x,y,rotation,magnification,flipped")
    for p in instances
        println(io, join((p.cellName, p.location..., p.rotation, p.magnification, p.flipped), ","))
    end
end
```
"""
function find_instances(oas::Oasis, pattern; top = nothing)
    top = isnothing(top) ? only_root(oas) : Symbol(top)
    get_existing_cell(oas, top)
    matches = name_matcher(pattern)

    # Whether a match is placed anywhere below a cell, worked out once per cell.
    below = Dict{Symbol, Bool}()
    function has_match_below(cell_name::Symbol)
        haskey(below, cell_name) && return below[cell_name]
        below[cell_name] = false # Guards against cells placed inside themselves.
        cell = get_cell(oas, cell_name)
        result = !isnothing(cell) &&
            any(c -> matches(c) || has_match_below(c), unique(p.cellName for p in placements(cell)))
        below[cell_name] = result
        return result
    end

    found = CellPlacement[]
    function visit(cell_name::Symbol, transform::CellPlacement)
        for p in placements(oas[cell_name])
            hit, descend = matches(p.cellName), has_match_below(p.cellName)
            (hit || descend) || continue
            for instance in expand(p)
                placed = transform * instance # The instance, in the coordinates of `top`
                hit && push!(found, placed)
                descend && visit(p.cellName, placed)
            end
        end
    end
    visit(top, CellPlacement(top, Point{2, Int64}(0, 0), 0.0, 1.0, false, nothing))
    return found
end

name_matcher(pattern::Regex) = cell_name -> occursin(pattern, String(cell_name))
name_matcher(pattern::Union{Symbol, AbstractString}) = cell_name -> cell_name == Symbol(pattern)
name_matcher(pattern) = pattern

function only_root(oas::Oasis)
    rts = roots(oas)
    length(rts) == 1 && return rts[1]
    error(
        isempty(rts) ?
            "No root cell is known; pass `top`, or call `update_roots!` to find the root cells." :
            "There are several root cells ($(join(rts, ", "))); pass `top` to pick one."
    )
end
