

function build_single_bid_model(inputs::Inputs, m::Union{JuMP.AbstractModel, Missing} = missing)::JuMP.AbstractModel

    if ismissing(m)
        m = JuMP.Model(HiGHS.Optimizer)
    end

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


function build_single_bid_kkt_model(
        inputs::Inputs;
        dual_bound::Float64 = 1.0e4,
    )::JuMP.AbstractModel

    m = JuMP.Model(HiGHS.Optimizer)
    T = length(inputs.demand)

    @variables(m, begin
        0                   <= p[t = 1:T] <= inputs.charge_max
        0                   <= g[t = 1:T] <= inputs.discharge_max
        inputs.soc_min      <= s[t = 0:T] <= inputs.soc_max
        inputs.thermal_min  <= x[t = 1:T] <= inputs.thermal_max
        0                   <= r[t = 1:T] <= inputs.renewable_capacity[t]

        -dual_bound <= nu0 <= dual_bound
        -dual_bound <= mu[t = 1:T] <= dual_bound
        -dual_bound <= lambda[t = 1:T] <= dual_bound

        0 <= sigma[t = 1:T] <= dual_bound
        0 <= tau[t = 1:T] <= dual_bound

        0 <= p_lb_dual[t = 1:T] <= dual_bound
        0 <= p_ub_dual[t = 1:T] <= dual_bound
        0 <= g_lb_dual[t = 1:T] <= dual_bound
        0 <= g_ub_dual[t = 1:T] <= dual_bound
        0 <= s_lb_dual[k = 0:T] <= dual_bound
        0 <= s_ub_dual[k = 0:T] <= dual_bound
        0 <= x_lb_dual[t = 1:T] <= dual_bound
        0 <= x_ub_dual[t = 1:T] <= dual_bound
        0 <= r_lb_dual[t = 1:T] <= dual_bound
        0 <= r_ub_dual[t = 1:T] <= dual_bound

        0 <= upper_soc_slack[t = 1:T]
        0 <= lower_soc_slack[t = 1:T]
        0 <= p_lb_slack[t = 1:T]
        0 <= p_ub_slack[t = 1:T]
        0 <= g_lb_slack[t = 1:T]
        0 <= g_ub_slack[t = 1:T]
        0 <= s_lb_slack[k = 0:T]
        0 <= s_ub_slack[k = 0:T]
        0 <= x_lb_slack[t = 1:T]
        0 <= x_ub_slack[t = 1:T]
        0 <= r_lb_slack[t = 1:T]
        0 <= r_ub_slack[t = 1:T]

        z_upper_soc[t = 1:T], Bin
        z_lower_soc[t = 1:T], Bin
        z_p_lb[t = 1:T], Bin
        z_p_ub[t = 1:T], Bin
        z_g_lb[t = 1:T], Bin
        z_g_ub[t = 1:T], Bin
        z_s_lb[k = 0:T], Bin
        z_s_ub[k = 0:T], Bin
        z_x_lb[t = 1:T], Bin
        z_x_ub[t = 1:T], Bin
        z_r_lb[t = 1:T], Bin
        z_r_ub[t = 1:T], Bin
    end)

    @constraint(m, s[0] == inputs.soc_init)

    @constraint(m, SOC[t = 1:T],
        s[t] == inputs.delta_T * inputs.alpha * p[t] -
                inputs.delta_T * inputs.beta * g[t] +
                inputs.gamma * s[t - 1]
    )

    @constraint(m, load_balance[t = 1:T],
        x[t] + g[t] + r[t] - p[t] == inputs.demand[t]
    )

    @constraint(m, [t = 1:T],
        upper_soc_slack[t] ==
        inputs.soc_max - inputs.gamma * s[t - 1] - inputs.delta_T * inputs.alpha * p[t]
    )
    @constraint(m, [t = 1:T],
        lower_soc_slack[t] ==
        inputs.gamma * s[t - 1] - inputs.delta_T * inputs.beta * g[t] - inputs.soc_min
    )

    @constraint(m, [t = 1:T], p_lb_slack[t] == p[t])
    @constraint(m, [t = 1:T], p_ub_slack[t] == inputs.charge_max - p[t])
    @constraint(m, [t = 1:T], g_lb_slack[t] == g[t])
    @constraint(m, [t = 1:T], g_ub_slack[t] == inputs.discharge_max - g[t])
    @constraint(m, [k = 0:T], s_lb_slack[k] == s[k] - inputs.soc_min)
    @constraint(m, [k = 0:T], s_ub_slack[k] == inputs.soc_max - s[k])
    @constraint(m, [t = 1:T], x_lb_slack[t] == x[t] - inputs.thermal_min)
    @constraint(m, [t = 1:T], x_ub_slack[t] == inputs.thermal_max - x[t])
    @constraint(m, [t = 1:T], r_lb_slack[t] == r[t])
    @constraint(m, [t = 1:T], r_ub_slack[t] == inputs.renewable_capacity[t] - r[t])

    @constraint(m, [t = 1:T],
        inputs.epsilon
        - inputs.delta_T * inputs.alpha * mu[t]
        + inputs.delta_T * inputs.alpha * sigma[t]
        - lambda[t]
        - p_lb_dual[t]
        + p_ub_dual[t]
        == 0
    )

    @constraint(m, [t = 1:T],
        inputs.zeta
        + inputs.delta_T * inputs.beta * mu[t]
        + inputs.delta_T * inputs.beta * tau[t]
        + lambda[t]
        - g_lb_dual[t]
        + g_ub_dual[t]
        == 0
    )

    @constraint(m, [t = 1:T],
        inputs.thermal_offer_price
        + lambda[t]
        - x_lb_dual[t]
        + x_ub_dual[t]
        == 0
    )

    @constraint(m, [t = 1:T],
        inputs.renewable_offer_price
        + lambda[t]
        - r_lb_dual[t]
        + r_ub_dual[t]
        == 0
    )

    @constraint(m,
        nu0
        - inputs.gamma * mu[1]
        + inputs.gamma * sigma[1]
        - inputs.gamma * tau[1]
        - s_lb_dual[0]
        + s_ub_dual[0]
        == 0
    )

    @constraint(m, [k = 1:T-1],
        mu[k]
        - inputs.gamma * mu[k + 1]
        + inputs.gamma * sigma[k + 1]
        - inputs.gamma * tau[k + 1]
        - s_lb_dual[k]
        + s_ub_dual[k]
        == 0
    )

    @constraint(m,
        -inputs.b
        + mu[T]
        - s_lb_dual[T]
        + s_ub_dual[T]
        == 0
    )

    upper_soc_slack_M = inputs.soc_max - inputs.gamma * inputs.soc_min
    lower_soc_slack_M = inputs.gamma * inputs.soc_max - inputs.soc_min
    s_slack_M = inputs.soc_max - inputs.soc_min
    x_slack_M = inputs.thermal_max - inputs.thermal_min

    @constraint(m, [t = 1:T], upper_soc_slack[t] <= upper_soc_slack_M * z_upper_soc[t])
    @constraint(m, [t = 1:T], sigma[t] <= dual_bound * (1 - z_upper_soc[t]))

    @constraint(m, [t = 1:T], lower_soc_slack[t] <= lower_soc_slack_M * z_lower_soc[t])
    @constraint(m, [t = 1:T], tau[t] <= dual_bound * (1 - z_lower_soc[t]))

    @constraint(m, [t = 1:T], p_lb_slack[t] <= inputs.charge_max * z_p_lb[t])
    @constraint(m, [t = 1:T], p_lb_dual[t] <= dual_bound * (1 - z_p_lb[t]))

    @constraint(m, [t = 1:T], p_ub_slack[t] <= inputs.charge_max * z_p_ub[t])
    @constraint(m, [t = 1:T], p_ub_dual[t] <= dual_bound * (1 - z_p_ub[t]))

    @constraint(m, [t = 1:T], g_lb_slack[t] <= inputs.discharge_max * z_g_lb[t])
    @constraint(m, [t = 1:T], g_lb_dual[t] <= dual_bound * (1 - z_g_lb[t]))

    @constraint(m, [t = 1:T], g_ub_slack[t] <= inputs.discharge_max * z_g_ub[t])
    @constraint(m, [t = 1:T], g_ub_dual[t] <= dual_bound * (1 - z_g_ub[t]))

    @constraint(m, [k = 0:T], s_lb_slack[k] <= s_slack_M * z_s_lb[k])
    @constraint(m, [k = 0:T], s_lb_dual[k] <= dual_bound * (1 - z_s_lb[k]))

    @constraint(m, [k = 0:T], s_ub_slack[k] <= s_slack_M * z_s_ub[k])
    @constraint(m, [k = 0:T], s_ub_dual[k] <= dual_bound * (1 - z_s_ub[k]))

    @constraint(m, [t = 1:T], x_lb_slack[t] <= x_slack_M * z_x_lb[t])
    @constraint(m, [t = 1:T], x_lb_dual[t] <= dual_bound * (1 - z_x_lb[t]))

    @constraint(m, [t = 1:T], x_ub_slack[t] <= x_slack_M * z_x_ub[t])
    @constraint(m, [t = 1:T], x_ub_dual[t] <= dual_bound * (1 - z_x_ub[t]))

    @constraint(m, [t = 1:T], r_lb_slack[t] <= inputs.renewable_capacity[t] * z_r_lb[t])
    @constraint(m, [t = 1:T], r_lb_dual[t] <= dual_bound * (1 - z_r_lb[t]))

    @constraint(m, [t = 1:T], r_ub_slack[t] <= inputs.renewable_capacity[t] * z_r_ub[t])
    @constraint(m, [t = 1:T], r_ub_dual[t] <= dual_bound * (1 - z_r_ub[t]))

    m[:kkt_lambda] = lambda
    m[:kkt_mu] = mu
    m[:kkt_sigma] = sigma
    m[:kkt_tau] = tau
    m[:kkt_nu0] = nu0

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

    m[:s_double_bar] = inputs.gamma^T * inputs.soc_init
    
    @objective(m, Min, 
        inputs.thermal_offer_price * sum([x[t] for t = 1:T])
        + inputs.renewable_offer_price * sum([r[t] for t = 1:T])
        + sum(inputs.ess_offers[t] * g[t] for t in 1:T)
        - sum(inputs.ess_bids[t] * p[t] for t in 1:T)
    )

    return m
end
