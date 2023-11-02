@kwdef struct Goo{T} <: AbstractParameter{T}
    bar::T
    baz::T
end

struct PopGooWrapper{NP, G<:Goo, P<:AbstractPopulationActionsParameters{NP,G}}
    goos::P
end

function wrap_goo(; kwargs...)
    PopGooWrapper(pops(Goo; kwargs...))
end

struct VaguePopGooWrapper{NP, G<:Goo, P<:Simulation73.AbstractPopulationP{NP,G}}
    goos::P
end

 