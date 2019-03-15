
#region Model
abstract type Model{T,N,P} <: AbstractParameter{T} end

#endregion

#region Solver
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
save_dt(s::Solver{T}) where T = s.simulated_dt * s.time_save_every

function save_idxs(solver::Solver{T}, space::SP) where {T,P, SP <: Pops{P,T}}#::Unio{P,n}{Nothing,Array{CartesianIndex}}
    if all(solver.space_save_every .== 1)
        return nothing
    end
    all_indices = CartesianIndices(space)
    space_saved_subsample(all_indices, solver)
end
#endregion

#region Simulation
"""A Simulation object runs its own simulation upon initialization."""
struct Simulation{T,M<:Model{T},S<:Solver{T}}
    model::M
    solver::S
    solution::DESolution
    Simulation{T,M,S}(m,s) where {T,M<:Model{T},S<:Solver{T}} = new(m,s,_solve(m,s))
end

function Simulation(; model::M, solver::S) where {T, M<:Model{T}, S<:Solver{T}}
    Simulation{T,M,S}(model,solver)
end

initial_value(model::Model{T,N,P}) where {T,N,P} = zero(model.space)
initial_value(sim::Simulation) = initial_value(sim.model)
time_span(solver::Solver{T}) where T = solver.tspan
time_span(sim::Simulation) = time_span(sim.solver)
function space_saved_subsample(arr, solver::Solver)
    collect(arr)[[StrideToEnd(i) for i in solver.space_save_every]...,:]
end
saved_space_arr(model::Model, solver::Solver) = space_saved_subsample(coordinates(model.space), solver)
saved_space_arr(sim::Simulation) = saved_space_arr(sim.model, sim.solver)
function saved_time_arr(solver::Solver{T}) where T
    start, stop = time_span(solver)
    start:save_dt(solver):stop
end
saved_time_arr(sim::Simulation) = saved_time_arr(sim.solver)#sim.solution.t

function get_space_origin_idx(model::Model)
    get_space_origin_idx(model.space)
end
function get_space_origin_idx(model::Model, solver::Solver)  # TODO: Remove 1D assumption
    round(Int, get_space_origin_idx(model)[1] / solver.space_save_every)
end
function get_space_origin_idx(sim::Simulation)
    get_space_origin_idx(sim.model, sim.solver)
end

save_dt(sim::Simulation{T}) where T = save_dt(sim.solver)
save_dx(model::Model, solver::Solver)= step(model.space) * solver.space_save_every
save_dx(sim::Simulation{T}) where T = save_dx(sim.model, sim.solver)
Base.minimum(sim::Simulation) = minimum(map(minimum, sim.solution.u))
Base.maximum(sim::Simulation) = maximum(map(maximum, sim.solution.u))

get_space_index_info(model::Model{T}, solver::Solver{T}) where T = IndexInfo(save_dx(model, solver), get_space_origin_idx(model, solver))
get_space_index_info(sim::Simulation{T}) where T = get_space_index_info(sim.model, sim.solver)
get_time_index_info(solver::Solver{T}) where T = IndexInfo(save_dt(solver), 1)
get_time_index_info(sim::Simulation{T}) where T = get_time_index_info(sim.solver)

@generated function pop_frame(solution::ODESolution{T,NPT,<:Array{<:Array{T,NP},1}}, pop_dx::Int, time_dx::Int) where {T,NP,NPT}
    N = NP - 1
    colons = [:(:) for i in 1:N]
    :(solution[$(colons...),pop_dx, time_dx])
end

function write_params(sim::Simulation)
    write_object(sim.output, "parameters.jld2", "sim", sim)
end

function subsampling_idxs(model::Model, solver::Solver, time_subsampler, space_subsampler)
    x_info = get_space_index_info(model, solver)
    t_info = get_time_index_info(solver)

    x_dxs = subsampling_idxs(x_info, space_subsampler)
    t_dxs = subsampling_idxs(t_info, time_subsampler)

    return (x_dxs, 1, t_dxs)
end

function subsampling_idxs(simulation::Simulation{T,<:Model{T,1}}, time_subsampler::Subsampler, space_subsampler::Subsampler) where T
    subsampling_idxs(simulation.model, simulation.solver, time_subsampler, space_subsampler)
end
function subsampling_time_idxs(solver::Solver, t_target::AbstractArray)
    t_solver = time_span(solver)[1]:save_dt(solver):time_span(solver)[end]
    subsampling_idxs(t_target, t_solver)
end
function subsampling_space_idxs(model::Model, solver::Solver, x_target::AbstractArray)
    x_model = saved_space_arr(model, solver)
    subsampling_idxs(x_target, x_model)
end

function subsample(simulation::Simulation{T,<:Model{T,1}}; time_subsampler, space_subsampler) where T
    t = time_arr(simulation)
    x = space_arr(simulation)

    x_dxs, pop_dxs, t_dxs = subsampling_idxs(simulation, time_subsampler, space_subsampler)

    t = t[t_dxs]
    x = x[x_dxs] # TODO: Remove 1D return assumption
    wave = simulation.solution[x_dxs,pop_dxs,t_dxs]

    return (t,x,wave)
end


#endregion

"""
    _solve wraps the DifferentialEquations function, solve.
    Note that the method accepting a Simulation object should take a
    partially initialized Simulation.
"""
generate_problem() = error("undefined")
function _solve(model,solver)
    problem = generate_problem(model, solver)
    _solve(problem, solver, model.space)
end
function _solve(problem::ODEProblem, solver::Solver{T,Euler}, space::Pops{P,T}) where {P,T}
    # TODO: Calculate save_idxs ACCOUNTING FOR pops
    @show "Solving Euler"
    solve(problem, Euler(), dt=solver.simulated_dt,
            #saveat=save_dt(solver),
            timeseries_steps=solver.time_save_every,
            save_idxs=save_idxs(solver, space))
end
function _solve(problem::ODEProblem, solver::Solver{T,Nothing}, space::Pops{P,T}) where {P,T}
    @show "Solving with default ALG"
    solve(problem, saveat=save_dt(solver), timeseries_steps=solver.time_save_every,
        save_idxs=save_idxs(solver, space), alg_hints=[solver.stiffness])
end

""" run_simulation loads a simulation object defined in a jl script, and saves the parameters. """
function run_simulation(jl_filename::AbstractString)
    include(jl_filename)
    filecopy(simulation.output, jl_filename, basename(jl_filename))
    return simulation
end

function generate_problem(model::M, solver::SV) where {T,M<:Model{T},SV<:Solver{T}}
    tspan = time_span(solver)
    u0 = initial_value(model)

    calculated_model = Calculated(model)

    system_fn! = make_calculated_function(calculated_model)

    ode_fn = convert(ODEFunction{true}, system_fn!)
    return ODEProblem(ode_fn, u0, tspan, nothing)
end