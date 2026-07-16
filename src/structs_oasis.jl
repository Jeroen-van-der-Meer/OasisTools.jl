"""
    struct Shape(shape, layerNumber, datatypeNumber, repetition)

Geometric shape (such as a polygon or rectangle) or text.

# Properties

- `shape`: The actual shape. If the shape is geometric, then `shape::GeometryBasics.GeometryPrimitive{2, Int64}`,
  unless the shape is a path, in which case `shape::OasisTools.Path` because `GeometryBasics`
  doesn't have an appropriate object to encode paths. If the shape is text, then
  `shape::OasisTools.Text`.
- `layerNumber::UInt64`: The layer that your shape lives in. You can find the name of the layer
  using [`layer`](@ref).
- `datatypeNumber::UInt64`: The 'datatype' that your shape lives in. To clarify, if your shape
  lives in `(1/0)`, then `datatypeNumber = 0`.
- `repetition`: Specifies whether the shape is repeated. If not, `repetition = nothing`.
"""
struct Shape{T}
    shape::T
    layerNumber::UInt64 # If T = Text, this refers to textlayerNumber
    datatypeNumber::UInt64 # If T = Text, this refers to texttypeNumber
    repetition::Union{Nothing, Vector{Point{2, Int64}}, PointGridRange}
end

"""
    struct Layer

A named layer, associating a human-readable name with a layer number and datatype number
(or ranges thereof).

# Properties

- `name::Symbol`: Name of the layer.
- `layerNumber::Interval`: Layer number or range of layer numbers.
- `datatypeNumber::Interval`: Datatype number or range of datatype numbers.
"""
struct Layer
    name::Symbol
    layerNumber::Interval
    datatypeNumber::Interval
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

layer(layers::AbstractVector{Layer}, s::Shape) = layer(layers, s.layerNumber, s.datatypeNumber)

function find_layer(layers::AbstractVector{Layer}, l::Integer, d::Integer)
    return findfirst(r -> (l in r.layerNumber && d in r.datatypeNumber), layers)
end

function find_layer(layers::AbstractVector{Layer}, name::Symbol)
    return findfirst(r -> r.name == name, layers)
end

find_layer(layers::AbstractVector{Layer}, s::Shape) = find_layer(layers, s.layerNumber, s.datatypeNumber)

Base.isdisjoint(l1::Layer, l2::Layer) =
    isdisjoint(l1.layerNumber, l2.layerNumber) ||
    isdisjoint(l1.datatypeNumber, l2.datatypeNumber)

struct FileProperty
    nameOrNumber::Union{UInt64, Symbol}
    valueList::Vector{Any}
end

Base.@kwdef mutable struct Metadata
    unit::Float64 = DEFAULT_UNIT
    const fileProperties::Vector{FileProperty} = []
    const roots::Vector{Symbol} = []
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
end

"""
    struct CellPlacement

Object encoding the placement of a cell in another cell.

# Properties

- `cellName::Symbol`: Name of cell that's being placed.
- `location::Point{2, Int64}`: Where the cell will be placed.
- `rotation::Float64`: Counterclockwise rotation (in degrees) of the cell.
- `magnification::Float64`: Magnification of the cell.
- `flipped::Bool`: Indicates whether or not the cell is reflected (or flipped) around the
  x-axis. Note: If a cell is flipped and has nonzero rotation, then the flip is applied first,
  and the rotation is applied second.
- `repetition`: Specifies whether the placement is repeated. If not, `repetition = nothing`.
"""
struct CellPlacement
    cellName::Symbol
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

    return CellPlacement(inner.cellName, loc, rot, mag, flip, rep)
end

function _transform_point(
    p::Point{2, Int64}, rotation::Float64, magnification::Float64, flipped::Bool
)
    x, y = Float64(p[1]), Float64(p[2])
    if flipped
        y = -y
    end
    θ = deg2rad(rotation)
    c, s = cos(θ), sin(θ)
    return Point{2, Int64}(
        round(Int64, magnification * (c * x - s * y)),
        round(Int64, magnification * (s * x + c * y))
    )
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
        CellPlacement(p.cellName, p.location + offset, p.rotation, p.magnification, p.flipped, nothing)
        for offset in rep
    )
end

abstract type AbstractCell end

"""
    struct Cell

# Properties

- `name::Symbol`: Name of the cell.
- `shapes::Vector{Shape}`: Lists the shapes, such as polygons and lines, that are contained in
  the cell.
- `placements::Vector{CellPlacement}`: Lists all other cells that are placed in this cell.
- `unit::Float64`: Unit length.
- `_root::Bool`: Indicates whether the cell is a root cell (i.e., isn't contained in any other
  cell).

See also [`LazyCell`](@ref).
"""
mutable struct Cell <: AbstractCell
    const name::Symbol
    const shapes::Vector{Shape}
    const placements::Vector{CellPlacement}
    const unit::Float64
    _root::Bool
end

Cell(name::AbstractString, args...) = Cell(Symbol(name), args...)

"""
    shapes(cell)
    shapes(cell, layer)
    shapes(cell, layer_number)
    shapes(cell, layer_number, datatype_number)

List the shapes contained in `cell`, optionally filtered by layer or layer number.

# Examples

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "boxes.oas");

julia> oas = oasisread(filename);

julia> cell = oas[:BOTTOM];

julia> shapes(cell)
1-element Vector{Shape}:
 Rectangle in layer (1/0) at (-185, 2875)

julia> shapes(cell, 1, 0)
1-element Vector{Shape}:
 Rectangle in layer (1/0) at (-185, 2875)

julia> wrong_layer = layer(oas, :V1);

julia> shapes(cell, wrong_layer)
Shape[]
```
"""
shapes(cell::Cell) = cell.shapes
shapes(cell::Cell, l::Layer) = shapes(cell, l.layerNumber, l.datatypeNumber)
shapes(cell::Cell, l::Integer) = shapes(cell, Interval(l, l))
shapes(cell::Cell, l::Integer, d::Integer) = shapes(cell, Interval(l, l), Interval(d, d))
shapes(cell::Cell, l::Interval) = shapes(cell, l, Interval(0, typemax(UInt64)))

function shapes(cell::Cell, l::Interval, d::Interval)
    return filter(cell.shapes) do s
        s.layerNumber in l && s.datatypeNumber in d
    end
end

"""
    placements(cell)

List the placements contained in `cell`. Not yet supported for `LazyCell`s.
"""
placements(cell::Cell) = cell.placements

"""
    name(cell)

Name of a cell.
"""
name(cell::Cell) = cell.name

"""
    unit(cell)
    unit(oas)

Unit length of a cell or OASIS object, in grid steps per micron.
"""
unit(cell::Cell) = cell.unit

"""
    struct LazyCell

Lazy-loaded version of a `Cell`.

# Properties

- `name::Symbol`: Name of the cell.
- `bytes::Vector{UInt8}`: Bytes of the corresponding CELL record.
- `cellnameReferences::Dict{UInt64, Symbol}`: To ensure all bytes of the corresponding CELL
  record are interpretable, a `LazyCell` stores a list of internal cell name references.
- `textstringReferences::Dict{UInt64, Symbol}`: Internal text string references, stored for the
  same reason as `cellnameReferences`.
- `unit::Float64`: Unit length.
- `_root::Bool`: Indicates whether the cell is a root cell (i.e., isn't contained in any other
  cell).

See also [`Cell`](@ref), [`load_cell!`](@ref).
"""
mutable struct LazyCell <: AbstractCell
    const name::Symbol
    const bytes::SubArray{UInt8, 1, Vector{UInt8}, Tuple{UnitRange{Int64}}, true}
    const cellnameReferences::Dict{UInt64, Symbol}
    const textstringReferences::Dict{UInt64, Symbol}
    const unit::Float64
    _root::Bool
end

name(cell::LazyCell) = cell.name
unit(cell::LazyCell) = cell.unit

struct PreprocessedCell <: AbstractCell
    nameOrNumber::Union{Symbol, UInt64}
    bytes::SubArray{UInt8, 1, Vector{UInt8}, Tuple{UnitRange{Int64}}, true}
end

"""
    struct Oasis

Object containing all the data of your OASIS file.

# Properties

- `cells::Vector{Union{LazyCell, Cell}}`: Cells in your OASIS file. The cells can either be
  `Cell` objects or lazy-loaded `LazyCell` objects.
- `layers::Vector{Layer}`: Lists all named layers in your OASIS file.
"""
Base.@kwdef struct Oasis
    cells::Vector{Union{LazyCell, Cell}} = []
    layers::Vector{Layer} = [] # FIXME: Unnamed layers aren't added right now.
end

Base.getindex(oas::Oasis, name::AbstractString) = getindex(oas, Symbol(name))
function Base.getindex(oas::Oasis, name::Symbol)
    return get_cell(oas, name)
end

get_cell(oas::Oasis, name) = get_cell(cells(oas), name)
get_cell(cells::AbstractVector{Union{LazyCell, Cell}}, name::AbstractString) =
    get_cell(cells, Symbol(name))
function get_cell(cells::AbstractVector{Union{LazyCell, Cell}}, name::Symbol)
    index = find_cell(cells, name)
    isnothing(index) && return nothing
    return cells[index]
end

find_cell(oas::Oasis, name) = find_cell(cells(oas), name)
find_cell(cells::AbstractVector{Union{LazyCell, Cell}}, name::AbstractString) =
    find_cell(cells, Symbol(name))
find_cell(cells::AbstractVector{Union{LazyCell, Cell}}, name::Symbol) =
    findfirst(cell -> cell.name == name, cells)

unit(oas::Oasis) = unit(cells(oas))

function unit(cells::AbstractVector{Union{LazyCell, Cell}})
    if isempty(cells)
        @warn "No cells found; taking unit $DEFAULT_UNIT steps per micron"
        unit = DEFAULT_UNIT
    else
        units = unique(cell.unit for cell in cells)
        unit = first(units)
        if length(units) > 1
            @warn "OASIS file has multiple unit lengths"
        end
    end
    return unit
end

"""
    cells(oas)

Returns a list of all cells in your OASIS object.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "polygon.oas");

julia> oas = oasisread(filename);

julia> cells(oas)
1-element Vector{Union{Cell, LazyCell}}:
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
