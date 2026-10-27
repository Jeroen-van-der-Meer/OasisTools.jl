"""
    isloaded(cell)

Whether the shapes and placements of `cell` are held in memory.

See also [`load_cell!`](@ref), [`tier`](@ref).
"""
isloaded(cell::Cell) = !isnothing(cell.shapes)

"""
    tier(cell)

How much is known about `cell` without decoding it again:

- `0`: Nothing but where its contents live in the file.
- `1`: Its placements, and how many shapes it has on each layer. See [`index_cell!`](@ref).
- `2`: Additionally, the bounding box of its own shapes. See [`extent`](@ref).
- `3`: Everything, as the cell is loaded. See [`load_cell!`](@ref).

Operations on a cell compute whatever they need on demand, so the tier only affects how much
work they do.
"""
function tier(cell::Cell)
    isloaded(cell) && return 3
    isnothing(cell.index) && return 0
    return cell.index.hasExtent ? 2 : 1
end

"""
    load_cell!(cell)
    load_cell!(oas, cell_name)

Load the shapes and placements of a cell into memory, applying any pending edits. Returns the
cell.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> oas[:TOP]
Cell TOP (tier 0)

julia> load_cell!(oas, :TOP)
Cell TOP with 5 placements and 0 shapes
```

See also [`load_cell`](@ref), [`load_all_cells!`](@ref).
"""
function load_cell!(cell::Cell)
    isloaded(cell) && return cell
    sink = decode_cell(ContentsSink(), cell)
    cell.shapes = sink.shapes
    cell.placements = sink.placements
    cell.index = nothing
    empty!(cell.edits)
    return cell
end

load_cell!(oas::Oasis, cell_name) = load_cell!(get_existing_cell(oas, cell_name))

"""
    load_cell(cell)

Loaded version of `cell`, leaving `cell` itself untouched. Returns `cell` if it is already
loaded.

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "polygon.oas");

julia> oas = oasisread(filename; lazy = true);

julia> load_cell(oas[:TOP])
Cell TOP with 0 placements and 1 shape
```

See also [`load_cell!`](@ref).
"""
function load_cell(cell::Cell)
    isloaded(cell) && return cell
    sink = decode_cell(ContentsSink(), cell)
    return Cell(cell.name, sink.shapes, sink.placements, cell._root)
end

"""
    load_all_cells!(oas)

Load all cells of `oas` into memory. Equivalent to calling [`load_cell!`](@ref) on every cell.

Cells are decoded in parallel when Julia is started with more than one thread.
"""
function load_all_cells!(oas::Oasis)
    foreach_cell_in_parallel(load_cell!, cells(oas))
    return oas
end

"""
    index_cell!(cell; extent = false)
    index_cell!(oas, cell_name; extent = false)

Summarize the contents of a cell in a [`CellIndex`](@ref), bringing it to [`tier`](@ref) 1, or
to tier 2 if `extent = true`. The index is kept with the cell for later use, unless the cell is
loaded, in which case it is computed from the cell's contents every time.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> index_cell!(oas, :TOP);

julia> oas[:TOP]
Cell TOP with 5 placements and 0 shapes (tier 1)
```

See also [`index_all_cells!`](@ref).
"""
function index_cell!(cell::Cell; extent::Bool = false)
    isloaded(cell) && return CellIndex(decode_cell(IndexSink(true), cell))
    index = cell.index
    if isnothing(index) || (extent && !index.hasExtent)
        index = CellIndex(decode_cell(IndexSink(extent), cell))
        cell.index = index
    end
    return index
end

index_cell!(oas::Oasis, cell_name; extent::Bool = false) =
    index_cell!(get_existing_cell(oas, cell_name); extent = extent)

"""
    index_all_cells!(oas; extent = false)

Call [`index_cell!`](@ref) on every cell of `oas` that isn't loaded. Cells are decoded in
parallel when Julia is started with more than one thread.
"""
function index_all_cells!(oas::Oasis; extent::Bool = false)
    foreach_cell_in_parallel(cells(oas)) do cell
        isloaded(cell) || index_cell!(cell; extent = extent)
    end
    return oas
end

# Decoding a cell only reads the reference tables it shares with other cells, so cells can be
# decoded in parallel.
function foreach_cell_in_parallel(f, cs::Vector{Cell})
    if Threads.nthreads() > 1
        Threads.@threads for i in eachindex(cs)
            f(cs[i])
        end
    else
        foreach(f, cs)
    end
end

"""
    placements(cell)

List the placements contained in `cell`. For a cell that isn't loaded, this brings the cell to
[`tier`](@ref) 1. Use [`add_placement!`](@ref) and [`remove_cell!`](@ref) rather than modifying
the returned list, which for such cells is not the cell's own.
"""
placements(cell::Cell) = isloaded(cell) ? cell.placements : index_cell!(cell).placements

# Placements of `cell` if they're known without decoding anything, and `nothing` otherwise.
function known_placements(cell::Cell)
    isloaded(cell) && return cell.placements
    isnothing(cell.index) && return nothing
    return cell.index.placements
end

"""
    layer_counts(cell)

For every `(layer, datatype)` pair used by the shapes of `cell`, how many shapes there are, as
[`ElementCounts`](@ref). Brings a cell that isn't loaded to [`tier`](@ref) 1.
"""
layer_counts(cell::Cell) = index_cell!(cell).layers

"""
    extent(cell)
    extent(oas, cell_name)

Bounding box of a cell, as a `Rect{2, Int64}`, or `nothing` if the cell is empty.

`extent(cell)` only takes the cell's own shapes into account, and brings a cell that isn't loaded
to [`tier`](@ref) 2. `extent(oas, cell_name)` also includes everything placed in the cell, and
does the same for all cells below it. Bounding boxes of paths, and of cells placed at angles
other than multiples of 90 degrees, may be slightly larger than strictly necessary.
"""
extent(cell::Cell) = index_cell!(cell; extent = true).extent

extent(oas::Oasis, cell_name) =
    hierarchical_extent!(Dict{Symbol, Union{Nothing, Rect{2, Int64}}}(), oas, Symbol(cell_name))

function hierarchical_extent!(
    known::Dict{Symbol, Union{Nothing, Rect{2, Int64}}}, oas::Oasis, cell_name::Symbol,
    visiting::Set{Symbol} = Set{Symbol}()
)
    haskey(known, cell_name) && return known[cell_name]
    cell = get_cell(oas, cell_name)
    # Placements of missing cells don't contribute anything.
    isnothing(cell) && return nothing
    cell_name in visiting && error("Cell $cell_name is placed inside itself")
    push!(visiting, cell_name)
    box = extent(cell)
    for p in placements(cell)
        child_box = hierarchical_extent!(known, oas, p.cellName, visiting)
        isnothing(child_box) && continue
        box = union_box(box, placement_extent(p, child_box))
    end
    delete!(visiting, cell_name)
    known[cell_name] = box
    return box
end

"""
    shapes(cell)
    shapes(cell, layer)
    shapes(cell, layer_number)
    shapes(cell, layer_number, datatype_number)

List the shapes contained in `cell`, optionally filtered by layer or layer number.

The shapes of a cell that isn't loaded are decoded afresh on every call, and not kept. Use
[`add_shape!`](@ref) and [`remove_layer!`](@ref) rather than modifying the returned list, which
for such cells is not the cell's own, and [`foreach_shape`](@ref) to go through the shapes of a
large cell without holding them all in memory.

# Examples

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "boxes.oas");

julia> oas = oasisread(filename);

julia> cell = oas[:BOTTOM];

julia> shapes(cell)
1-element ShapeStore:
 Rectangle in layer (1/0) at (-185, 2875)

julia> shapes(cell, 1, 0)
1-element Vector{Shape}:
 Rectangle in layer (1/0) at (-185, 2875)

julia> wrong_layer = layer(oas, :V1);

julia> shapes(cell, wrong_layer)
Shape[]
```
"""
shapes(cell::Cell) = isloaded(cell) ? cell.shapes : decode_cell(ContentsSink(), cell).shapes
shapes(cell::Cell, l::Layer) = shapes(cell, l.layerNumber, l.datatypeNumber)
shapes(cell::Cell, l::Integer) = shapes(cell, Interval(l, l))
shapes(cell::Cell, l::Integer, d::Integer) = shapes(cell, Interval(l, l), Interval(d, d))
shapes(cell::Cell, l::Interval) = shapes(cell, l, Interval(0, typemax(UInt64)))

function shapes(cell::Cell, l::Interval, d::Interval)
    matches = Shape[]
    foreach_shape(cell) do s
        (s.layerNumber in l && s.datatypeNumber in d) && push!(matches, s)
    end
    return matches
end

"""
    foreach_shape(f, cell)

Call `f` on every shape of `cell`. Shapes of a cell that isn't loaded are decoded one at a time
and not kept, so this works for cells too large to hold in memory.
"""
foreach_shape(f, cell::Cell) = (decode_cell(ShapeCallback(f), cell); nothing)

function get_existing_cell(oas::Oasis, cell_name)
    cell = get_cell(oas, Symbol(cell_name))
    isnothing(cell) && error("Could not find cell with name $cell_name")
    return cell
end

# Copy of a cell that can be edited independently of the original. The bytes a cell is decoded
# from never change, so they can be shared.
function copy_cell(cell::Cell; name::Symbol = cell.name, root::Bool = cell._root)
    if isloaded(cell)
        return Cell(name, copy(cell.shapes), copy(cell.placements), root)
    else
        return Cell(name, nothing, nothing, cell.source, cell.index, map(copy_edit, cell.edits), root)
    end
end
