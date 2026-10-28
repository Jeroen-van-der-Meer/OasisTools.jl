# Changes to a cell that isn't loaded are recorded as edits rather than carried out straight
# away. Whenever the cell's contents are decoded, every decoded shape and placement passes
# through the cell's edits in order. Each edit hands on zero or more elements through `emit`,
# and may emit further elements once the whole cell has been decoded.

apply_edit(emit, ::CellEdit, element) = emit(element)
finish_edit(emit, ::CellEdit) = nothing

# Edits holding mutable state are copied along with the cell they belong to.
copy_edit(edit::CellEdit) = edit

# Keeps only the shapes for which a function returns `true`.
struct FilterShapes{F} <: CellEdit
    f::F
end

function apply_edit(emit, e::FilterShapes, s::Shape)
    e.f(s) && emit(s)
    return nothing
end

# Removes all placements of a cell.
struct RemovePlacements <: CellEdit
    cell::Symbol
end

function apply_edit(emit, e::RemovePlacements, p::CellPlacement)
    p.cell == e.cell || emit(p)
    return nothing
end

# Changes which cell placements refer to.
struct RenamePlacements <: CellEdit
    old::Symbol
    new::Symbol
end

function apply_edit(emit, e::RenamePlacements, p::CellPlacement)
    emit(p.cell == e.old ? CellPlacement(e.new, p.location, p.rotation, p.magnification, p.flipped, p.repetition, p.properties) : p)
    return nothing
end

# Replaces all placements by a new set.
struct ReplacePlacements <: CellEdit
    placements::Vector{CellPlacement}
end

apply_edit(emit, ::ReplacePlacements, ::CellPlacement) = nothing
finish_edit(emit, e::ReplacePlacements) = foreach(emit, e.placements)

# Adds shapes and placements.
struct AppendElements <: CellEdit
    shapes::Vector{Shape}
    placements::Vector{CellPlacement}
end

function finish_edit(emit, e::AppendElements)
    foreach(emit, e.placements)
    foreach(emit, e.shapes)
end

copy_edit(e::AppendElements) = AppendElements(copy(e.shapes), copy(e.placements))

# Clips all shapes to a box; see `clip_shape`.
struct ClipShapes <: CellEdit
    window::Rect{2, Int64}
end

apply_edit(emit, e::ClipShapes, s::Shape) = clip_shape(emit, s, e.window)

# Carries out `edit` on `cell`: straight away if the cell is loaded, or else by recording it.
function edit_cell!(cell::Cell, edit::CellEdit)
    if isloaded(cell)
        sink = ContentsSink()
        emit = element -> push_element!(sink, element)
        for p in cell.placements
            apply_edit(emit, edit, p)
        end
        for v in shape_vectors(cell.shapes), s in v
            apply_edit(emit, edit, s)
        end
        finish_edit(emit, edit)
        # Refill the existing containers, so that references to them stay valid.
        copy!(cell.placements, sink.placements)
        for (old, new) in zip(shape_vectors(cell.shapes), shape_vectors(sink.shapes))
            copy!(old, new)
        end
    else
        push!(cell.edits, edit)
        cell.index = nothing
    end
    return cell
end

# Adds a shape or placement to a cell that isn't loaded.
function append_element!(cell::Cell, element::Union{Shape, CellPlacement})
    if isempty(cell.edits) || !(cell.edits[end] isa AppendElements)
        push!(cell.edits, AppendElements(Shape[], CellPlacement[]))
    end
    append = cell.edits[end]
    element isa Shape ? push!(append.shapes, element) : push!(append.placements, element)
    cell.index = nothing
    return cell
end
