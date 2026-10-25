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

# julia --project=. --threads=1 -p 6 run_experiments.jl
# run_base()
run_uniform_error(bid_perfect_foresight = true)
run_uniform_error(bid_perfect_foresight = false)
