using CSV
using DataFrames
using Random

@testset "Multiple-battery experiments" begin
    inputs = replace_inputs(inputs_multiple_ess; b = 0.0)
    original_bids = deepcopy(inputs.ess_bids)
    original_offers = deepcopy(inputs.ess_offers)
    m, net = build_bim_single_bid(inputs, MULTIPLE_ESS_NETWORK_PATH; silent = true)
    reference = collect_results(inputs, m, net)
    @test Set(keys(reference.battery_data)) == Set(["battery1", "battery2"])
    @test reference.data.Charge ≈ round.(sum(b.charge for b in values(reference.battery_data)); digits = 2)
    @test reference.ess_surplus ≈ round(sum(b.surplus for b in values(reference.battery_data)); digits = 2)

    mktempdir() do dir
        function experiment(name; foresight = false, error_range = 20.0)
            Random.seed!(123)
            paths = run_uniform_error_multibid_experiment(inputs;
                network_file_path = MULTIPLE_ESS_NETWORK_PATH, n_samples = 3,
                error_range, output_csv = joinpath(dir, name * ".csv"),
                bid_perfect_foresight = foresight, show_progress = false)
            CSV.read(paths.output_csv, DataFrame)
        end
        df = experiment("first")
        @test nrow(df) == 3 * 2 * net.Ntimesteps
        @test allunique(select(df, :sample, :battery, :time))
        @test all(abs.(df.noise) .<= 20.0)
        @test df.ess_offer ≈ round.(max.(df.optimized_price .+ df.noise, 0.0); digits = 4) atol = 1e-4
        @test df[df.battery .== "battery1", :noise] != df[df.battery .== "battery2", :noise]
        @test df == experiment("repeat")
        for rows in groupby(df, [:sample, :time])
            @test all(==(rows.price[1]), rows.price)
            @test all(==(rows.ess_surplus[1]), rows.ess_surplus)
            @test rows.thermal[1] + rows.renewable[1] + sum(rows.discharge) - sum(rows.charge) ≈ rows.demand[1] atol = 0.02
        end
        for rows in groupby(df, :sample)
            batteries = unique(select(rows, :battery, :battery_surplus, :battery_profit))
            @test sum(batteries.battery_surplus) ≈ rows.ess_surplus[1] atol = 0.011
            @test sum(batteries.battery_profit) ≈ rows.ess_profit[1] atol = 0.011
        end
        perfect = experiment("foresight"; foresight = true)
        for row in eachrow(perfect)
            expected = reference.battery_data[row.battery].charge[row.time] > 0 ? 0.0 : inputs.ess_bids[row.battery][row.time]
            @test row.ess_bid == expected
        end
        @test all(iszero, experiment("zero"; error_range = 0.0).noise)
        @test inputs.ess_bids == original_bids
        @test inputs.ess_offers == original_offers
        @test_throws ArgumentError run_uniform_error_multibid_experiment(inputs; n_samples = 0)
        @test_throws ArgumentError run_uniform_error_multibid_experiment(inputs; error_range = -1.0)
    end
end
