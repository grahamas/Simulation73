module WCMAnalysis

using Modeling
using Analysis
using Records
import DifferentialEquations: DESolution
using Meshes
using Colors
using RecipesBase


(a::WCMAnalyses{WCMSpatial1D})(soln::DESolution, sim::Simulation{WCMSpatial1D})
    sample_timeseries
end
# * Plotting

macro defined_userplot(typename::Symbol)
    @shorthands((Symbol ∘ lowercase ∘ string)(typename))
end

@userplot struct WCMPlot
    soln::DESolution
    analyses::Array{Symbol}
end
@recipe function f(w::WCMPlot)
    plot_fns = Dict(
            :nonlinearity => nonlinearityplot,
            :heatmap => popactivityheatmap
        )
    [plot_fns[plt_sym](w.soln) for plt_sym in w.plot_syms]
end

# # ** Plot gif of solution
# function plot_activity_gif(t, x, timeseries::PopTimeseries1D, output::Output; file_name="solution.gif",
# 		      disable=0, fps=15, pop_peak_timeseries=[])
#     @assert size(timeseries, 2) == 2
#     if disable != 0
# 	   return
#     end
#     gr()
#     max_activity = maximum(timeseries, (1,2,3))[1] # I don't know why this index is here.
#     min_activity = minimum(timeseries, (1,2,3))[1]
#     anim = @animate for i in 1:length(t)
# 	Plots.plot(x, timeseries[:,1,i], lab="E",
# 	     ylim=(min_activity, max_activity), title="t=$(t[i])",
#              xlab="Space", ylab="Proportion pop. active")
#         Plots.plot!(x, timeseries[:,2,i], lab="I")
# 	for peak_timeseries in pop_peak_timeseries
# 	    Plots.scatter!(peak_timeseries[i][1], peak_timeseries[i][2], markercolor=peak_timeseries[i][3])
# 	end
#     end
#     write_fn(output)((path) -> gif(anim, path, fps=floor(Int,fps)), "activity.gif")
# end

const PopActivity1D = Array{Float64, 3}
@userplot struct PopActivityPlot
    v_time::Array{Float64,1}
    v_space::Array{Float64,1}
    timeseries::PopActivity1D
end
@recipe function f(h::PopActivityPlot)
    v_time, v_space, timeseries = h.v_time, h.v_space, h.timeseries
    @assert size(timeseries, 2) == 2      # only defined for 2 pops
    clims := (minimum(timeseries), maximum(timeseries))
    grid := false
    layout := (2,1)
    for i_pop in 1:size(timeseries,2)
        @series begin
            seriestype --> :heatmap
            subplot := i_pop
            x := v_time
            y := v_space
            timeseries[:,i_pop,:]
        end
    end
end

# ** Plot nonlinearity
@userplot struct NonlinearityPlot
    soln::DESolution
end
@recipe function f(n::NonlinearityPlot; resolution=100, fn_bounds=(-1,15))
    pop_names = n.soln.pop_names
    nonlinearity_fn = n.nonlinearity_fn
    n_pops = length(pop_names)

    one_pop_x = linspace(fn_bounds..., resolution)
    delete!.(plotattributes,[:resolution,:fn_bounds])

    x_range = repeat(one_pop_x, outer=(n_pops))
    y_output = reshape(nonlinearity_fn(x_range), (:, n_pops))

    lab --> pop_names
    xlab := "Input current"
    ylab := "Proportion pop. reaching at least threshold"
    x := one_pop_x
    y := y_output
    ()
end

function Sampler{WCMSpatial1D}(; dt::Float64=0, spatial_stride::Int=1)
    @assert dt > 0
    Sampler{WCMSpatial1D}(dt, [spatial_stride])
end



(sampler::Sampler{M})(soln::DESolution, model::M) where {M <: WCMSpatial1D}
    timepoints = minimum(soln.t):sampler.dt:maximum(soln.t)
    # Assuming densely sampled.
    timesampled_u = soln(timepoints)

    space = space(model)
    space_stride = sampler.space_strides[1]
    sampled_space = space[1:space_stride:end]

    sampled_u = timesampled_u[1:space_stride:end,:,:]

    return timepoints, sampled_space, sampled_u
end

"Subsample timeseries that was solved with fixed dt; no interpolation."
function sample_timeseries(soln::DESolution, model::Model,
    spatial_stride::Int, temporal_stride::Int)
    t = soln.t
    x = Calculated(model.space).value
    u = cat(3, soln.u...)
    t_dx = 1:temporal_stride:length(t)
    x_dx = 1:spatial_stride:length(x)
    return t[t_dx], x[x_dx], u[x_dx, :, t_dx]
end

"Sample timeseries through interpolation of given timepoints"
function sample_timeseries(soln::DESolution, model::Model,
    spatial_stride::Int, timepoints::AbstractRange)
    x = Calculated(model.space).value
    u = cat(3, soln(timepoints)...)
    x_dx = 1:spatial_stride:length(x)
    return timepoints, x[x_dx], u[x_dx, :, :]
end

function sample_timeseries(soln::DESolution, model::Model;
        spatial_stride::Int=1, temporal_stride::Int=1,
        n_time_samples::Int=-1, dt::Float64=0)
    @assert sum([(temporal_stride == 1),
        (n_time_samples == 0),
        (dt == 0)]) == 1 # Only one sampling spec allowed
    if temporal_stride != 1
        sample_timeseries(soln, model, spatial_stride, temporal_stride)
    elseif n_time_samples > 0
        timepoints = linspace(0,maximum(soln.t),n=n_time_samples)
        sample_timeseries(soln, model, spatial_stride, timepoints)
    else
        timepoints = 0:dt:maximum(soln.t)
        sample_timeseries(soln, model, spatial_stride, timepoints)
    end
end

end