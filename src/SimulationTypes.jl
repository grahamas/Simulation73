using Parameters

# * Aliases
const PopulationParam{T} = RowVector{T, Array{T,1}} where T <: Real
const InteractionParam{T} = Array{T, 2} where T <: Real
const ExpandedParam{T} = Array{T, 2} where T <: Real
const ExpandedParamFlat{T} = Array{T, 1} where T <: Real
const InteractionTensor{T} = Array{T, 4} where T <: Real
const Interaction1DFlat{T} = Array{T, 2} where T <: Real
const SpaceState1D{T} = Array{T, 2} where T <: Real
const SpaceState1DFlat{T} = Array{T, 1} where T <: Real
const SpaceDim{DistT} = StepRangeLen{DistT} where T <: Real

export PopulationParam, InteractionParam, ExpandedParam
export ExpandedParamFlat, InteractionTensor, Interaction1DFlat
export SpaceState1D, SpaceState1DFlat, SpaceDim

# * Space
abstract type Space end
struct Segment{DistT} <: Space
    extent::DistT
    n_points::Int
    mesh::StepRangeLen{DistT}
    Segment(extent, n_points) = new(extent, n_points, linspace(-(extent/2), (extent/2), N))
end
function refresh_if_different(seg::Segment, extent, n_points)
    if ((extent == seg.extent) && (n_points == seg.n_points))
        return seg
    else
        return Segment(extent, n_points)
    end
end

# * Mesh
# Define a mesh type that standardizes interaction with the discretization of
# space (and populations, though those are inherently discrete, as we currently
# conceptualize them).

# ** Type Definition and Constructors
# All meshes are subtyped from AbstractMesh. SpaceMesh contains only discretized
# spatial dimensions. PopMesh contains a SpaceMesh, but also an integer indicating
# the number of colocalized populations (i.e. each spatial point contains members
# of each population). FlatMesh is merely a flattened representation of a PopMesh
# containing only one spatial dimension. Rather than concatenating populations
# along a "population dimension," the populations are concatenated along the
# single spatial dimension. This is useful so that the convolution can be
# implemented as a matrix multiplication, however I don't see how to extend
# it. I would not have implemented it, except that's how the preceding Python
# implementation worked, and I needed to have a direct comparison in order to
# debug.

abstract type AbstractMesh{DistT <: Real} end
struct SpaceMesh{DistT} <: AbstractMesh{DistT}
    dims::Array{SpaceDim{DistT}}
end
struct PopMesh{DistT} <: AbstractMesh{DistT}
    space::SpaceMesh{DistT}
    n_pops::Integer
end
struct FlatMesh{DistT} <: AbstractMesh{DistT}
    pop_mesh::PopMesh{DistT}
    FlatMesh{DistT}(mesh) where {DistT <: Real} = ndims(mesh) != 2 ? error("cannot flatten >1D mesh.") : new(mesh)
end

function FlatMesh(mesh::AbstractMesh{DistT}) where {DistT <: Real}
    FlatMesh{DistT}(mesh)
end

# Flatten and unflatten take a PopMesh to a FlatMesh and vice versa (only if the
# PopMesh has only 1D space).
flatten(mesh::PopMesh) = FlatMesh(mesh)
unflatten(mesh::FlatMesh) = mesh.pop_mesh

# FlatMesh has no outer constructor, as it uses the more descriptive "flatten."
function SpaceMesh(dim_dcts::Array{Dict{Symbol,DistT}}) where {DistT <: Real}
    dims = Array{StepRangeLen}(length(dim_dcts))
    for (i, dim) in enumerate(dim_dcts)
        extent::DistT = dim[:extent]
        N::Integer = floor(Int,dim[:N])
        dims[i] = linspace(-(extent/2), (extent/2), N)
    end
    SpaceMesh{DistT}(dims)
end
function PopMesh(dim_dcts::Array{<:Dict{Symbol,DistT}}, n_pops::Integer) where {DistT <: Real}
    PopMesh{DistT}(SpaceMesh(dim_dcts),n_pops)
end

export SpaceMesh

# ** Methods
# Numerous functions operating on meshes, including size, ndims, true_ndims,
# coords, zeros, and expand_param.

import Base: size, ndims, zeros, reshape
function x_range(mesh::PopMesh)
    x_range(mesh.space)
end
function x_range(mesh::FlatMesh)
    x_range(mesh.pop_mesh)
end
function x_range(mesh::SpaceMesh)
    mesh.dims[1]
end
function size(mesh::SpaceMesh)
    return length.(mesh.dims)
end
function size(mesh::PopMesh)
    return (size(mesh.space)..., mesh.n_pops)
end
function size(mesh::FlatMesh)
    return size(mesh.pop_mesh)[1] * mesh.pop_mesh.n_pops
end
function flatten(array, mesh::FlatMesh)
    return array[:]
end
function unflatten(array, mesh::PopMesh)
    return reshape(array, (:,mesh.n_pops))
end
function ndims(mesh::AbstractMesh)
    return length(size(mesh))
end
function true_ndims(mesh::AbstractMesh)
    return ndims(mesh)
end
# true_ndims returns the "real" structure of the mesh, i.e. unflattened.
function true_ndims(mesh::FlatMesh)
    return ndims(mesh.pop_mesh)
end
function coords(mesh::SpaceMesh)
    @assert ndims(mesh) == 1
    return mesh.dims[1]
end
function coords(mesh::PopMesh)
    @assert ndims(mesh) == 2
    return repeat(coords(mesh.space), outer=(1, mesh.n_pops))
end
function coords(mesh::FlatMesh)
    return repeat(coords(mesh.pop_mesh.space), outer=mesh.pop_mesh.n_pops)
end
function zeros(mesh::AbstractMesh)
    zeros(coords(mesh))
end
function expand_param(mesh::PopMesh{DistT}, param::RowVector{ValueT})::ExpandedParam{ValueT} where {ValueT <: Real, DistT <: Real}
    space_dims = size(mesh.space)
    return repeat(param, inner=(space_dims..., 1))
end
function expand_param(mesh::FlatMesh{DistT}, param::RowVector{ValueT})::ExpandedParamFlat{ValueT} where {ValueT <: Real, DistT <: Real}
    return expand_param(mesh.pop_mesh, param)[:]
end
function expand_param(mesh::FlatMesh{DistT}, param::InteractionParam{ValueT})::Interaction1DFlat{ValueT} where {ValueT <: Real, DistT <: Real}
    expanded = [expand_param(mesh, RowVector(param[i,:])) for i in 1:size(param,1)]
    hcat(expanded...)
end


# ** Interface for applying functions
function apply(fn, mesh::SpaceMesh)
    return hcat([fn.(dim) for dim in mesh.dims]...)
end

function apply_with_time(fn, mesh::SpaceMesh, time)
    return hcat([fn.(dim, time) for dim in mesh.dims]...)
end

function apply_through_time(fn, mesh::SpaceMesh, time_len, dt)
    time_range = 0:dt:time_len
    output = Array{Float64,2}(size(mesh)..., length(time_range))
    for (i_time, time) in enumerate(time_range)
        output[:, i_time] = apply_with_time(fn, mesh, time)
    end
    return output
end

export apply, apply_through_time
