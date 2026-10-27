"""
    isloaded(cell)

Whether the shapes and placements of `cell` are held in memory.

See also [`load!`](@ref), [`tier`](@ref).
"""
isloaded(cell::Cell) = !isnothing(cell.shapes)

"""
    tier(cell)

How much is known about `cell` without decoding it again:

- `0`: Nothing but where its contents live in the file.
- `1`: Its placements, and how many shapes it has on each layer. See [`index!`](@ref).
- `2`: Additionally, the bounding box of its own shapes. See [`extent`](@ref).
- `3`: Everything, as the cell is loaded. See [`load!`](@ref).

Operations on a cell compute whatever they need on demand, so the tier only affects how much
work they do.
"""
function tier(cell::Cell)
    isloaded(cell) && return 3
    isnothing(cell.index) && return 0
    return cell.index.hasExtent ? 2 : 1
end

"""
    load!(cell)
    load!(oas)

Load the shapes and placements of a cell, or of every cell in `oas`, into memory, applying any
pending edits. Cells of `oas` are decoded in parallel when Julia is started with more than one
thread. Returns its argument.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> oas[:TOP]
Cell TOP (tier 0)

julia> load!(oas[:TOP])
Cell TOP with 5 placements and 0 shapes
```
"""
function load!(cell::Cell)
    isloaded(cell) && return cell
    sink = decode_cell(ContentsSink(), cell)
    cell.shapes = sink.shapes
    cell.placements = sink.placements
    cell.index = nothing
    empty!(cell.edits)
    return cell
end

function load!(oas::Oasis)
    foreach_cell_in_parallel(load!, cells(oas))
    return oas
end

"""
    index!(cell; extent = false)
    index!(oas; extent = false)

Bring a cell that isn't loaded, or every such cell in `oas`, to [`tier`](@ref) 1, or to tier 2
if `extent = true`, by summarizing its contents. The summary is kept with the cell for later
use. Cells of `oas` are decoded in parallel when Julia is started with more than one thread.
Returns its argument.

Functions such as [`placements`](@ref) and [`extent`](@ref) do this whenever they need to, so
this is only useful to do the work up front.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> index!(oas[:TOP])
Cell TOP with 5 placements and 0 shapes (tier 1)
```
"""
index!(cell::Cell; extent::Bool = false) = (cached_index(cell; extent = extent); cell)

function index!(oas::Oasis; extent::Bool = false)
    foreach_cell_in_parallel(cells(oas)) do cell
        isloaded(cell) || index!(cell; extent = extent)
    end
    return oas
end

# The summary of the contents of `cell`, computing it if needed. For a cell that isn't loaded,
# this is the summary kept with the cell, so it must not be modified. For a loaded cell, it is
# computed afresh every time, as the cell's contents may have changed.
function cached_index(cell::Cell; extent::Bool = false)
    isloaded(cell) && return CellIndex(decode_cell(IndexSink(true), cell))
    index = cell.index
    if isnothing(index) || (extent && !index.hasExtent)
        index = CellIndex(decode_cell(IndexSink(extent), cell))
        cell.index = index
    end
    return index
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
[`tier`](@ref) 1, and returns a copy: modifying it doesn't change the cell. Use
[`add_placement!`](@ref) and [`remove_cell!`](@ref) to change the placements of any cell.
"""
placements(cell::Cell) = isloaded(cell) ? cell.placements : copy(cached_placements(cell))

# Placements of `cell`, without making a copy for cells that aren't loaded. The result must not
# be modified.
cached_placements(cell::Cell) = isloaded(cell) ? cell.placements : cached_index(cell).placements

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
layer_counts(cell::Cell) = isloaded(cell) ? cached_index(cell).layers : copy(cached_index(cell).layers)

"""
    extent(cell)
    extent(oas, cell_name)

Bounding box of a cell, as a `Rect{2, Int64}`, or `nothing` if the cell is empty.

`extent(cell)` only takes the cell's own shapes into account, and brings a cell that isn't loaded
to [`tier`](@ref) 2. `extent(oas, cell_name)` also includes everything placed in the cell, and
does the same for all cells below it. Bounding boxes of paths, and of cells placed at angles
other than multiples of 90 degrees, may be slightly larger than strictly necessary.
"""
extent(cell::Cell) = cached_index(cell; extent = true).extent

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
    for p in cached_placements(cell)
        child_box = hierarchical_extent!(known, oas, p.cell, visiting)
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
[`add_shape!`](@ref) and [`filter_shapes!`](@ref) rather than modifying the returned list, which
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
shapes(cell::Cell, l::Layer) = shapes(cell, l.layer, l.datatype)
shapes(cell::Cell, l::Integer) = shapes(cell, Interval(l, l))
shapes(cell::Cell, l::Integer, d::Integer) = shapes(cell, Interval(l, l), Interval(d, d))
shapes(cell::Cell, l::Interval) = shapes(cell, l, Interval(0, typemax(UInt64)))

function shapes(cell::Cell, l::Interval, d::Interval)
    matches = Shape[]
    foreach_shape(cell) do s
        (s.layer in l && s.datatype in d) && push!(matches, s)
    end
    return matches
end

"""
    foreach_shape(f, cell)

Call `f` on every shape of `cell`. Shapes of a cell that isn't loaded are decoded one at a time
and not kept, so this works for cells too large to hold in memory.
"""
foreach_shape(f, cell::Cell) = (decode_cell(ShapeCallback(f), cell); nothing)

# Copy of a cell that can be edited independently of the original. The bytes a cell is decoded
# from never change, so they can be shared.
function copy_cell(cell::Cell; name::Symbol = cell.name)
    if isloaded(cell)
        return Cell(name, copy(cell.shapes), copy(cell.placements))
    else
        return Cell(name, nothing, nothing, cell.source, cell.index, map(copy_edit, cell.edits))
    end
end
