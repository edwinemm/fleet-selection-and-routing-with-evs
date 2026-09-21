using JuMP, Gurobi

function build_and_solve_model(data, alpha_val)
println("Optimizing for alpha = ", alpha_val)
model = Model(Gurobi.Optimizer)
set_attribute(model, "OutputFlag", 1)

# Unpack necessary data components
N, I, M, K, KD, KE = data.N_set, data.I_set, data.M_set, data.K_set, data.K_D, data.K_E
tp, p = data.tp, data.params

# Decision Variables
@variable(model, y_D[KD], Bin)  
@variable(model, y_E[KE], Bin)  
@variable(model, z[N, M] >= 0, Int)
@variable(model, x[N, N, K], Bin)
@variable(model, u[N, K] >= 0)
@variable(model, e[N, KE] >= 0)
@variable(model, h[N, M, KE] >= 0)
@variable(model, tau[I, M, KE] >= 0) # tau, the charging time, in the objective function is only needed for charging at customer locations (mid-route) where a driver wage has to be paid

# Accounting Expressions
@expression(model, Fuel_D, sum(tp[:EC_D][k] * data.d[i, j] * x[i, j, k] for i in N, j in N, k in KD if i != j))
@expression(model, Energy_E[s in N], sum(h[s, m, k] for m in M, k in KE))
@expression(model, E_CO2_D, p[:gamma_D] * Fuel_D)
@expression(model, E_CO2_E, p[:gamma_E] * sum(Energy_E[s] for s in N))

# Objective Function
p_el_depot = 0.18 # Depot electricity price, Must match in results.jl
@objective(model, Min,
    sum(tp[:f_capex][k] * y_D[k] for k in KD) +
    sum(tp[:f_capex][k] * y_E[k] for k in KE) +
    sum(data.f_m[m] * z[s, m] for s in N, m in M) +
    p[:p_diesel] * Fuel_D +
    sum((s == 1 ? p_el_depot : p[:p_el]) * Energy_E[s] for s in N) +
    sum((tp[:Wage][k] / 60.0) * (data.d[i, j] / tp[:speed][k] * 60.0 + data.s_service[i]) * x[i, j, k] for i in N, j in N, k in K if i != j) +
    sum((tp[:Wage][k] / 60.0) * sum(tau[i, m, k] for m in M) for i in I, k in KE) + # Wages only for mid-route charging
    sum(tp[:Maint][k] * data.d[i, j] * x[i, j, k] for i in N, j in N, k in K if i != j) +
    sum(tp[:Toll][k] * data.d[i, j] * x[i, j, k] for i in N, j in N, k in K if i != j) +
    p[:lambda_co2] * (E_CO2_D + E_CO2_E)
)

# CONSTRAINTS
for i in I
    @constraint(model, sum(x[j, i, k] for j in N, k in K if j != i) == 1)
end

for k in K
    @constraint(model, sum(x[1, j, k] for j in I) == sum(x[j, 1, k] for j in I))
    for i in I
        @constraint(model, sum(x[j, i, k] for j in N if j != i) == sum(x[i, j, k] for j in N if j != i))
    end
end

for k in K
    if k in KD
        @constraint(model, sum(x[1, j, k] for j in I) == y_D[k])
    elseif k in KE
        @constraint(model, sum(x[1, j, k] for j in I) == y_E[k])
    end
end

for k in K
    @constraint(model, u[1, k] == 0)
    for j in I
        if data.q[j] > tp[:Q][k]
            @constraint(model, sum(x[i, j, k] for i in N if i != j) == 0)
        end
    end
    for i in N, j in I
        if i != j
            @constraint(model, x[i, j, k] => {u[j, k] >= u[i, k] + data.q[j]})
        end
    end
    for i in N
        @constraint(model, u[i, k] <= tp[:Q][k])
    end
end

# EV Battery Bounds
for k in KE
    @constraint(model, e[1, k] == tp[:SOC_max][k] * tp[:E_cap][k])
    for i in I
        @constraint(model, e[i, k] >= tp[:SOC_min][k] * tp[:E_cap][k])
        @constraint(model, e[i, k] <= tp[:SOC_max][k] * tp[:E_cap][k])
        
        # Battery cannot be charged beyond maximum battery capacity
        @constraint(model, e[i, k] + sum(h[i, m, k] for m in M) <= tp[:SOC_max][k] * tp[:E_cap][k])
    end
end

# EV Energy Propagation
for k in KE
    usable_battery = (tp[:SOC_max][k] - tp[:SOC_min][k]) * tp[:E_cap][k]
    for i in N, j in N
        if i != j && (tp[:EC_E][k] * data.d[i, j] > usable_battery)
            @constraint(model, x[i, j, k] == 0)
        end
    end

    # Strict energy equality
    for j in I
        # Leaving the depot
        @constraint(model, x[1, j, k] => {e[j, k] == e[1, k] - tp[:EC_E][k] * data.d[1, j]})
        
        # Customer to customer
        for i in I
            if i != j
                @constraint(model, x[i, j, k] => {e[j, k] == e[i, k] - tp[:EC_E][k] * data.d[i, j] + sum(h[i, m, k] for m in M)})
            end
        end
    end
    
    # Safe return to depot (trucks must arrive at depot >= Min_SOC)
    for i in I
        @constraint(model, x[i, 1, k] => {tp[:SOC_min][k] * tp[:E_cap][k] <= e[i, k] - tp[:EC_E][k] * data.d[i, 1] + sum(h[i, m, k] for m in M)})
    end
end

# Charging time limits (mid-route, can be modified to account for acceptable dwell time, e.g. a 45 minutes driver break)
for k in KE, i in I
    @constraint(model, sum((h[i, m, k] / data.eta_m[m]) * 60.0 for m in M) <= 360.0)
end

# Charger counts limits
for i in I
    @constraint(model, sum(z[i, m] for m in M) <= 1)
end
@constraint(model, sum(z[1, m] for m in M) <= 10)

# Charger capacity and charging time
for k in KE, m in M
    # Depot overnight charger (individual truck limit)
    @constraint(model, h[1, m, k] <= tp[:E_cap][k] * z[1, m])
    
    # Customer mid-route charger (individual truck limit)
    for i in I
        @constraint(model, h[i, m, k] <= tp[:E_cap][k] * z[i, m])
        @constraint(model, h[i, m, k] <= data.eta_m[m] * tau[i, m, k] / 60.0)
        @constraint(model, tau[i, m, k] <= 480.0 * sum(x[i, j, k] for j in N if j != i))
    end
end

# Aggregate depot charger time limit (12 hours / 720 mins overnight)
for m in M
    @constraint(model, 
        sum((h[1, m, k] / data.eta_m[m]) * 60.0 for k in KE) <= 720.0 * z[1, m]
    )
end

for s in I, m in M
    @constraint(model, sum(tau[s, m, k] for k in KE) <= 480.0 * z[s, m]) 
end

# Shift duration constraint (depot charging tau[1] is excluded because it is outside the driver shift)
for k in K
    @constraint(model, sum((data.d[i, j] / tp[:speed][k] * 60.0) * x[i, j, k] for i in N, j in N if i != j) +
                       sum(data.s_service[i] * sum(x[i, j, k] for j in N if j != i) for i in I) +
                       sum(k in KE ? tau[i, m, k] : 0.0 for i in I, m in M) <= 480.0)
end

# Overnight energy balance
for k in KE
    @constraint(model, sum(h[i, m, k] for i in N, m in M) == sum(tp[:EC_E][k] * data.d[i, j] * x[i, j, k] for i in N, j in N if i != j))
end

# Electrification policy constraint
# Based on number of BETs in the fleet
@constraint(model, sum(y_E[k] for k in KE) >= alpha_val * (sum(y_E[k] for k in KE) + sum(y_D[k] for k in KD)))

if alpha_val == 0.0
    for k in KE
        @constraint(model, y_E[k] == 0)
    end
end

# Symmetry breaking
for i in 1:(length(KD)-1)
    if data.truck_map[KD[i]] == data.truck_map[KD[i+1]]
        @constraint(model, y_D[KD[i]] >= y_D[KD[i+1]])
    end
end
for i in 1:(length(KE)-1)
    if data.truck_map[KE[i]] == data.truck_map[KE[i+1]]
        @constraint(model, y_E[KE[i]] >= y_E[KE[i+1]])
    end
end

optimize!(model)
status = termination_status(model)

if status == MOI.INFEASIBLE
    println("\n!!! MODEL INFEASIBLE.")
end

return model, status, Fuel_D, Energy_E, E_CO2_D, E_CO2_E


end