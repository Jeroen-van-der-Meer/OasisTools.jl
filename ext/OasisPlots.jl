module OasisPlots

if isdefined(Base, :get_extension)
    using OasisTools
else
    using ..OasisTools
end

using GeometryBasics
using Makie

"""
    plot_shape!(ax, shape)

Plot a single [`Shape`](@ref) onto a Makie `Axis`. Supported for shapes backed by
`AbstractGeometry{2, Int64}` (rectangles, polygons, etc.).
"""
function OasisTools.plot_shape!(ax::Axis, shape::Shape{<:Any})
    @error "Not implemented"
end

function OasisTools.plot_shape!(ax::Axis, shape::Shape{<:AbstractGeometry{2, Int64}})
    Makie.poly!(ax, shape.shape)
end

"""
    plot_cell(cell)

Plot a cell using Makie.
"""
function OasisTools.plot_cell(cell::Cell)
    fig = Figure()
    ax = Axis(fig[1, 1])
    for shape in cell.shapes
        plot_shape!(ax, shape)
    end
    return fig
end

end # module OasisPlots
