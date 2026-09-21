# inputs.jl
using XLSX, DataFrames

function load_model_data(data_dir::String, instances_per_type::Int)
    println("--- Step 1: Loading and Processing Excel Sheets ---")
    
    # Read raw data
    df_trucks    = DataFrame(XLSX.readtable(joinpath(data_dir, "truck_types.xlsx"), 1))
    df_chargers  = DataFrame(XLSX.readtable(joinpath(data_dir, "charging_infrastructure.xlsx"), 1))
    df_co2       = DataFrame(XLSX.readtable(joinpath(data_dir, "CO2_accounting.xlsx"), 1))
    df_nodes     = DataFrame(XLSX.readtable(joinpath(data_dir, "nodes_demand_service_time.xlsx"), 1))
    
    raw_dm_file  = XLSX.readxlsx(joinpath(data_dir, "distance_matrix.xlsx"))
    raw_dm       = raw_dm_file[1][:]

    # Extract single-value parameters
    params = Dict(
        :gamma_D    => Float64(df_co2[1, :diesel_emissions_factor_kgCO2_per_litre]),
        :gamma_E    => Float64(df_co2[1, :electricity_emissions_factor_kgCO2_per_kWh]),
        :lambda_co2 => Float64(df_co2[1, :monetary_value_of_CO2_emissions_euros_per_kgCO2]),
        :p_diesel   => Float64(first(skipmissing(df_trucks.diesel_cost_euros_per_litre))),
        :p_el       => Float64(first(skipmissing(df_trucks.electricity_cost_euros_per_kWh)))
    )

    # Sets definition
    N_nodes = size(df_nodes, 1)
    N_set = 1:N_nodes          
    I_set = 2:N_nodes # Assuming row 1 is always depot
    M_set = 1:size(df_chargers, 1)

    # Process distance matrix 
    d = zeros(N_nodes, N_nodes)
    for i in 1:N_nodes
        orig_i = df_nodes[i, :node_ID] + 1 
        for j in 1:N_nodes
            orig_j = df_nodes[j, :node_ID] + 1
            d[i, j] = Float64(raw_dm[orig_i, orig_j])
        end
    end

    # Node parameters: demand and service time
    q = Dict(i => Float64(df_nodes[i, :demand_tonnes]) for i in N_set)
    s_service = Dict(i => Float64(df_nodes[i, :service_time_minutes]) for i in N_set)

    # Generate candidate vehicle sets: each truck must be tracked and evaluated
    # at each node (useful for electric trucks SOC tracking)
    K_D, K_E = Int[], Int[]
    truck_params = Dict(:Q => Dict{Int, Float64}(), :f_capex => Dict{Int, Float64}(), 
                        :EC_D => Dict{Int, Float64}(), :EC_E => Dict{Int, Float64}(), 
                        :Wage => Dict{Int, Float64}(), :Maint => Dict{Int, Float64}(), 
                        :Toll => Dict{Int, Float64}(), :E_cap => Dict{Int, Float64}(), 
                        :SOC_min => Dict{Int, Float64}(), :SOC_max => Dict{Int, Float64}(), 
                        :speed => Dict{Int, Float64}())
    
    truck_types_map = Dict{Int, String}()
    truck_counter = 1
    
    for (row_idx, row) in enumerate(eachrow(df_trucks))
        is_ev = !ismissing(row.net_battery_capacity_kWh) && row.net_battery_capacity_kWh > 0
        for inst in 1:instances_per_type
            k = truck_counter
            truck_types_map[k] = String(row.truck_type)
            if is_ev
                push!(K_E, k)
                truck_params[:EC_E][k] = Float64(row.electricity_consumption_kWh_per_km)
                truck_params[:E_cap][k] = Float64(row.net_battery_capacity_kWh)
                truck_params[:SOC_min][k] = Float64(row.SOC_min)
                truck_params[:SOC_max][k] = Float64(row.SOC_max)
            else
                push!(K_D, k)
                truck_params[:EC_D][k] = Float64(row.diesel_consumption_litres_per_km)
            end
            truck_params[:Toll][k] = ismissing(row.tolls_euros_per_km) ? 0.0 : Float64(row.tolls_euros_per_km)
            truck_params[:Q][k] = Float64(row.weight_capacity_tonnes)
            truck_params[:f_capex][k] = Float64(row.daily_CAPEX_euros_per_day)
            truck_params[:Wage][k] = Float64(row.driver_wage_euros_per_hour)
            truck_params[:Maint][k] = Float64(row.maintenance_euros_per_km)
            truck_params[:speed][k] = Float64(row.average_travel_speed_km_per_hour)
            truck_counter += 1
        end
    end
    K_set = vcat(K_E, K_D)

    # Charger mapping
    eta_m = Dict(m => Float64(df_chargers[m, :power_output_capacity_kW]) for m in M_set)
    f_m   = Dict(m => Float64(df_chargers[m, :TCO_per_charing_point_per_day_euros]) for m in M_set)
    charger_names = Dict(m => String(df_chargers[m, :charger_type]) for m in M_set)

    # Package everything into a NamedTuple for easy passing
    return (
        N_set=N_set, I_set=I_set, M_set=M_set, K_set=K_set, K_D=K_D, K_E=K_E,
        d=d, q=q, s_service=s_service, params=params, tp=truck_params, 
        eta_m=eta_m, f_m=f_m, df_trucks=df_trucks, truck_map=truck_types_map,
        charger_names=charger_names
    )
end