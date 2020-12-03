import Base: typesof, insert!

separate_kwargs(args...; kwargs...) = (args, kwargs.data)

function gen_call_with_extracted_types(__module__, fcn, ex0)
    if isa(ex0, Expr)
        if any(a->(Meta.isexpr(a, :kw) || Meta.isexpr(a, :parameters)), ex0.args)
            return quote
                local arg1 = $(esc(ex0.args[1]))
                local args, kwargs = $separate_kwargs($(map(esc, ex0.args[2:end])...))
                $(fcn)(Core.kwfunc(arg1),
                       Tuple{typeof(kwargs), Core.Typeof(arg1), map(Core.Typeof, args)...})
            end
        elseif ex0.head === :call
            return Expr(:call, fcn, esc(ex0.args[1]),
                        Expr(:call, typesof, map(esc, ex0.args[2:end])...))
        elseif ex0.head === :(=) && length(ex0.args) == 2
            lhs, rhs = ex0.args
            if isa(lhs, Expr)
                if lhs.head === :(.)
                    return Expr(:call, fcn, Base.setproperty!,
                                Expr(:call, typesof, map(esc, lhs.args)..., esc(rhs)))
                elseif lhs.head === :ref
                    return Expr(:call, fcn, Base.setindex!,
                                Expr(:call, typesof, esc(lhs.args[1]), esc(rhs), map(esc, lhs.args[2:end])...))
                end
            end
        elseif ex0.head === :vcat || ex0.head === :typed_vcat
            if ex0.head === :vcat
                f, hf = Base.vcat, Base.hvcat
                args = ex0.args
            else
                f, hf = Base.typed_vcat, Base.typed_hvcat
                args = ex0.args[2:end]
            end
            if any(a->isa(a,Expr) && a.head === :row, args)
                rows = Any[ (isa(x,Expr) && x.head === :row ? x.args : Any[x]) for x in args ]
                lens = map(length, rows)
                return Expr(:call, fcn, hf,
                            Expr(:call, typesof,
                                 (ex0.head === :vcat ? [] : Any[esc(ex0.args[1])])...,
                                 Expr(:tuple, lens...),
                                 map(esc, vcat(rows...))...))
            else
                return Expr(:call, fcn, f,
                            Expr(:call, typesof, map(esc, ex0.args)...))
            end
        else
            for (head, f) in (:ref => Base.getindex, :hcat => Base.hcat, :(.) => Base.getproperty, :vect => Base.vect, Symbol("'") => Base.adjoint, :typed_hcat => Base.typed_hcat, :string => string)
                if ex0.head === head
                    return Expr(:call, fcn, f,
                                Expr(:call, typesof, map(esc, ex0.args)...))
                end
            end
        end
    end
    if isa(ex0, Expr) && ex0.head === :macrocall # Make @edit @time 1+2 edit the macro by using the types of the *expressions*
        return Expr(:call, fcn, esc(ex0.args[1]), Tuple{#=__source__=#LineNumberNode, #=__module__=#Module, Any[ Core.Typeof(a) for a in ex0.args[3:end] ]...})
    end

    ex = Meta.lower(__module__, ex0)
    if !isa(ex, Expr)
        return Expr(:call, :error, "expression is not a function call or symbol")
    end

    exret = Expr(:none)
    if ex.head === :call
        if any(e->(isa(e, Expr) && e.head === :(...)), ex0.args) &&
            (ex.args[1] === GlobalRef(Core,:_apply) ||
             ex.args[1] === GlobalRef(Base,:_apply))
            # check for splatting
            exret = Expr(:call, ex.args[1], fcn,
                        Expr(:tuple, esc(ex.args[2]),
                            Expr(:call, typesof, map(esc, ex.args[3:end])...)))
        else
            exret = Expr(:call, fcn, esc(ex.args[1]),
                         Expr(:call, typesof, map(esc, ex.args[2:end])...))
        end
    end
    if ex.head === :thunk || exret.head === :none
        exret = Expr(:call, :error, "expression is not a function call, "
                                  * "or is too complex for @$fcn to analyze; "
                                  * "break it down to simpler parts if possible")
    end
    return exret
end

"""
Same behaviour as gen_call_with_extracted_types except that keyword arguments
of the form "foo=bar" are passed on to the called function as well.
The keyword arguments must be given before the mandatory argument.
"""
function gen_call_with_extracted_types_and_kwargs(__module__, fcn, ex0)
    kwargs = Vector{Any}[]
    arg = ex0[end] # Mandatory argument
    for i in 1:length(ex0)-1
        x = ex0[i]
        if x isa Expr && x.head === :(=) # Keyword given of the form "foo=bar"
            push!(kwargs, x.args)
        else
            return Expr(:call, :error, "@$fcn expects only one non-keyword argument")
        end
    end
    thecall = gen_call_with_extracted_types(__module__, fcn, arg)
    for kwarg in kwargs
        if length(kwarg) != 2
            x = string(Expr(:(=), kwarg...))
            return Expr(:call, :error, "Invalid keyword argument: $x")
        end
        push!(thecall.args, Expr(:kw, kwarg[1], kwarg[2]))
    end
    return thecall
end

for fname in [:where]
    @eval begin
        macro ($fname)(ex0)
            gen_call_with_extracted_types(__module__, $(Expr(:quote, fname)), ex0)
        end
    end
end

function where(@nospecialize(f), @nospecialize(t))
    if isa(f, Core.Builtin)
        throw(ArgumentError("argument is not a generic function"))
    end
    t = Base.to_tuple_type(t)
    tt = Base.signature_type(f, t)
    m = ccall(:jl_gf_invoke_lookup, Any, (Any, UInt), tt, typemax(UInt))
    if m === nothing
        error("no unique matching method found for the specified argument types")
    end
    # global MM = m
    # return m.func::Method
    F = string(m.func.file)
    L = m.func.line
    run(`gedit $F +$L`)
    return nothing
end

"""
    where(module, symbol)

Return the module in whwere the binding for the variable referenced by `symbol` in `module` was created.
"""
function where(m::Module, s::Symbol)
    if !isdefined(m, s)
        error("\"$s\" is not defined in module $m")
    end
    return binding_module(m, s)
end

macro where(ex0::Symbol)
    ex0 = QuoteNode(ex0)
    return :(where($__module__, $ex0))
end

for fname in [:code_warntype, :code_llvm, :code_native]
    @eval begin
        macro ($fname)(ex0...)
            gen_call_with_extracted_types_and_kwargs(__module__, $(Expr(:quote, fname)), ex0)
        end
    end
end

"""
    @where

Applied to a function or macro call, it evaluates the arguments to the specified call, and
opens the location of the function's call in a local text editor, with the cursor being at
the line of call.
"""
:@where