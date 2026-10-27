module OasisTools

using CodecZlib
using GeometryBasics
import Mmap: mmap

export add_cell!
export add_layer!
export add_placement!
export add_shape!
export Cell
export cell_names
export CellPlacement
export cells
export crop
export expand
export filter_shapes!
export find_instances
export extent
export foreach_shape
export index!
export isloaded
export Layer
export layer
export layer_counts
export layers
export load!
export merge_oases
export merge_oases!
export name
export Oasis
export oasisread
export OasisParseError
export oasiswrite
export placements
export plot_cell
export plot_shape!
export PointGridRange
export remove_cell!
export rename_cell!
export roots
export Shape
export shapes
export ShapeStore
export show_cells
export tier
export unit
export validate_placements

# Structs
include("structs_data.jl")
include("modal_variables.jl")
include("structs_oasis.jl")
include("structs_io.jl")

# Geometry
include("geometry.jl")

# Decoding cells, with or without edits
include("edits.jl")
include("sinks.jl")
include("cells.jl")

# Editing
include("mutate.jl")
include("crop.jl")

# Cell hierarchy
include("hierarchy.jl")

# Custom shows
include("shows.jl")

# Reading
include("read_data.jl")
include("read_records.jl")
include("read_utils.jl")
include("read_oasis.jl")

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

# Consts
const MAGIC_BYTES = [0x25, 0x53, 0x45, 0x4d, 0x49, 0x2d, 0x4f, 0x41, 0x53, 0x49, 0x53, 0x0d, 0x0a]
const TESTDATA_DIRECTORY = joinpath(@__DIR__, "..", "test", "testdata")
const DEFAULT_UNIT = 1000

end # module OasisTools
