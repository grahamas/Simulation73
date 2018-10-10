using Modeling, Exploration, WC73, Meshes, Records, CalculatedParameters, WCMConnectivity, WCMNonlinearity, WCMStimulus, WCMTarget
using WC73: WCMSpatial1D

if !(@isdefined UV)
  const UV = UnboundedVariable
  const BV = BoundedVariable
  const varying{T} = Union{T,BV{T}}
  const v = varying{Float64}
end
T= 2.0
p_search = ParameterSearch(
        variable_model = WCMSpatial1D(;#{varying{Float64}}(;
            pop_names = ["E", "I"],
            α = v[BV(1.1, (0.8, 1.3)), BV(1.0, (0.8, 1.3))],
            β = v[1.1, 1.1],
            τ = v[BV(0.1, (0.05,0.25)), 0.18],
            P = v[0.0, BV(0.1, (0.0,1.0))],
            space = Segment{v}(; n_points=1001, extent=250.5),
            nonlinearity = pops(SigmoidNonlinearity{v}; a=[BV(1.2, (0.5,2.0)), BV(1.0, (0.5,2.0))],
                                                        θ=[BV(2.6, (2.0,8.5)), BV(8.0, (2.0,8.5))]),
            stimulus = pops(SharpBumpStimulus{v}; strength=[BV(1.0, (0.1, 4.0)),0.0],
                                                  duration=[0.75,0.75],
                                                  width=[3.0,3.0]),
            connectivity = pops(ShollConnectivity{v};
                amplitude = v[BV(16.0, (10.0,30.0)) BV(-18.2, (-30.0,-10.0));
                              BV(27.0, (10.0,30.0)) BV(-4.0, (-7.0,-0.5))],
                spread = v[BV(2.5, (2.0,4.0)) BV(2.7, (2.0,4.0));
                           BV(2.7, (2.0,4.0)) BV(2.5, (2.0,4.0))])
            ),
        solver = Solver(;
            T = T,
            params = Dict(
                #:dt => 0.001,
                :dense => true
                #:alg_hints => [:stiff]
                )
            ),
        analyses = Analyses{WCMSpatial1D}(;
           subsampler = SubSampler{WCMSpatial1D}(;
               spatial_stride = 4,
               dt = 0.05
               ),
           plots = [
              (x...) -> Animation(x...;
                disable = 0,
                fps = 20
                ),
              NonlinearityPlot,
              SpaceTimePlot
              ]
            ),
        output = SingleOutput(;
            root = "/home/grahams/Dropbox/Research/simulation-73/results/",
            simulation_name = ""
            ),
        target = DecayingTraveling(;
            space_start=0.0,
            timepoints=1.5:0.01:T,
            target_pop=1
            )
        )

using JLD2

@save "parameters.jld2" p_search
