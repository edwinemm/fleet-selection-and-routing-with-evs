# plots.jl
using Plots, DataFrames, StatsPlots

default(
    titlefont   = font(16, "sans-serif"),  # Main figure title
    guidefont   = font(14, "sans-serif"),  # X and Y axis titles
    tickfont    = font(12, "sans-serif"),  # Numbers on X and Y axes
    legendfont  = font(11, "sans-serif"),  # Key / Legend labels
    dpi         = 300                      # Presentation-quality export
)

# 1. TCO Breakdown Plot (Stacked Bar Chart)
function plot_tco_breakdown(all_results, plots_dir)
    alphas = sort(collect(keys(all_results)))
    
    # Exact string matching strictly tied to results.jl output
    capex_d = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Veh CAPEX Diesel (EUR)", :Value][1] for a in alphas]
    capex_e = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Veh CAPEX EV (EUR)", :Value][1] for a in alphas]
    infra   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Infra CAPEX (EUR)", :Value][1] for a in alphas]
    opex_d  = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Diesel OPEX (EUR)", :Value][1] for a in alphas]
    opex_e  = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Electricity OPEX (EUR)", :Value][1] for a in alphas]
    wages   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Wages (EUR)", :Value][1] for a in alphas]
    tolls   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Tolls (EUR)", :Value][1] for a in alphas]
    maint   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Maintenance (EUR)", :Value][1] for a in alphas]
    co2_pen = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "CO2 Penalty Cost (EUR)", :Value][1] for a in alphas]
    
    labels = string.(alphas)
    
    actual_totals = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Total Generalized Cost (EUR)", :Value][1] for a in alphas]
    y_max = isempty(actual_totals) ? 1.0 : maximum(actual_totals) * 1.15
    
    p = groupedbar(labels, [capex_d capex_e infra opex_d opex_e wages tolls maint co2_pen],
        bar_position = :stack,
        label = ["CAPEX Diesel" "CAPEX EV" "CAPEX Infra" "OPEX Diesel" "OPEX Elec" "Wages" "Tolls" "Maintenance" "CO2 Penalty"],
        title = "TCO Breakdown Across Target Alphas",
        xlabel = "Target Alpha",
        ylabel = "Cost (EUR)",
        legend = :outertopright,
        size = (800, 500),
        ylims = (0.0, y_max)
    )
    
    scatter!(p, labels, actual_totals, label="Total TCO", color=:black, marker=:circle, markersize=5)
    
    for i in 1:length(labels)
        annotate!(p, labels[i], actual_totals[i] + (y_max * 0.03), text("€" * string(round(actual_totals[i], digits=0)), 14, :bottom, :black))
    end
    
    savefig(p, joinpath(plots_dir, "1a_TCO_Stacked_Breakdown.png"))
end

# 1b. TCO Grouped by Category Plot (Side-by-Side Bar Chart)
function plot_tco_grouped_categories(all_results, plots_dir)
    alphas = sort(collect(keys(all_results)))
    
    # Extract individual components
    capex_d = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Veh CAPEX Diesel (EUR)", :Value][1] for a in alphas]
    capex_e = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Veh CAPEX EV (EUR)", :Value][1] for a in alphas]
    infra   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Infra CAPEX (EUR)", :Value][1] for a in alphas]
    
    opex_d  = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Diesel OPEX (EUR)", :Value][1] for a in alphas]
    opex_e  = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Electricity OPEX (EUR)", :Value][1] for a in alphas]
    wages   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Wages (EUR)", :Value][1] for a in alphas]
    tolls   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Tolls (EUR)", :Value][1] for a in alphas]
    maint   = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Maintenance (EUR)", :Value][1] for a in alphas]
    
    co2_pen = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "CO2 Penalty Cost (EUR)", :Value][1] for a in alphas]
    
    # Sum into the three master categories
    total_capex = capex_d .+ capex_e .+ infra
    total_opex  = opex_d .+ opex_e .+ wages .+ tolls .+ maint
    emissions   = co2_pen
    
    # Create the plotting matrix (Rows = Categories, Columns = Alphas)
    # The transpose (') converts the vectors into rows for the matrix
    plot_matrix = [total_capex'; total_opex'; emissions']
    categories = ["Total CAPEX", "Total OPEX", "Emissions Cost"]
    
    # Create a 1D row array for the legend labels to map to the columns
    legend_labels = reshape(["Alpha = $a" for a in alphas], 1, length(alphas))
    
    p = groupedbar(categories, plot_matrix,
        bar_position = :dodge,
        label = legend_labels,
        title = "Cost Component Comparison Across Alphas",
        ylabel = "Cost (EUR)",
        legend = :outertopright,
        size = (800, 500)
    )
    
    savefig(p, joinpath(plots_dir, "1b_TCO_Grouped_Categories.png"))
end

# 2. Pareto Frontier (Cost vs Emissions)
function plot_pareto_frontier(all_results, plots_dir)
    alphas = sort(collect(keys(all_results)))
    costs = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Total Generalized Cost (EUR)", :Value][1] for a in alphas]
    emissions = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Total Fleet Emissions (kg CO2)", :Value][1] for a in alphas]
    
    p = plot(emissions, costs, marker=:circle, lw=2,
        title = "Pareto Frontier: Total Cost vs CO2 Emissions",
        xlabel = "Total Fleet Emissions (kg CO2)",
        ylabel = "Total Generalized Cost (EUR)",
        legend = false,
        size = (700, 500)
    )
    
    for (i, alpha) in enumerate(alphas)
        annotate!(p, emissions[i], costs[i], text("  α=$alpha", 14, :left, :bottom))
    end
    
    savefig(p, joinpath(plots_dir, "2_Pareto_Frontier.png"))
end

# 3. Spatial Infrastructure Map
function plot_spatial_infrastructure(all_results, plots_dir)
    alphas = sort(collect(keys(all_results)))
    
    for alpha in alphas
        df_infra = all_results[alpha]["infra"]
        
        if nrow(df_infra) > 0
            max_installed = maximum(df_infra.Installed)
            
            p = scatter(df_infra.Node, df_infra.Installed, 
                group = df_infra.Charger_Type,
                title = "Charger Installations (Alpha = $alpha)",
                xlabel = "Node ID (0 = Depot)",
                ylabel = "Number of Chargers Installed",
                legend = :outertopright,
                size = (700, 400),
                markersize = 8,
                xticks = 0:maximum(df_infra.Node),
                yticks = 0:1:(max_installed + 1)
            )
            alpha_str = replace(string(alpha), "." => "_")
            savefig(p, joinpath(plots_dir, "3_Spatial_Infra_Alpha_$alpha_str.png"))
        end
    end
end

# 4. Fleet Mix
function plot_fleet_mix(all_results, plots_dir)
    alphas = sort(collect(keys(all_results)))
    
    ev_active = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Active EVs", :Value][1] for a in alphas]
    diesel_active = [all_results[a]["fleet"][all_results[a]["fleet"].Metric .== "Active Diesels", :Value][1] for a in alphas]
    
    labels = string.(alphas)
    
    max_active = isempty(ev_active) ? 1 : Int(maximum(ev_active .+ diesel_active))
    
    p = groupedbar(labels, [diesel_active ev_active],
        bar_position = :stack,
        label = ["Active Diesels" "Active EVs"],
        title = "Active Fleet Mix",
        xlabel = "Target Alpha",
        ylabel = "Number of Active Trucks",
        legend = :topleft,
        color = [:gray :green],
        size = (700, 500),
        yticks = 0:1:(max_active + 1)
    )
    savefig(p, joinpath(plots_dir, "4_Fleet_Mix.png"))
end

# 5. Payload vs Distance Scatter
function plot_payload_vs_distance(all_results, plots_dir)
    all_trucks = DataFrame()
    for alpha in keys(all_results)
        append!(all_trucks, all_results[alpha]["trucks"])
    end
    
    if nrow(all_trucks) > 0
        point_colors = [p == "EV" ? :green : :gray for p in all_trucks.Powertrain]
    
        p = scatter(all_trucks.Total_Distance_km, all_trucks.Total_Payload_Carried_t,
            group = all_trucks.Powertrain,
            title = "Truck Assignments: Payload vs Distance",
            xlabel = "Total Distance Driven (km)",
            ylabel = "Total Payload Delivered (t)",
            legend = :topright,
            color = point_colors,
            markersize = 6,
            size = (700, 500)
        )
        savefig(p, joinpath(plots_dir, "5_Payload_vs_Distance.png"))
    end
end

# 6. Infrastructure Utilization
function plot_infrastructure_utilization(all_results, plots_dir)
    all_infra = DataFrame()
    for alpha in keys(all_results)
        append!(all_infra, all_results[alpha]["infra"])
    end
    
    if nrow(all_infra) > 0
        p = scatter(all_infra.Alpha, all_infra.Utilisation_Pct,
            group = all_infra.Charger_Type,
            title = "Charger Utilization vs Alpha Policy",
            xlabel = "Target Alpha",
            ylabel = "Time Utilization (%)",
            legend = :outertopright,
            markersize = 7,
            size = (700, 500),
            xlims = (0.0, 1.05),
            xticks = 0.0:0.2:1.0
        )
        savefig(p, joinpath(plots_dir, "6_Infra_Utilization.png"))
    end
end

# 7. Telemetry Tracking (Sawtooth SOC & Diesel Fuel)
function plot_truck_telemetry(df_profiles, alpha_target, plots_dir)
    df_alpha = filter(row -> row.Alpha == alpha_target, df_profiles)
    alpha_str = replace(string(alpha_target), "." => "_")
    
    # 7a. Plot EV Battery Drain & Charging (De-overlapped & Enlarged)
ev_data = filter(row -> row.Powertrain == "EV", df_alpha)
if nrow(ev_data) > 0
    max_soc = max(maximum(ev_data.Arrival_SOC), maximum(ev_data.Departure_SOC))
    y_upper = max_soc > 0.0 ? max_soc * 1.15 : 1.05
    min_soc_val = maximum(ev_data.Min_SOC)

    p1 = plot(
        title = "EV Battery Profile (Alpha = $alpha_target)", 
        xlabel = "Distance (km)", 
        ylabel = "State of Charge (SOC)", 
        legend = :outertopright, 
        ylims = (0.0, y_upper),
        size = (850, 520)
    )

    hline!(p1, [min_soc_val], label = "Min SOC Limit", color = :red, linestyle = :dash, lw = 2)

    # Palette of distinct marker shapes for each truck
    truck_markers = [:circle, :square, :diamond, :utriangle, :hexagon, :star5]
    unique_trucks = unique(ev_data.Truck_ID)

    for (t_idx, k) in enumerate(unique_trucks)
        truck_route = filter(row -> row.Truck_ID == k, ev_data)
        x_vals = Float64[]
        y_vals = Float64[]
        
        m_shape = truck_markers[mod1(t_idx, length(truck_markers))]
        
        # Subtle horizontal visual jitter per truck (avoids exact pixel collisions at x=0)
        x_jitter = (t_idx - 1) * 1.5 

        for (idx, row) in enumerate(eachrow(truck_route))
            # Arrival point
            push!(x_vals, row.Cumulative_Distance_km + x_jitter)
            push!(y_vals, row.Arrival_SOC)

            # De-overlapped annotation:
            # Stagger text vertically based on truck index to prevent text pile-ups
            y_offset = (t_idx % 2 == 0 ? 0.03 : -0.04)
            lbl = row.Node == "Depot" && idx > 1 ? "Depot (End)" : string(row.Node)

            # Skip writing "Depot" four times at x = 0; only write it once for Truck 1
            if !(row.Node == "Depot" && idx == 1 && t_idx > 1)
                annotate!(p1, 
                    row.Cumulative_Distance_km + x_jitter, 
                    clamp(row.Arrival_SOC + y_offset, 0.05, 1.02), 
                    text(" " * lbl, 12, :left, :black)
                )
            end

            # Departure point (if mid-route charging occurred)
            push!(x_vals, row.Cumulative_Distance_km + x_jitter)
            push!(y_vals, row.Departure_SOC)
        end

        plot!(p1, x_vals, y_vals, 
            label = "Truck $k ($(truck_route.Truck_Type[1]))", 
            lw = 3, 
            marker = m_shape, 
            markersize = 6,
            markeralpha = 0.85,
            markerstrokewidth = 1.5,
            markerstrokecolor = :auto
        )
    end
    savefig(p1, joinpath(plots_dir, "7a_EV_Profile_Alpha_$(alpha_str).png"))
end
    
    # 7b. Plot Diesel Cumulative Fuel
    diesel_data = filter(row -> row.Powertrain == "Diesel", df_alpha)
    if nrow(diesel_data) > 0
        max_fuel = maximum(diesel_data.Cumulative_Fuel_L)
        y_upper = max_fuel > 0.0 ? max_fuel * 1.15 : 10.0
        
        p2 = plot(title="Diesel Fuel Usage (Alpha = $alpha_target)", 
                  xlabel="Distance (km)", ylabel="Cumulative Fuel Consumed (L)", 
                  legend=:outertopright, ylims=(0.0, y_upper))
        
        for k in unique(diesel_data.Truck_ID)
            truck_route = filter(row -> row.Truck_ID == k, diesel_data)
            
            for row in eachrow(truck_route)
                annotate!(p2, row.Cumulative_Distance_km, row.Cumulative_Fuel_L, text("  " * string(row.Node), 12, :left, :bottom))
            end
            
            plot!(p2, truck_route.Cumulative_Distance_km, truck_route.Cumulative_Fuel_L, 
                  label="Truck $k ($(truck_route.Truck_Type[1]))", lw=2, marker=:square, markersize=4)
        end
        savefig(p2, joinpath(plots_dir, "7b_Diesel_Profile_Alpha_$(alpha_str).png"))
    end
end

# MASTER PLOTTING FUNCTION
function generate_plots(all_results, plots_dir)
    println("Generating plots...")
    
    plot_tco_breakdown(all_results, plots_dir)
    plot_tco_grouped_categories(all_results, plots_dir)
    plot_pareto_frontier(all_results, plots_dir)
    plot_spatial_infrastructure(all_results, plots_dir)
    plot_fleet_mix(all_results, plots_dir)
    plot_payload_vs_distance(all_results, plots_dir)
    plot_infrastructure_utilization(all_results, plots_dir)
    
    for alpha_val in keys(all_results)
        if haskey(all_results[alpha_val], "profiles")
            plot_truck_telemetry(all_results[alpha_val]["profiles"], alpha_val, plots_dir)
        end
    end
    
    println("All plots successfully generated and saved to: ", plots_dir)
end