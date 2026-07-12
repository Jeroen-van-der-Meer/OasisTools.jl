abstract type AbstractParserState end

"""
    mutable struct FileParserState

Struct used to encode the state of the OASIS file parser.

# Properties

- `buf::Vector{UInt8}`: Mmapped buffer of OASIS file.
- `pos::Int64`: Byte position in buffer.
- `cells::Vector{PreprocessedCell}`: Pre-processed cells that the parser has collected.
- `layers::Vector{Layer}`: (Explicitly named) layers that the parser has encountered.
- `cellnameReferences::Dict{UInt64, Symbol}`: Internal cell name references.
- `textstringReferences::Dict{UInt64, Symbol}`: Internal text string references.
- `propnameReferences::Dict{UInt64, Symbol}`: Internal references to names of properties.
- `propstringReferences::Dict{UInt64, Symbol}`: Internal references to property string values.
- `propertyPositions::Vector{Int64}`: Byte locations of file-level properties that the parser
  has encountered. Currently only used to find `S_TOP_CELL` after having parsed the file.
- `metadata::Metadata`: Some metadata associated to the file.
- `mod::FileModalVariables`: File-level modal variables.

See also [`WriterState`](@ref), [`CellParserState`](@ref).
"""
mutable struct FileParserState <: AbstractParserState
    const buf::Vector{UInt8}
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
    return FileParserState(
        buf, 1, [], [],
        Dict(), Dict(), Dict(), Dict(),
        [], Metadata(), FileModalVariables()
    )
end

"""
    mutable struct CellParserState

Struct used to encode the state of the CELL record parser.

# Properties

- `buf::Vector{UInt8}`: Mmapped buffer of OASIS file.
- `pos::Int64`: Byte position in buffer.
- `cellnameReferences::Dict{UInt64, Symbol}`: Internal cell name references.
- `textstringReferences::Dict{UInt64, Symbol}`: Internal text string references.
- `shapes::Vector{Shape}`: The shapes it's collecting.
- `placements::Vector{CellPlacement}`: The placements it's collecting.
- `mod::ModalVariables`: Modal variables it needs to keep track of.

See also [`LazyCellParserState`](@ref).
"""
mutable struct CellParserState <: AbstractParserState
    const buf::Vector{UInt8}
    pos::Int64
    const cellnameReferences::Dict{UInt64, Symbol}
    const textstringReferences::Dict{UInt64, Symbol}
    const shapes::Vector{Shape}
    const placements::Vector{CellPlacement}
    const mod::ModalVariables
end

function CellParserState(cell::LazyCell)
    return CellParserState(
        cell.bytes, 1,
        cell.cellnameReferences, cell.textstringReferences,
        [], [],
        ModalVariables()
    )
end

function CellParserState(buf::AbstractVector{UInt8})
    return CellParserState(
        buf, 1,
        Dict(), Dict(),
        [], [],
        ModalVariables()
    )
end

"""
    struct LazyCellParserState

Struct used to encode the state of the lazy CELL record parser.

# Properties

- `buf::Vector{UInt8}`: Mmapped buffer of OASIS file.
- `pos::Int64`: Byte position in buffer.

See also [`CellParserState`](@ref).
"""
mutable struct LazyCellParserState <: AbstractParserState
    const buf::Vector{UInt8}
    pos::Int64
end

function LazyCellParserState(state::FileParserState)
    return LazyCellParserState(state.buf, state.pos)
end

new_state(state::FileParserState, new_buf::AbstractVector{UInt8}) =
    FileParserState(
        new_buf, 1,
        state.cells, state.layers,
        state.cellnameReferences, state.textstringReferences,
        state.propnameReferences, state.propstringReferences,
        state.propertyPositions,
        state.metadata,
        state.mod
    )

new_state(state::CellParserState, new_buf::AbstractVector{UInt8}) =
    CellParserState(
        new_buf, 1,
        state.cellnameReferences, state.textstringReferences,
        state.shapes, state.placements, 
        state.mod
    )

new_state(::LazyCellParserState, new_buf::AbstractVector{UInt8}) =
    LazyCellParserState(new_buf, 1)

"""
    struct WriterState

Struct used to encode the state of the OASIS file writer.

# Properties

- `oas::Oasis`: The object we're trying to save.
- `io::IO`: File we're saving to.
- `buf::Vector{UInt8}`: We write to the file in batches, and temporarily store the output in
  this buffer.
- `bufsize::Int64`: Size of `buf`.
- `pos::Int64`: Position in the buffer.

See also [`ParserState`](@ref), [`CellParserState`](@ref).
"""
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
