function uniform_samples(xmin, xmax, N)
    xmin <= xmax || throw(ArgumentError("xmin must be <= xmax"))
    return xmin .+ (xmax - xmin) .* rand(N)
end


"""Copy BIM bids/costs without mutating the base inputs. `b` sets terminal SOC bids."""
function replace_inputs(
        inputs::BIMInputs;
        b::Union{Real, Nothing} = nothing,
        ess_offers::AbstractDict = inputs.ess_offers,
        ess_bids::AbstractDict = inputs.ess_bids,
    )::BIMInputs
    return BIMInputs(
        experiment_name = inputs.experiment_name,
        offer_prices = deepcopy(inputs.offer_prices),
        charging_cost = deepcopy(inputs.charging_cost),
        discharging_cost = deepcopy(inputs.discharging_cost),
        ess_offers = deepcopy(ess_offers),
        ess_bids = deepcopy(ess_bids),
        net_soc_bid = isnothing(b) ? deepcopy(inputs.net_soc_bid) :
            Dict(name => fill(Float64(b), length(values)) for (name, values) in inputs.net_soc_bid),
    )
end


# One row per sample, battery, and interval. System metrics repeat across batteries.
const EXPERIMENT_HEADER = "sample,battery,time,optimized_price,noise,ess_offer,ess_bid,demand,thermal,renewable,charge,discharge,soc,price,objective_value,ess_surplus,ess_profit,cost_to_serve,actual_cost,battery_surplus,battery_profit"

function write_battery_rows(io, sample, inputs, results, net;
        optimized_prices = results.data.Price, noise = nothing)
    demand = CPF.total_load_p(net)
    for name in sort!(collect(keys(results.battery_data)))
        battery = results.battery_data[name]
        # Escape identifiers using standard CSV quoting.
        quoted_name = "\"" * replace(name, "\"" => "\"\"") * "\""
        for t in 1:net.Ntimesteps
            values = (optimized_prices[t], isnothing(noise) ? 0.0 : noise[name][t],
                inputs.ess_offers[name][t], inputs.ess_bids[name][t], demand[t],
                results.data.Thermal[t], results.data.Renewable[t], battery.charge[t],
                battery.discharge[t], battery.soc[t], results.data.Price[t],
                results.objective_value, results.ess_surplus, results.ess_profit,
                results.cost_to_serve, results.actual_cost, battery.surplus, battery.profit)
            println(io, sample, ",", quoted_name, ",", t, ",",
                join(round.(values; digits = 4), ","))
        end
    end
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
    offers = Dict(name => max.(optimized_prices .+ noise[name], clamp_min) for name in keys(bids))
    sample_inputs = replace_inputs(inputs; ess_offers = offers, ess_bids = bids)
    m, net = build_bim_multi_bid(sample_inputs, network_file_path; silent = true)
    assert_sample_has_solution(m, sample, "uniform_error_multibid")
    results = collect_results(sample_inputs, m, net)
    isnothing(results) && error("Could not collect sample $(sample)")
    io = IOBuffer()
    write_battery_rows(io, sample, sample_inputs, results, net; optimized_prices, noise)
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

Solve the single-bid reference once, then run multibid samples with perturbed
discharge offers and write their results to CSV. The reference minimizes generator
and battery degradation costs minus terminal SOC value. Its optimal prices are
load-balance duals divided by the interval length in hours, rounded to two decimals
by `collect_results`.

Draw an independent `Uniform(-error_range, error_range)` error for every sample,
battery, and time interval (independent across batteries). Set each discharge offer to
`max(optimized_prices[t] + noise[t], clamp_min)` and solve the multibid model.
The CSV records each interval's reference price, error, offer, and clearing price.

Charging bids remain `inputs.ess_bids` unless `bid_perfect_foresight` is true:
then each battery's bids are zero wherever its own reference charge is positive, and the
output filename gains `_bid_perfect_foresight`.
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
    n_samples > 0 || throw(ArgumentError("n_samples must be positive"))
    isfinite(error_range) && error_range >= 0 || throw(ArgumentError("error_range must be finite and nonnegative"))
    single_model, net = build_bim_single_bid(inputs, network_file_path; silent = true)
    assert_sample_has_solution(single_model, 1, "single_bid_reference")

    T = net.Ntimesteps
    optimal_results = collect_results(inputs, single_model, net)
    optimized_prices = optimal_results.data.Price

    batteries = sort!(collect(keys(optimal_results.battery_data)))
    Set(batteries) == Set(keys(inputs.ess_bids)) || throw(ArgumentError("Battery inputs must match the network"))
    bids = deepcopy(inputs.ess_bids)
    if bid_perfect_foresight
        bids = Dict(name => ifelse.(optimal_results.battery_data[name].charge .> 0,
            0.0, inputs.ess_bids[name]) for name in batteries)
        output_csv = replace(output_csv, ".csv" => "_bid_perfect_foresight.csv")
    end

    # Draw on the main process in stable battery order before distributing solves.
    noise_by_sample = [Dict(name => uniform_samples(-error_range, error_range, T)
        for name in batteries) for _ in 1:n_samples]
    header = EXPERIMENT_HEADER

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
