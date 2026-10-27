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
