function read_or_modal(
    state,
    reader::Function,
    ::Val{modal}, # Seems to help performance because modal variables have different types.
    info_byte::UInt8,
    position::Int64
) where modal
    if bit_is_one(info_byte, position)
        v = reader(state)
        setproperty!(state.mod, modal, v)
        return v
    else
        return getproperty(state.mod, modal)
    end
end

# If an x or y value is parsed, we require logic to deal with the current value of xy-mode.
function read_or_modal_xy(
    state,
    ::Val{modalX},
    ::Val{modalY},
    info_byte::UInt8,
    position::Int64 # Position of bit determining x-value; the y-value is always the next bit.
) where {modalX, modalY}
    if state.mod.xyAbsolute
        x = read_or_modal(state, read_signed_integer, Val(modalX), info_byte, position)
        y = read_or_modal(state, read_signed_integer, Val(modalY), info_byte, position + 1)
    else
        if bit_is_one(info_byte, position)
            x = read_signed_integer(state) + getproperty(state.mod, modalX)
            setproperty!(state.mod, modalX, x)
        else
            x = getproperty(state.mod, modalX)
        end
        if bit_is_one(info_byte, position + 1)
            y = read_signed_integer(state) + getproperty(state.mod, modalY)
            setproperty!(state.mod, modalY, y)
        else
            y = getproperty(state.mod, modalY)
        end
    end
    return x, y
end

function read_repetition(
    state,
    info_byte::UInt8,
    position::Int64
)
    if bit_is_one(info_byte, position)
        v = read_repetition(state)
        state.mod.repetition = v
        return v
    else
        return nothing
    end
end

function bit_is_one(byte::UInt8, position::Integer)
    return isone(byte >> (8 - position) & 0x01)
end

function is_end_of_cell(state, next_record::UInt8)
    # The end of a cell is implied when the upcoming record is any of the following:
    # END, CELLNAME, TEXTSTRING, PROPNAME, PROPSTRING, LAYERNAME, CELL, XNAME
    if (0x02 <= next_record <= 0x0e) || (next_record == 0x1e) || (next_record == 0x1f)
        return true
    elseif next_record == 34
        # If a CBLOCK is encountered, the first record within the CBLOCK implies whether or
        # not the CBLOCK belongs to the cell or not.
        comp_type = read_byte(state)
        comp_type == 0x00 || parse_error(state, "Unknown CBLOCK compression type $comp_type")
        skip_integer(state) # uncomp_byte_count
        comp_byte_count = rui(state)
        comp_bytes = view_bytes(state, comp_byte_count)
        first_record_in_cblock = first_decompressed_byte(state, comp_bytes)
        # A CBLOCK without any records in it can't end a cell.
        isnothing(first_record_in_cblock) && return false
        return is_end_of_cell(state, first_record_in_cblock)
    else
        return false
    end
end

# Looks up a reference number in one of a file's tables of names, with a clear error if the
# file doesn't define it.
function lookup_reference(state, table::Dict{UInt64, Symbol}, number::UInt64, kind::String, record::String)
    name = get(table, number, nothing)
    isnothing(name) && parse_error(state, "Reference to $kind number $number, which no $record record defines")
    return name
end

# Decompressing CBLOCKs. Setting up a decompressor takes much longer than decompressing a typical
# CBLOCK, so decompressors are reused. Cells are decoded in parallel, and a decompressor can't be
# shared between tasks, so each task keeps its own.

const TranscodingStreams = CodecZlib.TranscodingStreams

# Releases the memory of a decompressor once its task is done with it.
mutable struct Decompressor
    const codec::DeflateDecompressor

    function Decompressor()
        codec = DeflateDecompressor()
        TranscodingStreams.initialize(codec)
        return finalizer(d -> TranscodingStreams.finalize(d.codec), new(codec))
    end
end

decompressor() = get!(Decompressor, task_local_storage(), :OasisToolsDecompressor).codec

# Decompresses `bytes` into `output`, filling at most all of it. Returns how many bytes it wrote,
# and whether it reached the end of the compressed data.
function decompress!(state, output::Vector{UInt8}, bytes::AbstractVector{UInt8})
    codec = decompressor()
    error = TranscodingStreams.Error()
    TranscodingStreams.startproc(codec, :write, error) === :error && parse_error(
        state, "Could not decompress a CBLOCK: $(error[])"
    )
    nin, nout = 0, 0
    GC.@preserve bytes output while true
        input = TranscodingStreams.Memory(pointer(bytes) + nin, length(bytes) - nin)
        space = TranscodingStreams.Memory(pointer(output) + nout, length(output) - nout)
        Δin, Δout, code = TranscodingStreams.process(codec, input, space, error)
        nin += Δin
        nout += Δout
        code === :end && return nout, true
        code === :error && parse_error(state, "Could not decompress a CBLOCK: $(error[])")
        # Asking for more without any space left counts as an error, so stop when full. Also
        # stop when no progress is made, which means that the input has run out.
        (nout == length(output) || (iszero(Δin) && iszero(Δout))) && return nout, false
    end
end

function decompress_cblock(state, bytes::AbstractVector{UInt8}, uncomp_byte_count::Integer)
    # A spare byte both lets the decompressor reach the end of the data, and reveals data
    # that decompresses to more than declared.
    output = Vector{UInt8}(undef, uncomp_byte_count + 1)
    nout, finished = decompress!(state, output, bytes)
    (finished && nout == uncomp_byte_count) || parse_error(
        state, "CBLOCK doesn't decompress to the $uncomp_byte_count bytes it declares"
    )
    return resize!(output, uncomp_byte_count)
end

# The first byte of a CBLOCK, without decompressing the rest of it; `nothing` if it is empty.
function first_decompressed_byte(state, bytes::AbstractVector{UInt8})
    output = Vector{UInt8}(undef, 1)
    nout, _ = decompress!(state, output, bytes)
    return iszero(nout) ? nothing : output[1]
end
