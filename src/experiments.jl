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
        charge_efficiency = inputs.charge_efficiency,
        discharge_efficiency = inputs.discharge_efficiency,
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


"""Copy BIM bids/costs without mutating the base inputs. `b` sets terminal SOC bids."""
function replace_inputs(
    inputs::BIMInputs;
    b::Union{Real, Nothing} = nothing,
    ess_offers::AbstractDict = inputs.ess_offers,
    ess_bids::AbstractDict = inputs.ess_bids,
)::BIMInputs
    return BIMInputs(
        offer_prices = deepcopy(inputs.offer_prices),
        charging_cost = deepcopy(inputs.charging_cost),
        discharging_cost = deepcopy(inputs.discharging_cost),
        ess_offers = deepcopy(ess_offers),
        ess_bids = deepcopy(ess_bids),
        net_soc_bid = isnothing(b) ? deepcopy(inputs.net_soc_bid) :
            Dict(name => fill(Float64(b), length(values)) for (name, values) in inputs.net_soc_bid),
    )
end


# The existing CSV format describes one battery on a copper plate.
experiment_battery(inputs::BIMInputs) = only(keys(inputs.ess_bids))


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
    if nprocs() == 1
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
        inputs::BIMInputs,
        bids,
        optimized_prices,
        noise_by_sample,
        clamp_min::Float64,
        T::Int,
        network_file_path::AbstractString,
    )
    noise = noise_by_sample[sample]
    offers = max.(optimized_prices .+ noise, clamp_min)
    sample_inputs = replace_inputs(
        inputs;
        ess_offers = Dict(experiment_battery(inputs) => offers),
        ess_bids = Dict(experiment_battery(inputs) => bids),
    )
    m, net = build_bim_multi_bid(sample_inputs, network_file_path; silent = true)
    assert_sample_has_solution(m, sample, "uniform_error_multibid")
    results = collect_results(sample_inputs, m, net)
    isnothing(results) && return nothing

    demand = CPF.total_load_p(net)
    io = IOBuffer()
    for t in 1:T
        write_results_row(
            io,
            sample,
            t,
            round(optimized_prices[t], digits = 4),
            round(noise, digits = 4),
            round(offers[t], digits = 4),
            round(sample_inputs.ess_bids[experiment_battery(inputs)][t], digits = 4),
            Float64(demand[t]),
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
        inputs::BIMInputs,
        bids,
        optimized_prices,
        noise_by_sample,
        clamp_min::Float64,
        T::Int,
        network_file_path::AbstractString,
    )
    noise = noise_by_sample[sample]
    offers = max.(optimized_prices .+ noise, clamp_min)
    sample_inputs = replace_inputs(
        inputs;
        ess_offers = Dict(experiment_battery(inputs) => offers),
        ess_bids = Dict(experiment_battery(inputs) => bids),
    )
    m, net = build_bim_multi_bid(sample_inputs, network_file_path; silent = true)
    assert_sample_has_solution(m, sample, "noisy_offer_multibid")
    results = collect_results(sample_inputs, m, net)
    isnothing(results) && return nothing

    demand = CPF.total_load_p(net)
    io = IOBuffer()
    for t in 1:T
        write_results_row(
            io,
            sample,
            t,
            round(optimized_prices[t], digits = 4),
            round(noise[t], digits = 4),
            round(offers[t], digits = 4),
            round(sample_inputs.ess_bids[experiment_battery(inputs)][t], digits = 4),
            Float64(demand[t]),
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


function build_noisy_offer_singlebid_sample_rows(inputs::BIMInputs, results, net, T::Int)
    sample = 1
    sample_inputs = inputs
    demand = CPF.total_load_p(net)
    io = IOBuffer()
    for t in 1:T
        write_results_row(
            io,
            sample,
            t,
            "NaN",
            "NaN",
            sample_inputs.net_soc_bid[experiment_battery(inputs)][end],
            round(sample_inputs.net_soc_bid[experiment_battery(inputs)][end], digits = 4),
            Float64(demand[t]),
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
        inputs::BIMInputs;
        network_file_path::AbstractString = BASE_NETWORK_PATH,
        n_samples::Int = 100,
        error_range::Float64 = 10.0,
        clamp_min::Float64 = 0.0,
        output_csv::AbstractString = "outputs/uniform_error_multibid_results.csv",
        bid_perfect_foresight::Bool = true,
    )

Runs the multibid experiment for a given set of inputs, adding uniformly distributed noise to the
optimized prices from the single-bid reference. Writes results to
a CSV file. 

If `bid_perfect_foresight` is true, sets bids to zero in any time period where the
optimal charge is greater than zero.
"""
function run_uniform_error_multibid_experiment(
        inputs::BIMInputs;
        network_file_path::AbstractString = BASE_NETWORK_PATH,
        n_samples::Int = 100,
        error_range::Float64 = 10.0,
        clamp_min::Float64 = 0.0,
        output_csv::AbstractString = "outputs/uniform_error_multibid_results.csv",
        bid_perfect_foresight::Bool = true,
        show_progress::Bool = true,
        log_every::Int = 250,
    )
    single_model, net = build_bim_single_bid(inputs, network_file_path; silent = true)
    assert_sample_has_solution(single_model, 1, "single_bid_reference")

    T = net.Ntimesteps
    optimal_results = collect_results(inputs, single_model, net)
    optimized_prices = optimal_results.data.Price

    bids = inputs.ess_bids[experiment_battery(inputs)]
    if bid_perfect_foresight
        bids = ifelse.(optimal_results.data.Charge .> 0, 0.0, inputs.ess_bids[experiment_battery(inputs)])
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
            network_file_path,
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
        inputs::BIMInputs;
        network_file_path::AbstractString = BASE_NETWORK_PATH,
        n_samples::Int = 100,
        sigma::Float64 = 5.0,
        seed::Int = 1,
        clamp_min::Float64 = 0.0,
        multi_output_csv::AbstractString = "outputs/noisy_offer_multibid_results.csv",
        single_output_csv::AbstractString = "outputs/noisy_offer_singlebid_results.csv",
        bid_perfect_foresight::Bool = true,
    )

Runs single-bid once with the provided inputs, then adds normally distributed noise to its
optimized prices for the multibid samples. Both use inputs.net_soc_bid, including result calculations.
Writes separate CSVs with the same columns: single-bid has one sample (sample = 1), with
one row per timestep; multibid has n_samples samples, each with one row per timestep.

If `bid_perfect_foresight` is true, sets bids to zero in any time period where the optimal charge is
greater than zero for the multibid experiment. The single-bid reference uses the provided inputs.
"""
function run_noisy_offer_experiment(
        inputs::BIMInputs;
        network_file_path::AbstractString = BASE_NETWORK_PATH,
        n_samples::Int = 100,
        sigma::Float64 = 5.0,
        seed::Int = 1,
        clamp_min::Float64 = 0.0,
        multi_output_csv::AbstractString = "outputs/noisy_offer_multibid_results.csv",
        single_output_csv::AbstractString = "outputs/noisy_offer_singlebid_results.csv",
        bid_perfect_foresight::Bool = true,
        show_progress::Bool = true,
        log_every::Int = 50,
    )
    single_model, net = build_bim_single_bid(inputs, network_file_path; silent = true)
    assert_sample_has_solution(single_model, 1, "single_bid_reference")

    T = net.Ntimesteps
    optimal_results = collect_results(inputs, single_model, net)
    optimized_prices = optimal_results.data.Price

    bids = inputs.ess_bids[experiment_battery(inputs)]
    if bid_perfect_foresight
        bids = ifelse.(optimal_results.data.Charge .> 0, 0.0, inputs.ess_bids[experiment_battery(inputs)])
        multi_output_csv = replace(multi_output_csv, ".csv" => "_bid_perfect_foresight.csv")
        single_output_csv = replace(single_output_csv, ".csv" => "_bid_perfect_foresight.csv")
    end

    rng = MersenneTwister(seed)
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
            network_file_path,
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

    # Reuse the single-bid reference solve above without changing any inputs.
    single_rows = build_noisy_offer_singlebid_sample_rows(inputs, optimal_results, net, T)
    open(single_output_csv, "w") do io
        println(io, header)
        print(io, single_rows)
    end

    return (
        multi_output_csv = multi_output_csv,
        single_output_csv = single_output_csv,
    )
end
