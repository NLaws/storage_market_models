Base.@kwdef mutable struct Inputs
    demand::Vector{Float64}
    renewable_capacity::Vector{Float64}
    renewable_offer_price::Float64
    soc_max::Float64
    soc_min::Float64
    soc_init::Float64
    b::Float64  # ESS willingness to pay for s[T]
    charge_max::Float64
    discharge_max::Float64
    charge_efficiency::Float64
    discharge_efficiency::Float64
    gamma::Float64
    epsilon::Float64
    zeta::Float64
    delta_T::Float64
    thermal_offer_price::Float64
    thermal_max::Float64
    thermal_min::Float64
    eta::Float64
    ess_bids::Vector{Float64}
    ess_offers::Vector{Float64}
end

legacy_inputs_base = Inputs(;
    demand =             [100.0, 200, 300, 300, 200, 100],
    renewable_capacity = [200.0, 100, 500, 500, 25,  0],
    renewable_offer_price = 0.0,
    soc_max = 800.0,
    soc_min = 0.0,
    soc_init = 0.0,
    b = 40.0,
    charge_max = 200.0,
    discharge_max = 200.0,
    charge_efficiency = 0.9,
    discharge_efficiency = 0.9,
    gamma = 1.0,
    epsilon = 1.0,
    zeta = 1.0,
    delta_T = 4.0,
    thermal_offer_price=50.0,
    thermal_max = 100.0,
    thermal_min = 0.0,
    eta = 0.9,
    # perfect foresight bids and offers
    ess_bids = [43.1, 50.0, 0.0, 0.0, 50.0, 40.0],
    ess_offers = [43.1, 50.0, 0.0, 0.0, 49.9, 49.9],
)


Base.@kwdef mutable struct BIMInputs
    experiment_name::AbstractString
    offer_prices::Dict{String, Vector{Float64}}
    charging_cost::Dict{String, Vector{Float64}}
    discharging_cost::Dict{String, Vector{Float64}}
    ess_bids::Dict{String, Vector{Float64}}
    ess_offers::Dict{String, Vector{Float64}}
    net_soc_bid::Dict{String, Vector{Float64}}  # ESS willingness to pay for s[T]
end

const BASE_NETWORK_PATH = joinpath(@__DIR__, "networks", "base-single-ess.yaml")

inputs_base = BIMInputs(
    experiment_name = "base",
    offer_prices = Dict("thermal" => fill(50.0, 6), "renewable" => zeros(6)),
    charging_cost = Dict("battery" => ones(6)),
    discharging_cost = Dict("battery" => ones(6)),
    ess_bids = Dict("battery" => [43.1, 50.0, 0.0, 0.0, 50.0, 40.0]),
    ess_offers = Dict("battery" => [43.1, 50.0, 0.0, 0.0, 49.9, 49.9]),
    net_soc_bid = Dict("battery" => fill(40.0, 6)),
)
