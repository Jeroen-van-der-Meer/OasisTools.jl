"""
    flatten(oas, cell_name; depth = typemax(Int))

Flatten the layout below a cell, moving the shapes of the cells it places into the cell itself,
down to `depth` levels below it. Returns a new [`Oasis`](@ref) holding the flattened cell, under
its own name, along with every cell it still places; `oas` is left untouched.

With `depth = 1`, the shapes of the cells placed directly in the cell are moved into it, and
whatever those cells place in turn becomes placed in the cell directly. By default, the layout is
flattened completely, leaving a single cell without any placements.

Nothing is decoded in the process. The flattened cell only records what to bring together, which
happens, one placed cell at a time, whenever it is written or its contents are needed. Arrays stay
arrays: a shape in an array of placed cells becomes a single shape with a repetition.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> flat = flatten(oasisread(filename), :TOP; depth = 1);

julia> load!(flat[:TOP])
Cell TOP with 8 placements and 3 shapes

julia> unique(p.cell for p in placements(flat[:TOP]))
3-element Vector{Symbol}:
 :ROCKBOTTOM
 :BOTTOM2
 :BOTTOM
```

# Limitations

- Rotations by angles other than multiples of 90 degrees turn rectangles into polygons.
- With such rotations, or magnifications other than whole numbers, coordinates are rounded to the
  grid. Path widths and circle radii are scaled along with the magnification and rounded too; path
  widths to even numbers, as OASIS requires.
"""
function flatten(oas::Oasis, cell_name; depth::Integer = typemax(Int))
    depth >= 0 || throw(ArgumentError("The depth must not be negative; got $depth"))
    cell_name = Symbol(cell_name)
    top = oas[cell_name]
    check_acyclic(oas, cell_name)
    inlined, kept = flatten_levels(oas, cell_name, depth)

    result = Oasis(Cell[], copy(layers(oas)); unit = unit(oas))
    if depth == 0
        push_cell!(result, copy_cell(top))
    else
        cells = Dict(name => copy_cell(oas[name]) for name in inlined)
        push_cell!(result, flattened_cell(top, InlinePlacements(cells, depth)))
    end
    for name in kept
        copy_subtree!(result, oas, name)
    end
    return result
end

# Which cells get flattened into the top cell, and which remain placed in it.
function flatten_levels(oas::Oasis, top::Symbol, depth::Integer)
    inlined, kept = Set{Symbol}(), Set{Symbol}()
    current = Set(p.cell for p in cached_placements(oas[top]))
    level = 1
    while !isempty(current) && level <= depth
        next = Set{Symbol}()
        for cell_name in current
            cell = get_cell(oas, cell_name)
            # Placements of missing cells stay as they are.
            isnothing(cell) && continue
            push!(inlined, cell_name)
            union!(next, p.cell for p in cached_placements(cell))
        end
        current = next
        level += 1
    end
    union!(kept, current)
    return inlined, kept
end

function check_acyclic(oas::Oasis, top::Symbol)
    done, visiting = Set{Symbol}(), Set{Symbol}()
    function visit(cell_name::Symbol)
        cell_name in done && return
        cell_name in visiting && error("Cell $cell_name is placed inside itself")
        cell = get_cell(oas, cell_name)
        isnothing(cell) && return
        push!(visiting, cell_name)
        foreach(p -> visit(p.cell), cached_placements(cell))
        delete!(visiting, cell_name)
        push!(done, cell_name)
    end
    visit(top)
end

# Adds a copy of a cell and everything below it to `result`, unless it's there already.
function copy_subtree!(result::Oasis, oas::Oasis, cell_name::Symbol)
    haskey(result, cell_name) && return
    cell = get_cell(oas, cell_name)
    isnothing(cell) && return
    push_cell!(result, copy_cell(cell))
    for child in unique(p.cell for p in cached_placements(cell))
        copy_subtree!(result, oas, child)
    end
end

# The flattened version of `cell`. A loaded cell's contents are turned into edits as well, so
# that the flattened contents are put together whenever they're needed rather than in memory.
function flattened_cell(cell::Cell, edit::CellEdit)
    if isloaded(cell)
        contents = AppendElements(Shape[s for v in shape_vectors(cell.shapes) for s in v], copy(cell.placements))
        return Cell(cell.name, nothing, nothing, nothing, nothing, CellEdit[contents, edit])
    end
    flattened = copy_cell(cell)
    push!(flattened.edits, edit)
    flattened.index = nothing
    return flattened
end

# Replaces placements by the contents of the cells they place, `depth` levels deep.
struct InlinePlacements <: CellEdit
    cells::Dict{Symbol, Cell}
    depth::Int
    # Shapes of small cells, so that they're decoded only once however often they're placed.
    shapes::Dict{Symbol, Vector{Shape}}
end

InlinePlacements(cells::Dict{Symbol, Cell}, depth::Integer) =
    InlinePlacements(cells, depth, Dict{Symbol, Vector{Shape}}())

apply_edit(emit, e::InlinePlacements, p::CellPlacement) = inline_placement(emit, e, p, e.depth)

copy_edit(e::InlinePlacements) =
    InlinePlacements(Dict(name => copy_cell(cell) for (name, cell) in e.cells), e.depth)

# Cells whose contents take up fewer bytes than this have their shapes kept once decoded.
const INLINE_CACHE_LIMIT = 1024 * 1024

function inline_placement(emit, e::InlinePlacements, p::CellPlacement, levels::Integer)
    cell = get(e.cells, p.cell, nothing)
    (levels <= 0 || isnothing(cell)) && return emit(p)
    foreach_inline_shape(s -> emit(transform_shape(s, p)), e, cell)
    for q in cached_placements(cell)
        inline_placement(emit, e, p * q, levels - 1)
    end
end

function foreach_inline_shape(f, e::InlinePlacements, cell::Cell)
    if isloaded(cell) || length(cell.source.bytes) >= INLINE_CACHE_LIMIT
        foreach_shape(f, cell)
    else
        cached = get!(e.shapes, cell.name) do
            collected = Shape[]
            foreach_shape(s -> push!(collected, s), cell)
            collected
        end
        foreach(f, cached)
    end
end
