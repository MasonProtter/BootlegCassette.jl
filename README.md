
# BootlegCassette.jl

BootlegCassette.jl is a quick and dirty package that tries to mimic
the interface of
[Cassette.jl](https://github.com/JuliaLabs/Cassette.jl) using
[IRTools.jl](https://github.com/FluxML/IRTools.jl) under the
hood. This isn't a great implementation, but provided you do not use
tagging and only use `@context`, `ovderdub`, `prehook`, `posthook` and
`recurse`, BootlegCassette.jl should work as a drop-in replacement for
Cassette.jl. 

While Cassette.jl is functioning, this package has little or no reason
to be used. It may be interesting for educational purposes.

BootlegCassette.jl is currently signigicantly slower than regular
Cassette.jl and has a different mechanism for setting recursion
barriers. Currently, it's set by default to not recurse into functions
from the `Core` module and also will leave the functions
`isdispatchtuple`, `eltype`, `convert`, `getproperty`, and `throw`
alone. This can be modified, but it's modified in a different way from
in standard non-bootleg Cassette.jl

## Examples


```julia
using BootlegCassette: BootlegCassette, @context, prehook, overdub, posthook, recurse
const Cassette = BootlegCassette

Cassette.@context Ctx 
Cassette.prehook(::Ctx, f, args...) = println(f, args)
Cassette.overdub(Ctx(), /, 1, 2)

#+RESULTS
float(1,)
AbstractFloat(1,)
Float64(1,)
sitofp(Float64, 1)
float(2,)
AbstractFloat(2,)
Float64(2,)
sitofp(Float64, 2)
/(1.0, 2.0)
div_float(1.0, 2.0)
```

```julia 
Cassette.prehook(::Ctx, f, args...) = nothing
Cassette.prehook(::Ctx{Val{T}}, f, arg::T, rest...) where {T} = println(f, (arg, rest...))
Cassette.overdub(Ctx(metadata=Val(Int)), /, 1, 2)

#+RESULTS
 float(1,)
 AbstractFloat(1,)
 Float64(1,) 
 float(2,)
 AbstractFloat(2,)
 Float64(2,)
 0.5
```

```julia 
Cassette.overdub(Ctx(metadata=Val(DataType)), /, 1, 2)

#+RESULTS
 sitofp(Float64, 1)
 sitofp(Float64, 2)
 0.5
```

```julia 
Cassette.@context TraceCtx

mutable struct Trace
    current::Vector{Any}
    stack::Vector{Any}
    Trace() = new(Any[], Any[])
end

function enter!(t::Trace, args...)
    pair = args => Any[]
    push!(t.current, pair)
    push!(t.stack, t.current)
    t.current = pair.second
    return nothing
end

function exit!(t::Trace)
    t.current = pop!(t.stack)
    return nothing
end

Cassette.prehook(ctx::TraceCtx, args...) = enter!(ctx.metadata, args...)
Cassette.posthook(ctx::TraceCtx, args...) = exit!(ctx.metadata)

trace = Trace()
x, y, z = rand(3)
f(x, y, z) = x*y + y*z
Cassette.overdub(TraceCtx(metadata = trace), () -> f(x, y, z))

trace.current == Any[
    (f,x,y,z) => Any[
        (*,x,y) => Any[(Base.mul_float,x,y)=>Any[]]
        (*,y,z) => Any[(Base.mul_float,y,z)=>Any[]]
        (+,x*y,y*z) => Any[(Base.add_float,x*y,y*z)=>Any[]]
    ]
]

#+RESULTS
true
```

```julia 
Cassette.@context SinToCosCtx

Cassette.overdub(::SinToCosCtx, ::typeof(sin), x) = cos(x)

x = rand(10)
y = Cassette.overdub(SinToCosCtx(), sum, i -> cos(i) + sin(i), x)
y == sum(i -> 2 * cos(i), x)

#+RESULTS
true
```

```julia 
fib(x) = x < 3 ? 1 : fib(x - 2) + fib(x - 1)
fibtest(n) = fib(2 * n) + n

@context MemoizeCtx

function Cassette.overdub(ctx::MemoizeCtx, ::typeof(fib), x)
    result = get(ctx.metadata, x, 0)
    if result === 0
        result = recurse(ctx, fib, x)
        ctx.metadata[x] = result
    end
    return result
end

ctx = MemoizeCtx(metadata=Dict{Int, Int}())

@time overdub(ctx, fibtest, 20)
@time overdub(ctx, fibtest, 20)
@time fibtest(20)

#+RESULTS
   0.188974 seconds (361.71 k allocations: 21.705 MiB, 7.02% gc time, 99.87% compilation time)
   0.000010 seconds (2 allocations: 32 bytes)
   0.318917 seconds
 102334175
```


The final example from https://julia.mit.edu/Cassette.jl/stable/contextualdispatch.html does not currently work. 
