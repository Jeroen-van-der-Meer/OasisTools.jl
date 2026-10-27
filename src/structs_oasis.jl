"""
    struct Shape(shape, layer, datatype, repetition)

Geometric shape (such as a polygon or rectangle) or text.

# Properties

- `shape`: The actual shape. If the shape is geometric, then `shape::GeometryBasics.GeometryPrimitive{2, Int64}`,
  unless the shape is a path, in which case `shape::OasisTools.Path` because `GeometryBasics`
  doesn't have an appropriate object to encode paths. If the shape is text, then
  `shape::OasisTools.Text`.
- `layer::UInt64`: The layer that your shape lives in. You can find the name of the layer
  using [`layer`](@ref).
- `datatype::UInt64`: The 'datatype' that your shape lives in. To clarify, if your shape
  lives in `(1/0)`, then `datatype = 0`.
- `repetition`: Specifies whether the shape is repeated. If not, `repetition = nothing`.
"""
struct Shape{T}
    shape::T
    layer::UInt64 # The text layer, for texts
    datatype::UInt64 # The text type, for texts
    repetition::Union{Nothing, Vector{Point{2, Int64}}, PointGridRange}
end

"""
    struct Layer

A named layer, associating a human-readable name with a layer number and datatype number
(or ranges thereof).

# Properties

- `name::Symbol`: Name of the layer.
- `layer::Interval`: Layer number or range of layer numbers.
- `datatype::Interval`: Datatype number or range of datatype numbers.
"""
struct Layer
    name::Symbol
    layer::Interval
    datatype::Interval
end

Layer(name::AbstractString, args...) = Layer(Symbol(name), args...)

"""
    name(layer)

Name of a layer.
"""
name(layer::Layer) = layer.name

function layer(layers::AbstractVector{Layer}, l::Integer, d::Integer)
    index = find_layer(layers, l, d)
    isnothing(index) && return nothing
    return layers[index]
end

function layer(layers::AbstractVector{Layer}, name::Symbol)
    index = find_layer(layers, name)
    isnothing(index) && return nothing
    return layers[index]
end

layer(layers::AbstractVector{Layer}, s::Shape) = layer(layers, s.layer, s.datatype)

function find_layer(layers::AbstractVector{Layer}, l::Integer, d::Integer)
    return findfirst(r -> (l in r.layer && d in r.datatype), layers)
end

function find_layer(layers::AbstractVector{Layer}, name::Symbol)
    return findfirst(r -> r.name == name, layers)
end

find_layer(layers::AbstractVector{Layer}, s::Shape) = find_layer(layers, s.layer, s.datatype)

Base.isdisjoint(l1::Layer, l2::Layer) =
    isdisjoint(l1.layer, l2.layer) ||
    isdisjoint(l1.datatype, l2.datatype)

struct FileProperty
    nameOrNumber::Union{UInt64, Symbol}
    valueList::Vector{Any}
end

Base.@kwdef mutable struct Metadata
    unit::Float64 = DEFAULT_UNIT
    const fileProperties::Vector{FileProperty} = []
end

struct Text # Might want to think of a better name for this struct, since Text is used by Docs.
    text::Symbol
    location::Point{2, Int64}
    repetition::Union{Nothing, Vector{Point{2, Int64}}, PointGridRange}
end

"""
    Path(points, width)

A polyline with finite width, or equivalently, a `GeometryBasis.LineString` with specified
width.
"""
struct Path{Dim, T<:Real} <: AbstractGeometry{Dim, T}
    points::Vector{Point{Dim, T}}
    width::T

    function Path{Dim, T}(points::Vector{Point{Dim, T}}, width::T) where {Dim, T <: Real}
        # OASIS stores half of the width of a path, so odd widths couldn't be written.
        T <: Integer && isodd(width) && throw(ArgumentError(
            "The width of a path must be even, as OASIS stores half of it; got $width"
        ))
        return new{Dim, T}(points, width)
    end
end

Path(points::Vector{Point{Dim, T}}, width::Real) where {Dim, T <: Real} =
    Path{Dim, T}(points, convert(T, width))

"""
    struct CellPlacement

Object encoding the placement of a cell in another cell.

# Properties

- `cell::Symbol`: Name of cell that's being placed.
- `location::Point{2, Int64}`: Where the cell will be placed.
- `rotation::Float64`: Counterclockwise rotation (in degrees) of the cell.
- `magnification::Float64`: Magnification of the cell.
- `flipped::Bool`: Indicates whether or not the cell is reflected (or flipped) around the
  x-axis. Note: If a cell is flipped and has nonzero rotation, then the flip is applied first,
  and the rotation is applied second.
- `repetition`: Specifies whether the placement is repeated. If not, `repetition = nothing`.
"""
struct CellPlacement
    cell::Symbol
    location::Point{2, Int64}
    rotation::Float64
    magnification::Float64
    flipped::Bool
    repetition::Union{Nothing, Vector{Point{2, Int64}}, PointGridRange}
end

"""
    *(outer::CellPlacement, inner::CellPlacement)

Compose two cell placements. If `outer` places cell B inside cell A, and `inner` places cell C
inside cell B, then `outer * inner` describes the placement of cell C inside cell A.
"""
function Base.:*(outer::CellPlacement, inner::CellPlacement)
    mag = outer.magnification * inner.magnification
    
    flip = outer.flipped ⊻ inner.flipped

    # If outer is flipped, the inner rotation reverses direction.
    rot = outer.flipped ? outer.rotation - inner.rotation : outer.rotation + inner.rotation
    rot = mod(rot, 360.0)

    # Location: apply outer's linear transformation to inner's location, then add outer's offset.
    loc = _transform_point(inner.location, outer.rotation, outer.magnification, outer.flipped) +
          outer.location

    # Repetition: transform inner repetition by outer's linear part, then Minkowski sum.
    inner_rep = _transform_repetition(
        inner.repetition, outer.rotation, outer.magnification, outer.flipped
    )
    rep = _minkowski_repetition(outer.repetition, inner_rep)

    return CellPlacement(inner.cell, loc, rot, mag, flip, rep)
end

function _transform_point(
    p::Point{2, Int64}, rotation::Float64, magnification::Float64, flipped::Bool
)
    x, y = transform_point_float(p, rotation, magnification, flipped)
    # Rounding halves away from zero, as KLayout does.
    return Point{2, Int64}(round(Int64, x, RoundNearestTiesAway), round(Int64, y, RoundNearestTiesAway))
end

_transform_repetition(::Nothing, ::Float64, ::Float64, ::Bool) = nothing

function _transform_repetition(
    rep::Vector{Point{2, Int64}},
    rotation::Float64,
    magnification::Float64,
    flipped::Bool
)
    return [_transform_point(p, rotation, magnification, flipped) for p in rep]
end

function _transform_repetition(
    rep::PointGridRange,
    rotation::Float64,
    magnification::Float64,
    flipped::Bool
)
    return PointGridRange(
        _transform_point(rep.start, rotation, magnification, flipped),
        rep.nstepx, rep.nstepy,
        _transform_point(rep.stepx, rotation, magnification, flipped),
        _transform_point(rep.stepy, rotation, magnification, flipped)
    )
end

_minkowski_repetition(::Nothing, ::Nothing) = nothing
_minkowski_repetition(::Nothing, b) = b
_minkowski_repetition(a, ::Nothing) = a

function _minkowski_repetition(a::PointGridRange, b::PointGridRange)
    a_is_1d = a.nstepx == 1 || a.nstepy == 1
    b_is_1d = b.nstepx == 1 || b.nstepy == 1

    if a_is_1d && b_is_1d
        step_a, n_a = a.nstepy == 1 ? (a.stepx, a.nstepx) : (a.stepy, a.nstepy)
        step_b, n_b = b.nstepy == 1 ? (b.stepx, b.nstepx) : (b.stepy, b.nstepy)

        # Check linear independence via cross product
        if step_a[1] * step_b[2] - step_a[2] * step_b[1] != 0
            return PointGridRange(a.start + b.start, n_a, n_b, step_a, step_b)
        end
    end

    # Fall back to explicit enumeration
    return _minkowski_vector(collect(a), collect(b))
end

function _minkowski_repetition(a::Vector{Point{2, Int64}}, b::Vector{Point{2, Int64}})
    return _minkowski_vector(a, b)
end

function _minkowski_repetition(a::PointGridRange, b::Vector{Point{2, Int64}})
    return _minkowski_vector(collect(a), b)
end

function _minkowski_repetition(a::Vector{Point{2, Int64}}, b::PointGridRange)
    return _minkowski_vector(a, collect(b))
end

function _minkowski_vector(a::Vector{Point{2, Int64}}, b::Vector{Point{2, Int64}})
    result = Set{Point{2, Int64}}()
    for pa in a, pb in b
        push!(result, pa + pb)
    end
    return sort!(collect(result))
end

"""
    expand(placement::CellPlacement)

Expand a `CellPlacement` with a repetition into a generator of individual `CellPlacement`
objects, each with `repetition = nothing` and the repetition offset added to `location`.
If the placement has no repetition, yields a single placement.
"""
function expand(p::CellPlacement)
    rep = p.repetition
    if isnothing(rep)
        return (p for _ in 1:1)
    end
    return (
        CellPlacement(p.cell, p.location + offset, p.rotation, p.magnification, p.flipped, nothing)
        for offset in rep
    )
end

"""
    ShapeStore()
    ShapeStore(shapes)

Container holding the shapes of a [`Cell`](@ref), with one densely typed vector per geometry
kind.

Behaves as an `AbstractVector{Shape}`, so iterating, indexing and `length` all walk the groups
in order (rectangles, polygons, triangles, paths, circles, texts). Note that this means shapes
come out grouped by kind rather than in the order they appeared in the file; OASIS does not
assign meaning to the ordering of shapes within a cell.

Indexing boxes each element, because the element type has to widen to `Shape`. Reach for the
typed fields directly when that matters:

```julia
for shape in cell.shapes.rectangles
    # shape::Shape{Rect{2, Int64}}
end
```
"""
struct ShapeStore <: AbstractVector{Shape}
    rectangles::Vector{Shape{Rect{2, Int64}}}
    polygons::Vector{Shape{Polygon{2, Int64}}}
    triangles::Vector{Shape{Triangle{2, Int64}}}
    paths::Vector{Shape{Path{2, Int64}}}
    circles::Vector{Shape{Circle{Int64}}}
    texts::Vector{Shape{Text}}
end

ShapeStore() = ShapeStore(
    Shape{Rect{2, Int64}}[], Shape{Polygon{2, Int64}}[], Shape{Triangle{2, Int64}}[],
    Shape{Path{2, Int64}}[], Shape{Circle{Int64}}[], Shape{Text}[]
)

function ShapeStore(shapes)
    store = ShapeStore()
    for shape in shapes
        push!(store, shape)
    end
    return store
end

shape_vectors(s::ShapeStore) =
    (s.rectangles, s.polygons, s.triangles, s.paths, s.circles, s.texts)

Base.length(s::ShapeStore) = sum(length, shape_vectors(s))
Base.size(s::ShapeStore) = (length(s),)
Base.IndexStyle(::Type{ShapeStore}) = IndexLinear()

function Base.getindex(s::ShapeStore, i::Integer)
    @boundscheck checkbounds(s, i)
    offset = Int(i)
    for v in shape_vectors(s)
        n = length(v)
        offset <= n && return @inbounds v[offset]
        offset -= n
    end
    throw(BoundsError(s, i))
end

Base.push!(s::ShapeStore, shape::Shape{Rect{2, Int64}}) = (push!(s.rectangles, shape); s)
Base.push!(s::ShapeStore, shape::Shape{Polygon{2, Int64}}) = (push!(s.polygons, shape); s)
Base.push!(s::ShapeStore, shape::Shape{Triangle{2, Int64}}) = (push!(s.triangles, shape); s)
Base.push!(s::ShapeStore, shape::Shape{Path{2, Int64}}) = (push!(s.paths, shape); s)
Base.push!(s::ShapeStore, shape::Shape{Circle{Int64}}) = (push!(s.circles, shape); s)
Base.push!(s::ShapeStore, shape::Shape{Text}) = (push!(s.texts, shape); s)

function Base.filter!(f, s::ShapeStore)
    for v in shape_vectors(s)
        filter!(f, v)
    end
    return s
end

function Base.empty!(s::ShapeStore)
    for v in shape_vectors(s)
        empty!(v)
    end
    return s
end

Base.copy(s::ShapeStore) = ShapeStore(map(copy, shape_vectors(s))...)

"""
    struct CellSource

Where the contents of a cell that hasn't been loaded live: the bytes of its CELL record in the
memory-mapped file, along with the file's reference tables needed to interpret them.
"""
struct CellSource
    bytes::SubArray{UInt8, 1, Vector{UInt8}, Tuple{UnitRange{Int64}}, true}
    cellnameReferences::Dict{UInt64, Symbol}
    textstringReferences::Dict{UInt64, Symbol}
end

"""
    struct ElementCounts

How many records describe some group of elements, and how many instances those records
amount to once their repetitions are expanded.
"""
struct ElementCounts
    records::Int64
    instances::Int64
end

"""
    struct CellIndex

Summary of the contents of a cell, which can be collected without keeping its shapes in
memory. See [`index!`](@ref).

# Properties

- `placements::Vector{CellPlacement}`: All placements in the cell.
- `layers::Dict{Tuple{UInt64, UInt64}, ElementCounts}`: For every `(layer, datatype)` pair
  that the cell's shapes use, how many shapes there are. Texts are counted under their text
  layer and text type.
- `hasExtent::Bool`: Whether `extent` was computed.
- `extent::Union{Nothing, Rect{2, Int64}}`: Bounding box of the cell's own shapes, ignoring
  its placements; `nothing` if the cell has no shapes or if the extent wasn't computed.
"""
struct CellIndex
    placements::Vector{CellPlacement}
    layers::Dict{Tuple{UInt64, UInt64}, ElementCounts}
    hasExtent::Bool
    extent::Union{Nothing, Rect{2, Int64}}
end

"""
    abstract type CellEdit

A change to a cell that hasn't been loaded, recorded to be applied whenever the cell's contents
get decoded.
"""
abstract type CellEdit end

"""
    struct Cell

A cell of an OASIS file, holding shapes and placements of other cells.

A cell is either *loaded*, in which case its shapes and placements live in memory, or not, in
which case they are decoded from the file whenever they're needed. What is known about a cell
that isn't loaded comes in tiers; see [`tier`](@ref).

# Properties

- `name::Symbol`: Name of the cell.
- `shapes::Union{Nothing, ShapeStore}`: The shapes of a loaded cell; `nothing` otherwise. Use
  [`shapes`](@ref) to get the shapes of any cell.
- `placements::Union{Nothing, Vector{CellPlacement}}`: The placements of a loaded cell;
  `nothing` otherwise. Use [`placements`](@ref) to get the placements of any cell.
- `source::Union{Nothing, CellSource}`: Where the cell's contents can be decoded from, or
  `nothing` for a cell that was created in memory.
- `index::Union{Nothing, CellIndex}`: Summary of the contents of a cell that isn't loaded, if
  it was computed.
- `edits::Vector{CellEdit}`: Changes to a cell that isn't loaded, still to be applied.

A loaded cell can be created from its shapes and placements, as `Cell(name, shapes, placements)`.

See also [`load!`](@ref), [`index!`](@ref).
"""
mutable struct Cell
    const name::Symbol
    shapes::Union{Nothing, ShapeStore}
    placements::Union{Nothing, Vector{CellPlacement}}
    source::Union{Nothing, CellSource}
    index::Union{Nothing, CellIndex}
    const edits::Vector{CellEdit}
end

Cell(name::AbstractString, args...) = Cell(Symbol(name), args...)

Cell(name::Symbol, shapes::ShapeStore, placements::AbstractVector{CellPlacement}) =
    Cell(name, shapes, convert(Vector{CellPlacement}, placements), nothing, nothing, CellEdit[])

Cell(name::Symbol, shapes::Vector{<:Shape}, placements::AbstractVector{CellPlacement}) =
    Cell(name, ShapeStore(shapes), placements)

Cell(name::Symbol, source::CellSource) = Cell(name, nothing, nothing, source, nothing, CellEdit[])

"""
    name(cell)

Name of a cell.
"""
name(cell::Cell) = cell.name

struct PreprocessedCell
    nameOrNumber::Union{Symbol, UInt64}
    bytes::SubArray{UInt8, 1, Vector{UInt8}, Tuple{UnitRange{Int64}}, true}
end

"""
    struct Oasis

Object containing all the data of your OASIS file.

# Properties

- `cells::Vector{Cell}`: Cells in your OASIS file, loaded or not.
- `layers::Vector{Layer}`: Lists all named layers in your OASIS file.
- `unit::Float64`: Unit length, in grid steps per micron.
"""
mutable struct Oasis
    const cells::Vector{Cell}
    const layers::Vector{Layer} # FIXME: Unnamed layers aren't added right now.
    unit::Float64
    # Cell name to position in `cells`. Rebuilt on demand if `cells` is mutated directly.
    const _index::Dict{Symbol, Int64}
    _indexedLength::Int64
end

function Oasis(
    cells::AbstractVector = Cell[],
    layers::AbstractVector{Layer} = Layer[];
    unit::Real = DEFAULT_UNIT
)
    oas = Oasis(
        convert(Vector{Cell}, cells),
        convert(Vector{Layer}, layers),
        Float64(unit),
        Dict{Symbol, Int64}(),
        0
    )
    reindex_cells!(oas)
    return oas
end

# Appends without checking for duplicates; callers are responsible for that.
function push_cell!(oas::Oasis, new_cell::Cell)
    push!(oas.cells, new_cell)
    oas._index[new_cell.name] = length(oas.cells)
    oas._indexedLength = length(oas.cells)
    return oas
end

function reindex_cells!(oas::Oasis)
    index = oas._index
    empty!(index)
    for (i, cell) in enumerate(oas.cells)
        get!(index, cell.name, i)
    end
    oas._indexedLength = length(oas.cells)
    return oas
end

# `oas[name]` throws a `KeyError` for a missing cell; `get(oas, name, default)` doesn't.
function Base.getindex(oas::Oasis, name::Union{Symbol, AbstractString})
    cell = get_cell(oas, name)
    isnothing(cell) && throw(KeyError(Symbol(name)))
    return cell
end

Base.get(oas::Oasis, name::Union{Symbol, AbstractString}, default) =
    something(get_cell(oas, name), Some(default))

Base.haskey(oas::Oasis, name::Union{Symbol, AbstractString}) = !isnothing(get_cell(oas, name))

get_cell(oas::Oasis, name::AbstractString) = get_cell(oas, Symbol(name))
function get_cell(oas::Oasis, name::Symbol)
    index = find_cell(oas, name)
    isnothing(index) && return nothing
    return oas.cells[index]
end

find_cell(oas::Oasis, name::AbstractString) = find_cell(oas, Symbol(name))
function find_cell(oas::Oasis, name::Symbol)
    cs = oas.cells
    oas._indexedLength == length(cs) || reindex_cells!(oas)
    i = get(oas._index, name, nothing)
    isnothing(i) && return nothing
    # `cells` may have been reordered without going through the mutators.
    (i <= length(cs) && cs[i].name === name) && return i
    reindex_cells!(oas)
    return get(oas._index, name, nothing)
end

"""
    unit(oas)

Unit length of an OASIS object, in grid steps per micron.
"""
unit(oas::Oasis) = oas.unit

"""
    cells(oas)

Returns a list of all cells in your OASIS object.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "polygon.oas");

julia> oas = oasisread(filename);

julia> cells(oas)
1-element Vector{Cell}:
 Cell TOP with 0 placements and 1 shape
```
"""
cells(oas::Oasis) = oas.cells

"""
    layers(oas)

List all (explicitly named) layers in your OASIS object.
"""
layers(oas::Oasis) = oas.layers

"""
    cell_names(oas)

Returns a list of all cell names in your OASIS file.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "boxes.oas");

julia> oas = oasisread(filename);

julia> cell_names(oas)
2-element Vector{Symbol}:
 :BOTTOM
 :TOP
```

See also [`cells`](@ref), [`name`](@ref).
"""
cell_names(oas::Oasis) = [c.name for c in oas.cells]
