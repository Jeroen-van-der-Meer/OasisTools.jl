"""
    add_cell!(oas, cell)
    add_cell!(oas, cell_name)

Add a cell to `oas`: either a `Cell`, or a new, empty cell with the given name. Throws an error
if a cell with that name already exists. Returns `oas`.

# Example

```jldoctest
julia> using OasisTools;

julia> filename = joinpath(OasisTools.TESTDATA_DIRECTORY, "boxes.oas");

julia> oas = oasisread(filename)
OASIS file with the following cell hierarchy:
TOP
└─ BOTTOM

julia> add_cell!(oas, :NEW)
OASIS file with the following cell hierarchy:
TOP
└─ BOTTOM
NEW
```
"""
function add_cell!(oas::Oasis, new_cell::Cell)
    haskey(oas, new_cell.name) && error("Cell with name $(new_cell.name) already exists")
    return push_cell!(oas, new_cell)
end

add_cell!(oas::Oasis, cell_name::Union{Symbol, AbstractString}) =
    add_cell!(oas, Cell(Symbol(cell_name), ShapeStore(), CellPlacement[]))

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

The cell doesn't need to be loaded.
"""
add_shape!(cell::Cell, shape::Shape) =
    isloaded(cell) ? (push!(cell.shapes, shape); cell) : append_element!(cell, shape)

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

The cell doesn't need to be loaded.
"""
add_placement!(cell::Cell, p::CellPlacement) =
    isloaded(cell) ? (push!(cell.placements, p); cell) : append_element!(cell, p)

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
    remove_cell!(oas, cell_name)

Remove a cell from `oas`, along with all of its placements in other cells. Throws a `KeyError` if
there is no such cell. For cells that aren't loaded, removing the placements is recorded and
carried out whenever they are decoded, except where their [`tier`](@ref) shows that they don't
place the removed cell. Returns `oas`.
"""
function remove_cell!(oas::Oasis, cell_name::Union{Symbol, AbstractString})
    cell_name = Symbol(cell_name)
    index = find_cell(oas, cell_name)
    isnothing(index) && throw(KeyError(cell_name))
    deleteat!(oas.cells, index)
    reindex_cells!(oas)
    for cell in cells(oas)
        may_place(cell, cell_name) && edit_cell!(cell, RemovePlacements(cell_name))
    end
    return oas
end

"""
    rename_cell!(oas, old_name, new_name)

Rename a cell, along with all of its placements in other cells. Throws an error if there is no
cell called `old_name`, or if there already is one called `new_name`. For cells that aren't
loaded, renaming the placements is recorded and carried out whenever they are decoded, except
where their [`tier`](@ref) shows that they don't place the renamed cell. Returns `oas`.
"""
function rename_cell!(oas::Oasis, old_name, new_name)
    old_name, new_name = Symbol(old_name), Symbol(new_name)
    index = find_cell(oas, old_name)
    isnothing(index) && throw(KeyError(old_name))
    haskey(oas, new_name) && error("Cell with name $new_name already exists")
    # A cell's name can't change, but its contents can simply move to a new cell.
    cell = oas.cells[index]
    oas.cells[index] = Cell(new_name, cell.shapes, cell.placements, cell.source, cell.index, cell.edits)
    reindex_cells!(oas)
    for cell in cells(oas)
        may_place(cell, old_name) && edit_cell!(cell, RenamePlacements(old_name, new_name))
    end
    return oas
end

# Whether `cell` may place the cell `cell_name`: `false` only if the placements of `cell` are
# known without decoding anything, and none of them do.
function may_place(cell::Cell, cell_name::Symbol)
    known = known_placements(cell)
    return isnothing(known) || any(p -> p.cell == cell_name, known)
end

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
    filter_shapes!(f, oas)
    filter_shapes!(f, cell)

Keep only the shapes `s` for which `f(s)` returns `true`, in every cell of `oas` or in a single
cell. Cells that aren't loaded stay that way: the filter is recorded and carried out whenever
they are decoded.

# Example

Keeping only layer 1, datatype 0:

```julia
filter_shapes!(s -> s.layer == 1 && s.datatype == 0, oas)
```
"""
filter_shapes!(f, cell::Cell) = edit_cell!(cell, FilterShapes(f))

function filter_shapes!(f, oas::Oasis)
    for cell in cells(oas)
        filter_shapes!(f, cell)
    end
    return oas
end

# Adds the layers of `other` that `layers` doesn't have yet.
function merge_layers!(layers::AbstractVector{Layer}, other::AbstractVector{Layer})
    for new_layer in other
        new_layer in layers || push!(layers, new_layer)
    end
    return layers
end

# Copies can be edited independently of the original.
Base.copy(oas::Oasis) = Oasis(map(copy_cell, oas.cells), copy(oas.layers); unit = oas.unit)

"""
    merge_oases(oas, others...)

Combine the cells and layers of several OASIS objects into a new one, leaving the originals
untouched. Using an opinionated plural for 'OASIS'.

Throws an error if the objects use different database units (see `OasisTools.unit`), or if any
cell names occur in more than one of them; use [`rename_cell!`](@ref) to resolve such clashes.

# Example

```jldoctest
julia> using OasisTools;

julia> filename1 = joinpath(OasisTools.TESTDATA_DIRECTORY, "flipped.oas");

julia> filename2 = joinpath(OasisTools.TESTDATA_DIRECTORY, "trapezoids.oas");

julia> merge_oases(oasisread(filename1), oasisread(filename2))
OASIS file with the following cell hierarchy:
TOP
└─ POLY
noname
```

See also [`merge_oases!`](@ref).
"""
merge_oases(oas::Oasis, others::Oasis...) = merge_oases!(copy(oas), others...)

"""
    merge_oases!(oas, others...)

Add the cells and layers of `others` to `oas`, leaving `others` untouched. Throws an error, without
changing `oas`, if the objects use different database units, or if any cell names occur in more
than one of them. Using an opinionated plural for 'OASIS'.

See also [`merge_oases`](@ref).
"""
function merge_oases!(oas::Oasis, others::Oasis...)
    names = Set(cell_names(oas))
    for other in others
        unit(other) == unit(oas) || error(
            "Cannot merge OASIS objects with different database units: $(unit(oas)) and $(unit(other)) grid steps per micron"
        )
        clashes = [n for n in cell_names(other) if n in names]
        isempty(clashes) || error(
            "Cell names occur more than once: $(join(clashes, ", ")). Use `rename_cell!` to resolve this."
        )
        union!(names, cell_names(other))
    end
    for other in others
        for cell in cells(other)
            push_cell!(oas, copy_cell(cell))
        end
        merge_layers!(oas.layers, other.layers)
    end
    return oas
end
