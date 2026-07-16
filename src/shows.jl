# Public display functions

"""
    show_cells(oas; kw...)

Obtain an overview of the cells in your OASIS objects.

# Arguments

- `oas::Oasis`: Your OASIS object, loaded with `oasisread`.

# Keyword Arguments

- `maxdepth = 100`: Specify until what maxdepth you'd like to the cell hierarchy to be
  displayed.
- `flat = false`: If set to `true`, rather than displaying a hierarchy, `show_cells` simply
  lists the names of all cells that can be found in `oas`. If set to `true`, the keyword
  argument `maxdepth` is ignored.
"""
function show_cells(
    oas::Oasis;
    maxdepth = 100,
    flat = false,
    io = stdout,
    roots = roots(oas)
)
    if flat
        for cell in oas.cells
            println(io, cell.name)
        end
    else
        _show_hierarchy(oas; maxdepth = maxdepth, io = io, roots = roots)
    end
end

function show_shapes(oas::Oasis; cell::Symbol, maxdepth = 1, flat = false)
    @error "Not implemented"
end

# Custom shows

function Base.show(io::IO, oas::Oasis)
    print(io, "OASIS file ")
    rts = roots(oas)
    if isempty(rts)
        print(io, "with unknown cell hierarchy")
    else
        print(io, "with the following cell hierarchy:\n")
        show_cells(oas; maxdepth = 2, flat = false, io = io, roots = rts)
    end
end

function Base.show(io::IO, cell::Cell)
    nplacements = length(cell.placements)
    nshapes = length(cell.shapes)
    print(io, "Cell $(cell.name) with $(nplacements) placement$(nplacements == 1 ? "" : "s") and $(nshapes) shape$(nshapes == 1 ? "" : "s")")
end

function Base.show(io::IO, cell::LazyCell)
    print(io, "Lazy cell ")
    print(io, cell.name)
end

function Base.show(io::IO, layer::Layer)
    print(io, "$(layer.name) ($(layer.layerNumber)/$(layer.datatypeNumber))")
end

function Base.show(io::IO, interval::Interval)
    if interval.low == interval.high
        print(io, interval.low)
    else
        if interval.high == typemax(UInt64)
            print(io, "[$(interval.low),∞)")
        else
            print(io, "[$(interval.low),$(interval.high)]")
        end
    end
end

function Base.show(io::IO, placement::CellPlacement)
    print(io, "Placement of cell $(placement.cellName) at ($(placement.location[1]), $(placement.location[2]))")
    repetition = !isnothing(placement.repetition)
    if repetition
        nrep = length(placement.repetition)
        print(io, " ($nrep×)")
    end
end

function Base.show(io::IO, shape::Shape{Polygon{2, Int64}})
    location = sum(shape.shape.exterior) .÷ length(shape.shape.exterior)
    _show_shape(io, shape, "Polygon", location)
end

function Base.show(io::IO, shape::Shape{Rect{2, Int64}})
    location = shape.shape.origin + shape.shape.widths .÷ 2
    _show_shape(io, shape, "Rectangle", location)
end

function Base.show(io::IO, shape::Shape{Circle{Int64}})
    location = shape.shape.center
    _show_shape(io, shape, "Circle", location)
end

function Base.show(io::IO, shape::Shape{Path{2, Int64}})
    location = sum(shape.shape.points) .÷ length(shape.shape.points)
    _show_shape(io, shape, "Path", location)
end

# Internal functions

function _show_hierarchy(
    oas::Oasis;
    maxdepth = 100, io = stdout,
    current_depth = 0, prefix = "", last = true,
    roots = roots(oas)
)
    for (i, root_name) in enumerate(roots)
        if current_depth == 0
            i > 1 && print(io, '\n')
            print(io, prefix, root_name)
            new_prefix = prefix
        else
            print(io, '\n')
            connector = last ? "└─ " : "├─ "
            print(io, prefix, connector, root_name)
            new_prefix = prefix * (last ? "   " : "│  ")
        end
        root_cell = oas[root_name]
        if root_cell isa Cell
            children = unique([p.cellName for p in root_cell.placements])
            nunique_children = length(children)
            # If `maxdepth` is reached, we check whether the current element has any further children.
            # Rather than printing them, we print an ellipsis (⋯) to indicate that there are children.
            if current_depth >= maxdepth
                if nunique_children > 0
                    print(io, "\n", new_prefix, "└─ ⋯")
                end
                return
            end
            for (i, child) in enumerate(children)
                child_is_last = i == nunique_children
                _show_hierarchy(
                    oas;
                    maxdepth = maxdepth,
                    io = io,
                    roots = [child],
                    current_depth = current_depth + 1,
                    prefix = new_prefix,
                    last = child_is_last
                )
            end
        elseif root_cell isa LazyCell
            print(io, "\n", new_prefix, "└─ ?")
        end
    end
end

function _show_shape(io::IO, shape::Shape, name, location)
    print(io, "$name in layer ($(shape.layerNumber)/$(shape.datatypeNumber)) at ($(location[1]), $(location[2]))")
    repetition = !isnothing(shape.repetition)
    if repetition
        nrep = length(shape.repetition)
        print(io, " ($nrep×)")
    end
end