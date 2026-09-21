include(joinpath(@__DIR__, "src", "ESSModels.jl"))
using .ESSModels
using JuMP
using PrettyTables
using DataFrames
using CSV

function summarize_price_extrema(
        baseline_prices,
        price_vectors,
    )
    return DataFrame([
        let observed = [prices[t] for prices in price_vectors if !ismissing(prices)]
            (
                Time = t,
                BaselinePrice = baseline_prices[t],
                MinPrice = isempty(observed) ? missing : minimum(observed),
                MaxPrice = isempty(observed) ? missing : maximum(observed),
            )
        end for t in eachindex(baseline_prices)
    ])
end

"""
    sweep_demand_perturbations(inputs = inputs_base; perturbations, time_steps, ...)

Change demand at one time step at a time, relative to the original inputs.
The default sweep starts with decreases and covers magnitudes 1e-6 to 1 MW
in both directions. Prices are solver-selected prices of the perturbed LPs,
not bounds on optimal duals of the original LP. Return a summary, all solve
records (including failures), and full price/dispatch vectors for each solve.
Cross each demand perturbation with `charge_limit_offsets`: `nothing` uses
nameplate capacity, `0.0` caps charging at baseline dispatch, and `-0.001`
caps it 0.001 MW below baseline (clipped at zero and nameplate capacity).
Only the perturbed interval's charging bound changes. SecantPrice is reported
only for the original charging bound, to avoid mixing demand and cap effects.
Optionally write the records to `output_csv`.
"""
function sweep_demand_perturbations(
        inputs::Inputs = inputs_base;
        perturbations = vcat(-10.0 .^ range(-6, 0; length = 25),
            10.0 .^ range(-6, 0; length = 25)),
        time_steps = eachindex(inputs.demand),
        charge_limit_offsets = [nothing, 0.0, -1.0e-3],
        feasibility_tol::Float64 = 1.0e-9,
        price_tol::Float64 = 1.0e-6,
        output_csv::Union{Nothing, AbstractString} = nothing,
    )
    inputs.delta_T > 0 || error("delta_T must be positive")
    price_tol >= 0 || error("price_tol must be nonnegative")
    steps = unique(collect(time_steps))
    isempty(steps) && error("time_steps must not be empty")
    all(t -> t in eachindex(inputs.demand), steps) || error("Invalid time step")
    offsets = unique(Float64.(collect(perturbations)))
    all(isfinite, offsets) || error("Perturbations must be finite")

    cap_offsets = unique(collect(charge_limit_offsets))
    isempty(cap_offsets) && error("charge_limit_offsets must not be empty")
    all(x -> x === nothing || (x isa Real && isfinite(x)), cap_offsets) ||
        error("Charge limit offsets must be finite numbers or nothing")

    m = build_single_bid_model(inputs)
    set_silent(m)
    set_optimizer_attribute(m, "primal_feasibility_tolerance", feasibility_tol)
    set_optimizer_attribute(m, "dual_feasibility_tolerance", feasibility_tol)
    optimize!(m)
    is_solved_and_feasible(m; dual = true) ||
        error("Baseline LP failed: $(termination_status(m))")
    baseline_cost = objective_value(m)
    baseline_prices = dual.(m[:load_balance]) ./ inputs.delta_T
    baseline_charge = value.(m[:p])
    original_charge_bounds = upper_bound.(m[:p])
    records = NamedTuple[]
    solutions = NamedTuple[]
    for t in steps
        for cap_offset in cap_offsets, delta in unique(vcat(0.0, offsets))
            cap = cap_offset === nothing ? original_charge_bounds[t] :
                clamp(baseline_charge[t] + cap_offset, 0.0, original_charge_bounds[t])
            set_upper_bound(m[:p][t], cap)
            demand = inputs.demand[t] + delta
            set_normalized_rhs(m[:load_balance][t], demand)
            optimize!(m)
            solved = is_solved_and_feasible(m; dual = true)
            prices = solved ? dual.(m[:load_balance]) ./ inputs.delta_T : missing
            cost = solved ? objective_value(m) : missing
            unused = solved ? inputs.renewable_capacity[t] - value(m[:r][t]) : missing
            push!(records, (
                Time = t, DemandDelta = delta, Demand = demand,
                ChargeLimitOffset = cap_offset === nothing ? missing : Float64(cap_offset),
                ChargeLimit = cap, BaselineCharge = baseline_charge[t],
                Status = string(termination_status(m)),
                Price = solved ? prices[t] : missing,
                PriceChange = solved ? prices[t] - baseline_prices[t] : missing,
                Objective = cost, ObjectiveChange = solved ? cost - baseline_cost : missing,
                SecantPrice = solved && delta != 0 && cap_offset === nothing ?
                    (cost - baseline_cost) / (delta * inputs.delta_T) : missing,
                Charge = solved ? value(m[:p][t]) : missing,
                EffectiveDemand = solved ? demand + value(m[:p][t]) : missing,
                NetDemand = solved ? demand + value(m[:p][t]) - value(m[:g][t]) : missing,
                UnusedRenewable = unused,
                ZeroPrice = solved ? abs(prices[t]) <= price_tol : missing,
            ))
            push!(solutions, (
                time = t, demand_delta = delta, charge_limit_offset = cap_offset,
                charge_limit = cap, prices = prices,
                charge = solved ? value.(m[:p]) : missing,
                discharge = solved ? value.(m[:g]) : missing,
                thermal = solved ? value.(m[:x]) : missing,
                renewable = solved ? value.(m[:r]) : missing,
                soc = solved ? [value(m[:s][k]) for k in 0:length(inputs.demand)] : missing,
            ))
        end
        # Restore both changes before perturbing another interval.
        set_upper_bound(m[:p][t], original_charge_bounds[t])
        set_normalized_rhs(m[:load_balance][t], inputs.demand[t])
    end
    data = DataFrame(records)
    summary = DataFrame([
        let rows = filter(row -> row.Time == t &&
                isequal(row.ChargeLimitOffset, cap_offset === nothing ? missing : Float64(cap_offset)), data)
            failures = count(ismissing, rows.Price)
            rows = filter(row -> !ismissing(row.Price), rows)
            zeros = filter(row -> row.ZeroPrice, rows)
            closest = isempty(zeros) ? missing :
                zeros.DemandDelta[argmin(abs.(zeros.DemandDelta))]
            (
                Time = t, ChargeLimitOffset = cap_offset === nothing ? missing : Float64(cap_offset),
                BaselinePrice = baseline_prices[t],
                ObservedPriceMin = isempty(rows) ? missing : minimum(rows.Price),
                ObservedPriceMax = isempty(rows) ? missing : maximum(rows.Price),
                ClosestZeroPriceDelta = closest,
                FailedSolves = failures,
            )
        end for t in steps for cap_offset in cap_offsets
    ])
    println("Demand and charging-limit perturbations in MW; baseline objective: ", baseline_cost)
    println("Observed prices are from separate perturbed LPs, not dual ranges of the baseline.")
    extrema = summarize_price_extrema(baseline_prices, [s.prices for s in solutions])
    pretty_table(extrema)
    if output_csv !== nothing
        CSV.write(output_csv, data)
        println("Wrote perturbation records to: ", output_csv)
    end
    return (summary = summary, extrema = extrema, data = data, solutions = solutions,
        baseline_objective = baseline_cost, baseline_prices = baseline_prices,
        baseline_charge = baseline_charge)
end

"""
    check_duals(inputs = inputs_base; dual_bound = 1.0e4, price_tol = 1.0e-6)

Find each load-balance price's range using the single-bid KKT model.
`feasibility_tol = 1e-9` controls the LP and MILP feasibility tolerances.
Ranges are conditional on the KKT model's finite big-M dual bounds.
Endpoint price vectors are individually feasible; their components cannot
necessarily be combined into a feasible vector.
"""
function check_duals(
        inputs::Inputs = inputs_base;
        dual_bound::Float64 = 1.0e4, 
        price_tol::Float64 = 1.0e-6,
        feasibility_tol::Float64 = 1.0e-9,
    )
    inputs.delta_T > 0 || error("delta_T must be positive")
    dual_bound > 0 || error("dual_bound must be positive")
    price_tol >= 0 || error("price_tol must be nonnegative")

    primal = build_single_bid_model(inputs)
    set_optimizer_attribute(primal, "primal_feasibility_tolerance", feasibility_tol)
    set_optimizer_attribute(primal, "dual_feasibility_tolerance", feasibility_tol)
    set_silent(primal)
    optimize!(primal)
    is_solved_and_feasible(primal; dual = true) ||
        error("Primal LP failed: $(termination_status(primal))")
    optimal_cost = objective_value(primal)
    solver_price = dual.(primal[:load_balance]) ./ inputs.delta_T

    kkt = ESSModels.build_single_bid_kkt_model(inputs; dual_bound)
    set_optimizer_attribute(kkt, "mip_feasibility_tolerance", feasibility_tol)
    set_optimizer_attribute(kkt, "primal_feasibility_tolerance", feasibility_tol)
    set_optimizer_attribute(kkt, "dual_feasibility_tolerance", feasibility_tol)
    set_silent(kkt)
    set_optimizer_attribute(kkt, "mip_rel_gap", 0.0)
    set_optimizer_attribute(kkt, "mip_abs_gap", 0.0)
    T = length(inputs.demand)
    lambda = kkt[:kkt_lambda]
    # These are explicit KKT variables, not duals of the auxiliary MILP.
    price = @expression(kkt, [t = 1:T], -lambda[t] / inputs.delta_T)
    dispatch_cost = @expression(kkt,
        inputs.delta_T * (
            inputs.thermal_offer_price * sum(kkt[:x]) +
            inputs.renewable_offer_price * sum(kkt[:r]) +
            inputs.epsilon * sum(kkt[:p]) +
            inputs.zeta * sum(kkt[:g])
        ) - inputs.b * (kkt[:s][T] - inputs.gamma^T * inputs.soc_init)
    )
    # KKT feasibility already enforces primal optimality; verify it after
    # every solve instead of adding a rounded objective-value constraint.
    dual_names = (:nu0, :mu, :lambda, :sigma, :tau,
        :p_lb_dual, :p_ub_dual, :g_lb_dual, :g_ub_dual,
        :s_lb_dual, :s_ub_dual, :x_lb_dual, :x_ub_dual,
        :r_lb_dual, :r_ub_dual)
    dual_variables = VariableRef[kkt[:nu0]]
    for name in dual_names[2:end]
        append!(dual_variables, vec(collect(kkt[name])))
    end

    function endpoint(
            t,
            sense,
        )
        set_objective_sense(kkt, sense)
        set_objective_function(kkt, price[t])
        optimize!(kkt)
        is_solved_and_feasible(kkt) ||
            error("KKT endpoint failed at t=$t, sense=$sense: $(termination_status(kkt))")
        cost = value(dispatch_cost)
        isapprox(cost, optimal_cost; atol = 1.0e-5, rtol = 1.0e-7) ||
            error("KKT dispatch cost $cost differs from LP optimum $optimal_cost")
        bound_active = any(v -> isapprox(abs(value(v)), dual_bound;
            atol = 1.0e-5, rtol = 1.0e-7), dual_variables)
        return (price = value(price[t]), prices = value.(price),
            lambda = value.(lambda), dispatch_cost = cost,
            dual_bound_active = bound_active)
    end

    minima = [endpoint(t, MIN_SENSE) for t in 1:T]
    maxima = [endpoint(t, MAX_SENSE) for t in 1:T]
    price_min = [result.price for result in minima]
    price_max = [result.price for result in maxima]
    bound_active = [minima[t].dual_bound_active || maxima[t].dual_bound_active for t in 1:T]
    table = (
        Time = collect(1:T),
        SolverPrice = solver_price,
        PriceMin = price_min,
        PriceMax = price_max,
        Range = price_max - price_min,
        Nonunique = price_max - price_min .> price_tol,
        DualBoundActive = bound_active,
    )
    println("Original LP objective: ", optimal_cost)
    println("Price = -lambda / delta_T; endpoint ranges use dual_bound = ", dual_bound)
    pretty_table(table)
    if any(bound_active)
        println("A dual bound is active: increase dual_bound and check endpoint stability.")
    end
    return (data = table, objective_value = optimal_cost,
        # Negation reverses the order of the raw lambda endpoints.
        lambda_min = -inputs.delta_T .* price_max,
        lambda_max = -inputs.delta_T .* price_min,
        minima = minima, maxima = maxima, dual_bound = dual_bound)
end

"""
    sweep_discharge_limits(inputs = inputs_base; reductions, time_steps, ...)

Cap discharge below its original optimal dispatch at one interval at a time.
Report every interval's price for each solve to expose intertemporal effects.
Reductions are in MW and are clipped at zero discharge. These are sensitivities
of modified LPs, not optimal dual ranges of the original LP.
"""
function sweep_discharge_limits(
        inputs::Inputs = inputs_base;
        reductions = 10.0 .^ range(-6, -1; length = 21),
        time_steps = eachindex(inputs.demand),
        feasibility_tol::Float64 = 1.0e-9,
        output_csv::Union{Nothing, AbstractString} = nothing,
    )
    inputs.delta_T > 0 || error("delta_T must be positive")
    steps = unique(collect(time_steps))
    isempty(steps) && error("time_steps must not be empty")
    all(t -> t in eachindex(inputs.demand), steps) || error("Invalid time step")
    amounts = unique(vcat(0.0, Float64.(collect(reductions))))
    all(x -> isfinite(x) && x >= 0, amounts) ||
        error("Discharge reductions must be finite and nonnegative")

    m = build_single_bid_model(inputs)
    set_silent(m)
    set_optimizer_attribute(m, "primal_feasibility_tolerance", feasibility_tol)
    set_optimizer_attribute(m, "dual_feasibility_tolerance", feasibility_tol)
    optimize!(m)
    is_solved_and_feasible(m; dual = true) ||
        error("Baseline LP failed: $(termination_status(m))")
    baseline_cost = objective_value(m)
    baseline_prices = dual.(m[:load_balance]) ./ inputs.delta_T
    baseline_discharge = value.(m[:g])
    original_bounds = upper_bound.(m[:g])
    records = NamedTuple[]
    summaries = NamedTuple[]
    price_vectors = []
    T = length(inputs.demand)
    for t in steps
        for reduction in amounts
            cap = max(0.0, baseline_discharge[t] - reduction)
            set_upper_bound(m[:g][t], cap)
            optimize!(m)
            solved = is_solved_and_feasible(m; dual = true)
            prices = solved ? dual.(m[:load_balance]) ./ inputs.delta_T : missing
            push!(price_vectors, prices)
            cost = solved ? objective_value(m) : missing
            terminal_soc = solved ? value(m[:s][T]) : missing
            push!(summaries, (
                LimitedTime = t, Reduction = reduction, DischargeLimit = cap,
                Status = string(termination_status(m)),
                LocalPrice = solved ? prices[t] : missing,
                FinalPrice = solved ? prices[T] : missing,
                TerminalSOC = terminal_soc,
                ObjectiveChange = solved ? cost - baseline_cost : missing,
            ))
            for j in 1:T
                push!(records, (
                    LimitedTime = t, Reduction = reduction,
                    ActualLimitReduction = baseline_discharge[t] - cap,
                    DischargeLimit = cap, PriceTime = j,
                    Status = string(termination_status(m)),
                    BaselinePrice = baseline_prices[j],
                    Price = solved ? prices[j] : missing,
                    Charge = solved ? value(m[:p][j]) : missing,
                    Discharge = solved ? value(m[:g][j]) : missing,
                    Thermal = solved ? value(m[:x][j]) : missing,
                    Renewable = solved ? value(m[:r][j]) : missing,
                    SOC = solved ? value(m[:s][j]) : missing,
                    TerminalSOC = terminal_soc,
                    Objective = cost,
                    ObjectiveChange = solved ? cost - baseline_cost : missing,
                ))
            end
        end
        set_upper_bound(m[:g][t], original_bounds[t])
    end
    summary = DataFrame(summaries)
    data = DataFrame(records)
    println("Discharge caps relative to baseline dispatch; baseline objective: ", baseline_cost)
    println("Zero reduction caps at baseline dispatch; the original model uses nameplate limits.")
    extrema = summarize_price_extrema(baseline_prices, price_vectors)
    pretty_table(extrema)
    if output_csv !== nothing
        CSV.write(output_csv, data)
        println("Wrote discharge sensitivity records to: ", output_csv)
    end
    return (summary = summary, extrema = extrema, data = data, baseline_objective = baseline_cost,
        baseline_prices = baseline_prices, baseline_discharge = baseline_discharge)
end

# Run from code/: julia --project=. check_duals.jl
if abspath(PROGRAM_FILE) == @__FILE__
    sweep_demand_perturbations(;
        output_csv = joinpath(@__DIR__, "outputs", "demand_perturbations.csv"),
    )
    discharge_results = sweep_discharge_limits(;
        output_csv = joinpath(@__DIR__, "outputs", "discharge_limit_sensitivities.csv"),
    )
end
