function has_solution(m::JuMP.AbstractModel)
    result_count = JuMP.result_count(m)
    if result_count == 0
        return false
    end
    return true
end


function collect_results(
        inputs::Inputs, 
        m::JuMP.AbstractModel; 
        resolve_binary_for_duals::Bool = true,
    )

    T = length(inputs.demand)
    if !has_solution(m)
        return nothing
    end

    if resolve_binary_for_duals && (:z in keys(m.obj_dict))
        @debug "Model contains binary variables. Fixing z and re-solving as an LP to get duals for price calculation."
        zstar = value.(m[:z])

        for t in 1:T
            fix(m[:z][t], round(zstar[t]); force = true)
        end
        relax_integrality(m)
        optimize!(m)
        if !has_solution(m)
            return nothing
        end
    end

    data = (
        Time = collect(1:T),
        Thermal = round.(value.(m[:x]), digits = 2),
        Renewable = round.(value.(m[:r]), digits = 2),
        Charge = round.(value.(m[:p]), digits = 2),
        Discharge = round.(value.(m[:g]), digits = 2),
        SOC = round.([value(m[:s][t]) for t in 1:T], digits = 2),
        # Load balance is in power units; convert its dual to an energy price.
        Price = round.([dual(m[:load_balance][t]) / inputs.delta_T for t in 1:T], digits = 2),
    )

    objective = round(objective_value(m), digits = 2)

    # SOC is already energy, so its terminal value needs no time scaling.
    terminal_soc_value = inputs.b * (data.SOC[end] - m[:s_double_bar])

    ess_surplus = data.Discharge' * data.Price - data.Charge' * data.Price -
        # degradation cost
        inputs.epsilon * sum(data.Charge) - inputs.zeta * sum(data.Discharge)
    ess_surplus = round(ess_surplus * inputs.delta_T + terminal_soc_value, digits = 2)

    ess_profit = data.Discharge' * data.Price - data.Charge' * data.Price
    ess_profit = round(ess_profit * inputs.delta_T, digits = 2)

    cost_to_serve = data.Thermal' * data.Price +
        data.Renewable' * data.Price +
        data.Discharge' * data.Price -
        data.Charge' * data.Price
    cost_to_serve = round(cost_to_serve * inputs.delta_T, digits = 2)

    actual_cost = round(data.Thermal' * data.Price * inputs.delta_T - terminal_soc_value, digits = 2)


    return (
        data = data,
        objective_value = objective,
        ess_surplus = ess_surplus,
        ess_profit = ess_profit,
        cost_to_serve = cost_to_serve,
        actual_cost = actual_cost,
    )
end


function print_results(inputs::Inputs, m::JuMP.AbstractModel)

    results = collect_results(inputs, m)

    pretty_table(results.data)

    println("\nObjective Value: \$$(results.objective_value)")
    println("\nESS Surplus: \$$(results.ess_surplus)")
    println("\nESS Profit: \$$(results.ess_profit)")
    println("\nCost to Serve: \$$(results.cost_to_serve)")

end


"""Collect BIM copper-plate fleet and per-battery results with named thermal/renewable generators.

Compute monetary metrics from unrounded dispatch; round only the reported values.
"""
function collect_results(inputs::BIMInputs, m::JuMP.AbstractModel, net)
    has_solution(m) || return nothing
    length(CPF.busses(net)) == 1 || throw(ArgumentError("Experiment CSVs require a copper-plate network"))
    bus = only(CPF.battery_busses(net))
    batteries = sort!(collect(keys(m[:p_charge][bus])))
    # Prices are LP duals conditional on the optimal charging/discharging modes.
    binaries = filter(is_binary, all_variables(m))
    if !isempty(binaries)
        modes = round.(value.(binaries))
        for (variable, mode) in zip(binaries, modes)
            fix(variable, mode; force = true)
            unset_binary(variable)
        end
        optimize!(m)
        has_solution(m) || return nothing
    end
    T = net.Ntimesteps
    dt = 1 / net.time_steps_per_hour
    thermal = value.(m[:p_gen][bus]["thermal"])
    renewable = value.(m[:p_gen][bus]["renewable"])
    prices = dual.(m[:load_balance]) / dt
    battery_data = Dict(name => begin
        charge = value.(m[:p_charge][bus][name])
        discharge = value.(m[:p_discharge][bus][name])
        soc = [value(m[:soc][bus][name][t]) for t in 1:T]
        terminal_value = inputs.net_soc_bid[name][T] * (soc[end] - value(m[:soc][bus][name][0]))
        profit = dt * sum((discharge .- charge) .* prices)
        degradation = dt * sum(inputs.charging_cost[name] .* charge + inputs.discharging_cost[name] .* discharge)
        (; charge, discharge, soc, terminal_value, profit,
            surplus = profit - degradation + terminal_value)
    end for name in batteries)
    charge = sum(battery_data[name].charge for name in batteries)
    discharge = sum(battery_data[name].discharge for name in batteries)
    soc = sum(battery_data[name].soc for name in batteries)
    terminal_value = sum(battery_data[name].terminal_value for name in batteries)
    profit = sum(battery_data[name].profit for name in batteries)
    surplus = sum(battery_data[name].surplus for name in batteries)
    return (
        battery_data = battery_data,
        data = (
            Time = collect(1:T),
            Thermal = round.(thermal; digits = 2),
            Renewable = round.(renewable; digits = 2),
            Charge = round.(charge; digits = 2),
            Discharge = round.(discharge; digits = 2),
            SOC = round.(soc; digits = 2),
            Price = round.(prices; digits = 2),
        ),
        objective_value = round(objective_value(m); digits = 2),
        ess_surplus = round(surplus; digits = 2),
        ess_profit = round(profit; digits = 2),
        cost_to_serve = round(dt * sum((thermal .+ renewable .+ discharge .- charge) .* prices); digits = 2),
        # Preserve the experiment's thermal-payment-minus-terminal-value definition.
        actual_cost = round(dt * sum(thermal .* prices) - terminal_value; digits = 2),
    )
end


function print_results(inputs::BIMInputs, m::JuMP.AbstractModel, net)
    results = collect_results(inputs, m, net)
    pretty_table(results.data)
    println("\nObjective Value: \$$(results.objective_value)")
    println("\nESS Surplus: \$$(results.ess_surplus)")
    println("\nESS Profit: \$$(results.ess_profit)")
    println("\nCost to Serve: \$$(results.cost_to_serve)")
end
