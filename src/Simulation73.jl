module Simulation73

using DrWatson
using Markdown # for doc_str
using DifferentialEquations, DiffEqBase#, DiffEqParamEstim
#using BlackBoxOptim, Optim
using StaticArrays
using JLD2
import DifferentialEquations: DESolution, OrdinaryDiffEqAlgorithm, solve, Euler, ODEProblem
using OrdinaryDiffEq
#using RecipesBase
using Parameters
using RecipesBase
using Lazy

# ENV["GKSwstype"] = "100" # For headless plotting (on server)
# ENV["MPLBACKEND"]="Agg"
# using Plots

# "variables.jl"
export AbstractVariable, UnboundedVariable, BoundedVariable,
	default_value, bounds, pops, MaybeVariable,
	AbstractParameter, AbstractAction, AbstractSpaceAction

# space.jl
export AbstractSpace, AbstractLattice, AbstractPeriodicLattice, AbstractCompactLattice,
	AbstractEmbeddedLattice

export CompactLattice, PeriodicLattice

export RandomlyEmbeddedLattice, unembed_values

export coordinates, origin_idx, differences, coordinate_axes, timepoints, space,
    extent, abs_difference, abs_difference_periodic, discrete_segment

# "subsampling.jl" (note: should probably be meshed with meshes)
export scalar_to_idx_window, subsampling_Δidx, subsampling_idxs,
	subsampling_time_idxs, subsampling_space_idxs, AbstractSubsampler,
    IndexSubsampler, ValueSubsampler, ValueWindower, RadialSlice

# "analysing.jl"
export AbstractPlotSpecification, AbstractSpaceTimePlotSpecification, Analyses,
	output_name, plot_and_save, analyse, subsample, subsampling_idxs

# "targets.jl"
export AbstractTarget, target_loss

export execute

# "simulating.jl"
export AbstractModel, AbstractModelwithDelay, Solver, Simulation, Execution,
	initial_value, history, time_span, saved_dt, saved_dx,
	generate_problem, solve, run_simulation,
	make_mutators, make_system_mutator,
	population, population_coordinates, population_repeat, population_timepoint

# # "exploring.jl"
# export Search, SearchExecution, make_problem_generator, search, run_search

include("helpers.jl")
include("deconstructing.jl")
include("variables.jl")
include("space.jl")
include("subsampling.jl") # depends on space.jl
include("solutions.jl")
#include("solvers.jl")
include("simulating.jl")
include("targets.jl")
# include("exploring.jl")
include("analysing.jl")
end
