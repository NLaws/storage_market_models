include("./src/ESSModels.jl")
using .ESSModels
using JuMP


function run_base()
    m = build_single_bid_model(inputs_base)
    optimize!(m)
    print_results(inputs_base, m)


    m = build_multi_bid_model(inputs_base)
    optimize!(m)
    print_results(inputs_base, m)

end

run_base()
