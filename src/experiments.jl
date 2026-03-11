using Random


function replace_ess_offers(inputs::Inputs, ess_offers::Vector{Float64})::Inputs
    return Inputs(
        demand = inputs.demand,
        renewable_capacity = inputs.renewable_capacity,
        renewable_offer_price = inputs.renewable_offer_price,
        soc_max = inputs.soc_max,
        soc_min = inputs.soc_min,
        soc_init = inputs.soc_init,
        b = inputs.ess_bids[end],  # keep the same willingness to pay for final SOC
        charge_max = inputs.charge_max,
        discharge_max = inputs.discharge_max,
        alpha = inputs.alpha,
        beta = inputs.beta,
        gamma = inputs.gamma,
        epsilon = inputs.epsilon,
        zeta = inputs.zeta,
        delta_T = inputs.delta_T,
        thermal_offer_price = inputs.thermal_offer_price,
        thermal_max = inputs.thermal_max,
        thermal_min = inputs.thermal_min,
        eta = inputs.eta,
        ess_bids = inputs.ess_bids,
        ess_offers = ess_offers,
    )
end


function run_noisy_offer_experiment(
    inputs::Inputs;
    n_samples::Int = 100,
    sigma::Float64 = 5.0,
    seed::Int = 1,
    clamp_min::Float64 = 0.0,
    output_csv::AbstractString = "outputs/noisy_offer_results.csv",
)

    if inputs.b != inputs.ess_bids[end]
        @warn("The single bid model has a different willingness to pay for the final SOC compared to the ESS bids.")
        @warn("The single bid in t=T is $(inputs.b) while the ESS bid in t=T is $(inputs.ess_bids[end]).")
    end
    single_model = build_single_bid_model(inputs)
    set_silent(single_model)

    optimize!(single_model)
    single_results = collect_results(inputs, single_model)

    T = length(inputs.demand)
    optimized_prices = [dual(single_model[:load_balance][t]) for t in 1:T]

    rng = MersenneTwister(seed)

    mkpath(dirname(output_csv))
    open(output_csv, "w") do io
        println(io, "sample,time,optimized_price,noise,ess_offer,ess_bid,demand,thermal,renewable,charge,discharge,soc,price,objective_value,ess_surplus,ess_profit,cost_to_serve,actual_cost")
        println(io,
            string(
                0, ",",
                0, ",",
                "NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,",
                round(single_results.objective_value, digits = 4), ",",
                round(single_results.ess_surplus, digits = 4), ",",
                round(single_results.ess_profit, digits = 4), ",",
                round(single_results.cost_to_serve, digits = 4), ",",
                round(single_results.actual_cost, digits = 4),
            )
        )

        for sample in 1:n_samples
            noise = sigma .* randn(rng, T)
            offers = max.(optimized_prices .+ noise, clamp_min)
            # hack for now: set the offer in time T to single bid model's willingness to pay for final SOC
            offers[end] = inputs.b

            sample_inputs = replace_ess_offers(inputs, offers)
            m = build_multi_bid_model(sample_inputs)
            set_silent(m)

            optimize!(m)
            results = collect_results(sample_inputs, m)

            for t in 1:T
                println(io,
                    string(
                        sample, ",",
                        t, ",",
                        round(optimized_prices[t], digits = 4), ",",
                        round(noise[t], digits = 4), ",",
                        round(offers[t], digits = 4), ",",
                        round(sample_inputs.ess_bids[t], digits = 4), ",",
                        round(sample_inputs.demand[t], digits = 4), ",",
                        round(results.data.Thermal[t], digits = 4), ",",
                        round(results.data.Renewable[t], digits = 4), ",",
                        round(results.data.Charge[t], digits = 4), ",",
                        round(results.data.Discharge[t], digits = 4), ",",
                        round(results.data.SOC[t], digits = 4), ",",
                        round(results.data.Price[t], digits = 4), ",",
                        round(results.objective_value, digits = 4), ",",
                        round(results.ess_surplus, digits = 4), ",",
                        round(results.ess_profit, digits = 4), ",",
                        round(results.cost_to_serve, digits = 4), ",",
                        round(results.actual_cost, digits = 4),
                    )
                )
            end
        end
    end

    return output_csv
end
