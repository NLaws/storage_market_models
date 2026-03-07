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
    output_csv = run_noisy_offer_experiment(
        inputs_base;
        n_samples = 5,
        sigma = 5.0,
        seed = 42,
        output_csv = "outputs/noisy_offer_results.csv",
    )
    println("Wrote noisy-offer experiment results to: $(output_csv)")
end

# run_base()
run_noisy_offers()
