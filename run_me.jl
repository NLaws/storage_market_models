include("./src/ESSModels.jl")
using .ESSModels
using JuMP


function run_base()
    m = build_model(inputs_base)
    optimize!(m)
    print_results(m)
    return m
end

run_base()
