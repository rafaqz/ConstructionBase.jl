module ConstructionBase

export setproperties
export constructorof


"""
    constructorof(T::Type)

Return an object `ctor` that can be used to construct objects of type `T`
from their field values. Typically `ctor` will be the type `T` with all parameters removed:
```jldoctest
julia> using ConstructionBase

julia> struct T{A,B}
           a::A
           b::B
       end

julia> constructorof(T{Int,Int})
T
```
It is however not guaranteed, that `ctor` is a type at all:
```jldoctest; setup = :(using ConstructionBase)
julia> struct S
           a
           b
           checksum
           S(a,b) = new(a,b,a+b)
       end

julia> ConstructionBase.constructorof(::Type{<:S}) =
           (a, b, checksum=a+b) -> (@assert a+b == checksum; S(a,b))

julia> constructorof(S)(1,2)
S(1, 2, 3)

julia> constructorof(S)(1,2,4)
ERROR: AssertionError: a + b == checksum
```
Instead `ctor` can be any object that satisfies the following properties:
* It must be possible to reconstruct an object from its fields:
```julia
ctor = constructorof(typeof(obj))
@assert obj == ctor(fieldvalues(obj)...)
@assert typeof(obj) == typeof(ctor(fieldvalues(obj)...))
```
* The other direction should hold for as many values of `args` as possible:
```julia
ctor = constructorof(T)
fieldvalues(ctor(args...)) == args
```
For instance given a suitable parametric type it should be possible to change
the type of its fields:
```jldoctest; setup = :(using ConstructionBase)
julia> struct T{A,B}
           a::A
           b::B
       end

julia> t = T(1,2)
T{Int64,Int64}(1, 2)

julia> constructorof(typeof(t))(1.0, 2)
T{Float64,Int64}(1.0, 2)

julia> constructorof(typeof(t))(10, 2)
T{Int64,Int64}(10, 2)
```
"""
@generated function constructorof(::Type{T}) where T
    getfield(parentmodule(T), nameof(T))
end

constructorof(::Type{<:Tuple}) = tuple
constructorof(::Type{<:NamedTuple{names}}) where names =
    NamedTupleConstructor{names}()

struct NamedTupleConstructor{names} end

@generated function (::NamedTupleConstructor{names})(args...) where names
    quote
        Base.@_inline_meta
        $(NamedTuple{names, Tuple{args...}})(args)
    end
end

function assert_hasfields(T, fnames)
    for fname in fnames
        if !(fname in fieldnames(T))
            msg = "$T has no field $fname"
            throw(ArgumentError(msg))
        end
    end
end

"""
    setproperties(obj, patch::NamedTuple)

Return a copy of `obj` with attributes updates accoring to `patch`.

# Examples
```jldoctest
julia> using ConstructionBase

julia> struct S
           a
           b
           c
       end

julia> s = S(1,2,3)
S(1, 2, 3)

julia> setproperties(s, (a=10,c=4))
S(10, 2, 4)

julia> setproperties((a=1,c=2,b=3), (a=10,c=4))
(a = 10, c = 4, b = 3)
```

There is also a convenience method, which builds the `patch` argument from
keywords:

    setproperties(obj; kw...)

# Examples
```jldoctest
julia> using ConstructionBase

julia> struct S;a;b;c; end

julia> o = S(10, 2, 4)
S(10, 2, 4)

julia> setproperties(o, a="A", c="cc")
S("A", 2, "cc")
```

# Overloading

**WARNING** The signature `setproperties(obj::MyType; kw...)` should never be overloaded. Instead `setproperties(obj::MyType, patch::NamedTuple)` should be overloaded.

# Specification

`setproperties` guarantees a couple of invariants. When overloading it, the user is responsible for ensuring them:

1. Purity: `setproperties` is supposed to have no side effects. In particular `setproperties(obj, patch::NamedTuple)` may not mutate `obj`.
2. Relation to `propertynames` and `fieldnames`: `setproperties` relates to `propertynames` and `getproperty`, not to `fieldnames` and `getfield`.
This means that any subset `p₁, p₂, ..., pₙ` of `propertynames(obj)` is a valid set of properties, with respect to which the lens laws below must hold.
3. `setproperties` should satisfy the lens laws:
For any valid set of properties `p₁, p₂, ..., pₙ`, following equalities must hold:

* You get what you set.

```julia
let obj′ = setproperties(obj, (\$p₁=v₁, \$p₂=v₂, ..., \$pₙ=vₙ))
    @assert obj′.\$p₁ == v₁
    @assert obj′.\$p₂ == v₂
    ...
    @assert obj′.\$pₙ == vₙ
end
```

* Setting what was already there changes nothing:

```julia
@assert setproperties(obj, (\$p₁=obj.\$p₁, \$p₂=obj.\$p₂, ..., \$pₙ=obj.\$pₙ)) == obj
```

* The last set wins:
```julia
let obj′ = setproperties(obj, (\$p₁=v₁, \$p₂=v₂, ..., \$pₙ=vₙ)),
    obj′′ = setproperties(obj′, (\$p₁=w₁, \$p₂=w₂, ..., \$pₙ=wₙ))
    @assert obj′′.\$p₁ == w₁
    @assert obj′′.\$p₂ == w₂
    ...
    @assert obj′′.\$pₙ == wₙ
end
```
"""
function setproperties end

function setproperties(obj; kw...)
    setproperties(obj, (;kw...))
end

@generated function setproperties(obj, patch::NamedTuple)
    assert_hasfields(obj, fieldnames(patch))
    args = map(fieldnames(obj)) do fn
        if fn in fieldnames(patch)
            :(patch.$fn)
        else
            :(obj.$fn)
        end
    end
    Expr(:block,
        Expr(:meta, :inline),
        Expr(:call,:(constructorof($obj)), args...)
    )
end


end # module
