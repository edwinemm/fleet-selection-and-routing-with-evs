# Road Freight Electrification

## A Total Cost of Ownership and Routing Optimization Approach

This repository contains the Mixed Integer Linear Programming (MILP) model developed in Julia.

The model solves the Electric Vehicle Routing Problem (EVRP) with a heterogeneous fleet, evaluating the Total Cost of Ownership for deploying internal combustion engine (ICE) trucks and battery electric trucks (BETs) to meet a specified electrification level defined as the proportion of BETs in the fleet. It goes beyond simple 1:1 vehicle substitution by performing a complete re-planning of routes to optimize daily operations.

## Key Features

- **Mixed Fleet Routing:** Dynamically selects the optimal mix of ICE and BET models based on payload capacities, variable costs, and target electrification rates (`alpha`).

- **Physics-Based Battery Tracking:** Strictly enforces a minimum State of Charge (e.g., `SOC_min = 30%`) and tracks energy propagation continuously across network arcs to eliminate range anxiety.

- **Charging Infrastructure Deployment:** Optimizes the number and location of private chargers (with specified power e.g., 50 kW, 150 kW) considering both CAPEX and OPEX.

- **Comprehensive TCO Objective:** Minimizes the generalized daily cost, which includes vehicle and infrastructure CAPEX, fuel/electricity OPEX, driver wages, maintenance, tolls, and monetized societal CO2 emissions.

## Prerequisites

To run this model, you need the following:

- Julia (v1.8 or higher recommended)
- Gurobi Optimizer (a valid academic or commercial Gurobi license is required to solve the MILP)

### Required Julia Packages

Install the dependencies by opening the Julia REPL and running:

```julia
using Pkg

Pkg.add(["JuMP", "Gurobi", "DataFrames", "XLSX", "Plots", "StatsPlots"])
```

## Repository Structure

### Code Scripts (`.jl`)

- **`main.jl`**: The execution controller. Iterates through target electrification scenarios (`alpha`) and aggregates results.

- **`inputs.jl`**: Handles data ingestion. Processes the 9-node network distance matrix, scales candidate truck instances, and loads cost/energy parameters.

- **`model.jl`**: The mathematical core containing the JuMP MILP formulation. Defines constraints for flow conservation, battery propagation, driver shift duration, and maximum dwell times.

- **`results.jl`**: Extracts the solved Gurobi decision variables, calculates TCO metrics, evaluates actual vs. target `alpha` rates, and builds telemetry logs.

- **`plots.jl`**: Generates presentation-quality visualizations matching the thesis figures (TCO breakdowns, fleet mix, infrastructure utilization, and "sawtooth" SOC profiles).

### Data Inputs (`.xlsx`)

The model relies on five structured Excel files located in the root directory:

- **`nodes_demand_service_time.xlsx`**: Customer locations, demand, and service time.

- **`distance_matrix.xlsx`**: Pre-calculated geographic distances between the depot and all customer nodes.

- **`truck_types.xlsx`**: Financial and physical parameters for ICE and BET models (adapted from Zackrisson et al., 2025).

- **`charging_infrastructure.xlsx`**: Power capacities and CAPEX/OPEX costs for private chargers.

- **`CO2_accounting.xlsx`**: Global economic parameters, including diesel spot prices, grid electricity costs, and carbon penalty rates.

## How to Run

1. Clone or download this repository to your local machine.

2. Ensure all five Excel data files are in the same folder as the `.jl` scripts.

3. Open your terminal or command prompt, navigate to the folder, and execute:

```bash
julia main.jl
```

## Outputs

Upon successful execution, the script will automatically create a `plots/` directory containing:

- **`optimised_results.xlsx`**: A comprehensive spreadsheet logging truck routing sequences, charging telemetry, and exact fleet economics.

- High-resolution `.png` visualizations illustrating the TCO comparisons, active fleet mix, Pareto frontiers (Cost vs. Emissions), and step-by-step BET battery degradation/recharging routes.
