@testset "DC Copper Plate" begin
    # base case single bid model with $40 terminal SOC bid, $1 charging/discharging costs, and a 6-period horizon.
    network_path = joinpath(@__DIR__, "..", "src", "networks", "base-single-ess.yaml")
    charging_cost = 1.0
    discharging_cost = 1.0
    terminal_soc_bid = 40.0
    inputs = ESSModels.BIMInputs(
        offer_prices = Dict("thermal" => fill(50.0, 6), "renewable" => zeros(6)),
        charging_cost = Dict("battery" => fill(charging_cost, 6)),
        discharging_cost = Dict("battery" => fill(discharging_cost, 6)),
        ess_bids = Dict("battery" => [43.1, 50.0, 0.0, 0.0, 50.0, 40.0]),
        ess_offers = Dict("battery" => [43.1, 50.0, 0.0, 0.0, 49.9, 49.9]),
        net_soc_bid = Dict("battery" => fill(terminal_soc_bid, 6)),
    )
    m, net = ESSModels.build_copper_plate_single_bid_model(inputs, network_path)

    @test JuMP.termination_status(m) == JuMP.OPTIMAL

    # Convert the load-balance dual to an energy price using the objective's time scaling.
    prices = dual.(m[:load_balance]) * net.time_steps_per_hour
    discharge = value.(m[:p_discharge]["b1"]["battery"])
    charge = value.(m[:p_charge]["b1"]["battery"])
    thermal = value.(m[:p_gen]["b1"]["thermal"])
    renewable = value.(m[:p_gen]["b1"]["renewable"])
    soc = value.(m[:soc]["b1"]["battery"])
    terminal_soc_value = terminal_soc_bid * (soc[net.Ntimesteps] - soc[0])

    @test isapprox(prices, [38.69, 50.0, 0.0, 0.0, 50.0, 50.0], atol = 1e-2)

    ess_surplus = discharge' * prices - charge' * prices -
        charging_cost * sum(charge) - discharging_cost * sum(discharge)
    ess_surplus = round(ess_surplus / net.time_steps_per_hour + terminal_soc_value, digits = 2)
    # Use unrounded solver values when computing surplus.
    @test isapprox(ess_surplus, 34391.11, atol = 1e-2)

    # Charging and renewable dispatch are unique for this case.
    @test isapprox(charge, [100.0, 0.0, 200.0, 22.2222, 0.0, 0.0], atol = 1e-2)
    @test isapprox(renewable, [200.0, 100.0, 500.0, 322.2222, 25.0, 0.0], atol = 1e-2)

    # Discharge and thermal dispatch are unique through period 4.
    @test isapprox(discharge[1:4], [0.0, 81.0, 0.0, 0.0], atol = 1e-2)
    @test isapprox(thermal[1:4], [0.0, 19.0, 0.0, 0.0], atol = 1e-2)

    # Equal prices and operating costs make the period-5/6 split non-unique.
    # Test invariant totals instead of a solver-specific dispatch split.
    @test isapprox(sum(discharge[5:6]), 180.0, atol = 1e-2)
    @test isapprox(sum(thermal[5:6]), 95.0, atol = 1e-2)
    @test isapprox(sum(discharge), 261.0, atol = 1e-2)
    @test isapprox(sum(thermal), 114.0, atol = 1e-2)

    # SOC is unique through period 4, and every optimum fully discharges by period 6.
    @test isapprox([soc[t] for t in 1:4], [360.0, 0.0, 720.0, 800.0], atol = 1e-2)
    @test isapprox(soc[net.Ntimesteps], 0.0, atol = 1e-2)
    @test isapprox(objective_value(m), 25132.89, atol = 1e-2)
end
