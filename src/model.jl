
function build_model(inputs::Inputs)::JuMP.AbstractModel

    m = JuMP.Model(HiGHS.Optimizer)

    T = length(inputs.demand)

    @variables(m, begin
        0                   <= p[t = 1:T] <= inputs.charge_max
        0                   <= g[t = 1:T] <= inputs.discharge_max
        inputs.soc_min      <= s[t = 0:T] <= inputs.soc_max
        inputs.thermal_min  <= x[t = 1:T] <= inputs.thermal_max
        0                   <= r[t = 1:T] <= inputs.renewable_capacity[t]
    end)

    @constraint(m, s[0] == inputs.soc_init)

    @constraint(m, SOC[t = 1:T],
        s[t] == inputs.delta_T * inputs.alpha * p[t] 
            - inputs.delta_T * inputs.beta * g[t] 
            + inputs.gamma * s[t-1]
    )

    @constraint(m, [t = 1:T],
        inputs.gamma * s[t-1] + inputs.delta_T * inputs.alpha * p[t] <= inputs.soc_max
    )

    @constraint(m, [t = 1:T],
        inputs.gamma * s[t-1] - inputs.delta_T * inputs.beta * g[t]  >= inputs.soc_min
    )

    @constraint(m, load_balance[t = 1:T],
        x[t] + g[t] + r[t] - p[t] == inputs.demand[t]
    )

    s_double_bar = inputs.gamma^T * inputs.soc_init
    
    @objective(m, Min, 
        inputs.thermal_offer_price * sum([x[t] for t = 1:T])
        + inputs.renewable_offer_price * sum([r[t] for t = 1:T])
        + inputs.epsilon * sum([p[t] for t = 1:T])
        + inputs.zeta * sum([g[t] for t = 1:T])
        - inputs.b * (s[T] - s_double_bar)
    )

    return m
end
