"A Solver holds the parameters of the differential equation solver."
struct Solver{T,ALG<:Union{OrdinaryDiffEqAlgorithm,Nothing},DT<:Union{T,Nothing}}
    tspan::Tuple{T,T}
    algorithm::ALG
    simulated_dt::DT
    time_save_every::Int
    space_save_every::Int # TODO: Remove 1D Assumption
    stiffness::Symbol
    #dense::Bool
end

function Solver{S}(; start_time::S=0.0, stop_time::S, dt::DT, time_save_every::Int=1, space_save_every=1, algorithm::ALG=nothing, stiffness=:auto) where {S, ALG, DT<:Union{S,Nothing}}
    Solver{S,ALG,DT}((start_time, stop_time), algorithm, dt, time_save_every, space_save_every, stiffness)
end

"""
    saved_dt(solver)

Return the time step saved by a solver.
"""
saved_dt(s::Solver{T}) where T = s.simulated_dt * s.time_save_every

"""
    initial_value(solver)
    initial_value(simulation)

Return the model's initial value (defaults to all zeros)
"""
initial_value(solver::AbstractSolver) = error("undefined.")

"""
    time_span(solver)
    time_span(simulation)

Return the time span over which the solver runs.
"""
time_span(solver::Solver{T}) where T = solver.tspan

"""
    history(solver)
    history(simulation)
Return the "history" of the simulation prior to start time
"""


"""
    save_idxs(solver, space)

Return the indices into space of the values that the solver saves.
"""
function save_idxs(solver::Solver{T}) where {T}#::Unio{P,n}{Nothing,Array{CartesianIndex}}
    if all(solver.space_save_every .== 1)
        return nothing
    end
    all_indices = CartesianIndices(initial_value(solver))
    space_saved_subsample(all_indices, solver)
end

"""
    coordinates(model, solver)
    coordinates(simulation)

Return the spatial coordinates of values saved by `solver`
"""
function saved_coordinates(solver::Solver)
    @warn "not subsampling in _coordinates_"
    coordinates(solver.space)
#    collect(arr)[[StrideToEnd(i) for i in solver.space_save_every]...]
end

"""
    timepoints(solver)
    timepoints(simulation)

Return the times saved by `solver`.
"""
function timepoints(solver::Solver{T}) where T
    start, stop = time_span(solver)
    start:saved_dt(solver):stop
end

"""
    origin_idx(solver)
    origin_idx(simulation)

Return the index of the spatial origin of `model`'s `space`.
"""
function origin_idx(solver::Solver)  # TODO: Remove 1D assumption
    CartesianIndex(round.(Int, Tuple(origin_idx(solver.space)) ./ solver.space_save_every))
end

saved_dx(model::AbstractModel, solver::Solver)= step(model.space) .* solver.space_save_every

"""
    space_index_info(model, solver)
    space_index_info(simulation)

Return IndexInfo for saved space array.
"""
space_index_info(solver::Solver{T}) where T = IndexInfo(saved_dx(solver), origin_idx(solver))

"""
    time_index_info(solver)
    time_index_info(simulation)

Return IndexInfo for saved time array.
"""
time_index_info(solver::Solver{T}) where T = IndexInfo(saved_dt(solver), (1,))

function subsampling_idxs(solver::Solver, space_subsampler, time_subsampler)
    x_info = get_space_index_info(solver)
    t_info = get_time_index_info(solver)

    x_dxs = subsampling_idxs(x_info, space_subsampler)
    t_dxs = subsampling_idxs(t_info, time_subsampler)

    return (x_dxs, 1, t_dxs)
end

# FIXME bad assumptions
# function subsampling_idxs(simulation::Simulation{T,<:AbstractModel{T}}, x_target::AbstractArray, t_target::AbstractArray) where T
#     return (subsampling_space_idxs(simulation.model, simulation.solver, x_target)...,
#             1,
#             subsampling_time_idxs(simulation.solver, t_target))
# end
function subsampling_time_idxs(solver::Solver, t_target::AbstractArray)
    t_solver = time_span(solver)[1]:saved_dt(solver):time_span(solver)[end]
    subsampling_idxs(t_target, t_solver)
end
function subsampling_space_idxs(solver::Solver, x_target::AbstractArray)
    x_model = coordinates(model, solver)
    subsampling_idxs(x_target, x_model)
end
