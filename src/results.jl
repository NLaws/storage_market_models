
function print_results(inputs::Inputs, m::JuMP.AbstractModel)

    T = length(inputs_base.demand)
    
    # Create a table of results using DataFrames for easier formatting
    data = (
        Time = 1:T,
        Thermal = round.(value.(m[:x]), digits=2),
        Renewable = round.(value.(m[:r]), digits=2),
        Charge = round.(value.(m[:p]), digits=2),
        Discharge = round.(value.(m[:g]), digits=2),
        SOC = round.([value(m[:s][t]) for t in 1:T], digits=2),
        Price = round.([dual(m[:load_balance][t]) for t in 1:T], digits=2),
    )
    
    pretty_table(data)
    
    println("\nObjective Value: \$$(round(objective_value(m), digits=2))")

    ess_surplus = data.Discharge' * data.Price - data.Charge' * data.Price - 
        inputs.epsilon * sum(data.Charge) - inputs.zeta * sum(data.Discharge) + 
        inputs.b * (data.SOC[end] - m[:s_double_bar])
    # TODO Ross has $43,111 for ESS Surplus in the base case. I get $9577.78 
    println("\nESS Surplus: \$$(round(ess_surplus, digits=2))")

end
