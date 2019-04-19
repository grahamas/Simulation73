
"`AbstractSpace{T,D}` with distance-type `T` and dimension `D`"
abstract type AbstractSpace{T,D} <: AbstractParameter{T} end

"""
    coordinates(space::AbstractSpace)

Return an object in the shape of the space where each element is the coordinate of that element.
"""
coordinates(space::AbstractSpace) = error("undefined.")

@doc """
    euclidean_metric(edge)

Return the distance between two points in euclidean space, given an edge between those points.

# Example
```jldoctest
julia> Simulation73.euclidean_metric( (5,1) )
4

julia> Simulation73.euclidean_metric( ((2,2), (5,-5)) )
(3, 7)
```
"""
euclidean_metric(edge::Tuple{T,T}) where T<:Number = abs(edge[1] - edge[2])
euclidean_metric(edge::Tuple{Tup,Tup}) where {T,N,Tup<:NTuple{N,T}} = abs.(edge[1] .- edge[2])

"""
    euclidean_metric_periodic(edge, period)

Return the distance between two points in euclidean space as in euclidean_metric, but let the space wrap with period.

# Example
```jldoctest
julia> Simulation73.euclidean_metric_periodic( (5,1), 3 )
3

julia> Simulation73.euclidean_metric_periodic( ((2,2), (5,-5)), (3,4) )
(0, 3)
```
"""
function euclidean_metric_periodic(edge::Tuple{T,T}, period::T) where T<:Number
    diff = euclidean_metric(edge)
    if diff > period / 2
        return period - diff
    else
        return diff
    end
end
function euclidean_metric_periodic(edge::Tuple{Tup,Tup}, periods::Tup) where {N,T,Tup<:NTuple{N,T}}
    diffs = euclidean_metric(edge)
    diffs = map(zip(diffs, periods)) do (diff, period)
        if diff > period / 2
            return period - diff
        else
            return diff
        end
    end
    return Tup(diffs)
end

"""
    discrete_segment(extent, n_points)

Return an object containing `n_points` equidistant coordinates of a segment of length `extent` centered at 0. If you want 0 to be an element of the segment, make sure `n_points` is odd.

# Example
```jldoctest
julia> seg = Simulation73.discrete_segment(5.0, 7);

julia> length(seg) == 5
true

julia> seg[end] - seg[1] ≈ 5.0
true
```
"""
function discrete_segment(extent::T, n_points::Int) where {T <: Number}
    n_points % 2 == 1 || @warn "n_points = $n_points is not odd, so the segment will not have the origin."
    LinRange{T}(-(extent/2),(extent/2), n_points)
end
"""
    discrete_grid(extent, n_points)

Return an object containing `n_points` equidistant coordinates along each dimension of a grid of length `extent` along each dimension, centered at (0,0,...,0).
"""
discrete_grid(extent::NTuple{N,T}, n_points::NTuple{N,Int}) where {N,T} = Iterators.product(
    discrete_segment.(extent, n_points)...)

"A simple Segment of length `extent` and `n_points`-many points"
struct Segment{T} <: AbstractSpace{T,1}
    extent::T
    n_points::Int
end
distance_metric(segment::Segment, edge) = euclidean_metric(edge)
@doc "A Circle with circumference `extent` represented by `n_points`-many points"
struct Circle{T} <: AbstractSpace{T,1}
    extent::T
    n_points::Int
end
distance_metric(circle::Circle, edge) = euclidean_metric_periodic(edge, circle.extent)
@memoize Dict function coordinates(lineish::AbstractSpace{T,1}) where T
    discrete_segment(lineish.extent, lineish.n_points)
end
"""
    Pops{P}(space)

Wrap a generic AbstractSpace so that it repeats P-many times
"""
struct Pops{P,T,D,S} <: AbstractSpace{T,D}
    space::S
end
@memoize Dict function coordinates(space::Pops)
    coordinates(space)#repeat(calculate(space), outer=(ones(Int,D)...,P))
end
Pops{n_pops}(space::S) where {T,D,n_pops,S <: AbstractSpace{T,D}} = Pops{n_pops,T,D,S}(space)
distance_metric(pops::Pops, edge) = distance_metric(pops.space, edge)

"""
    one_pop(calc_pops)

Return the coordinates for a single population of a multi-Pops space.
"""
function one_pop(pops::Pops{P,T,D,S}) where {P,T,D,S}
    coordinates(pops)
end

@doc """
A square Grid of points with `extent` describing the length along each dimension and `n_points` describing the number of points representing each dimension.
"""
struct Grid{T} <: AbstractSpace{T,2}
    extent::Tuple{T,T}
    n_points::Tuple{Int,Int}
end
distance_metric(grid::Grid, edge) = euclidean_metric(edge)

"""A Torus shaped grid of points."""
struct Torus{T} <: AbstractSpace{T,2}
    extent::Tuple{T,T}
    n_points::Tuple{Int,Int}
end
distance_metric(torus::Torus, edge) = euclidean_metric_periodic(edge, torus.extent)

@memoize Dict function coordinates(space::AbstractSpace{T,2}) where T
    discrete_grid(extent, n_points)
end

"""
    get_distances(calc_space)

Return the distances between every pair of points in `calc_space`
"""
@memoize Dict function get_distances(space::AbstractSpace{T}) where T
    edges = Iterators.product(coordinates(space), coordinates(space))
    distances = distance_metric.(Ref(space), edges)
end

"""
    get_space_origin_idx(space)

Return the coordinate of the zero point in `space`. Without respect to populations.

# Example
```jldoctest
julia> segment = Segment(10.0, 11)
Segment{Float64}(10.0, 11)

julia> origin_idx = Simulation73.get_space_origin_idx(segment)
CartesianIndex(6,)

julia> collect(Simulation73.calculate(segment))[origin_idx] == 0.0
true

julia> Simulation73.get_space_origin_idx(Pops{2}(segment))
CartesianIndex(6,)

julia> grid = Grid((10.0,50.0), (11, 13))
Grid{Float64}((10.0, 50.0), (11, 13))

julia> origin_idx = Simulation73.get_space_origin_idx(Grid((10.0,50.0), (11, 13)))
CartesianIndex(6, 7)

julia> collect(Simulation73.calculate(grid))[origin_idx] == (0.0, 0.0)
true
```
"""
get_space_origin_idx(space::AbstractSpace{T}) where T = CartesianIndex(round.(Int, space.n_points ./ 2, RoundNearestTiesUp))
get_space_origin_idx(pops::Pops) = get_space_origin_idx(pops.space)

# Extend Base methods to AbstractSpace types
import Base: step, zero, length, size, ndims
step(line::AbstractSpace{T,1}) where T = line.extent / (line.n_points - 1)
step(space::AbstractSpace{T}) where T = space.extent ./ (space.n_points .- 1)
length(line::AbstractSpace{T,1}) where T = line.n_points

step(ps::Pops) = step(ps.space)
length(ps::Pops) = length(ps.space)



size(space::AbstractSpace{T,1}) where T = (space.n_points,)
size(space::AbstractSpace{T}) where T = space.n_points
size(ps::Pops{P}) where P = (size(ps.space)...,P)

zero(::Type{NTuple{N,T}}) where {N,T} = NTuple{N,T}(zero(T) for i in 1:N)
zero(space::AbstractSpace{T}) where {T} = zeros(T,size(space)...)
one_pop_zero(pops::Pops) = zero(pops.space)

ndims(space::AbstractSpace) = length(size(space))
