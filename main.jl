# main.jl
include("inputs.jl")
include("model.jl")
include("results.jl")
include("plots.jl")  

const DATA_DIR = @__DIR__
const PLOTS_DIR = joinpath(DATA_DIR, "plots")
const INSTANCES_PER_TYPE = 4 

function main()
    mkpath(PLOTS_DIR)
    data = load_model_data(DATA_DIR, INSTANCES_PER_TYPE)
    
    alphas = [0.0, 0.5, 1.0]
    all_results = Dict{Float64, Dict}()
    
    for alpha in alphas
        model, status, fuel_d, energy_e, co2_d, co2_e = build_and_solve_model(data, alpha)
        
        if status == MOI.OPTIMAL || (status == MOI.TIME_LIMIT && has_values(model))
            println("Solution accepted for alpha = ", alpha)
            exprs = (fuel_d, energy_e, co2_d, co2_e)
            all_results[alpha] = extract_metrics(model, data, alpha, exprs, status)
        else
            println("Warning: Infeasible or no valid solution found before time limit for alpha = ", alpha)
        end
    end
    
    if !isempty(all_results)
        # 1. Export data to Excel
        export_to_excel(all_results, joinpath(PLOTS_DIR, "optimised_results.xlsx"))
        
        # 2. Generate plots
        generate_plots(all_results, PLOTS_DIR)
    else
        println("No optimal configurations found.")
    end
end

main()