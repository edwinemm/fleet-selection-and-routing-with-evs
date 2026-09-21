# results.jl
using DataFrames, XLSX, JuMP

function extract_metrics(model, data, alpha_val, exprs, status)
    Fuel_D, Energy_E, E_CO2_D, E_CO2_E = exprs
    N, I, M, K, KD, KE = data.N_set, data.I_set, data.M_set, data.K_set, data.K_D, data.K_E
    tp, p = data.tp, data.params
    
    y_D = value.(model[:y_D])
    y_E = value.(model[:y_E])
    x   = value.(model[:x])
    tau = value.(model[:tau]) # Only defined for i in I
    z   = value.(model[:z])
    h   = value.(model[:h])
    run_time_sec = solve_time(model)

    df_trucks_out = DataFrame(
        Alpha = Float64[], Powertrain = String[], Truck_Number = Int[], Truck_Type = String[], 
        Nodes_Visited = String[], Total_Payload_Carried_t = Float64[], Total_Distance_km = Float64[], 
        Total_Driving_Time_h = Float64[], Total_Service_Time_m = Float64[], Total_Charging_Time_m = Float64[], 
        Charging_Locations = String[], Total_Driver_Wage_EUR = Float64[], Total_Toll_Costs_EUR = Float64[], 
        Total_Maintenance_Costs_EUR = Float64[], Total_CO2_Emissions_kg = Float64[]
    )
    
    df_profiles_out = DataFrame(
        Alpha = Float64[], Truck_Type = String[], Truck_ID = Int[], Powertrain = String[], 
        Node = String[], Cumulative_Distance_km = Float64[], 
        Arrival_SOC = Float64[], Departure_SOC = Float64[], 
        Cumulative_Fuel_L = Float64[], Cumulative_Energy_kWh = Float64[],
        Min_SOC = Float64[] 
    )
    
    n_ev_selected, n_diesel_selected, n_ev_active, n_diesel_active = 0, 0, 0, 0
    wages_total, maint_total, tolls_total = 0.0, 0.0, 0.0
    dist_ev, dist_diesel = 0.0, 0.0          
    payload_ev, payload_diesel = 0.0, 0.0    
    
    purch_ev_names = String[]
    purch_diesel_names = String[]
    active_ev_names = String[]
    active_diesel_names = String[]
    
    for k in K
        is_ev = (k in KE)
        powertrain = is_ev ? "EV" : "Diesel"
        
        if is_ev && y_E[k] > 0.5
            n_ev_selected += 1
            push!(purch_ev_names, data.truck_map[k])
        elseif !is_ev && y_D[k] > 0.5
            n_diesel_selected += 1
            push!(purch_diesel_names, data.truck_map[k])
        end
    
        is_active = sum(x[1, j, k] for j in I) > 0.5
        if is_active
            if is_ev 
                n_ev_active += 1 
                push!(active_ev_names, data.truck_map[k])
            else 
                n_diesel_active += 1 
                push!(active_diesel_names, data.truck_map[k])
            end
            
            route, current_node, max_safe = [1], 1, length(N) + 1
            while true
                if length(route) > max_safe break end
                next_node = nothing
                for j in N
                    if current_node != j && x[current_node, j, k] > 0.5
                        next_node = j; break
                    end
                end
                if next_node === nothing || next_node == 1
                    push!(route, 1); break
                else
                    push!(route, next_node); current_node = next_node
                end
            end
    
            dist = sum(data.d[route[idx], route[idx+1]] for idx in 1:(length(route)-1))
            payload = sum(data.q[n] for n in route if n != 1; init=0.0)
            t_service = sum(data.s_service[n] for n in route if n != 1)
            t_charge = is_ev ? sum(tau[n, m, k] for n in route, m in M if n != 1) : 0.0
            
            if is_ev
                dist_ev += dist
                payload_ev += payload
            else
                dist_diesel += dist
                payload_diesel += payload
            end
            
            tr_wage  = (tp[:Wage][k] / 60.0) * ((dist / tp[:speed][k] * 60.0) + t_service + t_charge)
            tr_toll  = tp[:Toll][k] * dist
            tr_maint = tp[:Maint][k] * dist
            
            wages_total += tr_wage
            tolls_total += tr_toll
            maint_total += tr_maint
    
            tr_co2 = is_ev ? p[:gamma_E] * sum(h[n, m, k] for n in route, m in M) : p[:gamma_D] * (tp[:EC_D][k] * dist)
    
            push!(df_trucks_out, (
                alpha_val, powertrain, k, data.truck_map[k], join(route .- 1, " -> "), 
                payload, dist, 
                sum(data.d[route[idx], route[idx+1]] / tp[:speed][k] for idx in 1:(length(route)-1)), 
                t_service, t_charge, is_ev ? "Yes" : "None", 
                tr_wage, tr_toll, tr_maint, tr_co2
            ))
    
            # --- TELEMETRY TRACKING ---
            curr_dist = 0.0
            curr_fuel = 0.0
            curr_energy = is_ev ? (tp[:SOC_max][k] * tp[:E_cap][k]) : 0.0
            curr_energy_used = 0.0
    
            for idx in 1:length(route)
                curr_node = route[idx]
                node_name = curr_node == 1 ? "Depot" : string(curr_node - 1)
    
                if is_ev
                    charge_amt = (curr_node == 1 && idx == 1) ? 0.0 : sum(value(h[curr_node, m, k]) for m in M)
                    
                    arrival_soc = curr_energy / tp[:E_cap][k]
                    departure_soc = (curr_energy + charge_amt) / tp[:E_cap][k]
    
                    push!(df_profiles_out, (
                        alpha_val, data.truck_map[k], k, "EV", node_name, 
                        curr_dist, arrival_soc, departure_soc, 0.0, curr_energy_used, tp[:SOC_min][k]
                    ))
    
                    if idx < length(route)
                        next_node = route[idx+1]
                        trip_eng = tp[:EC_E][k] * data.d[curr_node, next_node]
                        curr_energy = curr_energy + charge_amt - trip_eng
                        curr_energy_used += trip_eng
                        curr_dist += data.d[curr_node, next_node]
                    end
                else
                    push!(df_profiles_out, (
                        alpha_val, data.truck_map[k], k, "Diesel", node_name, 
                        curr_dist, 0.0, 0.0, curr_fuel, 0.0, 0.0
                    ))
    
                    if idx < length(route)
                        next_node = route[idx+1]
                        curr_fuel += tp[:EC_D][k] * data.d[curr_node, next_node]
                        curr_dist += data.d[curr_node, next_node]
                    end
                end
            end
        end
    end
    
    inf_capex = sum(data.f_m[m] * z[s, m] for s in N, m in M)
    d_opex = p[:p_diesel] * value(Fuel_D)
    p_el_depot = 0.18 # Must match in model.jl
    e_opex = sum((s == 1 ? p_el_depot : p[:p_el]) * value(Energy_E[s]) for s in N) # <--- CHANGED LINE
    total_cost = objective_value(model)
    tot_emiss = value(E_CO2_D) + value(E_CO2_E)
    
    co2_cost = p[:lambda_co2] * tot_emiss
    
    tot_purchased = n_ev_selected + n_diesel_selected
    tot_active    = n_ev_active + n_diesel_active
    tot_dist      = dist_ev + dist_diesel
    tot_payload   = payload_ev + payload_diesel
    
    alpha_purchased = tot_purchased > 0 ? (n_ev_selected / tot_purchased) : 0.0
    alpha_active    = tot_active > 0    ? (n_ev_active / tot_active) : 0.0
    alpha_distance  = tot_dist > 0.0    ? (dist_ev / tot_dist) : 0.0
    alpha_payload   = tot_payload > 0.0 ? (payload_ev / tot_payload) : 0.0
    
    str_purch_ev = isempty(purch_ev_names) ? "None" : join(purch_ev_names, ", ")
    str_purch_diesel = isempty(purch_diesel_names) ? "None" : join(purch_diesel_names, ", ")
    str_active_ev = isempty(active_ev_names) ? "None" : join(active_ev_names, ", ")
    str_active_diesel = isempty(active_diesel_names) ? "None" : join(active_diesel_names, ", ")
    
    df_fleet_out = DataFrame(
        Metric = [
            "Solver Termination Status",
            "Solver Runtime (seconds)",
            "Total Generalized Cost (EUR)", "Total Fleet Emissions (kg CO2)",
            "CO2 Penalty Cost (EUR)", 
            "Veh CAPEX Diesel (EUR)", "Veh CAPEX EV (EUR)", "Infra CAPEX (EUR)",
            "Diesel OPEX (EUR)", "Electricity OPEX (EUR)", "Wages (EUR)", "Tolls (EUR)", "Maintenance (EUR)",
            "Purchased EVs", "Purchased EV Models",
            "Purchased Diesels", "Purchased Diesel Models",
            "Active EVs", "Active EV Models",
            "Active Diesels", "Active Diesel Models",
            "Target Policy Alpha",
            "Actual Alpha (Purchased Count)", 
            "Actual Alpha (Active Count)", 
            "Actual Alpha (Distance Driven)", 
            "Actual Alpha (Payload Delivered)",
            "alpha_number",     
            "alpha_distance"    
        ],
        Value = [
            string(status),
            run_time_sec,
            total_cost, tot_emiss,
            co2_cost, 
            sum(tp[:f_capex][k] * y_D[k] for k in KD), sum(tp[:f_capex][k] * y_E[k] for k in KE),
            inf_capex, d_opex, e_opex, wages_total, tolls_total, maint_total,
            Float64(n_ev_selected), str_purch_ev,             
            Float64(n_diesel_selected), str_purch_diesel,     
            Float64(n_ev_active), str_active_ev,              
            Float64(n_diesel_active), str_active_diesel,      
            Float64(alpha_val),
            alpha_purchased, alpha_active, alpha_distance, alpha_payload,
            alpha_active,       # Mapped to Active Fleet Count
            alpha_distance      # Mapped to Distance Driven
        ]
    )
    
    df_infra_out = DataFrame(Alpha = Float64[], Node = Int[], Charger_Type = String[], Installed = Int[], Energy_kWh = Float64[], Utilisation_Pct = Float64[])
    
    for s in N, m in M
        if z[s, m] > 0.5
            installed_qty = Int(round(z[s, m]))
            energy_delivered = sum(h[s, m, k] for k in KE)
            
            # tau[1] is no longer tracked, so depot chargers utilization is based purely on kWh delivered
            time_used = s == 1 ? (energy_delivered / data.eta_m[m]) * 60.0 : sum(tau[s, m, k] for k in KE)
            available_time = s == 1 ? 720.0 : 480.0 # Depot charger available for 12 hours overnight
            
            util_pct = (time_used / (available_time * installed_qty)) * 100.0
            
            push!(df_infra_out, (alpha_val, s - 1, data.charger_names[m], installed_qty, energy_delivered, util_pct))
        end
    end
    
    return Dict("trucks" => df_trucks_out, "fleet" => df_fleet_out, "infra" => df_infra_out, "profiles" => df_profiles_out, "cost" => total_cost, "emissions" => tot_emiss)
end

function export_to_excel(all_results, file_path)
    XLSX.openxlsx(file_path, mode="w") do xf
        first_sheet = true
        for alpha_val in sort(collect(keys(all_results)))
            alpha_str = replace(string(alpha_val), "." => "_")
            if first_sheet
                XLSX.rename!(xf[1], "A_$(alpha_str)_Trucks"); first_sheet = false
            else
                XLSX.addsheet!(xf, "A_$(alpha_str)_Trucks")
            end
            XLSX.writetable!(xf["A_$(alpha_str)_Trucks"], all_results[alpha_val]["trucks"])
    
            XLSX.addsheet!(xf, "A_$(alpha_str)_Fleet")
            XLSX.writetable!(xf["A_$(alpha_str)_Fleet"], all_results[alpha_val]["fleet"])
    
            XLSX.addsheet!(xf, "A_$(alpha_str)_Infra")
            XLSX.writetable!(xf["A_$(alpha_str)_Infra"], all_results[alpha_val]["infra"])
    
            XLSX.addsheet!(xf, "A_$(alpha_str)_Profiles")
            XLSX.writetable!(xf["A_$(alpha_str)_Profiles"], all_results[alpha_val]["profiles"])
        end
    end
    println("Results exported to Excel: ", file_path)
end