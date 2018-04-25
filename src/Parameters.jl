using Parameters
using JSON

# * Parameter object
# ** Definition
@with_kw struct WilsonCowan73Params{InteractionType, ParamType}
  # Explict fields in parameter file
  # May also be given as LaTeX command (e.g. alpha for α)
    α::ParamType     # Weight on homeostatic term
    β::ParamType     # Weight on nonlinear term
    τ::ParamType     # Time constant
    a::ParamType     # Sigmoid steepness
    θ::ParamType     # Sigmoid translation
    r::ParamType     # Refractory period multiplier
  # Other fields in parameter file include
  # :time => {[:N], :extent}
  # :space => {:N, :extent}
  # :stimulus => {:weight, :duration, :strength}
  # :connectivity => {:amplitudes, :spreads}
  # Constructed fields
    W::InteractionType    # Tensor interaction multiplier
    stimulus_fn::Function
    mesh::AbstractMesh
end
# ** Constructor and helper
function WilsonCowan73Params(p)
    p = deepcopy(p) # to prevent mutation
    npops = length(p[:r])

    space_dims = pop!(p, :space)
    @assert length(space_dims) == 1      # Currently only supports 1D
    mesh = PopMesh(space_dims, npops)
    if ndims(mesh) == 2
        mesh = flatten(mesh)
    end
    @assert mesh isa FlatMesh

    stimulus_params = expand_params(mesh, pop!(p, :stimulus))
    connectivity_params = expand_params(mesh, pop!(p, :connectivity))
    p = expand_params(mesh, p)

    p[:mesh] = mesh
    p[:stimulus_fn] = make_stimulus_fn(mesh; stimulus_params...)
    p[:W] = sholl_connectivity(mesh, connectivity_params[:amplitudes],
                               connectivity_params[:spreads])

    return WilsonCowan73Params(; p...)
end

function expand_params(mesh::AbstractMesh, dct::T) where T <: Dict
    for (k,v) in dct
        if v isa PopulationParam
            dct[k] = expand_param(mesh, v)
        end
    end
    return dct
end

# ** Export
export WilsonCowan73Params
# * Load Parameters
#=
Because I originally wrote this in Python, the parameter files are JSON. (In the
process of moving to fully Julia parameters).
=#
# ** Conversion from Python to Julia
function convert_py(val::Number)
    float(val)
end

function convert_py(a::T) where T <: Array
    if a[1] isa Array && a[1][1] isa Number # eltype gives Any, for some reason
        return InteractionParam(vcat([convert_py(arr) for arr in a]...))
    elseif a[1] isa Dict
        return convert_py.(a)
    elseif a[1] isa Number
        return PopulationParam(convert_py.(vcat(a...))) # Python arrays are rows...
    else
        error("Unsupported parse input array of eltype $(typeof(a[1]))")
    end
end

convert_py(val::String) = val

function convert_py(d::T) where T <: Dict
    # TODO: Find package that does this...
    unicode_dct = Dict(:alpha=>:α, :beta=>:β, :tau=>:τ, :theta=>:θ)
    function convert_pykey(k_sym::Symbol)
        if k_sym in keys(unicode_dct)
            return unicode_dct[k_sym]
        else
            return k_sym
        end
    end
    convert_pykey(k::String) = (convert_pykey ∘ Symbol)(k)

    return Dict(convert_pykey(k) => convert_py(v) for (k,v) in d)
end

# ** Merge dictionaries
function deep_merge(dct1, dct2::D) where D <: Dict
    new_dct = deepcopy(dct1)
    for k in keys(dct2)
        if k in keys(dct1)
            new_dct[k] = deep_merge(dct1[k], dct2[k])
        else
            new_dct[k] = dct2[k]
        end
    end
    return new_dct
end
function deep_merge(el1, el2)
    return el2
end
function deep_merge(el1, void::Void)
    return el1
end

# ** Loading function

function load_WilsonCowan73_parameters(json_filename::String, modifications=nothing)
    # Parse JSON with keys as symbols.
    param_dct = (convert_py ∘ JSON.parsefile)(json_filename)
    return deep_merge(param_dct, modifications)
end
# ** Export
export load_WilsonCowan73_parameters
# * Stimulus functions
doc"""
    make_stimulus_fn(mesh; name, stimulus_args...)

A factory taking the domain (`mesh`) and `name` of a stimulus and returning the function
defined to be associated with that name mapped over the given domain.
"""
function make_stimulus_fn(mesh; name=nothing, stimulus_args...)
    stimulus_factories = Dict(
        "smooth_bump" => smooth_bump_factory,
        "sharp_bump" => sharp_bump_factory
    )
    return stimulus_factories[name](mesh; args...)
end

# ** Smooth bump
"Implementation of smooth_bump_frame used in smooth_bump_factory."
function make_smooth_bump_frame(mesh_coords::Array{DistT}, width::DistT, strength::ValueT, steepness::ValueT) where {ValueT <: Real, DistT <: Real}
    @. strength * (simple_sigmoid_fn(mesh_coords, steepness, -width/2) - simple_sigmoid_fn(mesh_coords, steepness, width/2))
end

"""
The smooth bump is a smooth approximation of the sharp impulse defined
elsewhere. It is smooth in both time and space. It is constructed essentially
from three sigmoids: Two coplanar in space, and one orthogonal to those in
time. The two in space describe a bump: up one sigmoid, then down a negative
sigmoid. The one in time describes the decay of that bump.

This stimulus has the advantages of being 1) differentiable, and 2) more
realistic. The differentiabiilty may be useful for the automatic solvers that
Julia has, which can try to automatically differentiate the mutation function
in order to improve the solving.
"""
function smooth_bump_factory(mesh::AbstractMesh;
                             width=nothing, strength=nothing, duration=nothing,
                             steepness=nothing)
    # WARNING: Defaults are ugly; Remove when possible.
    on_frame = make_smooth_bump_frame(coords(mesh), width, strength, steepness)
    return (t) -> @. on_frame * (1 - simple_sigmoid_fn(t, steepness, duration))
end

# ** Sharp bump
# TODO Understand these functions again.....
"Implementation of sharp_bump_frame used in sharp_bump_factory"
function make_sharp_bump_frame(mesh::PopMesh{ValueT}, width::DistT, strength::ValueT) where {ValueT <: Real, DistT <: Real}
    mesh_coords = coords(mesh)
    frame = zeros(mesh_coords)
    mid_point = 0     # half length, half width
    half_width = width / 2      # using truncated division
    xs = mesh_coords[:,1]   # Assumes all pops have same mesh_coords
    start_dx = find(xs .>= mid_point - half_width)[1]
    stop_dx = find(xs .<= mid_point + half_width)[end]
    frame[start_dx:stop_dx,:] = strength
    return frame
end
function make_sharp_bump_frame(mesh::FlatMesh, args...)
    structured_frame = make_sharp_bump_frame(mesh.pop_mesh, args...)
    flat_frame = structured_frame[:] # Works because FlatMesh must have 1D PopMesh
    return flat_frame
end
"""
The "sharp bump" is the usual theoretical impulse: Binary in both time and
space. On, then off.
"""
function sharp_bump_factory(mesh; width=nothing, strength=nothing, duration=nothing)
        # WARNING: Defaults are ugly; Remove when possible.
    on_frame = make_sharp_bump_frame(mesh, width, strength)
    off_frame = zeros(on_frame)
    return (t) -> (t <= duration) ? on_frame : off_frame
end

# * Connectivity functions

doc"""
This matrix contains values such that the $j^{th}$ column of the $i^{th}$ row
contains the distance between locations $i$ and $j$ in the 1D space dimension provided.
"""
function distance_matrix(xs::SpaceDim)
    # aka Hankel, but that method isn't working in SpecialMatrices
    distance_mx = zeros(eltype(xs), length(xs), length(xs))
    for i in range(1, length(xs))
        distance_mx[:, i] = abs.(xs - xs[i])
    end
    return distance_mx'
end
doc"""
We use an exponential connectivity function, inspired both by Sholl's
experimental work, and by certain theoretical considerations.

The interaction between two populations is entirely characterized by this
function and its two parameters: the amplitude (weight) and the spread
(σ). The spatial step size is also a factor, but as a computational concern
rather than a fundamental one.
"""
function sholl_matrix(amplitude::ValueT, spread::ValueT,
                      dist_mx::Interaction1DFlat{ValueT}, step_size::ValueT) where {ValueT <: Real}
    conn_mx = @. amplitude * step_size * exp(
        -abs(dist_mx / spread)
    ) / (2 * spread)
    return conn_mx
end
doc"""
This calculates a matrix of Sholl's exponential decay for each pair of
populations, thus describing all pairwise interactions. The result is a tensor
describing the effect of the source population at one location on the target
population in another location (indexed: `[tgt_loc, tgt_pop, src_loc,
src_pop]`). This works for arbitrarily many populations (untested) but only for
1D space.
"""
function sholl_connectivity(mesh::PopMesh{ValueT}, W::Interaction1DFlat{ValueT},
			    Σ::Interaction1DFlat{ValueT})::InteractionTensor{ValueT} where {ValueT <: Real}
    xs = mesh.space.dims[1]
    N_x = length(xs)
    N_pop = size(W)[1]
    conn_tn = zeros(N_x, N_pop, N_x, N_pop)
    for tgt_pop in range(1,N_pop)
	for src_pop in range(1,N_pop)
	    conn_tn[:, tgt_pop, :, src_pop] .= sholl_matrix(W[tgt_pop, src_pop],
			  Σ[tgt_pop, src_pop], distance_matrix(xs), step(xs))
	end
    end
    return conn_tn
end
doc"""
In the two population case, flattening the tensor and using matrix
multiplication is 3x faster. This function provides exactly that.
"""
function sholl_connectivity(mesh::FlatMesh, args...)
    # Why didn't I provide an unflattened mesh in the first place?
    sholl_connectivity(unflatten(mesh), args...) |> flatten_sholl
end
function flatten_sholl(tensor)::Interaction1DFlat
    N_x, N_p = size(tensor)[1:2]
    @assert N_p < N_x
    @assert size(tensor) == (N_x, N_p, N_x, N_p)
    flat = zeros(eltype(tensor), N_x*N_p, N_x*N_p)
    for i in 1:N_p
        for j in 1:N_p
            flat[(1:N_x)+((i-1)*N_x), (1:N_x)+((j-1)*N_x)] = tensor[:,i,:,j]
        end
    end
    return flat
end
