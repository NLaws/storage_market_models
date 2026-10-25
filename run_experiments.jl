using Distributed
using Random
using CSV
using DataFrames

@everywhere include(joinpath(@__DIR__, "src", "ESSModels.jl"))
@everywhere using .ESSModels

const EXPERIMENT_OUTPUT_DIR = joinpath(@__DIR__, "outputs", "bim")

function run_base()
    m, net = build_bim_single_bid(inputs_base; silent = true)
    print_results(inputs_base, m, net)

    m, net = build_bim_multi_bid(inputs_base; silent = true)
    print_results(inputs_base, m, net)
end


function run_uniform_error_multibid(;
        inputs::BIMInputs = inputs_base,
        network_file_path::AbstractString = BASE_NETWORK_PATH,
        bid_perfect_foresight::Bool = false,
        n_samples::Int = 10_000,
        b::Float64 = 0.0,  # b is used for perfect foresight only, should be zero b/c multibid has no future value?
        error_range::Float64 = 20.0,
        seed::Int = 42,
        output_dir::AbstractString = EXPERIMENT_OUTPUT_DIR,
    )
    Random.seed!(seed)
    fname = "uniform_error_multibid_results_$(inputs.experiment_name)_b$(b)_n$(n_samples)_e$(error_range).csv"

    paths = run_uniform_error_multibid_experiment(
        replace_inputs(inputs; b = b);
        network_file_path = network_file_path,
        n_samples = n_samples, error_range = error_range,
        output_csv = joinpath(output_dir, fname),
        bid_perfect_foresight = bid_perfect_foresight
    )
    println("Wrote uniform-error results to: $(paths.output_csv)")
    return paths
end


"""Solve the single-bid model once per terminal SOC bid and save its results."""
function run_single_bid(;
        inputs::BIMInputs = inputs_base,
        network_file_path::AbstractString = BASE_NETWORK_PATH,
        b_values::AbstractVector{<:Real} = [0.0],
        output_dir::AbstractString = EXPERIMENT_OUTPUT_DIR,
    )
    paths = String[]
    for b in b_values
        sample_inputs = replace_inputs(inputs; b = b)
        m, net = build_bim_single_bid(sample_inputs, network_file_path; silent = true)
        ESSModels.assert_sample_has_solution(m, length(paths) + 1, "single_bid b=$(b)")
        results = collect_results(sample_inputs, m, net)
        isnothing(results) && error("Could not collect single-bid results for b=$(b)")

        data = DataFrame(results.data)
        data.b .= Float64(b)
        for metric in (:objective_value, :ess_surplus, :ess_profit, :cost_to_serve, :actual_cost)
            data[!, metric] .= getproperty(results, metric)
        end
        output_csv = joinpath(
            output_dir,
            "singlebid_results_$(inputs.experiment_name)_b$(b).csv",
        )
        mkpath(dirname(output_csv))
        CSV.write(output_csv, data)
        push!(paths, output_csv)
        println("Wrote single-bid results to: $(output_csv)")
    end
    return paths
end

# julia --project=. --threads=1 -p 6 run_experiments.jl
# run_base()
# run_uniform_error_multibid(bid_perfect_foresight = true)
run_uniform_error_multibid(bid_perfect_foresight = false)
# run_single_bid(b_values = [0.0, 10.0, 20.0, 30.0, 40.0, 50.0])