Base.@kwdef struct Inputs
    demand::Vector{Float64}
    renewable_capacity::Vector{Float64}
    renewable_offer_price::Float64
    soc_max::Float64
    soc_min::Float64
    soc_init::Float64
    b::Float64  # ESS willingness to pay for s[T]
    charge_max::Float64
    discharge_max::Float64
    alpha::Float64
    beta::Float64
    gamma::Float64
    epsilon::Float64
    zeta::Float64
    delta_T::Float64
    thermal_offer_price::Float64
    thermal_max::Float64
    thermal_min::Float64
end

inputs_base = Inputs(;
    demand =             [100.0, 200, 300, 300, 200, 100],
    renewable_capacity = [200.0, 100, 500, 500, 25,  0],
    renewable_offer_price = 0.0,
    soc_max = 200.0,
    soc_min = 0.0,
    soc_init = 0.0,
    b = 40.0,
    charge_max = 200.0,
    discharge_max = 200.0,
    alpha = 0.9,
    beta = 1.0,
    gamma = 1.0,
    epsilon = 1.0,
    zeta = 1.0,
    delta_T = 1.0,
    thermal_offer_price=50.0,
    thermal_max = 100.0,
    thermal_min = 0.0,
)