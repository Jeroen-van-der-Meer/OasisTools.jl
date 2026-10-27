using Documenter
using GeometryBasics
using Makie
using OasisTools
import OasisTools: FileParserState, CellParserState
import Suppressor
using Test

# A single top-level testset, so that a failure doesn't stop the remaining tests from running.
@testset "OasisTools" begin
    include("read_data_test.jl")
    include("read_oasis_test.jl")
    include("structs_oasis_test.jl")
    include("mutate_test.jl")
    include("hierarchy_test.jl")
    include("cells_test.jl")
    include("write_data_test.jl")
    include("write_oasis_test.jl")
    if !isempty(get(ENV, "KLAYOUT_PYTHON", ""))
        include("interop/interop_test.jl")
    else
        @info "Skipping the tests against KLayout. To run them, set KLAYOUT_PYTHON to a Python " *
            "with the `klayout` package installed."
    end
    include("plots_test.jl")
    include("docs_test.jl")
end
