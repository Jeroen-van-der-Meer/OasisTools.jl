Base.@kwdef mutable struct FileModalVariables
    lastPropertyName::Union{UInt64, Symbol} = Symbol()
    lastValueList::Vector{Any} = [] # Can be of essentially any type
end

Base.@kwdef mutable struct ModalVariables
    repetition::Union{Nothing, Vector{Point{2, Int64}}, PointGridRange} = nothing
    placementX::Int64 = 0
    placementY::Int64 = 0
    placementCell::Symbol = Symbol()
    layer::UInt64 = 0
    datatype::UInt64 = 0
    textlayer::UInt64 = 0
    texttype::UInt64 = 0
    textX::Int64 = 0
    textY::Int64 = 0
    textString::Symbol = Symbol()
    geometryX::Int64 = 0
    geometryY::Int64 = 0
    xyAbsolute::Bool = true
    geometryW::UInt64 = 0
    geometryH::UInt64 = 0
    polygonPointList::Vector{Point{2, Int64}} = []
    pathHalfwidth::UInt64 = 0
    pathPointList::Vector{Point{2, Int64}} = []
    pathStartExtension::Int64 = 0
    pathEndExtension::Int64 = 0
    ctrapezoidType::UInt64 = 0
    circleRadius::UInt64 = 0
end

# The writer's view of the modal variables. Here `nothing` stands for the undefined state, which
# no value compares equal to, so the first use of a modal variable within a cell always ends up
# in the file explicitly. As per the spec, only the positional variables start out at 0.
Base.@kwdef mutable struct WriterModalVariables
    repetition::Union{Nothing, Vector{Point{2, Int64}}, PointGridRange} = nothing
    placementX::Int64 = 0
    placementY::Int64 = 0
    placementCell::Union{Nothing, Symbol} = nothing
    layer::Union{Nothing, UInt64} = nothing
    datatype::Union{Nothing, UInt64} = nothing
    textlayer::Union{Nothing, UInt64} = nothing
    texttype::Union{Nothing, UInt64} = nothing
    textX::Int64 = 0
    textY::Int64 = 0
    textString::Union{Nothing, Symbol} = nothing
    geometryX::Int64 = 0
    geometryY::Int64 = 0
    geometryW::Union{Nothing, UInt64} = nothing
    geometryH::Union{Nothing, UInt64} = nothing
    pathHalfwidth::Union{Nothing, UInt64} = nothing
    circleRadius::Union{Nothing, UInt64} = nothing
end

# Every CELL record resets the modal variables. Resetting in place rather than swapping in a new
# object keeps any writer states that share this one (such as CBLOCK writers) in sync.
function reset_modal_variables!(mod::WriterModalVariables)
    fresh = WriterModalVariables()
    for field in fieldnames(WriterModalVariables)
        setfield!(mod, field, getfield(fresh, field))
    end
    return mod
end
