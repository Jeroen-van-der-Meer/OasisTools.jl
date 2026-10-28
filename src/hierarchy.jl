"""
    roots(oas)

Names of the root cells of `oas`, i.e. those that aren't placed in any other cell. Cells that
aren't loaded are brought to [`tier`](@ref) 1 to find their placements.

To see the whole cell hierarchy, use [`show_cells`](@ref). [`placements`](@ref) lists what a
single cell places, so that the hierarchy can be had as a dictionary with

```julia
Dict(name(cell) => unique(p.cell for p in placements(cell)) for cell in cells(oas))
```
"""
function roots(oas::Oasis)
    index!(oas)
    return roots_from_placements(cells(oas), cached_placements)
end

# The top cells according to the file's S_TOP_CELL properties, as far as they exist. Files are
# free to leave this property out, or to get it wrong, so it is only a hint.
function declared_top_cells(oas::Oasis)
    names = Symbol[]
    for p in properties(oas)
        p.name == "S_TOP_CELL" || continue
        for v in p.values
            v isa String && haskey(oas, v) && Symbol(v) ∉ names && push!(names, Symbol(v))
        end
    end
    return names
end

# Root cells if they're known without decoding anything, and `nothing` otherwise.
function known_roots(cs::AbstractVector{Cell})
    all(cell -> !isnothing(known_placements(cell)), cs) || return nothing
    return roots_from_placements(cs, known_placements)
end

function roots_from_placements(cs::AbstractVector{Cell}, placements_of)
    placed = Set{Symbol}()
    for cell in cs, p in placements_of(cell)
        p.cell == cell.name || push!(placed, p.cell)
    end
    return [cell.name for cell in cs if cell.name ∉ placed]
end

"""
    validate_placements(oas)

Check for dangling cell placements, i.e. placements that reference cells not present in `oas`.
Returns a list of warning strings; an empty list means no issues were found. Cells that aren't
loaded are brought to [`tier`](@ref) 1 to find their placements.
"""
function validate_placements(oas::Oasis)
    index!(oas)
    warnings = String[]
    known_cells = Set(cell_names(oas))
    for cell in cells(oas)
        for p in cached_placements(cell)
            if p.cell ∉ known_cells
                push!(warnings, "Cell $(cell.name) places unknown cell $(p.cell)")
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
        println(io, join((p.cell, p.location..., p.rotation, p.magnification, p.flipped), ","))
    end
end
```
"""
function find_instances(oas::Oasis, pattern; top = nothing)
    top = isnothing(top) ? only_root(oas) : Symbol(top)
    oas[top] # Throws if there is no such cell
    matches = name_matcher(pattern)

    # Whether a match is placed anywhere below a cell, worked out once per cell.
    below = Dict{Symbol, Bool}()
    function has_match_below(cell_name::Symbol)
        haskey(below, cell_name) && return below[cell_name]
        below[cell_name] = false # Guards against cells placed inside themselves.
        cell = get_cell(oas, cell_name)
        result = !isnothing(cell) &&
            any(c -> matches(c) || has_match_below(c), unique(p.cell for p in cached_placements(cell)))
        below[cell_name] = result
        return result
    end

    found = CellPlacement[]
    function visit(cell_name::Symbol, transform::CellPlacement)
        for p in cached_placements(oas[cell_name])
            hit, descend = matches(p.cell), has_match_below(p.cell)
            (hit || descend) || continue
            for instance in expand(p)
                placed = transform * instance # The instance, in the coordinates of `top`
                hit && push!(found, placed)
                descend && visit(p.cell, placed)
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
            "There is no root cell; pass `top` to pick a cell." :
            "There are several root cells ($(join(rts, ", "))); pass `top` to pick one."
    )
end
