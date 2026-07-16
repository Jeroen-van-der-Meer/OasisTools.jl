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

"""
    load_all_cells!(oas)

Load all [`LazyCell`](@ref) objects in `oas` into memory, replacing them with [`Cell`](@ref)
objects. Equivalent to calling [`load_cell!`](@ref) on every cell.
"""
function load_all_cells!(oas::Oasis)
    for (i, cell) in enumerate(cells(oas))
        load_cell!(oas, cell, i)
    end
end

load_cell!(oas, cell_name::AbstractString) = load_cell!(oas, Symbol(cell_name))

"""
    load_cell!(oas, cell_name)

Load a `LazyCell` into memory and replace the `LazyCell` with a corresponding `Cell` in the
input OASIS file.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> oas[:TOP]
Lazy cell TOP

julia> load_cell!(oas, :TOP);

julia> oas[:TOP]
Cell TOP with 5 placements and 0 shapes
```

See also [`load_cell`](@ref).
"""
function load_cell!(oas::Oasis, cell_name::Symbol)
    cell = get_cell(oas, cell_name)
    cell_index = find_cell(oas, cell_name)
    isnothing(cell_index) && error("Could not find cell with name $cell_name")
    cell = oas.cells[cell_index]
    load_cell!(oas, cell, cell_index)
end

load_cell!(::Oasis, ::Cell, ::Int64) = return

function load_cell!(oas::Oasis, lazy_cell::LazyCell, cell_index::Int64)
    cell = load_cell(lazy_cell)
    oas.cells[cell_index] = cell
    return oas
end

load_cell(cell::Cell) = cell

"""
    load_cell(lazy_cell)

Load a `LazyCell` into memory.

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "polygon.oas");

julia> oas = oasisread(filename; lazy = true);

julia> lazy_cell = oas[:TOP]
Lazy cell TOP

julia> loaded_cell = load_cell(lazy_cell)
Cell TOP with 0 placements and 1 shape
```

See also [`load_cell!`](@ref).
"""
function load_cell(lazy_cell::LazyCell)
    state = CellParserState(lazy_cell)
    nbytes = length(lazy_cell.bytes)
    while state.pos < nbytes
        record_type = read_byte(state)
        read_record(record_type, state)
    end
    cell = Cell(lazy_cell.name, state.shapes, state.placements, lazy_cell.unit, lazy_cell._root)
    return cell
end

function add_cell!(oas::Oasis, new_cell; unit::Real = unit(oas))
    add_cell!(cells(oas), new_cell; unit = unit)
    return oas
end

add_cell!(
    cells::AbstractVector{Union{LazyCell, Cell}},
    cell_name::AbstractString;
    unit = unit(cells)
) = add_cell!(cells, Symbol(cell_name); unit = unit)

function add_cell!(
    cells::AbstractVector{Union{LazyCell, Cell}},
    cell_name::Symbol;
    unit::Real = unit(cells)
)
    add_cell!(cells, Cell(cell_name, [], [], unit, true))
    return cells
end

"""
    add_cell!(oas, cell)

Add a cell to an OASIS object.

# Arguments

- `oas::Oasis`: Your input OASIS object.
- `cell`: Can be a `Cell`, `LazyCell`, or simply the name of the new cell you wish to add.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "boxes.oas");

julia> oas = oasisread(filename)
OASIS file with the following cell hierarchy:
TOP\
└─ BOTTOM

julia> add_cell!(oas, :NEW)
OASIS file with the following cell hierarchy:
TOP\
└─ BOTTOM\
NEW
```
"""
function add_cell!(
    cells::AbstractVector{Union{LazyCell, Cell}},
    new_cell::Union{LazyCell, Cell};
    kwargs...
)
    if isnothing(find_cell(cells, new_cell.name))
        push!(cells, new_cell)
    else
        error("Cell with name $(new_cell.name) already exists")
    end
    return cells
end

"""
    add_shape!(cell, shape)
    add_shape!(cell, geometry, layer, datatype; repetition = nothing)

Add a shape to a cell.

# Arguments

- `cell::Cell`: The cell to add the shape to.
- `shape::Shape`: A pre-constructed shape

Or:

- `cell::Cell`: The cell to add the shape to.
- `geometry`: A geometry primitive (e.g. `Rect`, `Polygon`, `Path`).
- `layer::Integer`: The layer number.
- `datatype::Integer`: The datatype number.
- `repetition`: Optional repetition specification.
"""
add_shape!(cell::Cell, shape::Shape) = (push!(cell.shapes, shape); cell)

function add_shape!(
    cell::Cell, geom, layer::Integer, datatype::Integer;
    repetition = nothing
)
    add_shape!(cell, Shape(geom, UInt64(layer), UInt64(datatype), repetition))
end

"""
    add_placement!(cell, placement)
    add_placement!(cell, cell_name, location; rotation = 0.0, magnification = 1.0,
                   flipped = false, repetition = nothing)

Add a cell placement to a cell.

# Arguments

- `cell::Cell`: The cell to add the placement to.
- `placement::CellPlacement`: A pre-constructed placement

Or:

- `cell::Cell`: The cell to add the placement to.
- `cell_name::Symbol`: Name of the cell to place.
- `location::Point{2, Int64}`: Placement location.
- `rotation`, `magnification`, `flipped`, `repetition`: Optional placement parameters.
"""
add_placement!(cell::Cell, p::CellPlacement) = (push!(cell.placements, p); cell)

function add_placement!(
    cell::Cell, cell_name::Symbol, location::Point{2, Int64};
    rotation::Real = 0.0, magnification::Real = 1.0,
    flipped::Bool = false, repetition = nothing)
    add_placement!(
        cell, CellPlacement(
            cell_name, location, Float64(rotation),
            Float64(magnification), flipped, repetition
        )
    )
end

"""
    remove_cell!(oas, cell_name; cascade = false)

Remove a cell from an OASIS object. Throws an error if no cell with the given name exists.

If `cascade = true`, also removes all placements of the deleted cell from other cells. Beware
that lazy-loaded cells are skipped.

Otherwise, use [`validate_placements`](@ref) to check for dangling references.
"""
function remove_cell!(oas::Oasis, cell_name::Symbol; cascade::Bool = false)
    index = find_cell(oas, cell_name)
    isnothing(index) && error("No cell with name $cell_name")
    deleteat!(oas.cells, index)
    if cascade
        for cell in cells(oas)
            cell isa LazyCell && continue
            filter!(p -> p.cellName != cell_name, cell.placements)
        end
    end
    return oas
end

merge_cells(
    cells::AbstractVector{Union{LazyCell, Cell}},
    others::AbstractVector{Union{LazyCell, Cell}}...
) = merge_cells!(copy(cells), others...)

function merge_cells!(
    cells::AbstractVector{Union{LazyCell, Cell}},
    others::AbstractVector{Union{LazyCell, Cell}}...
)
    for other in others
        merge_cells!(cells, other)
    end
    return cells
end

function merge_cells!(
    cells::AbstractVector{Union{LazyCell, Cell}},
    other::AbstractVector{Union{LazyCell, Cell}}
)
    for new_cell in other
        merge_cells!(cells, new_cell)
    end
    return cells
end

function merge_cells!(
    cells::AbstractVector{Union{LazyCell, Cell}},
    new_cell::Union{LazyCell, Cell}
)
    if isnothing(find_cell(cells, new_cell.name))
        push!(cells, new_cell)
    else
        @warn "Duplicate cell name $(new_cell.name) detected"
    end
    return cells
end

"""
    roots(oas)

List cells that are known or presumed to be root cells in the OASIS file.
"""
roots(oas::Oasis) = roots(cells(oas))

roots(cells::AbstractVector{Union{LazyCell, Cell}}) = [c.name for c in cells if c._root]

"""
    layer(oas, shape)
    layer(oas, layer_number, datatype_number)
    layer(oas, name::Symbol)

Find the [`Layer`](@ref) that a given shape, layer/datatype number pair, or name belongs to.
Returns `nothing` if no matching layer is found.
"""
layer(oas::Oasis, args...) = layer(layers(oas), args...)
find_layer(oas::Oasis, args...) = find_layer(layers(oas), args...)

"""
    add_layer!(oas, layer)

Add new layer to your OASIS file.

# Arguments

- `oas::Oasis`: Your OASIS file.
- `layer::Layer`: The layer you want to add.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> oas = oasisread(filename; lazy = true);

julia> layers(oas)
1-element Vector{Layer}:
 M0 (1/0)

julia> add_layer!(oas, Layer(:V0, 2, 0));

julia> layers(oas)
2-element Vector{Layer}:
 M0 (1/0)
 V0 (2/0)
```
"""
add_layer!(oas::Oasis, args...) = add_layer!(layers(oas), args...)

add_layer!(layers::AbstractVector{Layer}, layername, l, d) =
    add_layer!(layers::AbstractVector{Layer}, Layer(layername, l, d))

function add_layer!(layers::AbstractVector{Layer}, new_layer::Layer)
    for layer in layers
        if !isdisjoint(layer, new_layer)
            error("A layer with this signature already exists: ", layer)
        end
    end
    push!(layers, new_layer)
end

"""
    remove_layer!(oas, name::Symbol; cascade = false)
    remove_layer!(oas, layer_number, datatype_number; cascade = false)

Remove a layer from an OASIS object.

If `cascade = true`, also removes all shapes whose layer/datatype numbers fall within the
removed layer's intervals. Beware that lazy-loaded cells are skipped.
"""
function remove_layer!(oas::Oasis, name::Symbol; cascade::Bool=false)
    index = find_layer(oas, name)
    isnothing(index) && error("No layer with name $name")
    removed = oas.layers[index]
    deleteat!(oas.layers, index)
    cascade && _cascade_remove_layer!(oas, removed)
    return oas
end

function remove_layer!(oas::Oasis, l::Integer, d::Integer; cascade::Bool=false)
    index = find_layer(oas, l, d)
    isnothing(index) && error("No layer matching ($l, $d)")
    removed = oas.layers[index]
    deleteat!(oas.layers, index)
    cascade && _cascade_remove_layer!(oas, removed)
    return oas
end

function _cascade_remove_layer!(oas::Oasis, l::Layer)
    for cell in cells(oas)
        cell isa LazyCell && continue
        filter!(s -> !(s.layerNumber in l.layerNumber && s.datatypeNumber in l.datatypeNumber), cell.shapes)
    end
end

merge_layers(layers::AbstractVector{Layer}, others::AbstractVector{Layer}...) =
    merge_layers!(copy(layers), others...)

function merge_layers!(layers::AbstractVector{Layer}, others::AbstractVector{Layer}...)
    for other in others
        merge_layers!(layers, other)
    end
    return layers
end

function merge_layers!(layers::AbstractVector{Layer}, other::AbstractVector{Layer})
    for new_layer in other
        merge_layers!(layers, new_layer)
    end
    return layers
end

function merge_layers!(layers::AbstractVector{Layer}, new_layer::Layer)
    for (i, layer) in enumerate(layers)
        if !isdisjoint(layer, new_layer)
            if (layer.layerNumber == new_layer.layerNumber) &&
                (layer.datatypeNumber == new_layer.datatypeNumber)
                if layer.name != new_layer.name
                    layers[i] = Layer(
                        Symbol(layer.name, :", ", new_layer.name),
                        layer.layerNumber,
                        layer.datatypeNumber
                    )
                end
            else
                if layer.name != new_layer.name
                    @warn "Ambiguity merging layers $layer and $new_layer -- skipping $new_layer"
                else
                    layers[i] = Layer(
                        layer.name,
                        union(layer.layerNumber, new_layer.layerNumber),
                        union(layer.datatypeNumber, new_layer.datatypeNumber)
                    )
                end
            end
        end
    end
    return layers
end

Base.copy(oas::Oasis) = Oasis(copy(oas.cells), copy(oas.layers))

"""
    merge_oases(oas...)

Merge one or more OASIS files. Using an opinionated plural for 'OASIS'.

# Example

```jldoctest
julia> using OasisTools;

julia> filename1 = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");

julia> filename2 = joinpath(OasisTools.TESTDATA_DIRECTORY, "trapezoids.oas");

julia> oas1 = oasisread(filename1; lazy = true)
OASIS file with the following cell hierarchy:
TOP
└─ ?

julia> oas2 = oasisread(filename2)
OASIS file with the following cell hierarchy:
noname

julia> oas = merge_oases(oas1, oas2)
OASIS file with the following cell hierarchy:
TOP
└─ ?\
noname
```
"""
merge_oases(oasis::Oasis, others::Oasis...) = merge_oases!(copy(oasis), others...)

"""
    merge_oases!(oas, others...)

Update OASIS file with content from the other OASIS files. Using an opinionated plural for
'OASIS'.
"""
function merge_oases!(oasis::Oasis, others::Oasis...)
    for other in others
        merge_oases!(oasis, other)
    end
    return oasis
end

function merge_oases!(oasis::Oasis, other::Oasis)
    merge_cells!(oasis.cells, other.cells)
    merge_layers!(oasis.layers, other.layers)
    return oasis
end

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