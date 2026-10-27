function write_start(state::WriterState, unit::Float64)
    write_byte(state, 1) # START
    write_bn_string(state, "1.0")
    write_real(state, unit) # Convention: Grid steps per micron.
    write_byte(state, 0) # offset-flag
    for _ in 1:12
        write_byte(state, 0x00) # table-offsets
    end
end

function write_end(state::WriterState)
    write_byte(state, 2) # END
    wui(state, 252)  # Make END record exactly 256 bytes long
    write_bytes(state, zeros(UInt8, 252))
    write_byte(state, 0) # Validation scheme: No validation
end

function write_cellname(state::WriterState, name::Symbol)
    write_byte(state, 3) # CELLNAME
    write_bn_string(state, name)
end

function write_propname(state::WriterState, name::Symbol)
    write_byte(state, 7) # PROPNAME
    write_bn_string(state, name)
end

function write_layername(state::WriterState, layer::Layer)
    write_byte(state, 11) # LAYERNAME
    write_bn_string(state, layer.name)
    write_interval(state, layer.layerNumber)
    write_interval(state, layer.datatypeNumber)
end

function write_textlayername(state::WriterState, layer::Layer)
    write_byte(state, 12) # LAYERNAME
    write_bn_string(state, layer.name)
    write_interval(state, layer.layerNumber)
    write_interval(state, layer.datatypeNumber)
end

function write_cell(state::WriterState, cell::Cell)
    write_byte(state, 13) # CELL
    wui(state, state.cellnameReferences[cell.name])
    reset_modal_variables!(state.mod)
    if isloaded(cell) || !isempty(cell.edits)
        # Hand every element to the encoder, decoding them first if the cell isn't loaded. As
        # `decode_cell` passes the shapes of a loaded cell on a kind at a time, the modal
        # variables stay stable across each group.
        decode_cell(state, cell)
    else
        copywrite_source(state, cell.source)
    end
end

function write_placement_record(state::WriterState, placement::CellPlacement)
    if !isone(placement.magnification) || !iszero(mod(placement.rotation, 90))
        write_placement_mag_angle(state, placement)
    else
        write_placement(state, placement)
    end
end

# The contents of a cell that hasn't been loaded or changed can mostly be copied byte for byte.
# Only the references to cell names and text strings need translating, as the numbering is
# specific to each file.
function copywrite_source(state::WriterState, source::CellSource)
    cell_parser_state = SkipParserState(source.bytes, 1)
    nbytes = length(source.bytes)
    while cell_parser_state.pos <= nbytes
        record_type = read_byte(cell_parser_state)
        copywrite_record(record_type, state, source, cell_parser_state)
    end
end

function copywrite_placement(
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState
)
    write_byte(state, 17) # PLACEMENT
    info_byte = read_byte(cell_parser_state)
    write_cellname_reference(state, source, cell_parser_state, info_byte)

    # After writing the new reference, we copy the remaining records.
    remaining_record_start = cell_parser_state.pos
    bit_is_one(info_byte, 3) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 4) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 5) && skip_repetition(cell_parser_state)
    record_end = cell_parser_state.pos - 1
    nbytes = record_end - remaining_record_start + 1
    write_bytes(state, view(cell_parser_state.buf, remaining_record_start:record_end), nbytes)
end

function write_placement(state::WriterState, placement::CellPlacement)
    info_byte = UInt8(0)

    cellname = placement.cellName
    cellname_explicit = cellname != state.mod.placementCell
    if cellname_explicit
        info_byte = set_bit_to_one(info_byte, 1)
        info_byte = set_bit_to_one(info_byte, 2) # Write as reference
        state.mod.placementCell = cellname
    end

    x = placement.location[1]
    x_explicit = x != state.mod.placementX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 3)
        state.mod.placementX = x
    end

    y = placement.location[2]
    y_explicit = y != state.mod.placementY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.placementY = y
    end

    rep = placement.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 5)
    end

    info_byte |= UInt8(mod(placement.rotation, 360) ÷ 90) << 1

    if placement.flipped
        info_byte = set_bit_to_one(info_byte, 8)
    end

    write_byte(state, 17) # PLACEMENT
    write_byte(state, info_byte)
    cellname_explicit && wui(state, state.cellnameReferences[cellname])
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

function write_placement_mag_angle(state::WriterState, placement::CellPlacement)
    info_byte = UInt8(0)

    cellname = placement.cellName
    cellname_explicit = cellname != state.mod.placementCell
    if cellname_explicit
        info_byte = set_bit_to_one(info_byte, 1)
        info_byte = set_bit_to_one(info_byte, 2) # Write as reference
        state.mod.placementCell = cellname
    end

    x = placement.location[1]
    x_explicit = x != state.mod.placementX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 3)
        state.mod.placementX = x
    end

    y = placement.location[2]
    y_explicit = y != state.mod.placementY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.placementY = y
    end

    rep = placement.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 5)
    end

    mag = placement.magnification
    mag_explicit = !isone(mag)
    if mag_explicit
        info_byte = set_bit_to_one(info_byte, 6)
    end

    rot = placement.rotation
    rot_explicit = !iszero(rot)
    if rot_explicit
        info_byte = set_bit_to_one(info_byte, 7)
    end

    if placement.flipped
        info_byte = set_bit_to_one(info_byte, 8)
    end

    write_byte(state, 18) # PLACEMENT with magnification/angle
    write_byte(state, info_byte)
    cellname_explicit && wui(state, state.cellnameReferences[cellname])
    mag_explicit && write_real(state, mag)
    rot_explicit && write_real(state, rot)
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

function copywrite_placement_mag_angle(
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState
)
    write_byte(state, 18) # PLACEMENT
    info_byte = read_byte(cell_parser_state)
    write_cellname_reference(state, source, cell_parser_state, info_byte)

    # After writing the new reference, we copy the remaining records.
    remaining_record_start = cell_parser_state.pos
    bit_is_one(info_byte, 6) && skip_real(cell_parser_state)
    bit_is_one(info_byte, 7) && skip_real(cell_parser_state)
    bit_is_one(info_byte, 3) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 4) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 5) && skip_repetition(cell_parser_state)
    record_end = cell_parser_state.pos - 1
    nbytes = record_end - remaining_record_start + 1
    write_bytes(state, view(cell_parser_state.buf, remaining_record_start:record_end), nbytes)
end

function copywrite_text(
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState
)
    write_byte(state, 19) # TEXT
    info_byte = read_byte(cell_parser_state)
    write_text(state, source, cell_parser_state, info_byte)

    # After writing the new reference, we copy the remaining records.
    remaining_record_start = cell_parser_state.pos
    bit_is_one(info_byte, 8) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 7) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 4) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 5) && skip_integer(cell_parser_state)
    bit_is_one(info_byte, 6) && skip_repetition(cell_parser_state)
    record_end = cell_parser_state.pos - 1
    nbytes = record_end - remaining_record_start + 1
    write_bytes(state, view(cell_parser_state.buf, remaining_record_start:record_end), nbytes)
end

function write_shape(state::WriterState, shape::Shape{Polygon{2, Int64}})
    info_byte = UInt8(0)

    layer_number = shape.layerNumber
    layer_explicit = layer_number != state.mod.layer
    if layer_explicit
        info_byte = set_bit_to_one(info_byte, 8)
        state.mod.layer = layer_number
    end

    datatype_number = shape.datatypeNumber
    datatype_explicit = datatype_number != state.mod.datatype
    if datatype_explicit
        info_byte = set_bit_to_one(info_byte, 7)
        state.mod.datatype = datatype_number
    end

    # Always write point list explicitly
    info_byte = set_bit_to_one(info_byte, 3)
    exterior = shape.shape.exterior
    x = Int64(exterior[1][1])
    y = Int64(exterior[1][2])

    x_explicit = x != state.mod.geometryX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.geometryX = x
    end

    y_explicit = y != state.mod.geometryY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 5)
        state.mod.geometryY = y
    end

    rep = shape.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 6)
    end

    write_byte(state, 21) # POLYGON
    write_byte(state, info_byte)
    layer_explicit && wui(state, layer_number)
    datatype_explicit && wui(state, datatype_number)
    write_point_list(state, collect(exterior))
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

# Triangles are written as polygons.
function write_shape(state::WriterState, shape::Shape{Triangle{2, Int64}})
    tri = shape.shape
    polygon = Polygon([tri[1], tri[2], tri[3]])
    write_shape(state, Shape(polygon, shape.layerNumber, shape.datatypeNumber, shape.repetition))
end

function write_shape(state::WriterState, shape::Shape{Rect{2, Int64}})
    info_byte = UInt8(0)

    rect = shape.shape
    width = unsigned(rect.widths[1])
    height = unsigned(rect.widths[2])
    is_square = width == height
    if is_square
        info_byte = set_bit_to_one(info_byte, 1)
    end

    layer_number = shape.layerNumber
    layer_explicit = layer_number != state.mod.layer
    if layer_explicit
        info_byte = set_bit_to_one(info_byte, 8)
        state.mod.layer = layer_number
    end

    datatype_number = shape.datatypeNumber
    datatype_explicit = datatype_number != state.mod.datatype
    if datatype_explicit
        info_byte = set_bit_to_one(info_byte, 7)
        state.mod.datatype = datatype_number
    end

    width_explicit = width != state.mod.geometryW
    if width_explicit
        info_byte = set_bit_to_one(info_byte, 2)
        state.mod.geometryW = width
    end

    height_explicit = false
    if is_square
        state.mod.geometryH = width
    else
        height_explicit = height != state.mod.geometryH
        if height_explicit
            info_byte = set_bit_to_one(info_byte, 3)
            state.mod.geometryH = height
        end
    end

    x = Int64(rect.origin[1])
    y = Int64(rect.origin[2])

    x_explicit = x != state.mod.geometryX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.geometryX = x
    end

    y_explicit = y != state.mod.geometryY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 5)
        state.mod.geometryY = y
    end

    rep = shape.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 6)
    end

    write_byte(state, 20) # RECTANGLE
    write_byte(state, info_byte)
    layer_explicit && wui(state, layer_number)
    datatype_explicit && wui(state, datatype_number)
    width_explicit && wui(state, width)
    height_explicit && wui(state, height)
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

function write_shape(state::WriterState, shape::Shape{HyperSphere{2, Int64}})
    info_byte = UInt8(0)

    layer_number = shape.layerNumber
    layer_explicit = layer_number != state.mod.layer
    if layer_explicit
        info_byte = set_bit_to_one(info_byte, 8)
        state.mod.layer = layer_number
    end

    datatype_number = shape.datatypeNumber
    datatype_explicit = datatype_number != state.mod.datatype
    if datatype_explicit
        info_byte = set_bit_to_one(info_byte, 7)
        state.mod.datatype = datatype_number
    end

    radius = unsigned(shape.shape.r)
    radius_explicit = radius != state.mod.circleRadius
    if radius_explicit
        info_byte = set_bit_to_one(info_byte, 3)
        state.mod.circleRadius = radius
    end

    x = Int64(shape.shape.center[1])
    y = Int64(shape.shape.center[2])

    x_explicit = x != state.mod.geometryX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.geometryX = x
    end

    y_explicit = y != state.mod.geometryY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 5)
        state.mod.geometryY = y
    end

    rep = shape.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 6)
    end

    write_byte(state, 27) # CIRCLE
    write_byte(state, info_byte)
    layer_explicit && wui(state, layer_number)
    datatype_explicit && wui(state, datatype_number)
    radius_explicit && wui(state, radius)
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

function write_shape(state::WriterState, shape::Shape{Path{2, Int64}})
    info_byte = UInt8(0)

    layer_number = shape.layerNumber
    layer_explicit = layer_number != state.mod.layer
    if layer_explicit
        info_byte = set_bit_to_one(info_byte, 8)
        state.mod.layer = layer_number
    end

    datatype_number = shape.datatypeNumber
    datatype_explicit = datatype_number != state.mod.datatype
    if datatype_explicit
        info_byte = set_bit_to_one(info_byte, 7)
        state.mod.datatype = datatype_number
    end

    halfwidth = unsigned(shape.shape.width ÷ 2)
    halfwidth_explicit = halfwidth != state.mod.pathHalfwidth
    if halfwidth_explicit
        info_byte = set_bit_to_one(info_byte, 2)
        state.mod.pathHalfwidth = halfwidth
    end

    # Always write point list explicitly
    info_byte = set_bit_to_one(info_byte, 3)
    points = shape.shape.points
    x = Int64(points[1][1])
    y = Int64(points[1][2])

    x_explicit = x != state.mod.geometryX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.geometryX = x
    end

    y_explicit = y != state.mod.geometryY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 5)
        state.mod.geometryY = y
    end

    rep = shape.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 6)
    end

    # No extension scheme (bit 1 stays off)

    write_byte(state, 22) # PATH
    write_byte(state, info_byte)
    layer_explicit && wui(state, layer_number)
    datatype_explicit && wui(state, datatype_number)
    halfwidth_explicit && wui(state, halfwidth)
    write_point_list(state, points)
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

function write_shape(state::WriterState, shape::Shape{Text})
    info_byte = UInt8(0)

    text = shape.shape
    textstring = text.text

    # Always write text explicitly as a string (not reference)
    textstring_explicit = textstring != state.mod.textString
    if textstring_explicit
        info_byte = set_bit_to_one(info_byte, 2) # Text explicit
        # bit 3 stays off: text is a string, not a reference
        state.mod.textString = textstring
    end

    layer_number = shape.layerNumber
    layer_explicit = layer_number != state.mod.textlayer
    if layer_explicit
        info_byte = set_bit_to_one(info_byte, 8)
        state.mod.textlayer = layer_number
    end

    datatype_number = shape.datatypeNumber
    datatype_explicit = datatype_number != state.mod.texttype
    if datatype_explicit
        info_byte = set_bit_to_one(info_byte, 7)
        state.mod.texttype = datatype_number
    end

    x = Int64(text.location[1])
    y = Int64(text.location[2])

    x_explicit = x != state.mod.textX
    if x_explicit
        info_byte = set_bit_to_one(info_byte, 4)
        state.mod.textX = x
    end

    y_explicit = y != state.mod.textY
    if y_explicit
        info_byte = set_bit_to_one(info_byte, 5)
        state.mod.textY = y
    end

    rep = shape.repetition
    has_repetition = !isnothing(rep)
    if has_repetition
        info_byte = set_bit_to_one(info_byte, 6)
    end

    write_byte(state, 19) # TEXT
    write_byte(state, info_byte)
    textstring_explicit && write_a_string(state, textstring)
    layer_explicit && wui(state, layer_number)
    datatype_explicit && wui(state, datatype_number)
    x_explicit && write_signed_integer(state, x)
    y_explicit && write_signed_integer(state, y)
    has_repetition && write_repetition(state, rep)
end

function write_property(state::WriterState, propname::Integer, propvalue::Symbol)
    write_byte(state, 28) # PROPERTY
    write_byte(state, 0b00010111) # Single value; property name referenced numerically
    wui(state, propname) # Numerical reference to property name
    write_property_value(state, propvalue)
end

function copywrite_cblock(
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState
)
    # To handle a CBLOCK, we temporarily replace the buffer of the lazy cell parser, and continue
    # our copywriting adventure.
    skip_byte(cell_parser_state) # comp_type
    uncomp_byte_count = rui(cell_parser_state)
    comp_byte_count = rui(cell_parser_state)

    comp_bytes = view_bytes(cell_parser_state, comp_byte_count)
    z = DeflateDecompressorStream(IOBuffer(comp_bytes))
    buf_decompress = Vector{UInt8}(undef, uncomp_byte_count)
    read!(z, buf_decompress)
    close(z)

    cell_parser_decomp = new_state(cell_parser_state, buf_decompress)
    while cell_parser_decomp.pos <= uncomp_byte_count
        record_type = read_byte(cell_parser_decomp)
        copywrite_record(record_type, state, source, cell_parser_decomp)
    end
end

function copywrite_record(
    record_type::UInt8,
    state::WriterState,
    source::CellSource,
    cell_parser_state::SkipParserState
)
    # PLACEMENT and TEXT records need special attention as they contain internal references (to
    # cell name and text strings, respectively), which are unique to the file they are
    # contained in.
    record_type == 17 && return copywrite_placement(state, source, cell_parser_state)
    record_type == 18 && return copywrite_placement_mag_angle(state, source, cell_parser_state)
    record_type == 19 && return copywrite_text(state, source, cell_parser_state)

    # CBLOCK records also need special attention because they need to be uncompressed.
    record_type == 34 && return copywrite_cblock(state, source, cell_parser_state)

    # All remaining records can be copy-pasted.
    record_start = cell_parser_state.pos - 1
    read_record(record_type, cell_parser_state)
    record_end = cell_parser_state.pos - 1
    nbytes = record_end - record_start + 1
    write_bytes(state, view(cell_parser_state.buf, record_start:record_end), nbytes)
end
