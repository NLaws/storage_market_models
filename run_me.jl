using Distributed

if nworkers() == 0
    n_local_workers = max(Sys.CPU_THREADS - 1, 1)
    addprocs(
        n_local_workers;
        exeflags = "--project=$(Base.active_project()) --threads=1",
    )
end

@everywhere include(joinpath(@__DIR__, "src", "ESSModels.jl"))
@everywhere using .ESSModels

using .ESSModels
using JuMP


function run_base()
    m = build_single_bid_model(inputs_base)
    set_silent(m)

    optimize!(m)
    print_results(inputs_base, m)

    z_star = objective_value(m)

    # show that the price at t=1 can be zero by not using all the renewable energy at t=1
    # technically this raises the cost by a tiny amount
    @constraint(m, m[:p][1] <= 100 - 1e-6)

    # show that price at t=6 can be 41 by leaving a tiny amount of energy in the battery for t=6
    # s.t. thermal is not the marginal resource at t=6
    @constraint(m, m[:g][5] <= 100 - 1e-6)

    optimize!(m)
    print_results(inputs_base, m)

    z_star ≈ objective_value(m) || error("Objective value changed after adding constraints to manipulate prices. Original: $z_star, New: $(objective_value(m))")

end


function run_noisy_offers(;bid_perfect_foresight::Bool)
    output_paths = run_noisy_offer_experiment(
        inputs_base;
        n_samples = 10000,
        sigma = 10.0,
        max_willingness_to_pay = 60.0,
        min_willingness_to_pay = 0.0,
        seed = 42,
        multi_output_csv = "outputs/noisy_offer_multibid_results.csv",
        single_output_csv = "outputs/noisy_offer_singlebid_results.csv",
        bid_perfect_foresight = bid_perfect_foresight,

    )
    println("Wrote noisy-offer multibid results to: $(output_paths.multi_output_csv)")
    println("Wrote noisy-offer singlebid results to: $(output_paths.single_output_csv)")
end


function run_uniform_error(;bid_perfect_foresight::Bool)
    output_path = run_uniform_error_multibid_experiment(
        inputs_base;
        n_samples = 10000,
        error_range = 20.0,
        output_csv = "outputs/uniform_error_multibid_results.csv",
        bid_perfect_foresight = bid_perfect_foresight,
    )
    println("Wrote uniform-error multibid results to: $(output_path.output_csv)")
end


# julia --project=. -p 6 run_me.jl
run_base()
# run_noisy_offers(bid_perfect_foresight = true)
# run_uniform_error(bid_perfect_foresight = true)
# run_noisy_offers(bid_perfect_foresight = false)
# run_uniform_error(bid_perfect_foresight = false)
