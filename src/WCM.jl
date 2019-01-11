module WCM

using Parameters
using CalculatedParameters
import CalculatedParameters: Calculated, update!
using Simulating
using Modeling
using WCMConnectivity
using WCMNonlinearity
using WCMStimulus
using Meshes
#using Exploration
using DifferentialEquations
using Targets
using Records
import Records: required_modules
using StaticArrays

# Rename to remove N redundancy
struct WCMSpatial1D{T,N,P,C<:Connectivity{T},
                            L<:Nonlinearity{T},S<:Stimulus{T},SP<:PopSpace{T,N,P}} <: Model{T,N,P}
    α::SVector{P,T}
    β::SVector{P,T}
    τ::SVector{P,T}
    space::SP
    connectivity::SMatrix{P,P,C}
    nonlinearity::SVector{P,L}
    stimulus::SVector{P,S}
    pop_names::SVector{P,String}
end

function WCMSpatial1D{T,N,P}(; pop_names::Array{Str,1}, α::Array{T,1}, β::Array{T,1}, τ::Array{T,1},
        space::SP, connectivity::Array{C,2}, nonlinearity::Array{L,1}, stimulus::Array{S,1}) where {T,P,N,Str<:AbstractString,C<:Connectivity{T},L<:Nonlinearity{T},S<:Stimulus{T},SP<:Space{T,N}}
    WCMSpatial1D{T,N,P,C,L,S,SP}(SVector{P,T}(α),SVector{P,T}(β),SVector{P,T}(τ),space,SMatrix{P,P,C}(connectivity),SVector{P,L}(nonlinearity),SVector{P,S}(stimulus),SVector{P,Str}(pop_names))
end

space_array(model::WCMSpatial1D) = Calculated(model.space).value

# import Exploration: base_type
# function base_type(::Type{WCMSpatial1D{T1,T2,T3,T4,T5,T6,T7}}) where {T1,T2,T3,T4,T5,T6,T7}
#     BT1 = base_type(T1); BT2 = base_type(T2); BT3 = base_type(T3)
#     BT4 = base_type(T4); BT5 = base_type(T5); BT6 = base_type(T6)
#     BT7 = base_type(T7)#; BT8 = base_type(T8)
#     return WCMSpatial1D{BT1,BT2,BT3,BT4,BT5,BT6,BT7}
# end


# * Calculated WC73 Simulation Type
struct CalculatedWCMSpatial1D{T,N,P,C,L,S,CC<:CalculatedParam{C},CL <: CalculatedParam{L},CS <: CalculatedParam{S}} <: CalculatedParam{WCMSpatial1D{T,N,P,C,L,S}}
    α::SVector{P,T}
    β::SVector{P,T}
    τ::SVector{P,T}
    connectivity::SMatrix{P,P,CC}
    nonlinearity::SVector{P,CL}
    stimulus::SVector{P,CS}
end

function CalculatedWCMSpatial1D(wc::WCMSpatial1D{T,N,P,C,L,S}) where {T<:Real,N,P,
                                                  C<:Connectivity{T},
                                                  L<:Nonlinearity{T},
                                                  S<:Stimulus{T}}
    connectivity = Calculated.(wc.connectivity, Ref(wc.space))
    nonlinearity = Calculated.(wc.nonlinearity)
    stimulus = Calculated.(wc.stimulus,Ref(wc.space))
    CC = eltype(connectivity)
    CL = eltype(nonlinearity)
    CS = eltype(stimulus)
    CalculatedWCMSpatial1D{T,N,P,C,L,S,CC,CL,CS}(
        wc.α, wc.β, wc.τ,
        connectivity, nonlinearity, stimulus)
end

function Calculated(wc::WCMSpatial1D)
    CalculatedWCMSpatial1D(wc)
end


# function update_from_p!(cwc::CalculatedWCMSpatial1D, new_p, p_search::ParameterSearch{<:WCMSpatial1D})
#     # Use the variable model stored by p_search to create static model
#     new_model = model_from_p(p_search, new_p)

#     # Update the calculated values from the new static model
#     cwc.α = new_model.α
#     cwc.β = new_model.β
#     cwc.τ = new_model.τ
#     update!(cwc.connectivity, new_model.connectivity, space)
#     update!(cwc.nonlinearity, new_model.nonlinearity)
#     update!(cwc.stimulus, new_model.stimulus, space)
# end

function get_values(cwc::CalculatedWCMSpatial1D{T,N}) where {T,N}
    (cwc.α, cwc.β, cwc.τ, get_value.(cwc.connectivity), get_value.(cwc.nonlinearity), get_value.(cwc.stimulus))
end

# import Exploration: make_problem_generator
# # * Problem generation

# function make_problem_generator(p_search::ParameterSearch{<:WCMSpatial1D{T,N,P}}) where {T,N,P}
#     model = initial_model(p_search)
#     tspan = time_span(p_search)

#     u0 = initial_value(model)
#     cwc = Calculated(model)
#     function problem_generator(prob, new_p)
#         update_from_p!(cwc, new_p, p_search)
#         α, β, τ, P, connectivity_mx, nonlinearity_fn, stimulus_fn = get_values(cwc)
#         function WilsonCowan73!(dA::Array{T,2}, A::Array{T,2}, p::Array{T,1}, t::T)::Nothing where {T<:Float64}

#             for i in 1:P
#                 stim_val::Array{T,1} = stimulus_fn[i](t)
#                 nonl_val::Array{T,1} = nonlinearity_fn[i](sum(connectivity_mx[i,j]::Array{T,2} * A[:,j] for j in 1:n_pops) .+ stim_val)
#                 dA[:,i] .= (-α[i] .* A[:,i] .+ β[i] .* (1.0 .- A[:,i]) .*  nonl_val + P[i]) ./ τ[i]
#             end
#         end
#         ODEProblem(WilsonCowan73!, u0, tspan, new_p)
#     end
#     initial_problem = problem_generator(nothing, p_search.initial_p)
#     return initial_problem, problem_generator
# end
# export make_problem_generator

# function make_calculated_function(cwc::CalculatedWCMSpatial1D{T,1,2,2,C,L,S,CC,CL,CS}, space::Segment{T}) where {T,C<:Connectivity{T},L<:Nonlinearity{T},S<:Stimulus{T},CC<:CalculatedParam{C},CL <: CalculatedParam{L},CS <: CalculatedParam{S}}
#     (α, β, τ, connectivity_mx, nonlinearity_objs, stimulus_objs) = get_values(cwc)

#     let stim_val::Array{T,1}=zeros(space), nonl_val::Array{T,1}=zeros(space), α::Array{T,1}=α, β::Array{T,1}=β, τ::Array{T,1}=τ, connectivity_mx::Matrix{Matrix{T}}=connectivity_mx, nonlinearity_objs::Array{CL,1}=nonlinearity_objs, stimulus_objs::Array{CS,1}=stimulus_objs
#         (dA::Array{T,2}, A::Array{T,2}, p::Union{Array{T,1},Nothing}, t::T) -> (
#             for i in 1:2
#                 stimulate!(stim_val, stimulus_objs[i], t) # I'll bet it goes faster if we pull this out of the loop
#                 nonlinearity!(nonl_val, nonlinearity_objs[i], sum(connectivity_mx[i,j] * A[:,j] for j in 1:2) .+ stim_val)
#                 dA[:,i] .= (-α[i] .* A[:,i] .+ β[i] .* (1.0 .- A[:,i]) .*  nonl_val) ./ τ[i]
#             end
#         )
#     end
# end

function make_calculated_function(cwc::CalculatedWCMSpatial1D{T,1,P,C,L,S,CC,CL,CS}) where {T,P,C<:Connectivity{T},L<:Nonlinearity{T},S<:Stimulus{T},CC<:CalculatedParam{C},CL <: CalculatedParam{L},CS <: CalculatedParam{S}}
    (α, β, τ, connectivity_mx, nonlinearity_objs, stimulus_objs) = get_values(cwc)

    let α::SVector{P,T}=α, β::SVector{P,T}=β, τ::SVector{P,T}=τ, connectivity_mx::SMatrix{P,P,Matrix{T}}=connectivity_mx, nonlinearity_objs::SVector{P,CL}=nonlinearity_objs, stimulus_objs::SVector{P,CS}=stimulus_objs
        (dA::Array{T,2}, A::Array{T,2}, p::Union{Array{T,1},Nothing}, t::T) -> (
            @views for i in 1:P
                stimulate!(dA[:,i], stimulus_objs[i], t) # I'll bet it goes faster if we pull this out of the loop
                for j in 1:P
                    dA[:,i] .+= connectivity_mx[i,j] * A[:,j]
                end
                # dA[:,i] .+= sum(connectivity_mx[i,j] * A[:,j] for j in 1:2)
                nonlinearity!(dA[:,i], nonlinearity_objs[i])
                dA[:,i] .*= β[i] .* (1.0 .- A[:,i])
                dA[:,i] .+= -α[i] .* A[:,i]
                dA[:,i] ./= τ[i]
            end
        )
    end
end

function generate_problem(simulation::Simulation{T,M,SV}) where {T,M<:WCMSpatial1D{T},SV<:Solver{T}}
    tspan = time_span(simulation)
    model = simulation.model
    u0 = initial_value(model)

    cwc = Calculated(model)

    WilsonCowan73! = make_calculated_function(cwc)

    ode_fn = convert(ODEFunction{true}, WilsonCowan73!)
    return ODEProblem(ode_fn, u0, tspan, nothing)
end

export WCMSpatial1D, space_array
export base_type
export generate_problem

end
