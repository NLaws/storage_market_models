function collect_results(inputs::Inputs, m::JuMP.AbstractModel; resolve_binary_for_duals::Bool = true)

    T = length(inputs.demand)

    if resolve_binary_for_duals && (:z in keys(m.obj_dict))
        @debug "Model contains binary variables. Fixing z and re-solving as an LP to get duals for price calculation."
        zstar = value.(m[:z])

        for t in 1:T
            fix(m[:z][t], round(zstar[t]); force = true)
        end
        relax_integrality(m)
        optimize!(m)
    end

    data = (
        Time = collect(1:T),
        Thermal = round.(value.(m[:x]), digits = 2),
        Renewable = round.(value.(m[:r]), digits = 2),
        Charge = round.(value.(m[:p]), digits = 2),
        Discharge = round.(value.(m[:g]), digits = 2),
        SOC = round.([value(m[:s][t]) for t in 1:T], digits = 2),
        Price = round.([dual(m[:load_balance][t]) for t in 1:T], digits = 2),
    )

    objective = round(objective_value(m), digits = 2)

    ess_surplus = data.Discharge' * data.Price - data.Charge' * data.Price -
        inputs.epsilon * sum(data.Charge) - inputs.zeta * sum(data.Discharge) +
        inputs.b * (data.SOC[end] - m[:s_double_bar])
    ess_surplus = round(ess_surplus, digits = 2)

    ess_profit = data.Discharge' * data.Price - data.Charge' * data.Price
    ess_profit = round(ess_profit, digits = 2)

    cost_to_serve = data.Thermal' * data.Price +
        data.Renewable' * data.Price +
        data.Discharge' * data.Price -
        data.Charge' * data.Price
    cost_to_serve = round(cost_to_serve, digits = 2)

    actual_cost = data.Thermal' * data.Price - inputs.b * (data.SOC[end] - m[:s_double_bar])
    actual_cost = round(actual_cost, digits = 2)


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
