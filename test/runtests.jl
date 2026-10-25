using Test
using JuMP

include(joinpath(@__DIR__, "..", "src", "ESSModels.jl"))
using .ESSModels

include("copper_plate.jl")

include("experiments.jl")
