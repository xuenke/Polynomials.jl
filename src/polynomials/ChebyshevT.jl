export ChebyshevT

"""
    ChebyshevT{<:Number}(coeffs::AbstractVector, var=:x)

Chebyshev polynomial of the first kind
"""
struct ChebyshevT{T <: Number} <: AbstractPolynomial{T}
    coeffs::Vector{T}
    var::Symbol
    function ChebyshevT{T}(coeffs::AbstractVector{T}, var::Symbol) where {T <: Number}
        length(coeffs) == 0 && return new{T}(zeros(T, 1), var)
        last_nz = findlast(!iszero, coeffs)
        last = max(1, last_nz === nothing ? 0 : last_nz)
        return new{T}(coeffs[1:last], var)
    end
end

@register ChebyshevT

function Base.convert(P::Type{<:Polynomial}, ch::ChebyshevT)
    if length(ch) < 3
        return P(ch.coeffs, ch.var)
    end
    c0 = P(ch[end - 1], ch.var)
    c1 = P(ch[end], ch.var)
    @inbounds for i in degree(ch):-1:2
        tmp = c0
        c0 = P(ch[i - 2], ch.var) - c1
        c1 = tmp + c1 * variable(P) * 2
    end
    return c0 + c1 * variable(P)
end

function Base.convert(C::Type{<:ChebyshevT}, p::Polynomial)
    res = zero(C)
    @inbounds for i in degree(p):-1:0
        res = variable(C) * res + p[i]
    end
    return res
end

domain(::Type{<:ChebyshevT}) = Interval(-1, 1)

"""
    (::ChebyshevT)(x)

Evaluate the Chebyshev polynomial at `x`. If `x` is outside of the domain of [-1, 1], an error will be thrown. The evaluation uses Clenshaw Recursion.
"""
function (ch::ChebyshevT{T})(x::S) where {T,S}
    R = promote_type(T, S)
    length(ch) == 0 && return zero(R)
    length(ch) == 1 && return R(ch[0])
    c0 = ch[end - 1]
    c1 = ch[end]
    @inbounds for i in lastindex(ch) - 2:-1:0
        c0, c1 = ch[i] - c1, c0 + c1 * 2x
    end
    return R(c0 + c1 * x)
end

function fromroots(P::Type{<:ChebyshevT}, roots::AbstractVector{T}; var::SymbolLike = :x) where {T <: Number}
    p = [P([-r, 1]) for r in roots]
    n = length(p)
    while n > 1
        m, r = divrem(n, 2)
        tmp = [p[i] * p[i + m] for i in 1:m]
        if r > 0
            tmp[1] *= p[end]
        end
        p = tmp
        n = m
    end
    return truncate!(p[1])
end

function vander(P::Type{<:ChebyshevT}, x::AbstractVector{T}, n::Integer) where {T <: Number}
    A = Matrix{T}(undef, length(x), n + 1)
    A[:, 1] .= one(T)
    if n > 0
        A[:, 2] .= x
        @inbounds for i in 3:n + 1
            A[:, i] .= A[:, i - 1] .* 2x .- A[:, i - 2]
        end
    end
    return A
end

function integral(p::ChebyshevT{T}, k::S) where {T,S <: Number}
    R = promote_type(eltype(one(T) / 1), S)
    if hasnan(p) || isnan(k)
        return ChebyshevT([NaN])
    end
    n = length(p)
    if n == 1
        return ChebyshevT{R}([k, p[0]])
    end
    a2 = Vector{R}(undef, n + 1)
    a2[1] = zero(R)
    a2[2] = p[0]
    a2[3] = p[1] / 4
    @inbounds for i in 2:n - 1
        a2[i + 2] = p[i] / (2 * (i + 1))
        a2[i] -= p[i] / (2 * (i - 1))
    end
    a2[1] += R(k) - ChebyshevT(a2)(0)
    return ChebyshevT(a2, p.var)
end

function derivative(p::ChebyshevT{T}, order::Integer) where {T}
    order < 0 && error("Order of derivative must be non-negative")
    order == 0 && return p
    hasnan(p) && return ChebyshevT(T[NaN], p.var)
    order > length(p) && return zero(ChebyshevT{T})

    n = length(p)
    der = Vector{T}(undef, n)
    for i in 1:order
        n -= 1
        resize!(der, n)
        for j in n:-1:2
            der[j] = 2j * p[j]
            p[j - 2] += j * p[j] / (j - 2)
        end
        if n > 1
            der[2] = 4p[2]
        end
        der[1] = p[1]
    end
    return ChebyshevT(der, p.var)
end

##
function companion(p::ChebyshevT{T}) where T
    d = length(p) - 1
    d < 1 && error("Series must have degree greater than 1")
    d == 1 && return diagm(0 => [-p[0] / p[1]])
    R = eltype(one(T) / one(T))

    scl = append!([1.0], √5 .* ones(d - 1))

    diag = append!([√5], 0.5 .* ones(d - 2))
    comp = diagm(-1 => diag,
                  1 => diag)
    monics = p.coeffs ./ p.coeffs[end]
    comp[:, end] .-= monics[1:d] .* scl ./ scl[end]
    return R.(comp ./ 2)
end

function Base.:+(p1::ChebyshevT, p2::ChebyshevT)
    p1.var != p2.var && error("Polynomials must have same variable")
    n = max(length(p1), length(p2))
    c = [p1[i] + p2[i] for i = 0:n]
    return ChebyshevT(c, p1.var)
end


function Base.:*(p1::ChebyshevT{T}, p2::ChebyshevT{S}) where {T,S}
    p1.var != p2.var && error("Polynomials must have same variable")
    z1 = _c_to_z(p1.coeffs)
    z2 = _c_to_z(p2.coeffs)
    prod = fastconv(z1, z2)
    ret = ChebyshevT(_z_to_c(prod), p1.var)
    return truncate!(ret)
end

function Base.divrem(num::ChebyshevT{T}, den::ChebyshevT{S}) where {T,S}
    num.var != den.var && error("Polynomials must have same variable")
    n = length(num) - 1
    m = length(den) - 1

    R = typeof(one(T) / one(S))
    P = ChebyshevT{R}

    if n < m
        return zero(P), convert(P, num)
    elseif m == 0
        den[0] ≈ 0 && throw(DivideError())
        return num ./ den[end], zero(P)
    end

    znum = _c_to_z(num.coeffs)
    zden = _c_to_z(den.coeffs)
    quo, rem = _z_division(znum, zden)
    q_coeff = _z_to_c(quo)
    r_coeff = _z_to_c(rem)
    return P(q_coeff, num.var), P(r_coeff, num.var)
end

function printpoly(io::IO, p::ChebyshevT{T}, mimetype = MIME"text/plain"(); descending_powers = false, offset::Int = 0) where {T}
    chopped = chop(p)
    print(io, coeffs(chopped))
    return nothing
end

#=
zseries
=#

function _c_to_z(cs::AbstractVector{T}) where {T}
    n = length(cs)
    U = promote_type(T, typeof(one(T) / 2))
    zs = Vector{U}(undef, 2n - 1)
    zs[n:end] = cs ./ 2
    return zs .+ reverse(zs)
end

function _z_to_c(z::AbstractVector{T}) where {T}
    n = (length(z) + 1) ÷ 2
    cs = z[n:end]
    cs[2:n] *= 2
    return cs
end

function _z_division(z1::AbstractVector{T}, z2::AbstractVector{S}) where {T,S}
    R = eltype(one(T) / one(S))
    length(z1)
    length(z2)
    if length(z2) == 1
        z1 ./= z2
        return z1, zero(R)
    elseif length(z1) < length(z2)
        return zero(R), R.(z1)
    end
    dlen = length(z1) - length(z2)
    scl = z2[1]
    z2 ./= scl
    quo = Vector{R}(undef, dlen + 1)
    i = 1
    j = dlen + 1
    while i < j
        r = z1[i]
        quo[i] = z1[i]
        quo[end - i + 1] = r
        tmp = r .* z2
        z1[i:i + length(z2) - 1] .-= tmp
        z1[j:j + length(z2) - 1] .-= tmp
        i += 1
        j -= 1
    end
        
    r = z1[i]
    quo[i] = r
    tmp = r * z2
    z1[i:i + length(z2) - 1] .-= tmp
    quo ./= scl
    rem = z1[i + 1:i - 2 + length(z2)]
    return quo, rem
end
