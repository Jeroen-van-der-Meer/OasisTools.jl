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
TOP
└─ BOTTOM

julia> add_cell!(oas, :NEW)
OASIS file with the following cell hierarchy:
TOP
└─ BOTTOM
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
└─ ?
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
