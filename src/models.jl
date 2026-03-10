

function build_single_bid_model(inputs::Inputs)::JuMP.AbstractModel

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

    m[:s_double_bar] = inputs.gamma^T * inputs.soc_init
    
    @objective(m, Min, 
        inputs.thermal_offer_price * sum([x[t] for t = 1:T])
        + inputs.renewable_offer_price * sum([r[t] for t = 1:T])
        + inputs.epsilon * sum([p[t] for t = 1:T])
        + inputs.zeta * sum([g[t] for t = 1:T])
        - inputs.b * (s[T] - m[:s_double_bar])
    )

    return m
end


function build_multi_bid_model(inputs::Inputs)::JuMP.AbstractModel

    m = JuMP.Model(HiGHS.Optimizer)

    T = length(inputs.demand)

    @variables(m, begin
        0                   <= p[t = 1:T] <= inputs.charge_max
        0                   <= g[t = 1:T] <= inputs.discharge_max
        inputs.soc_min      <= s[t = 0:T] <= inputs.soc_max
        inputs.thermal_min  <= x[t = 1:T] <= inputs.thermal_max
        0                   <= r[t = 1:T] <= inputs.renewable_capacity[t]
        z[t = 1:T], Bin
    end)


    # @constraint(m, [t in 1:T], p[t] ⟂ g[t]) 
    Mp = inputs.charge_max      # upper bound for p[t]
    Mg = inputs.discharge_max   # upper bound for g[t]
    @constraint(m, [t in 1:T], p[t] <= Mp * z[t])
    @constraint(m, [t in 1:T], g[t] <= Mg * (1 - z[t]))

    @constraint(m, s[0] == inputs.soc_init)

    @constraint(m, SOC[t = 1:T],
        s[t] == inputs.delta_T * inputs.eta * p[t] 
            - inputs.delta_T  * g[t] 
            + s[t-1]
    )

    @constraint(m, load_balance[t = 1:T],
        x[t] + g[t] + r[t] - p[t] == inputs.demand[t]
    )

     m[:s_double_bar] = 0.0
    
    @objective(m, Min, 
        inputs.thermal_offer_price * sum([x[t] for t = 1:T])
        + inputs.renewable_offer_price * sum([r[t] for t = 1:T])
        + sum(inputs.ess_offers[t] * g[t] for t in 1:T)
        - sum(inputs.ess_bids[t] * p[t] for t in 1:T)
    )

    return m
end
