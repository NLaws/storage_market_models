using Random


function uniform_samples(xmin, xmax, N)
    xmin <= xmax || throw(ArgumentError("xmin must be <= xmax"))
    return xmin .+ (xmax - xmin) .* rand(N)
end


function replace_inputs(
    inputs::Inputs;
    b::Float64 = inputs.b,
    ess_offers::Vector{Float64} = inputs.ess_offers,
)::Inputs
    return Inputs(
        demand = inputs.demand,
        renewable_capacity = inputs.renewable_capacity,
        renewable_offer_price = inputs.renewable_offer_price,
        soc_max = inputs.soc_max,
        soc_min = inputs.soc_min,
        soc_init = inputs.soc_init,
        b = b,
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


function write_results_row(
    io,
    sample::Int,
    time::Int,
    optimized_price,
    noise,
    ess_offer,
    ess_bid,
    demand::Float64,
    thermal::Float64,
    renewable::Float64,
    charge::Float64,
    discharge::Float64,
    soc::Float64,
    price::Float64,
    objective_value::Float64,
    ess_surplus::Float64,
    ess_profit::Float64,
    cost_to_serve::Float64,
    actual_cost::Float64,
)
    println(
        io,
        string(
            sample, ",",
            time, ",",
            optimized_price, ",",
            noise, ",",
            ess_offer, ",",
            ess_bid, ",",
            round(demand, digits = 4), ",",
            round(thermal, digits = 4), ",",
            round(renewable, digits = 4), ",",
            round(charge, digits = 4), ",",
            round(discharge, digits = 4), ",",
            round(soc, digits = 4), ",",
            round(price, digits = 4), ",",
            round(objective_value, digits = 4), ",",
            round(ess_surplus, digits = 4), ",",
            round(ess_profit, digits = 4), ",",
            round(cost_to_serve, digits = 4), ",",
            round(actual_cost, digits = 4),
        ),
    )
end


"""
    run_noisy_offer_experiment
"""
function run_noisy_offer_experiment(
    inputs::Inputs;
    n_samples::Int = 100,
    sigma::Float64 = 5.0,
    seed::Int = 1,
    clamp_min::Float64 = 0.0,
    max_willingness_to_pay::Float64 = 40.0,
    min_willingness_to_pay::Float64 = 0.0,
    multi_output_csv::AbstractString = "outputs/noisy_offer_multibid_results.csv",
    single_output_csv::AbstractString = "outputs/noisy_offer_singlebid_results.csv",
)

    single_model = build_single_bid_model(inputs)
    set_silent(single_model)

    optimize!(single_model)

    T = length(inputs.demand)
    optimized_prices = [dual(single_model[:load_balance][t]) for t in 1:T]

    rng = MersenneTwister(seed)
    sample_bs = uniform_samples(min_willingness_to_pay, max_willingness_to_pay, n_samples)
    noise_by_sample = [sigma .* randn(rng, T) for _ in 1:n_samples]
    header = "sample,time,optimized_price,noise,ess_offer,ess_bid,demand,thermal,renewable,charge,discharge,soc,price,objective_value,ess_surplus,ess_profit,cost_to_serve,actual_cost"

    mkpath(dirname(multi_output_csv))
    mkpath(dirname(single_output_csv))

    open(multi_output_csv, "w") do io
        println(io, header)

        for sample in 1:n_samples
            noise = noise_by_sample[sample]
            offers = max.(optimized_prices .+ noise, clamp_min)
            sample_inputs = replace_inputs(
                inputs; 
                ess_offers = offers,
            )
            m = build_multi_bid_model(sample_inputs)
            set_silent(m)

            optimize!(m)
            results = collect_results(sample_inputs, m)

            for t in 1:T
                write_results_row(
                    io,
                    sample,
                    t,
                    round(optimized_prices[t], digits = 4),
                    round(noise[t], digits = 4),
                    round(offers[t], digits = 4),
                    round(sample_inputs.ess_bids[t], digits = 4),
                    sample_inputs.demand[t],
                    results.data.Thermal[t],
                    results.data.Renewable[t],
                    results.data.Charge[t],
                    results.data.Discharge[t],
                    results.data.SOC[t],
                    results.data.Price[t],
                    results.objective_value,
                    results.ess_surplus,
                    results.ess_profit,
                    results.cost_to_serve,
                    results.actual_cost,
                )
            end
        end
    end

    open(single_output_csv, "w") do io
        println(io, header)

        for sample in 1:n_samples
            sample_inputs = replace_inputs(inputs; b = sample_bs[sample])
            m = build_single_bid_model(sample_inputs)
            set_silent(m)

            optimize!(m)
            results = collect_results(sample_inputs, m)

            for t in 1:T
                write_results_row(
                    io,
                    sample,
                    t,
                    "NaN",
                    "NaN",
                    # abuse the bid column to store the willingness to pay for single-bid samples
                    sample_inputs.b,
                    round(sample_inputs.b, digits = 4),
                    sample_inputs.demand[t],
                    results.data.Thermal[t],
                    results.data.Renewable[t],
                    results.data.Charge[t],
                    results.data.Discharge[t],
                    results.data.SOC[t],
                    results.data.Price[t],
                    results.objective_value,
                    results.ess_surplus,
                    results.ess_profit,
                    results.cost_to_serve,
                    results.actual_cost,
                )
            end
        end
    end

    return (
        multi_output_csv = multi_output_csv,
        single_output_csv = single_output_csv,
    )
end
