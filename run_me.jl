include("./src/ESSModels.jl")
using .ESSModels
using JuMP


function run_base()
    m = build_time_coupled_model(inputs_base)
    optimize!(m)
    print_results(inputs_base, m)
    return m
end

run_base()
