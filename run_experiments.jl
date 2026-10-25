using Distributed
using Random

@everywhere include(joinpath(@__DIR__, "src", "ESSModels.jl"))
@everywhere using .ESSModels

const EXPERIMENT_OUTPUT_DIR = joinpath(@__DIR__, "outputs", "bim")

function run_base()
    m, net = build_bim_single_bid(inputs_base; silent = true)
    print_results(inputs_base, m, net)

    m, net = build_bim_multi_bid(inputs_base; silent = true)
    print_results(inputs_base, m, net)
end

function run_noisy_offers(;
    bid_perfect_foresight::Bool = false,
    n_samples::Int = 10_000,
    b::Float64 = 40.0,
    sigma::Float64 = 5.0,
    seed::Int = 42,
    output_dir::AbstractString = EXPERIMENT_OUTPUT_DIR,
)
    paths = run_noisy_offer_experiment(replace_inputs(inputs_base; b = b);
        n_samples = n_samples, sigma = sigma, seed = seed,
        multi_output_csv = joinpath(output_dir, "noisy_offer_multibid_results.csv"),
        single_output_csv = joinpath(output_dir, "noisy_offer_singlebid_results.csv"),
        bid_perfect_foresight = bid_perfect_foresight)
    println("Wrote noisy-offer results to: $(paths)")
    return paths
end

function run_uniform_error(;
    bid_perfect_foresight::Bool = false,
    n_samples::Int = 10_000,
    b::Float64 = 40.0,
    error_range::Float64 = 20.0,
    seed::Int = 42,
    output_dir::AbstractString = EXPERIMENT_OUTPUT_DIR,
)
    Random.seed!(seed)
    paths = run_uniform_error_multibid_experiment(replace_inputs(inputs_base; b = b);
        n_samples = n_samples, error_range = error_range,
        output_csv = joinpath(output_dir, "uniform_error_multibid_results.csv"),
        bid_perfect_foresight = bid_perfect_foresight)
    println("Wrote uniform-error results to: $(paths.output_csv)")
    return paths
end

"""Generate per-b CSVs for one sigma, as used by the notebook's sweep comparisons."""
function run_noisy_offer_sweep(;
    sigma::Float64 = 15.0,
    b_values = (0.0, 20.0, 40.0, 60.0),
    bid_perfect_foresight::Bool = false,
    n_samples::Int = 10_000,
    seed::Int = 42,
    output_dir::AbstractString = EXPERIMENT_OUTPUT_DIR,
)
    directory = sigma == 5.0 ? output_dir : joinpath(output_dir, "sigma_$(Int(sigma))")
    for b in b_values
        paths = run_noisy_offer_experiment(replace_inputs(inputs_base; b = b);
            n_samples = n_samples, sigma = sigma, seed = seed,
            multi_output_csv = joinpath(directory, "noisy_offer_multibid_results_b$(Float64(b)).csv"),
            single_output_csv = joinpath(directory, "noisy_offer_singlebid_results_b$(Float64(b)).csv"),
            bid_perfect_foresight = bid_perfect_foresight)
        println("Wrote noisy-offer sweep results to: $(paths)")
    end
    return directory
end

"""Generate every CSV used by notebooks/plot_experiments.ipynb."""
function run_plot_experiments(;
    n_samples::Int = 10_000,
    selected_b::Float64 = 40.0,
    output_dir::AbstractString = EXPERIMENT_OUTPUT_DIR,
)
    n_samples > 0 || throw(ArgumentError("n_samples must be positive"))
    for foresight in (false, true)
        run_noisy_offers(; n_samples, b = selected_b, output_dir, bid_perfect_foresight = foresight)
        run_uniform_error(; n_samples, b = selected_b, output_dir, bid_perfect_foresight = foresight)
    end
    for sigma in (5.0, 15.0, 35.0)
        run_noisy_offer_sweep(; n_samples, sigma, output_dir)
    end
    println("Results ready for plotting in: $(abspath(output_dir))")
    return output_dir
end

# julia --project=. --threads=1 -p 6 run_experiments.jl
# run_base()
run_noisy_offers(bid_perfect_foresight = true)
run_uniform_error(bid_perfect_foresight = true)
run_noisy_offers(bid_perfect_foresight = false)
run_uniform_error(bid_perfect_foresight = false)
