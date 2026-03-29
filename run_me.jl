include("./src/ESSModels.jl")
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

function run_noisy_offers()
    output_paths = run_noisy_offer_experiment(
        inputs_base;
        n_samples = 10000,
        sigma = 10.0,
        max_willingness_to_pay = 60.0,
        min_willingness_to_pay = 0.0,
        seed = 42,
        multi_output_csv = "outputs/noisy_offer_multibid_results.csv",
        single_output_csv = "outputs/noisy_offer_singlebid_results.csv",
    )
    println("Wrote noisy-offer multibid results to: $(output_paths.multi_output_csv)")
    println("Wrote noisy-offer singlebid results to: $(output_paths.single_output_csv)")
end

# run_base()
run_noisy_offers()
