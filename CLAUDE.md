# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Technology demonstrator for modeling malaria transmission dynamics, focused on the Chittagong Hill Tracts region of Bangladesh. The project uses a Ross-Macdonald-type metapopulation ODE model incorporating human mobility between patches (unions/upazilas).

## Architecture

The codebase lives entirely in `mahmud_model/` and consists of R scripts and a custom Rcpp package:

### Core Model
- **`change_m_incidence_union.R`** - Main simulation script. Runs the ODE model to equilibrium, then perturbs mosquito density (`m`) to zero in each patch one at a time (parallelized with `foreach`/`doParallel` on 80 cores). Outputs saved as RDS files in `analysis/`.
- **`make_output_csv.R`** - Post-processing script. Reads equilibrium and perturbation results, computes metrics (R0, source/sink scores, proportion imported infections), and writes summary CSVs to `analysis/`.
- **`R0_map.R`** - Computes and maps R0 with and without movement using the analytical mosquito density formula. Uses `sf` for spatial visualization.
- **`gravity_model.R`** - Fits negative binomial gravity models to travel data (both inter-patch travel and proportion staying). Fills in missing mobility data with model predictions.

### Key Functions
- **`malaria.ode.residence.analytical()`** - Analytically solves for mosquito density vector `m` given observed incidence, population, mobility matrix, and Ross-Macdonald parameters (a, b, c, mu, r, tau). Appears in multiple scripts.
- **`malaria.ode.fast()`** - ODE right-hand side function for `deSolve::ode()`. Uses Rcpp matrix multiplication for performance.
- **`rootfun()`** - Root-finding function for detecting ODE equilibrium (sum of absolute derivatives < 1e-13).

### Rcpp Package (`RcppFunctions/`)
- `eigenMapMatMult()` - Fast matrix multiplication via RcppEigen
- `malaria_ode_cpp()` - C++ implementation of the ODE system (alternative to the R version)
- Depends on: Rcpp, RcppEigen

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
Scripts expect data files in a `data/` directory:
- `Bangladesh_pij_include_absent.txt` - Mobility/movement matrix (Pij)
- `Bangladesh_inc_pop.txt` - Incidence and population by patch (columns: `union`, `upa`, `inc`, `H`)
- `chittagongsubset/chit_east_250818.shp` - Shapefile for mapping
- Various CSVs for gravity model fitting (referenced via `here()`)

## Running

R scripts are meant to be run individually (not as a pipeline). The typical workflow:
1. Fit gravity model to fill missing mobility data (`gravity_model.R`)
2. Run perturbation simulations (`change_m_incidence_union.R`) - requires HPC with many cores
3. Generate output metrics (`make_output_csv.R`)
4. Visualize R0 maps (`R0_map.R`)

To install the Rcpp package: `R CMD INSTALL mahmud_model/RcppFunctions`

## Key R Dependencies

deSolve, dplyr, sf, ggplot2, Rcpp, RcppEigen, foreach, doParallel, MASS, tidyverse, magrittr
