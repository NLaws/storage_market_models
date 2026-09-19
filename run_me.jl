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


    m = build_multi_bid_model(inputs_base)
    set_silent(m)

    optimize!(m)
    print_results(inputs_base, m)

end

function run_noisy_offers(;bid_perfect_foresight::Bool)
    for b in [0.0, 20.0, 40.0, 60.0]
        inputs = replace_inputs(inputs_base; b = b)
        output_paths = run_noisy_offer_experiment(
            inputs;
            n_samples = 10000,
            sigma = 15.0,
            seed = 42,
            multi_output_csv = "outputs/sigma_15/noisy_offer_multibid_results_b$(b).csv",
            single_output_csv = "outputs/sigma_15/noisy_offer_singlebid_results_b$(b).csv",
            bid_perfect_foresight = bid_perfect_foresight,
        )
        println("Wrote noisy-offer multibid results to: $(output_paths.multi_output_csv)")
        println("Wrote noisy-offer singlebid results to: $(output_paths.single_output_csv)")
    end
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
# run_base()
# run_noisy_offers(bid_perfect_foresight = true)
# run_uniform_error(bid_perfect_foresight = true)
run_noisy_offers(bid_perfect_foresight = false)
# run_uniform_error(bid_perfect_foresight = false)
