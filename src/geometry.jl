# Bounding boxes, transformations and clipping. Boxes are `Rect{2, Int64}`s; `nothing` stands
# for the bounding box of nothing at all.

box_lo(box::Rect{2, Int64}) = Point{2, Int64}(box.origin)
box_hi(box::Rect{2, Int64}) = Point{2, Int64}(box.origin + box.widths)
make_box(lo::Point{2, Int64}, hi::Point{2, Int64}) = Rect{2, Int64}(lo, hi - lo)

union_box(::Nothing, ::Nothing) = nothing
union_box(a::Rect{2, Int64}, ::Nothing) = a
union_box(::Nothing, b::Rect{2, Int64}) = b
function union_box(a::Rect{2, Int64}, b::Rect{2, Int64})
    alo, ahi, blo, bhi = box_lo(a), box_hi(a), box_lo(b), box_hi(b)
    return make_box(
        Point{2, Int64}(min(alo[1], blo[1]), min(alo[2], blo[2])),
        Point{2, Int64}(max(ahi[1], bhi[1]), max(ahi[2], bhi[2]))
    )
end

# Boxes are closed, so boxes that merely touch are not disjoint.
function is_disjoint(a::Rect{2, Int64}, b::Rect{2, Int64})
    alo, ahi, blo, bhi = box_lo(a), box_hi(a), box_lo(b), box_hi(b)
    return ahi[1] < blo[1] || bhi[1] < alo[1] || ahi[2] < blo[2] || bhi[2] < alo[2]
end

function contains_box(outer::Rect{2, Int64}, inner::Rect{2, Int64})
    olo, ohi, ilo, ihi = box_lo(outer), box_hi(outer), box_lo(inner), box_hi(inner)
    return olo[1] <= ilo[1] && olo[2] <= ilo[2] && ihi[1] <= ohi[1] && ihi[2] <= ohi[2]
end

function points_box(points)
    xs = (p[1] for p in points)
    ys = (p[2] for p in points)
    return make_box(
        Point{2, Int64}(minimum(xs), minimum(ys)),
        Point{2, Int64}(maximum(xs), maximum(ys))
    )
end

# Bounding box of a single instance of a geometry, ignoring repetitions.
geometry_box(r::Rect{2, Int64}) = r
geometry_box(p::Polygon{2, Int64}) = points_box(p.exterior)
geometry_box(t::Triangle{2, Int64}) = points_box((t[1], t[2], t[3]))
geometry_box(c::Circle{Int64}) = make_box(c.center .- c.r, c.center .+ c.r)
geometry_box(t::Text) = make_box(t.location, t.location)
function geometry_box(p::Path{2, Int64})
    # Expanding every vertex by the half-width in both directions covers the whole path, joints
    # included.
    halfwidth = cld(p.width, 2)
    box = points_box(p.points)
    return make_box(box_lo(box) .- halfwidth, box_hi(box) .+ halfwidth)
end

# Range of the offsets of a repetition, as the lowest and highest offset in each direction.
repetition_bounds(::Nothing) = (Point{2, Int64}(0, 0), Point{2, Int64}(0, 0))
function repetition_bounds(rep::PointGridRange)
    corners = (
        first(rep), rep.start + (rep.nstepx - 1) * rep.stepx,
        rep.start + (rep.nstepy - 1) * rep.stepy, last(rep)
    )
    box = points_box(corners)
    return box_lo(box), box_hi(box)
end
function repetition_bounds(rep::Vector{Point{2, Int64}})
    box = points_box(rep)
    return box_lo(box), box_hi(box)
end

function with_repetition_bounds(box::Rect{2, Int64}, rep)
    isnothing(rep) && return box
    lo, hi = repetition_bounds(rep)
    return make_box(box_lo(box) + lo, box_hi(box) + hi)
end

"""
    shape_extent(shape)

Bounding box of a [`Shape`](@ref), including all instances of its repetition.
"""
shape_extent(s::Shape) = with_repetition_bounds(geometry_box(s.shape), s.repetition)

# Applies the linear part of a placement (flip, rotation, magnification) to a point. Rotations
# by multiples of 90 degrees are carried out exactly.
function transform_point_float(
    p::Point{2, Int64}, rotation::Float64, magnification::Float64, flipped::Bool
)
    x, y = Float64(p[1]), Float64(p[2])
    flipped && (y = -y)
    if iszero(mod(rotation, 90))
        for _ in 1:mod(round(Int, rotation / 90), 4)
            x, y = -y, x
        end
    else
        θ = deg2rad(rotation)
        c, s = cos(θ), sin(θ)
        x, y = c * x - s * y, s * x + c * y
    end
    return magnification * x, magnification * y
end

# Bounding box of a single instance of a placement, given the bounding box of the placed cell.
# Rounds outwards, so that the result always covers the placed cell.
function placement_instance_box(p::CellPlacement, box::Rect{2, Int64})
    lo, hi = box_lo(box), box_hi(box)
    corners = (lo, Point{2, Int64}(hi[1], lo[2]), hi, Point{2, Int64}(lo[1], hi[2]))
    transformed = [transform_point_float(c, p.rotation, p.magnification, p.flipped) for c in corners]
    return make_box(
        Point{2, Int64}(floor(Int64, minimum(first, transformed)), floor(Int64, minimum(last, transformed))) +
            p.location,
        Point{2, Int64}(ceil(Int64, maximum(first, transformed)), ceil(Int64, maximum(last, transformed))) +
            p.location
    )
end

"""
    placement_extent(placement, box)

Bounding box of all instances of `placement`, given the bounding box `box` of the placed cell.
"""
placement_extent(p::CellPlacement, box::Rect{2, Int64}) =
    with_repetition_bounds(placement_instance_box(p, box), p.repetition)

# Maps a box in the coordinates of the cell containing placement `p` back into the coordinates
# of the placed cell. Only defined for rotations by multiples of 90 degrees, under which boxes
# stay boxes. Rounds outwards.
function inverse_placement_box(box::Rect{2, Int64}, p::CellPlacement)
    quarter_turns = mod(round(Int, p.rotation / 90), 4)
    xs, ys = Float64[], Float64[]
    for corner in (box_lo(box), box_hi(box))
        x, y = corner - p.location
        for _ in 1:quarter_turns
            x, y = y, -x
        end
        y = p.flipped ? -y : y
        push!(xs, x / p.magnification)
        push!(ys, y / p.magnification)
    end
    return make_box(
        Point{2, Int64}(floor(Int64, minimum(xs)), floor(Int64, minimum(ys))),
        Point{2, Int64}(ceil(Int64, maximum(xs)), ceil(Int64, maximum(ys)))
    )
end

# Moving a shape or placement by some offset.
translate(r::Rect{2, Int64}, o::Point{2, Int64}) = Rect{2, Int64}(r.origin + o, r.widths)
translate(p::Polygon{2, Int64}, o::Point{2, Int64}) = Polygon(p.exterior .+ Ref(o))
translate(t::Triangle{2, Int64}, o::Point{2, Int64}) = Triangle{2, Int64}(t[1] + o, t[2] + o, t[3] + o)
translate(p::Path{2, Int64}, o::Point{2, Int64}) = Path(p.points .+ Ref(o), p.width)
translate(c::Circle{Int64}, o::Point{2, Int64}) = Circle{Int64}(c.center + o, c.r)
translate(t::Text, o::Point{2, Int64}) = Text(t.text, t.location + o, t.repetition)
translate(s::Shape, o::Point{2, Int64}) =
    Shape(translate(s.shape, o), s.layer, s.datatype, s.repetition)
translate(p::CellPlacement, o::Point{2, Int64}) = CellPlacement(
    p.cell, p.location + o, p.rotation, p.magnification, p.flipped, p.repetition
)

with_repetition(s::Shape{Text}, rep) =
    Shape(Text(s.shape.text, s.shape.location, rep), s.layer, s.datatype, rep)
with_repetition(s::Shape, rep) = Shape(s.shape, s.layer, s.datatype, rep)
with_repetition(p::CellPlacement, rep) =
    CellPlacement(p.cell, p.location, p.rotation, p.magnification, p.flipped, rep)

# Recombines the instances of `element` (a shape or placement without repetition) at the given
# offsets into as few elements as possible.
function regroup(emit, element, offsets::Vector{Point{2, Int64}})
    isempty(offsets) && return
    base = translate(element, offsets[1])
    if length(offsets) == 1
        emit(base)
    else
        # Repetitions are stored relative to their first instance.
        emit(with_repetition(base, offsets .- Ref(offsets[1])))
    end
end

"""
    clip_shape(emit, shape, window)

Clips `shape` to the box `window`, calling `emit` on every resulting shape.

Rectangles and polygons (including triangles, which become polygons) are clipped exactly,
except that vertices introduced on diagonal edges are rounded to the grid. Paths and circles
that cross the edge of `window` are kept whole, and texts are kept if their location lies
within `window`. Repetitions crossing the edge are split into their instances.
"""
function clip_shape(emit, s::Shape, window::Rect{2, Int64})
    box = shape_extent(s)
    is_disjoint(box, window) && return
    if contains_box(window, box)
        emit(s)
        return
    end
    if isnothing(s.repetition)
        clip_instance(emit, s, window)
        return
    end
    single = with_repetition(s, nothing)
    inside = Point{2, Int64}[]
    for offset in s.repetition
        instance = translate(single, offset)
        instance_box = shape_extent(instance)
        is_disjoint(instance_box, window) && continue
        if contains_box(window, instance_box)
            push!(inside, offset)
        else
            clip_instance(emit, instance, window)
        end
    end
    regroup(emit, single, inside)
end

function clip_instance(emit, s::Shape{Rect{2, Int64}}, window::Rect{2, Int64})
    lo, hi = box_lo(s.shape), box_hi(s.shape)
    wlo, whi = box_lo(window), box_hi(window)
    clo = Point{2, Int64}(max(lo[1], wlo[1]), max(lo[2], wlo[2]))
    chi = Point{2, Int64}(min(hi[1], whi[1]), min(hi[2], whi[2]))
    (chi[1] > clo[1] && chi[2] > clo[2]) || return
    emit(Shape(make_box(clo, chi), s.layer, s.datatype, nothing))
end

clip_instance(emit, s::Shape{Polygon{2, Int64}}, window::Rect{2, Int64}) =
    clip_polygon_shape(emit, s, s.shape.exterior, window)

clip_instance(emit, s::Shape{Triangle{2, Int64}}, window::Rect{2, Int64}) =
    clip_polygon_shape(emit, s, [s.shape[1], s.shape[2], s.shape[3]], window)

# Paths and circles can't be clipped without turning them into polygons, so they are kept as
# they are. Texts never get here: they have no area, so they're either inside or outside.
clip_instance(emit, s::Shape, ::Rect{2, Int64}) = emit(s)

function clip_polygon_shape(emit, s::Shape, points, window::Rect{2, Int64})
    clipped = clip_polygon(points, window)
    (length(clipped) >= 3 && !iszero(twice_area(clipped))) || return
    emit(Shape(Polygon(clipped), s.layer, s.datatype, nothing))
end

# Sutherland–Hodgman clipping against each of the four sides of the window in turn. Concave
# polygons that the window cuts into several pieces come out as a single polygon whose pieces
# are connected by zero-width slivers along the edge of the window.
function clip_polygon(points, window::Rect{2, Int64})
    lo, hi = box_lo(window), box_hi(window)
    clipped = collect(Point{2, Int64}, points)
    for (axis, bound, keep_above) in ((1, lo[1], true), (1, hi[1], false), (2, lo[2], true), (2, hi[2], false))
        clipped = clip_polygon_side(clipped, axis, bound, keep_above)
        isempty(clipped) && return clipped
    end
    # Clipping leaves repeated vertices wherever a vertex lies on the edge of the window.
    deduplicated = Point{2, Int64}[]
    for p in clipped
        (isempty(deduplicated) || deduplicated[end] != p) && push!(deduplicated, p)
    end
    while length(deduplicated) > 1 && deduplicated[end] == deduplicated[1]
        pop!(deduplicated)
    end
    return deduplicated
end

function clip_polygon_side(points::Vector{Point{2, Int64}}, axis::Int, bound::Int64, keep_above::Bool)
    inside(p) = keep_above ? p[axis] >= bound : p[axis] <= bound
    clipped = Point{2, Int64}[]
    n = length(points)
    for i in 1:n
        current = points[i]
        previous = points[i == 1 ? n : i - 1]
        if inside(current)
            inside(previous) || push!(clipped, crossing(previous, current, axis, bound))
            push!(clipped, current)
        elseif inside(previous)
            push!(clipped, crossing(previous, current, axis, bound))
        end
    end
    return clipped
end

# Point where the segment from `p` to `q` crosses the line where coordinate `axis` equals
# `bound`, rounded to the grid.
function crossing(p::Point{2, Int64}, q::Point{2, Int64}, axis::Int, bound::Int64)
    other = 3 - axis
    t = (bound - p[axis]) / (q[axis] - p[axis])
    value = round(Int64, p[other] + t * (q[other] - p[other]))
    return axis == 1 ? Point{2, Int64}(bound, value) : Point{2, Int64}(value, bound)
end

function twice_area(points::Vector{Point{2, Int64}})
    total = Int128(0)
    n = length(points)
    for i in 1:n
        p, q = points[i], points[i == n ? 1 : i + 1]
        total += Int128(p[1]) * q[2] - Int128(q[1]) * p[2]
    end
    return total
end
