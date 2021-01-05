using Test
using BootlegCassette: BootlegCassette, @context, prehook, overdub, posthook, recurse
const Cassette = BootlegCassette


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

@test trace.current == Any[
    (f,x,y,z) => Any[
        (*,x,y) => Any[(Base.mul_float,x,y)=>Any[]]
        (*,y,z) => Any[(Base.mul_float,y,z)=>Any[]]
        (+,x*y,y*z) => Any[(Base.add_float,x*y,y*z)=>Any[]]
    ]
]


#--------------------------------------------------

Cassette.@context SinToCosCtx

# Override the default recursive `overdub` implementation for `sin(x)`.
# Note that there's no tricks here; this is just a normal Julia method
# overload using the normal multiple dispatch semantics.
Cassette.overdub(::SinToCosCtx, ::typeof(sin), x) = cos(x)

x = rand(10)
y = Cassette.overdub(SinToCosCtx(), sum, i -> cos(i) + sin(i), x)
@test y == sum(i -> 2 * cos(i), x)

#-----------------------------------------------------

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

@test overdub(ctx, fibtest, 20) == fibtest(20)
