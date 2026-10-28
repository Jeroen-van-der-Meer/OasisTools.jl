"""
    PropertyValue

The types a value of a [`Property`](@ref) can have: an unsigned or signed integer, a real number,
or a string. References to PROPSTRING records are resolved to the strings they refer to.
"""
const PropertyValue = Union{UInt64, Int64, Float64, String}

"""
    struct Property

An annotation of an OASIS file, a cell, a placement or a shape: a name with a list of values.

# Properties

- `name::String`: Name of the property.
- `values::Vector{PropertyValue}`: Its values, which may be unsigned or signed integers, reals,
  or strings. Reals are stored as `Float64`, whichever of the eight formats of the spec the file
  uses.
- `standard::Bool`: Whether this is one of the standard properties listed in the spec, such as
  `S_TOP_CELL` or `S_GDS_PROPERTY`.

See also [`properties`](@ref).
"""
struct Property
    name::String
    values::Vector{PropertyValue}
    standard::Bool
end

Property(name::AbstractString, values::AbstractVector = PropertyValue[]; standard::Bool = false) =
    Property(String(name), convert(Vector{PropertyValue}, values), standard)

Base.:(==)(a::Property, b::Property) =
    a.name == b.name && a.values == b.values && a.standard == b.standard
Base.hash(p::Property, h::UInt) = hash(p.values, hash(p.name, hash(p.standard, h)))

function Base.show(io::IO, p::Property)
    print(io, p.name, p.standard ? " (standard)" : "", ": ")
    join(io, (v isa UInt64 ? string(v) : repr(v) for v in p.values), ", ")
end

# Elements without properties share no list, so that they don't take up memory for one.
const NoProperties = Union{Nothing, Vector{Property}}

property_list(::Nothing) = Property[]
property_list(properties::Vector{Property}) = properties

"""
    properties(oas)
    properties(cell)
    properties(element)

The properties of an OASIS object, a cell, or a shape or placement, as a list of
[`Property`](@ref) objects.

The properties of a cell are those following its CELLNAME record as well as those following its
CELL record. Getting the latter for a cell that isn't loaded brings it to [`tier`](@ref) 1.
"""
function properties end

# While reading, property names and PROPSTRING references are kept as they are, as they may
# refer to PROPNAME and PROPSTRING records further on in the file.
struct PropStringReference
    number::UInt64
end

struct RawProperty
    name::Union{String, UInt64}
    values::Vector{Union{PropertyValue, PropStringReference}}
    standard::Bool
end

# Reads a PROPERTY record, with record type 28, after its record ID.
function read_raw_property(state)
    info_byte = read_byte(state) # 'UUUUVCNS'
    standard = bit_is_one(info_byte, 8)
    if bit_is_one(info_byte, 6)
        name = bit_is_one(info_byte, 7) ? rui(state) : read_string(state)
        state.mod.lastPropertyName = name
    else
        name = state.mod.lastPropertyName
        isnothing(name) && parse_error(state, "PROPERTY reuses the name of a previous PROPERTY, but there is none")
    end
    if bit_is_one(info_byte, 5)
        values = state.mod.lastValueList
        isnothing(values) && parse_error(state, "PROPERTY reuses the values of a previous PROPERTY, but there is none")
    else
        count = info_byte >> 4
        count == 0x0f && (count = rui(state))
        values = Union{PropertyValue, PropStringReference}[read_property_value(state) for _ in 1:count]
        state.mod.lastValueList = values
    end
    state.mod.lastPropertyStandard = standard
    return RawProperty(name, values, standard)
end

# Record type 29 repeats the previous PROPERTY record.
function repeat_raw_property(state)
    name, values = state.mod.lastPropertyName, state.mod.lastValueList
    (isnothing(name) || isnothing(values)) &&
        parse_error(state, "PROPERTY repeats a previous PROPERTY, but there is none")
    return RawProperty(name, values, state.mod.lastPropertyStandard)
end

function resolve_property(state, raw::RawProperty, propnames, propstrings)
    name = raw.name isa UInt64 ?
        String(lookup_reference(state, propnames, raw.name, "property name", "PROPNAME")) : raw.name
    values = PropertyValue[
        v isa PropStringReference ?
            String(lookup_reference(state, propstrings, v.number, "property string", "PROPSTRING")) : v
        for v in raw.values
    ]
    return Property(name, values, raw.standard)
end
