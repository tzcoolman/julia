module FieldValues

export FieldValue, validmax, secondmax

# FieldValue is a numeric type which helps dealing with
# infinities. It holds 5 numbers l0,l1,l2,l3,l4. It can
# be interpreted as a polynomial
#  x = a^4 * l0 + a^3 * l1 + a^2 + l2 + a^1 * l3 + l4
# where a -> Inf
# The levels are used as such:
#  l0 : for hard constraints (dependencies and requirements)
#  l1 : for favoring higher versions of the explicitly required
#       packages
#  l2 : for favoring higher versions of all other packages (and
#       favoring uninstallation of non-needed packages)
#  l3 : for favoring dependants over dependencies
#  l4 : for symmetry-breaking random noise
#
immutable FieldValue
    l0::Int
    l1::Int
    l2::Int
    l3::Int
    l4::Int
end
FieldValue(l0::Int,l1::Int,l2::Int,l3::Int) = FieldValue(l0, l1, l2, l3, 0)
FieldValue(l0::Int,l1::Int,l2::Int) = FieldValue(l0, l1, l2, 0)
FieldValue(l0::Int,l1::Int) = FieldValue(l0, l1, 0)
FieldValue(l0::Int) = FieldValue(l0, 0)
FieldValue() = FieldValue(0)

Base.zero(::Type{FieldValue}) = FieldValue()

Base.typemin(::Type{FieldValue}) = (x=typemin(Int); FieldValue(x,x,x,x,x))
Base.typemax(::Type{FieldValue}) = (x=typemax(Int); FieldValue(x,x,x,x,x))

Base.(:-)(a::FieldValue, b::FieldValue) = FieldValue(a.l0-b.l0, a.l1-b.l1, a.l2-b.l2, a.l3-b.l3, a.l4-b.l4)
Base.(:+)(a::FieldValue, b::FieldValue) = FieldValue(a.l0+b.l0, a.l1+b.l1, a.l2+b.l2, a.l3+b.l3, a.l4+b.l4)

Base.isequal(a::FieldValue, b::FieldValue) = (a.l0==b.l0 && a.l1==b.l1 && a.l2==b.l2 && a.l3==b.l3 && a.l4==b.l4)

function Base.isless(a::FieldValue, b::FieldValue)
    a.l0 < b.l0 && return true
    a.l0 > b.l0 && return false
    a.l1 < b.l1 && return true
    a.l1 > b.l1 && return false
    a.l2 < b.l2 && return true
    a.l2 > b.l2 && return false
    a.l3 < b.l3 && return true
    a.l3 > b.l3 && return false
    a.l4 < b.l4 && return true
    return false
end

Base.abs(a::FieldValue) = FieldValue(abs(a.l0), abs(a.l1), abs(a.l2), abs(a.l3), abs(a.l4))
Base.abs(v::Vector{FieldValue}) = FieldValue[abs(a) for a in v]

# if the maximum field has l0 < 0, it means that
# some hard constraint is being violated
validmax(a::FieldValue) = a.l0 >= 0

# like usual indmax, but favors the highest indices
# in case of a tie
function Base.indmax(v::Vector{FieldValue})
    m = typemin(FieldValue)
    mi = 0
    for j = length(v):-1:1
        if v[j] > m
            m = v[j]
            mi = j
        end
    end
    @assert mi != 0
    return mi
end

# secondmax returns the (normalized) value of the second maximum in a
# field (i.e. a Vector of FieldValues. It's used to determine the most
# polarized field.
function secondmax(v::Vector{FieldValue})
    m = typemin(FieldValue)
    m2 = typemin(FieldValue)
    for i = 1:length(v)
        a = v[i]
        if a > m
            m2 = m
            m = a
        elseif a > m2
            m2 = a
        end
    end
    return m2 - m
end

end
