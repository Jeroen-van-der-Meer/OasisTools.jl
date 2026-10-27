"""
    OasisParseError(message, position)

Thrown when the contents of an OASIS file cannot be interpreted.

# Properties

- `message::String`: Description of what went wrong.
- `position::Int64`: Byte offset at which parsing stopped. This is an offset into the file
  itself, unless the error occurred while parsing a [`LazyCell`](@ref) or the contents of a
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

mutable struct CellParserState{B <: AbstractVector{UInt8}} <: AbstractParserState
    const buf::B
    pos::Int64
    const cellnameReferences::Dict{UInt64, Symbol}
    const textstringReferences::Dict{UInt64, Symbol}
    const shapes::ShapeStore
    const placements::Vector{CellPlacement}
    const mod::ModalVariables
end

function CellParserState(cell::LazyCell)
    return CellParserState{typeof(cell.bytes)}(
        cell.bytes, 1,
        cell.cellnameReferences, cell.textstringReferences,
        ShapeStore(), CellPlacement[],
        ModalVariables()
    )
end

function CellParserState(buf::AbstractVector{UInt8})
    return CellParserState{typeof(buf)}(
        buf, 1,
        Dict(), Dict(),
        ShapeStore(), CellPlacement[],
        ModalVariables()
    )
end

mutable struct LazyCellParserState{B <: AbstractVector{UInt8}} <: AbstractParserState
    const buf::B
    pos::Int64
end

function LazyCellParserState(state::FileParserState)
    return LazyCellParserState{typeof(state.buf)}(state.buf, state.pos)
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

new_state(state::CellParserState, new_buf::AbstractVector{UInt8}) =
    CellParserState{typeof(new_buf)}(
        new_buf, 1,
        state.cellnameReferences, state.textstringReferences,
        state.shapes, state.placements, 
        state.mod
    )

new_state(::LazyCellParserState, new_buf::AbstractVector{UInt8}) =
    LazyCellParserState{typeof(new_buf)}(new_buf, 1)

mutable struct WriterState
    const io::IO # File we're saving to.
    const buf::Vector{UInt8} # An output buffer of some size, probably big.
    const bufsize::Int64 # Length of buffer stored separately.
    pos::Int64 # Position in buffer.
    const cells::Vector{Union{LazyCell, Cell}}
    const layers::Vector{Layer}
    const cellnameReferences::Dict{Symbol, UInt64}
    const mod::ModalVariables
end

function WriterState(oas::Oasis, filename::AbstractString, bufsize::Integer)
    return WriterState(
        open(filename, "w"),
        Vector{UInt8}(undef, bufsize), bufsize, 1,
        oas.cells, oas.layers,
        Dict(), ModalVariables()
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
        parent.cellnameReferences, parent.mod
    )
end
