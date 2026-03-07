# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Technology demonstrator for modeling malaria transmission dynamics, focused on the Chittagong Hill Tracts region of Bangladesh. The project uses a Ross-Macdonald-type metapopulation ODE model incorporating human mobility between patches (unions/upazilas).

## Architecture

The codebase has two layers: the original research model in `mahmud_model/` and progressively simplified demo scripts in the root directory.

### Demo scripts (root directory) — model evolution chain

Each step simplifies/translates the previous one:

1. **`mahmud_model/` (original)** — Full research codebase in R with Rcpp. Runs on real 118-patch Bangladesh data via HPC. See "Original Mahmud Model" section below.

2. **`mahmud_model/demo_sim.R` (intermediate demo)** — Simplified to a 3-patch toy example with constant mosquito density. Runs to equilibrium, does perturbation experiments (set m=0 per patch), computes R0/source-sink metrics. No external data needed. No seasonality.

3. **`demo_sim_endemic.R` (seasonal R demo)** — Adds seasonal mosquito density forcing (sinusoidal or normal-curve) to the 3-patch model. Runs 5-year simulation from equilibrium initial conditions. Plots prevalence, incidence, mosquito density, and EIR. Self-contained, no Rcpp dependency.

4. **`demo_sim.py` (Python translation)** — Direct translation of `demo_sim_endemic.R` to Python. Uses `scipy.integrate.solve_ivp` (LSODA), numpy, matplotlib. Same model equations, same synthetic data.

5. **`demo_sim_ss.py` (Starsim version)** — Reimplements the model as a `starsim.Module` (`Malaria_SS` class) with Euler integration. Importable as a library or run standalone. Uses `sciris` for parameter management and plotting.

### Key shared functions across all versions

- **`analytical_mosquito_density()` / `malaria.ode.residence.analytical()`** — Analytically solves for mosquito density vector `m` given observed incidence, population, mobility matrix, and Ross-Macdonald parameters. Used to initialize baseline `m` from equilibrium prevalence.

- **ODE system** — Multi-patch Ross-Macdonald with mobility: computes weighted prevalence `k` at each destination via the mobility matrix `pij`, then force of infection incorporating sporogony delay (`exp(-mu*tau)`).

- **Seasonal forcing** — `make_seasonal_sinusoidal()` and `make_seasonal_normal()` modulate baseline mosquito density over time.

### Original Mahmud Model (`mahmud_model/`)

Full research codebase for the published analysis:

- **`change_m_incidence_union.R`** — Main HPC simulation script. Runs ODE to equilibrium, then perturbs mosquito density to zero in each patch (parallelized with `foreach`/`doParallel` on 80 cores). Outputs saved as RDS files.
- **`make_output_csv.R`** — Post-processing: computes R0, source/sink scores, proportion imported infections.
- **`R0_map.R`** — Computes and maps R0 with/without movement using `sf`.
- **`gravity_model.R`** — Fits negative binomial gravity models to fill missing mobility data.

### Rcpp Package (`mahmud_model/RcppFunctions/`)
- `eigenMapMatMult()` — Fast matrix multiplication via RcppEigen
- `malaria_ode_cpp()` — C++ ODE system implementation
- Install: `R CMD INSTALL mahmud_model/RcppFunctions`

### Model Parameters
| Parameter | Description | Typical Value |
|-----------|-------------|---------------|
| `a` | Biting rate | 0.3 |
| `b` | Mosquito-to-human transmission probability | 0.1-0.54 |
| `c` | Human-to-mosquito transmission probability | 0.214-0.423 |
| `r` | Recovery rate | 1/150 |
| `mu` | Mosquito death rate | 1/10 |
| `tau` | Extrinsic incubation period | 10 |

### Data Dependencies (not in repo)
Original Mahmud model scripts expect data files in a `data/` directory:
- `Bangladesh_pij_include_absent.txt` — Mobility/movement matrix (Pij)
- `Bangladesh_inc_pop.txt` — Incidence and population by patch
- `chittagongsubset/chit_east_250818.shp` — Shapefile for mapping

Demo scripts are fully self-contained with synthetic 3-patch data.

## Running

**R demos:**
```bash
Rscript demo_sim_endemic.R          # seasonal 3-patch demo
Rscript mahmud_model/demo_sim.R     # constant-m equilibrium + perturbation demo
```

**Python demos:**
```bash
python demo_sim.py                  # scipy ODE version
python demo_sim_ss.py               # Starsim module version
```

## Key Dependencies

**R:** deSolve, ggplot2, dplyr, sf, Rcpp, RcppEigen, foreach, doParallel, MASS, tidyverse, magrittr

**Python:** numpy, scipy, matplotlib, starsim, sciris
