using Documenter
using GeometryBasics
using Makie
using OasisTools
import OasisTools: FileParserState, CellParserState
import Suppressor
using Test

include("read_data_test.jl")
include("read_oasis_test.jl")
include("structs_oasis_test.jl")
include("mutate_test.jl")
include("hierarchy_test.jl")
include("write_data_test.jl")
include("write_oasis_test.jl")
include("plots_test.jl")
include("docs_test.jl")
