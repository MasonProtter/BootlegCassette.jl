module BootlegCassette

using IRTools: IRTools, @code_ir, @dynamo, argument!, IR, xcall, isexpr, var

abstract type Context end

macro context(_ctx::Symbol)
    ctx = esc(_ctx)
    quote
        struct $ctx{T} <: Context
            metadata::T
        end
        $ctx(;metadata=nothing) = $ctx(metadata)
        $ctx{T}(;metadata=nothing) where {T} = $ctx{T}(metadata)
    end
end

function similarcontext(ctx::Ctx; metadata=nothing) where {Ctx<: Context}
    Ctx(metadata=metadata)
end

function default_is_blacklisted(x::GlobalRef, ::Type{<:Context})
    x.mod == Core || x ∈ (
        GlobalRef(Base, :isdispatchtuple),
        GlobalRef(Base, :eltype),
        GlobalRef(Base, :convert),
        GlobalRef(Base, :getproperty),
        GlobalRef(Base, :throw),
    )
end
default_is_blacklisted(::Any, ::Type{<:Context}) = false

is_blacklisted(x, y) = default_is_blacklisted(x, y)

@dynamo function overdub(ctx::C, f, args...) where {C <: Context}
    ir = IR(f, args...)
    ir == nothing && return
    ctx_arg = argument!(ir, at=1)
    for (x, st) in ir
        isexpr(st.expr, :call) || continue
        is_blacklisted(st.expr.args[1], ctx) && continue
        ir[x] = xcall(overdub_pass, ctx_arg, st.expr.args...)
    end
    return ir
end

@inline function overdub_pass(ctx, f, args...)
    prehook(ctx, f, args...)
    res = overdub(ctx, f, args...)
    posthook(ctx, res, f, args...)
    res
end

prehook(args...)  = nothing
@inline overdub(ctx::Context, f::Core.Builtin, args...) = f(args...)
posthook(args...) = nothing

recurse(args...) = invoke(overdub, Tuple{Vararg}, args...)
canrecurse(ctx, args...) = IR(typeof.(args)...) !== nothing

end # module
