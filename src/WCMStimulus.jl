module WCMStimulus

using Parameters

using Meshes
using CalculatedParameters
import CalculatedParameters: Calculated, update!

abstract type Stimulus{T} <: Parameter{T} end

function update!(calc_stims::Array{CS,1}, new_stims::Array{S,1}, space::Space{T}) where {T,S <: Stimulus{T}, CS<:CalculatedParam{S}}
    for i in 1:length(calc_stims)
        if calc_stims[i].stimulus != new_stims[i].stimulus
            calc_stims[i] = Calculated(new_stims[i], space)
        end
    end
end

#---------- CompoundStimulus ------------#

@with_kw struct AddedStimuli{T} <: Stimulus{T}
    stimuli::Array{Any} # Sadly can't specify all must be subtype of Stimulus
end

stim_param(stim::Stimulus{T}) where T = T

function AddedStimuli(stims...)
    T = stim_param(stims[1])
    AddedStimuli{T}([stims...])
end

function add(arr::Array)
    pop_stims = zip(arr...)
    T = stim_param(collect(pop_stims)[1][1])
    return AddedStimuli{T}[AddedStimuli(stims...) for stims in pop_stims]
end

mutable struct CalculatedAddedStimuli{T} <: CalculatedParam{AddedStimuli{T}}
    stimulus::AddedStimuli{T}
    space::Segment{T}
    calculated_stimuli::Array{Any}
end

function Calculated(as::AddedStimuli{T}, space::Segment{T}) where T
    calculated_stimuli = [Calculated(stim, space) for stim in as.stimuli]
    CalculatedAddedStimuli{T}(as, space, calculated_stimuli)
end

function stimulus(added_stims::CalculatedAddedStimuli{T}, t::T) where T
    sum(map((s) -> stimulus(s,t), added_stims.calculated_stimuli))
end

export AddedStimuli, CalculatedAddedStimuli, add

# ------------- GaussianNoiseStimulus ----------- #

function gaussian_noise(space, mean, sd) # assumes signal power is 0db
    return mean .+ sd .* randn(size(space))
end

struct GaussianNoiseStimulus{T} <: Stimulus{T}
    mean::T
    SNR::T
end

function GaussianNoiseStimulus{T}(; SNR::T=0.0, mean::T=0.0) where T
    GaussianNoiseStimulus{T}(mean, SNR)
end

struct CalculatedGaussianNoiseStimulus{T} <: CalculatedParam{GaussianNoiseStimulus{T}}
    stimulus::GaussianNoiseStimulus{T}
    space::Segment{T}
    mean::T
    sd::T
end


function Calculated(wns::GaussianNoiseStimulus{T}, space::Segment{T}) where T
    sd = sqrt(1/10 ^ (wns.SNR / 10))
    CalculatedGaussianNoiseStimulus{T}(wns, space, wns.mean, sd)
end

function stimulus(wns::CalculatedGaussianNoiseStimulus{T}, t::T) where T
    gaussian_noise(wns.space, wns.mean, wns.sd) # Not actually time dependent
end

export GaussianNoiseStimulus, CalculatedGaussianNoiseStimulus

# ----------- SharpBumpStimulus ------------ #

struct SharpBumpStimulus{T} <: Stimulus{T}
    width::T
    strength::T
    window::Tuple{T,T}
end

function SharpBumpStimulus{T}(; strength=nothing, width=nothing,
        duration=nothing, window=nothing) where T
    if window == nothing
        return SharpBumpStimulus{T}(width, strength, (zero(T), duration))
    else
        @assert duration == nothing
        return SharpBumpStimulus{T}(width, strength, window)
    end
end

function SharpBumpStimulus(p)
    SharpBumpStimulus(p[:(Stimulus.width)], p[:(Stimulus.strength)], p[:(Stimulus.window)])
end

function Calculated(sbs::SharpBumpStimulus{T}, space::Segment{T}) where T
    calculated_space = Calculated(space)
    on_frame = make_sharp_bump_frame(calculated_space.value, sbs.width, sbs.strength)
    off_frame = zero(on_frame)
    onset = sbs.window[1]
    offset = sbs.window[2]
    return CalculatedSharpBumpStimulus{T}(sbs, space, onset, offset, on_frame, off_frame)
end

struct CalculatedSharpBumpStimulus{T} <: CalculatedParam{SharpBumpStimulus{T}}
    stimulus::SharpBumpStimulus{T}
    space::Segment{T}
    onset::T
    offset::T
    on_frame::Array{T,1}
    off_frame::Array{T,1}
end

function make_sharp_bump_frame(mesh_coords::AbstractArray{DistT}, width::DistT, strength::T) where {DistT,T}
    mid_dx = floor(Int, size(mesh_coords, 1) / 2)
    mid_point = mesh_coords[mid_dx,1]
    frame = zero(mesh_coords)
    half_width = width / 2      # using truncated division
    xs = mesh_coords[:,1]   # Assumes all pops have same mesh_coords
    start_dx = findfirst(xs .>= mid_point - half_width)
    stop_dx = findlast(xs .<= mid_point + half_width)
    frame[start_dx:stop_dx,:] .= strength
    return frame
end

function stimulus(sharp_bump::CalculatedSharpBumpStimulus, t::T) where T
    if sharp_bump.onset <= t < sharp_bump.offset
        return sharp_bump.on_frame
    else
        return sharp_bump.off_frame
    end
end
CalculatedParameters.get_value(c::CalculatedGaussianNoiseStimulus{T}) where T = c
CalculatedParameters.get_value(c::CalculatedAddedStimuli{T}) where T = c
CalculatedParameters.get_value(c::CalculatedSharpBumpStimulus{T}) where T = c
export Stimulus, SharpBumpStimulus, Calculated, update!, stimulus

end