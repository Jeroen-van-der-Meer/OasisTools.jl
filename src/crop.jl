"""
    crop(oas, cell_name, window)

Crop the layout below a cell to the box `window`, a `Rect{2, Int64}` in the coordinates of
that cell. Returns a new [`Oasis`](@ref) holding the cropped cell, under its own name, along
with every cell it still needs; `oas` is left untouched.

Cells placed entirely within `window` are kept as they are, and placements entirely outside it
are dropped. Cells that cross the edge of `window` are replaced by cropped copies, named after
the original with a `\$CROP` suffix. Cells that aren't loaded stay that way: their cropped
copies only record what to clip, which happens when they are written or loaded.

# Limitations

- Rectangles and polygons are clipped exactly, but paths and circles crossing the edge of
  `window` are kept whole. See also `OasisTools.clip_shape`.
- Cells placed at angles other than multiples of 90 degrees cannot be cropped to a box in their
  own coordinates; if such a placement crosses the edge of `window`, it is kept whole.
- With a magnification other than 1, the window in the coordinates of the placed cell is
  rounded outwards to the grid.
"""
function crop(oas::Oasis, cell_name, window::Rect{2, Int64})
    cell_name = Symbol(cell_name)
    oas[cell_name] # Throws if there is no such cell
    context = CropContext(oas)
    crop_cell!(context, cell_name, window, cell_name)
    return context.result
end

struct CropContext
    oas::Oasis
    result::Oasis
    # Hierarchical extent of every cell looked at so far.
    extents::Dict{Symbol, Union{Nothing, Rect{2, Int64}}}
    # Cropped copies made so far, by original cell and window.
    variants::Dict{Tuple{Symbol, Rect{2, Int64}}, Symbol}
    # Cells copied over without cropping.
    whole::Set{Symbol}
    # Names that new cells must avoid.
    taken::Set{Symbol}
end

CropContext(oas::Oasis) = CropContext(
    oas, Oasis(Cell[], copy(layers(oas)); unit = unit(oas)),
    Dict(), Dict(), Set{Symbol}(), Set(cell_names(oas))
)

# Adds a copy of cell `cell_name` cropped to `window` (in its own coordinates) to the result,
# unless there is one already, and returns its name.
function crop_cell!(
    context::CropContext, cell_name::Symbol, window::Rect{2, Int64},
    new_name::Union{Nothing, Symbol} = nothing
)
    key = (cell_name, window)
    haskey(context.variants, key) && return context.variants[key]
    new_name = something(new_name, fresh_variant_name!(context, cell_name))
    context.variants[key] = new_name

    cell = context.oas[cell_name]
    new_placements = CellPlacement[]
    for p in cached_placements(cell)
        crop_placement!(context, new_placements, p, window)
    end

    if isloaded(cell)
        sink = ContentsSink(ShapeStore(), new_placements)
        emit = s -> push_element!(sink, s)
        for v in shape_vectors(cell.shapes), s in v
            clip_shape(emit, s, window)
        end
        cropped = Cell(new_name, sink.shapes, new_placements)
    else
        cropped = copy_cell(cell; name = new_name)
        push!(cropped.edits, ClipShapes(window), ReplacePlacements(new_placements))
        cropped.index = nothing
    end
    push_cell!(context.result, cropped)
    return new_name
end

function fresh_variant_name!(context::CropContext, cell_name::Symbol)
    i = 1
    while Symbol(cell_name, "\$CROP", i) in context.taken
        i += 1
    end
    name = Symbol(cell_name, "\$CROP", i)
    push!(context.taken, name)
    return name
end

# Adds whatever is left of placement `p` after cropping to `window` to `out`.
function crop_placement!(
    context::CropContext, out::Vector{CellPlacement}, p::CellPlacement, window::Rect{2, Int64}
)
    child_box = hierarchical_extent!(context.extents, context.oas, p.cell)
    # An empty or missing cell has nothing to crop.
    isnothing(child_box) && return keep_whole!(context, out, p)
    box = placement_extent(p, child_box)
    is_disjoint(box, window) && return
    contains_box(window, box) && return keep_whole!(context, out, p)
    if isnothing(p.repetition)
        crop_placement_instance!(context, out, p, window)
        return
    end
    single = with_repetition(p, nothing)
    inside = Point{2, Int64}[]
    for offset in p.repetition
        instance = translate(single, offset)
        instance_box = placement_instance_box(instance, child_box)
        is_disjoint(instance_box, window) && continue
        if contains_box(window, instance_box)
            push!(inside, offset)
        else
            crop_placement_instance!(context, out, instance, window)
        end
    end
    regroup(q -> keep_whole!(context, out, q), single, inside)
end

# Crops a single placement that crosses the edge of `window`.
function crop_placement_instance!(
    context::CropContext, out::Vector{CellPlacement}, p::CellPlacement, window::Rect{2, Int64}
)
    iszero(mod(p.rotation, 90)) || return keep_whole!(context, out, p)
    variant = crop_cell!(context, p.cell, inverse_placement_box(window, p))
    push!(out, CellPlacement(variant, p.location, p.rotation, p.magnification, p.flipped, nothing))
end

function keep_whole!(context::CropContext, out::Vector{CellPlacement}, p::CellPlacement)
    push!(out, p)
    copy_whole!(context, p.cell)
end

# Copies a cell and everything below it to the result without cropping.
function copy_whole!(context::CropContext, cell_name::Symbol)
    cell_name in context.whole && return
    push!(context.whole, cell_name)
    cell = get_cell(context.oas, cell_name)
    # Placements of missing cells stay as they are.
    isnothing(cell) && return
    for child in unique(p.cell for p in cached_placements(cell))
        copy_whole!(context, child)
    end
    push_cell!(context.result, copy_cell(cell))
end
