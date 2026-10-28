"""
    OasisParseError(message, position)

Thrown when the contents of an OASIS file cannot be interpreted.

# Properties

- `message::String`: Description of what went wrong.
- `position::Int64`: Byte offset at which parsing stopped. This is an offset into the file
  itself, unless the error occurred while decoding a cell or the contents of a
  CBLOCK, in which case it is relative to the start of that buffer.
"""
struct OasisParseError <: Exception
    message::String
    position::Int64
end

function Base.showerror(io::IO, e::OasisParseError)
    print(io, "OasisParseError: ", e.message, " (at byte ", e.position, ")")
end

parse_error(state, message::AbstractString) = throw(OasisParseError(message, state.pos))

abstract type AbstractParserState end

# The buffer is a type parameter so that a state can wrap a view into an mmap without the
# implicit `convert` to `Vector{UInt8}` copying the whole range.
mutable struct FileParserState{B <: AbstractVector{UInt8}} <: AbstractParserState
    const buf::B
    pos::Int64
    const cells::Vector{PreprocessedCell}
    const layers::Vector{Layer}
    const cellnameReferences::Dict{UInt64, Symbol}
    const textstringReferences::Dict{UInt64, Symbol}
    const propnameReferences::Dict{UInt64, Symbol}
    const propstringReferences::Dict{UInt64, Symbol}
    const propertyPositions::Vector{Int64}
    const metadata::Metadata
    const mod::FileModalVariables
end

function FileParserState(buf::AbstractVector{UInt8})
    return FileParserState{typeof(buf)}(
        buf, 1, PreprocessedCell[], Layer[],
        Dict(), Dict(), Dict(), Dict(),
        Int64[], Metadata(), FileModalVariables()
    )
end

# The properties of an element follow it, so the decoder holds on to each element until it knows
# that no more of its properties follow. What it holds is shared between the states that decode
# a cell and the CBLOCKs within it, as properties may follow their element across a CBLOCK.
mutable struct PendingElement
    # Nothing at the start of a cell, where properties belong to the cell; SKIPPED after
    # records that aren't handed on, such as XELEMENTs, whose properties are dropped.
    element::Any
    const properties::Vector{Property}
    const cellProperties::Vector{Property}
end

PendingElement() = PendingElement(nothing, Property[], Property[])

struct Skipped end
const SKIPPED = Skipped()

# Decodes the records of a cell, handing every shape and placement to `sink`, which decides what
# to do with them. See `sinks.jl`.
mutable struct CellParserState{B <: AbstractVector{UInt8}, S} <: AbstractParserState
    const buf::B
    pos::Int64
    const cellnameReferences::Dict{UInt64, Symbol}
    const textstringReferences::Dict{UInt64, Symbol}
    const propnameReferences::Dict{UInt64, Symbol}
    const propstringReferences::Dict{UInt64, Symbol}
    const sink::S
    const mod::ModalVariables
    const pending::PendingElement
end

function CellParserState(source::CellSource, sink)
    return CellParserState{typeof(source.bytes), typeof(sink)}(
        source.bytes, 1,
        source.cellnameReferences, source.textstringReferences,
        source.propnameReferences, source.propstringReferences,
        sink,
        ModalVariables(),
        PendingElement()
    )
end

function CellParserState(buf::AbstractVector{UInt8}, sink = ContentsSink())
    return CellParserState{typeof(buf), typeof(sink)}(
        buf, 1,
        Dict(), Dict(), Dict(), Dict(),
        sink,
        ModalVariables(),
        PendingElement()
    )
end

# Walks over the records of a cell without interpreting them, to find where records end.
mutable struct SkipParserState{B <: AbstractVector{UInt8}} <: AbstractParserState
    const buf::B
    pos::Int64
end

function SkipParserState(state::FileParserState)
    return SkipParserState{typeof(state.buf)}(state.buf, state.pos)
end

new_state(state::FileParserState, new_buf::AbstractVector{UInt8}) =
    FileParserState{typeof(new_buf)}(
        new_buf, 1,
        state.cells, state.layers,
        state.cellnameReferences, state.textstringReferences,
        state.propnameReferences, state.propstringReferences,
        state.propertyPositions,
        state.metadata,
        state.mod
    )

new_state(state::CellParserState{<:Any, S}, new_buf::AbstractVector{UInt8}) where S =
    CellParserState{typeof(new_buf), S}(
        new_buf, 1,
        state.cellnameReferences, state.textstringReferences,
        state.propnameReferences, state.propstringReferences,
        state.sink,
        state.mod,
        state.pending
    )

new_state(::SkipParserState, new_buf::AbstractVector{UInt8}) =
    SkipParserState{typeof(new_buf)}(new_buf, 1)

mutable struct WriterState
    const io::IO # File we're saving to.
    const buf::Vector{UInt8} # An output buffer of some size, probably big.
    const bufsize::Int64 # Length of buffer stored separately.
    pos::Int64 # Position in buffer.
    const cells::Vector{Cell}
    const layers::Vector{Layer}
    const cellnameReferences::Dict{Symbol, UInt64}
    const mod::WriterModalVariables
    # Shared with the states that write into CBLOCKs; see `compressor`.
    const compressor::Base.RefValue{Union{Nothing, DeflateCompressor}}
end

function WriterState(oas::Oasis, filename::AbstractString, bufsize::Integer)
    return WriterState(
        open(filename, "w"),
        Vector{UInt8}(undef, bufsize), bufsize, 1,
        oas.cells, oas.layers,
        Dict(), WriterModalVariables(),
        Ref{Union{Nothing, DeflateCompressor}}(nothing)
    )
end

WriterState(filename::AbstractString, bufsize::Integer) = WriterState(
    Oasis(), filename, bufsize
)

function WriterState(io::IO, parent::WriterState; bufsize::Integer = 4096)
    return WriterState(
        io,
        Vector{UInt8}(undef, bufsize), bufsize, 1,
        parent.cells, parent.layers,
        parent.cellnameReferences, parent.mod,
        parent.compressor
    )
end
