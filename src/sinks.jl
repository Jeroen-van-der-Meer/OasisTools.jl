# The cell decoder hands every shape and placement it decodes to a sink, which decides what to
# keep. This lets a single decoder serve loading, indexing, streaming and writing.

# Keeps everything, for loading a cell into memory.
struct ContentsSink
    shapes::ShapeStore
    placements::Vector{CellPlacement}
end

ContentsSink() = ContentsSink(ShapeStore(), CellPlacement[])

push_element!(sink::ContentsSink, shape::Shape) = push!(sink.shapes, shape)
push_element!(sink::ContentsSink, placement::CellPlacement) = push!(sink.placements, placement)

# Keeps placements, but only counts shapes, for building a `CellIndex`.
mutable struct IndexSink
    const placements::Vector{CellPlacement}
    const layers::Dict{Tuple{UInt64, UInt64}, ElementCounts}
    const trackExtent::Bool
    extent::Union{Nothing, Rect{2, Int64}}
end

IndexSink(track_extent::Bool) = IndexSink(CellPlacement[], Dict(), track_extent, nothing)

function push_element!(sink::IndexSink, shape::Shape)
    key = (shape.layerNumber, shape.datatypeNumber)
    counts = get(sink.layers, key, ElementCounts(0, 0))
    sink.layers[key] = ElementCounts(counts.records + 1, counts.instances + nrep(shape.repetition))
    sink.trackExtent && (sink.extent = union_box(sink.extent, shape_extent(shape)))
    return nothing
end

push_element!(sink::IndexSink, placement::CellPlacement) = push!(sink.placements, placement)

CellIndex(sink::IndexSink) = CellIndex(sink.placements, sink.layers, sink.trackExtent, sink.extent)

# Passes shapes on to a function, for streaming through them.
struct ShapeCallback{F}
    f::F
end

push_element!(sink::ShapeCallback, shape::Shape) = (sink.f(shape); nothing)
push_element!(::ShapeCallback, ::CellPlacement) = nothing

# Writes elements to a file. See `write_records.jl`.
push_element!(state::WriterState, shape::Shape) = write_shape(state, shape)
push_element!(state::WriterState, placement::CellPlacement) = write_placement_record(state, placement)

# Passes elements through a list of edits on their way to another sink.
struct EditedSink{S}
    sink::S
    edits::Vector{CellEdit}
end

push_element!(sink::EditedSink, element) = pass_through_edits(sink.sink, sink.edits, 1, element)

function pass_through_edits(sink, edits::Vector{CellEdit}, i::Int, element)
    if i > length(edits)
        push_element!(sink, element)
    else
        apply_edit(e -> pass_through_edits(sink, edits, i + 1, e), edits[i], element)
    end
    return nothing
end

function finish_edits(sink::EditedSink)
    for i in eachindex(sink.edits)
        finish_edit(e -> pass_through_edits(sink.sink, sink.edits, i + 1, e), sink.edits[i])
    end
end

"""
    decode_cell(sink, cell)

Hand every shape and placement of `cell` to `sink`, taking any pending edits into account.
Loaded cells hand over their contents in memory, with placements first and shapes grouped by
kind. Returns `sink`.
"""
function decode_cell(sink, cell::Cell)
    if isloaded(cell)
        for p in cell.placements
            push_element!(sink, p)
        end
        for v in shape_vectors(cell.shapes), s in v
            push_element!(sink, s)
        end
    elseif isempty(cell.edits)
        decode_source(sink, cell.source)
    else
        edited = EditedSink(sink, cell.edits)
        decode_source(edited, cell.source)
        finish_edits(edited)
    end
    return sink
end

function decode_source(sink, source::CellSource)
    state = CellParserState(source, sink)
    nbytes = length(source.bytes)
    while state.pos <= nbytes
        record_type = read_byte(state)
        read_record(record_type, state)
    end
end
