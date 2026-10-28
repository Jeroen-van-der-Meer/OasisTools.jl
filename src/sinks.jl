# The cell decoder hands every shape and placement it decodes to a sink, which decides what to
# keep. This lets a single decoder serve loading, indexing, streaming and writing. Once the cell
# is decoded, the sink also gets the properties of the cell that follow its CELL record, through
# `push_cell_properties!`.

push_cell_properties!(sink, ::Vector{Property}) = nothing

# Keeps everything, for loading a cell into memory.
struct ContentsSink
    shapes::ShapeStore
    placements::Vector{CellPlacement}
    properties::Vector{Property}
end

ContentsSink() = ContentsSink(ShapeStore(), CellPlacement[])
ContentsSink(shapes::ShapeStore, placements::Vector{CellPlacement}) = ContentsSink(shapes, placements, Property[])

push_cell_properties!(sink::ContentsSink, properties::Vector{Property}) = append!(sink.properties, properties)

push_element!(sink::ContentsSink, shape::Shape) = push!(sink.shapes, shape)
push_element!(sink::ContentsSink, placement::CellPlacement) = push!(sink.placements, placement)

# Keeps placements, but only counts shapes and takes their bounding box, for building a
# `CellIndex`.
mutable struct IndexSink
    const placements::Vector{CellPlacement}
    const layers::Vector{Pair{Tuple{UInt64, UInt64}, ElementCounts}}
    extent::Union{Nothing, Rect{2, Int64}}
    properties::Vector{Property}
end

IndexSink() = IndexSink(CellPlacement[], Pair{Tuple{UInt64, UInt64}, ElementCounts}[], nothing, NO_PROPERTIES)

push_cell_properties!(sink::IndexSink, properties::Vector{Property}) =
    isempty(properties) || (sink.properties = vcat(sink.properties, properties))

function push_element!(sink::IndexSink, shape::Shape)
    key = (shape.layer, shape.datatype)
    instances = nrep(shape.repetition)
    # Cells use few layers, so a linear search beats a dictionary.
    i = findfirst(entry -> first(entry) == key, sink.layers)
    if isnothing(i)
        push!(sink.layers, key => ElementCounts(1, instances))
    else
        counts = last(sink.layers[i])
        sink.layers[i] = key => ElementCounts(counts.records + 1, counts.instances + instances)
    end
    sink.extent = union_box(sink.extent, shape_extent(shape))
    return nothing
end

push_element!(sink::IndexSink, placement::CellPlacement) = push!(sink.placements, placement)

# Most cells place nothing, so they can all share one empty list. Lists in a `CellIndex` are
# never modified.
const NO_PLACEMENTS = CellPlacement[]

CellIndex(sink::IndexSink) =
    CellIndex(isempty(sink.placements) ? NO_PLACEMENTS : sink.placements, sink.layers, sink.extent, sink.properties)

# Most cells have no properties either. Like NO_PLACEMENTS, this list is never modified.
const NO_PROPERTIES = Property[]

# Passes shapes on to a function, for streaming through them.
struct ShapeCallback{F}
    f::F
end

push_element!(sink::ShapeCallback, shape::Shape) = (sink.f(shape); nothing)
push_element!(::ShapeCallback, ::CellPlacement) = nothing

# Writes elements to a file. See `write_records.jl`.
push_element!(state::WriterState, shape::Shape) = write_shape(state, shape)
push_element!(state::WriterState, placement::CellPlacement) = write_placement_record(state, placement)

# Writes elements to a file, calling `after_record` after each one.
struct WriterSink{F}
    state::WriterState
    after_record::F
end

function push_element!(sink::WriterSink, element::Union{Shape, CellPlacement})
    push_element!(sink.state, element)
    sink.after_record()
    return nothing
end

# Passes elements through a list of edits on their way to another sink.
struct EditedSink{S}
    sink::S
    edits::Vector{CellEdit}
end

push_element!(sink::EditedSink, element) = pass_through_edits(sink.sink, sink.edits, 1, element)
push_cell_properties!(sink::EditedSink, properties::Vector{Property}) = push_cell_properties!(sink.sink, properties)

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
        # A cell without a source consists of its edits alone.
        edited = EditedSink(sink, cell.edits)
        isnothing(cell.source) || decode_source(edited, cell.source)
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
    flush_pending!(state)
    push_cell_properties!(sink, state.pending.cellProperties)
end
