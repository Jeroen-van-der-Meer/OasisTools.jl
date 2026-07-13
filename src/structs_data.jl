struct Interval
    low::UInt64
    high::UInt64
end

Base.in(p::UInt64, i::Interval) = i.low <= p <= i.high

"""
    struct PointGridRange(start, nstepx, nstepy, stepx, stepy)

A two-dimensional version of an ordinary range.

# Example

`PointGridRange((0, 0), 4, 3, (5, 1), (2, -2))` would kind of look like:
```
                 o
            o      
       o           o
  o           o
         o           o
    o           o
           o
      o
```
"""
struct PointGridRange <: AbstractRange{Point{2, Int64}}
    start::Point{2, Int64}
    nstepx::Int64
    nstepy::Int64
    stepx::Point{2, Int64}
    stepy::Point{2, Int64}
end
Base.first(r::PointGridRange) = r.start
Base.step(r::PointGridRange) = (r.stepx, r.stepy)
Base.last(r::PointGridRange) = r.start + (r.nstepx - 1) * r.stepx + (r.nstepy - 1) * r.stepy
function Base.getindex(r::PointGridRange, i::Integer)
    1 <= i <= length(r) || throw(BoundsError(r, i))
    s1 = r.nstepx
    ix = rem(i - 1, s1)
    iy = div(i - 1, s1)
    return r.start + ix * r.stepx + iy * r.stepy
end
function Base.getindex(r::PointGridRange, i::Integer, j::Integer)
    s1, s2 = size(r)
    1 <= i <= s1 || throw(BoundsError(r, [i, j]))
    1 <= j <= s2 || throw(BoundsError(r, [i, j]))
    return r.start + (i - 1) * r.stepx + (j - 1) * r.stepy
end
Base.IteratorSize(::Type{PointGridRange}) = Base.HasLength()
Base.size(r::PointGridRange) = (r.nstepx, r.nstepy)
Base.length(r::PointGridRange) = prod(size(r))
function Base.iterate(r::PointGridRange, i::Integer = zero(length(r)))
    i += oneunit(i)
    length(r) < i && return nothing
    r[i], i
end
Base.convert(::Type{Interval}, x::Integer) = Interval(x, x)
Base.isdisjoint(i::Interval, j::Interval) = (i.high < j.low) || (j.high < i.low)
Base.union(i::Interval, j::Interval) = Interval(min(i.low, j.low), max(i.high, j.high))
Base.in(x::Integer, i::Interval) = i.low <= x <= i.high

nrep(::Nothing) = 1
nrep(rep::Vector{Point{2, Int64}}) = length(rep)
nrep(rep::PointGridRange) = length(rep)
