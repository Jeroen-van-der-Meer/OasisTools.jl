module OasisTools

using CodecZlib
using GeometryBasics
import Mmap: mmap

export add_cell!
export add_layer!
export add_placement!
export add_shape!
export Cell
export cell_hierarchy
export cell_names
export CellHierarchy
export CellPlacement
export cells
export expand
export Layer
export layer
export layers
export LazyCell
export load_all_cells!
export load_cell
export load_cell!
export merge_oases
export merge_oases!
export name
export Oasis
export oasisread
export oasiswrite
export placements
export plot_cell
export plot_shape!
export PointGridRange
export remove_cell!
export remove_layer!
export roots
export Shape
export shapes
export show_cells
export show_shapes
export unit
export update_roots!
export validate_placements

# Structs
include("modal_variables.jl")
include("structs_data.jl")
include("structs_oasis.jl")
include("structs_io.jl")

# Editing
include("mutate.jl")

# Cell hierarchy
include("hierarchy.jl")

# Custom shows
include("shows.jl")

# Reading
include("read_data.jl")
include("read_records.jl")
include("read_utils.jl")
include("read_oasis.jl")

# Lazy loading
include("lazy.jl")

# Skipping
include("skip_data.jl")
include("skip_records.jl")

# Writing
include("write_data.jl")
include("write_records.jl")
include("write_utils.jl")
include("write_oasis.jl")

# Plotting
function plot_cell end
function plot_shape! end
if !isdefined(Base, :get_extension)
    include("../ext/OasisPlots.jl")
end

# Consts
const MAGIC_BYTES = [0x25, 0x53, 0x45, 0x4d, 0x49, 0x2d, 0x4f, 0x41, 0x53, 0x49, 0x53, 0x0d, 0x0a]
const TESTDATA_DIRECTORY = joinpath(@__DIR__, "..", "test", "testdata")
const DEFAULT_UNIT = 1000

end # module OasisTools
