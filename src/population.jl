# FIXME not real dispatch, since it's just an alias
@inline population(A::AbstractArray{T,N}, i) where {T,N} = view_slice_last(A, i)
function population_coordinates(coordinates::AbstractArray{<:CartesianIndex,N}, P) where N
    cat([[CartesianIndex(coord,i) for coord in coordinates] for i in 1:P]...; dims=N+1)
end
population_repeat(arr::AbstractArray{T,N}, P) where {T,N} = repeat(arr, outer=([1 for _ in 1:N]..., P))
"""
    population_timepoint(solution, pop_dx, time_dx)

Return spatial frame for a given population `pop_dx` and time `time_dx`.
"""
@generated function population_timepoint(solution::Union{OrdinaryDiffEq.ODECompositeSolution{T,NPT_FULL,<:Array{<:Array{T,NP_SAVED}}},DifferentialEquations.ODESolution{T,NPT_FULL,<:Array{<:Array{T,NP_SAVED}}}}, pop_dx::Int, time_dx::Int) where {T,NPT_FULL,NP_SAVED}
    N = NP_SAVED - 1 # N + pops
    colons = [:(:) for i in 1:N]
    :(solution(solution.t[time_dx])[$(colons...), pop_dx])
end

# Going forward, make macro to construct actions and interactions between
# desired numbers of populations

# Essentially: Slow, bad type inference at construction level, but good, strong type
# inference at the solver-level.
# e.g.: use length of vector input to choose which type to construct, but then when the type
# is given to the solver, it's set and so all the inference is set for the hard part.

type_name(T::DataType) = T.name.wrapper
type_name(T::UnionAll) = type_name(T.body)
function (ap::Type{<:AbstractParameter})(pop::POP) where {POP <: AbstractPopulationP}
	type_name(POP)((ap(param) for param in getfield.(Ref(pop), fieldnames(POP)))...)
end

abstract type AbstractPOneD{NP,AP} <: AbstractPopulationP{NP,AP} end
abstract type AbstractPTwoD{NP,AP} <: AbstractPopulationP{NP,AP} end
abstract type AbstractPopulationActionsParameters{NP,AP} <: AbstractPOneD{NP,AP} end
abstract type AbstractPopulationInteractionsParameters{NP,AP} <: AbstractPTwoD{NP,AP} end
abstract type AbstractPopulationActions{NP,AP} <: AbstractPOneD{NP,AP} end
abstract type AbstractPopulationInteractions{NP,AP} <: AbstractPTwoD{NP,AP} end

const PopActParam{P,T} = Union{Array{<:AbstractPopulationActionsParameters,1},AbstractPopulationActionsParameters{P,<:T}}
const PopInteractParam{P,T} = Union{Array{<:AbstractPopulationInteractionsParameters,1},AbstractPopulationInteractionsParameters{P,T}}
const PopAct{P,T} = Union{Array{<:AbstractPopulationActions,1},AbstractPopulationActions{P,T}}
const PopInteract{P,T} = Union{Array{<:AbstractPopulationInteractions,1},AbstractPopulationInteractions{P,T}}

function array(p1d::AbstractPOneD{2})
    [p1d.P1, p1d.P2]
end

function array(p2d::AbstractPTwoD{2})
    [p2d.P11 p2d.P12;
     p2d.P21 p2d.P22]
end 

struct PopulationActionsParameters2{P,P1<:P,P2<:P} <: AbstractPopulationActionsParameters{2,P} 
    p1::P1
    p2::P2
    PopulationActionsParameters2(p1::P1,p2::P2) where {P1,P2} = new{typejoin(P1,P2),P1,P2}(p1,p2)
    PopulationActionsParameters2{P,P1,P2}(p1::P1,p2::P2) where {P,P1<:P,P2<:P} = new(p1,p2) 
end
(pp::PopulationActionsParameters2)(args...) = PopulationActions2(pp.p1(args...), pp.p2(args...))

struct PopulationActions2{P,P1<:P,P2<:P} <: AbstractPopulationActions{2,P}
    p1::P1
    p2::P2
    PopulationActions2(p1::P1,p2::P2) where {P1,P2} = new{typejoin(P1,P2),P1,P2}(p1,p2)
end
function (pop_actions::PopulationActions2)(inplace::AbstractArray{T,N}, source::AbstractArray{T,N}, args...) where {T,N}
    pop_actions.p1(population(inplace, 1), population(source, 1), args...)
    pop_actions.p2(population(inplace, 2), population(source, 2), args...)
end


struct PopulationInteractionsParameters2{P,P11<:P,P12<:P,P21<:P,P22<:P} <: AbstractPopulationInteractionsParameters{2,P}
    p11::P11
    p12::P12
    p21::P21
    p22::P22
    PopulationInteractionsParameters2(p11::P11,p12::P12,p21::P21,p22::P22) where {P11,P12,P21,P22} = new{typejoin(P11,P12,P21,P22),P11,P12,P21,P22}(p11,p12,p21,p22)
end
struct PopulationInteractions2{P,P11<:P,P12<:P,P21<:P,P22<:P} <: AbstractPopulationInteractions{2,P}
    p11::P11
    p12::P12
    p21::P21
    p22::P22
    PopulationInteractions2(p11::P11,p12::P12,p21::P21,p22::P22) where {P11,P12,P21,P22} = new{typejoin(P11,P12,P21,P22),P11,P12,P21,P22}(p11,p12,p21,p22)
end
(pp::PopulationInteractionsParameters2)(args...) = PopulationInteractions2(pp.p11(args...), pp.p12(args...),
                                                                           pp.p21(args...), pp.p22(args...))
function (pop_interactions::PopulationInteractions2)(inplace::ARR1, source::ARR2, args...) where {T,N,ARR1<:AbstractArray{T,N},ARR2<:AbstractArray{T,N}}
    pop_interactions.p11(population(inplace, 1), population(source, 1), args...)
    pop_interactions.p12(population(inplace, 1), population(source, 2), args...)
    pop_interactions.p21(population(inplace, 2), population(source, 1), args...)
    pop_interactions.p22(population(inplace, 2), population(source, 2), args...)
end
export PopulationInteractions2

function (arr::Array{<:AbstractPopulationP})(args...)
	[p(args...) for p in arr]
end

PopulationActionsParameters(p1::AbstractParameter, p2) = PopulationActionsParameters2(p1, p2)
PopulationActionsParameters(p1::AbstractAction, p2) = PopulationActions2(p1, p2)
PopulationInteractionsParameters(p11,p12,p21,p22) = PopulationInteractionsParameters2(p11,p12,p21,p22)

function pops(t::Type{T}; kwargs...) where T
    syms = keys(kwargs)
    args = zip(values(kwargs)...)
    new_kwargs = (zip(syms, arg) for arg in args)
    params = map((single_kwargs) -> t(;single_kwargs...), new_kwargs)
	if ndims(params) == 1
		return PopulationActionsParameters(params...)
	elseif ndims(params) == 2
		return PopulationInteractionsParameters(params...)
	else
		error("Weirdly shaped parameters.")
	end
end