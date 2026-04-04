using Random
using Distributed


function uniform_samples(xmin, xmax, N)
    xmin <= xmax || throw(ArgumentError("xmin must be <= xmax"))
    return xmin .+ (xmax - xmin) .* rand(N)
end


function replace_inputs(
    inputs::Inputs;
    b::Float64 = inputs.b,
    ess_offers::Vector{<:Real} = inputs.ess_offers,
    ess_bids::Vector{<:Real} = inputs.ess_bids,
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
        ess_bids = ess_bids,
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


function configure_experiment_model!(m)
    set_silent(m)
    set_attribute(m, JuMP.MOI.NumberOfThreads(), 1)
    return m
end


function assert_sample_has_solution(m, sample::Int, label::AbstractString)
    result_count = JuMP.result_count(m)
    if result_count == 0
        termination = JuMP.termination_status(m)
        primal = JuMP.primal_status(m)
        dual = JuMP.dual_status(m)
        raw_status = JuMP.raw_status(m)
        error(
            "Sample $(sample) in $(label) has no solution. " *
            "termination_status=$(termination), primal_status=$(primal), " *
            "dual_status=$(dual), raw_status=\"$(raw_status)\"",
        )
    end
    return nothing
end


function log_sample_progress!(
    progress::Base.RefValue{Int},
    n_samples::Int,
    label::AbstractString,
    log_every::Int,
)
    log_every = max(log_every, 1)
    progress[] += 1
    completed = progress[]
    if completed == 1 || completed == n_samples || completed % log_every == 0
        println("[$(label)] completed $(completed)/$(n_samples) samples")
    end
    return nothing
end


function map_samples(
        f,
        samples,
        label::AbstractString;
        show_progress::Bool = true,
        log_every::Int = 250,
    )
    n_samples = length(samples)
    if nworkers() == 0
        progress = Ref(0)
        return map(samples) do sample
            result = f(sample)
            if show_progress
                log_sample_progress!(progress, n_samples, label, log_every)
            end
            return result
        end
    end

    pool = Distributed.CachingPool(workers())
    progress_channel = show_progress ? RemoteChannel(() -> Channel{Union{Int, Nothing}}(n_samples + 1)) : nothing

    logger_task = if show_progress
        @async begin
            progress = Ref(0)
            while true
                update = take!(progress_channel)
                isnothing(update) && break
                log_sample_progress!(progress, n_samples, label, log_every)
            end
        end
    else
        nothing
    end

    try
        return Distributed.pmap(pool, samples) do sample
            result = f(sample)
            if show_progress
                put!(progress_channel, 1)
            end
            return result
        end
    finally
        if show_progress
            put!(progress_channel, nothing)
            wait(logger_task)
        end
    end
end


function build_uniform_error_multibid_sample_rows(
        sample::Int,
        inputs::Inputs,
        bids,
        optimized_prices,
        noise_by_sample,
        clamp_min::Float64,
        T::Int,
    )
    noise = noise_by_sample[sample]
    offers = max.(optimized_prices .+ noise, clamp_min)
    sample_inputs = replace_inputs(
        inputs;
        ess_offers = offers,
        ess_bids = bids,
    )
    m = build_multi_bid_model(sample_inputs)
    configure_experiment_model!(m)

    optimize!(m)
    assert_sample_has_solution(m, sample, "uniform_error_multibid")
    results = collect_results(sample_inputs, m)
    isnothing(results) && return nothing

    io = IOBuffer()
    for t in 1:T
        write_results_row(
            io,
            sample,
            t,
            round(optimized_prices[t], digits = 4),
            round(noise, digits = 4),
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
    return String(take!(io))
end


function build_noisy_offer_multibid_sample_rows(
        sample::Int,
        inputs::Inputs,
        bids,
        optimized_prices,
        noise_by_sample,
        clamp_min::Float64,
        T::Int,
    )
    noise = noise_by_sample[sample]
    offers = max.(optimized_prices .+ noise, clamp_min)
    sample_inputs = replace_inputs(
        inputs;
        ess_offers = offers,
        ess_bids = bids,
    )
    m = build_multi_bid_model(sample_inputs)
    configure_experiment_model!(m)

    optimize!(m)
    assert_sample_has_solution(m, sample, "noisy_offer_multibid")
    results = collect_results(sample_inputs, m)
    isnothing(results) && return nothing

    io = IOBuffer()
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
    return String(take!(io))
end


function build_noisy_offer_singlebid_sample_rows(
        sample::Int,
        inputs::Inputs,
        bids,
        sample_bs,
        T::Int,
    )
    sample_inputs = replace_inputs(inputs; b = sample_bs[sample], ess_bids = bids)
    m = build_single_bid_model(sample_inputs)
    configure_experiment_model!(m)

    optimize!(m)
    assert_sample_has_solution(m, sample, "noisy_offer_singlebid")
    results = collect_results(sample_inputs, m)
    isnothing(results) && return nothing

    io = IOBuffer()
    for t in 1:T
        write_results_row(
            io,
            sample,
            t,
            "NaN",
            "NaN",
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
    return String(take!(io))
end


"""
    run_uniform_error_multibid_experiment(
        inputs::Inputs;
        n_samples::Int = 100,
        error_range::Float64 = 10.0,
        clamp_min::Float64 = 0.0,
        output_csv::AbstractString = "outputs/uniform_error_multibid_results.csv",
        bid_perfect_foresight::Bool = true,
    )

Runs the multibid experiment for a given set of inputs, adding uniformly distributed noise to the
optimized prices and varying the willingness to pay for the single-bid experiment. Writes results to
a CSV file. 

If `bid_perfect_foresight` is true, sets bids to zero in any time period where the
optimal charge is greater than zero.
"""
function run_uniform_error_multibid_experiment(
        inputs::Inputs;
        n_samples::Int = 100,
        error_range::Float64 = 10.0,
        clamp_min::Float64 = 0.0,
        output_csv::AbstractString = "outputs/uniform_error_multibid_results.csv",
        bid_perfect_foresight::Bool = true,
        show_progress::Bool = true,
        log_every::Int = 250,
    )
    single_model = build_single_bid_model(inputs)
    configure_experiment_model!(single_model)

    optimize!(single_model)

    T = length(inputs.demand)
    optimal_results = collect_results(inputs, single_model)
    optimized_prices = optimal_results.data.Price

    bids = inputs.ess_bids
    if bid_perfect_foresight
        bids = ifelse.(optimal_results.data.Charge .> 0, 0, inputs.ess_bids)
        output_csv = replace(output_csv, ".csv" => "_bid_perfect_foresight.csv")
    end

    noise_by_sample = uniform_samples(-error_range, error_range, n_samples)
    header = "sample,time,optimized_price,noise,ess_offer,ess_bid,demand,thermal,renewable,charge,discharge,soc,price,objective_value,ess_surplus,ess_profit,cost_to_serve,actual_cost"

    mkpath(dirname(output_csv))
    sample_rows = map_samples(
        sample -> build_uniform_error_multibid_sample_rows(
            sample,
            inputs,
            bids,
            optimized_prices,
            noise_by_sample,
            clamp_min,
            T,
        ),
        1:n_samples,
        "uniform_error_multibid";
        show_progress = show_progress,
        log_every = log_every,
    )

    open(output_csv, "w") do io
        println(io, header)
        for sample in 1:n_samples
            rows = sample_rows[sample]
            isnothing(rows) && continue
            print(io, rows)
        end
    end

    return (
        output_csv = output_csv,
    )
end


"""
    run_noisy_offer_experiment(
        inputs::Inputs;
        n_samples::Int = 100,
        sigma::Float64 = 5.0,
        seed::Int = 1,
        clamp_min::Float64 = 0.0,
        max_willingness_to_pay::Float64 = 40.0,
        min_willingness_to_pay::Float64 = 0.0,
        multi_output_csv::AbstractString = "outputs/noisy_offer_multibid_results.csv",
        single_output_csv::AbstractString = "outputs/noisy_offer_singlebid_results.csv",
        bid_perfect_foresight::Bool = true,
    )

Runs the multibid and single-bid experiments for a given set of inputs, adding normally distributed
noise to the optimized prices for the multibid experiment and varying the willingness to pay for the
single-bid experiment. Writes results to separate CSV files for the multibid and single-bid
experiments.

If `bid_perfect_foresight` is true, sets bids to zero in any time period where the optimal charge is
greater than zero for both the single-bid and multibid experiments.
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
        bid_perfect_foresight::Bool = true,
        show_progress::Bool = true,
        log_every::Int = 50,
    )
    single_model = build_single_bid_model(inputs)
    configure_experiment_model!(single_model)

    optimize!(single_model)

    T = length(inputs.demand)
    optimal_results = collect_results(inputs, single_model)
    optimized_prices = optimal_results.data.Price

    bids = inputs.ess_bids
    if bid_perfect_foresight
        bids = ifelse.(optimal_results.data.Charge .> 0, 0, inputs.ess_bids)
        multi_output_csv = replace(multi_output_csv, ".csv" => "_bid_perfect_foresight.csv")
        single_output_csv = replace(single_output_csv, ".csv" => "_bid_perfect_foresight.csv")
    end

    rng = MersenneTwister(seed)
    sample_bs = uniform_samples(min_willingness_to_pay, max_willingness_to_pay, n_samples)
    # make sure we get a scenario with zero willingness to pay for the single-bid experiment
    sample_bs[1] = 0.0
    noise_by_sample = [sigma .* randn(rng, T) for _ in 1:n_samples]
    header = "sample,time,optimized_price,noise,ess_offer,ess_bid,demand,thermal,renewable,charge,discharge,soc,price,objective_value,ess_surplus,ess_profit,cost_to_serve,actual_cost"

    mkpath(dirname(multi_output_csv))
    mkpath(dirname(single_output_csv))
    multi_sample_rows = map_samples(
        sample -> build_noisy_offer_multibid_sample_rows(
            sample,
            inputs,
            bids,
            optimized_prices,
            noise_by_sample,
            clamp_min,
            T,
        ),
        1:n_samples,
        "noisy_offer_multibid";
        show_progress = show_progress,
        log_every = log_every,
    )

    open(multi_output_csv, "w") do io
        println(io, header)
        for sample in 1:n_samples
            rows = multi_sample_rows[sample]
            isnothing(rows) && continue
            print(io, rows)
        end
    end

    single_sample_rows = map_samples(
        sample -> build_noisy_offer_singlebid_sample_rows(
            sample,
            inputs,
            bids,
            sample_bs,
            T,
        ),
        1:n_samples,
        "noisy_offer_singlebid";
        show_progress = show_progress,
        log_every = log_every,
    )

    open(single_output_csv, "w") do io
        println(io, header)
        for sample in 1:n_samples
            rows = single_sample_rows[sample]
            isnothing(rows) && continue
            print(io, rows)
        end
    end

    return (
        multi_output_csv = multi_output_csv,
        single_output_csv = single_output_csv,
    )
end
