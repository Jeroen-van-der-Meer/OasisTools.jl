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
    oas::Oasis,
    cell_string::AbstractString = "";
    maxdepth = 100,
    flat = false,
    io = stdout
)
    if flat
        if isempty(cell_string)
            cell_numbers = keys(cells(oas))
        else
            cell_numbers = keys(placements(oas[cell_string]))
        end
        for cell_number in cell_numbers
            println(io, cell_name(oas, cell_number))
        end
    else
        cell_hierarchy = oas.hierarchy
        if isempty(cell_string)
            roots = cell_hierarchy.roots
        else
            roots = [cell_number(oas, cell_string)]
        end
        _show_hierarchy(oas; maxdepth = maxdepth, io = io, roots = roots)
    end
end

function show_shapes(oas::Oasis; cell::AbstractString, maxdepth = 1, flat = false)
    @error "Not implemented"
end

# Custom shows

function Base.show(io::IO, oas::Oasis)
    print(io, "OASIS file v", oas.metadata.version.major, ".", oas.metadata.version.minor, " ")
    if isempty(oas.hierarchy.roots)
        print(io, "with unknown cell hierarchy")
    else
        print(io, "with the following cell hierarchy:\n")
        show_cells(oas; maxdepth = 2, flat = false, io = io)
    end
end

function Base.show(io::IO, placement::CellPlacement)
    print(io, "Placement of cell $(placement.nameNumber) at ($(placement.location[1]), $(placement.location[2]))")
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
    cell_hierarchy = oas.hierarchy,
    maxdepth = 100, io = stdout, count = 1,
    current_depth = 0, prefix = "", last = true, roots = cell_hierarchy.roots
)
    for (i, root) in enumerate(roots)
        if current_depth == 0
            i > 1 && print('\n')
            print(io, prefix, get_reference(oas.metadata.source, root, oas.references.cellNames))
            new_prefix = prefix
        else
            print('\n')
            connector = last ? "└─ " : "├─ "
            print(io, prefix, connector, get_reference(oas.metadata.source, root, oas.references.cellNames))
            # If a cell occurs N times with N > 1, we annotate the cell name with "(N×)".
            count > 1 && print(io, " ($(count)×)")
            new_prefix = prefix * (last ? "   " : "│  ")
        end
        if haskey(cell_hierarchy.hierarchy, root)
            children = cell_hierarchy.hierarchy[root]
            nunique_children = length(children)
            # If `maxdepth` is reached, we check whether the current element has any further children.
            # Rather than printing them, we print an ellipsis (⋯) to indicate that there are children.
            if current_depth >= maxdepth
                if nunique_children > 0
                    print(io, '\n', new_prefix, "└─ ⋯")
                end
                return
            end
            
            for (i, child) in enumerate(children)
                child_is_last = i == nunique_children
                _show_hierarchy(
                    oas;
                    cell_hierarchy = cell_hierarchy,
                    maxdepth = maxdepth,
                    io = io,
                    count = count,
                    roots = [child],
                    current_depth = current_depth + 1,
                    prefix = new_prefix,
                    last = child_is_last
                )
            end
        else
            print(io, '\n', new_prefix, "└─ ?")
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