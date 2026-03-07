library(deSolve)
library(ggplot2)

# ODE right-hand side (base R matrix ops instead of RcppFunctions)
malaria.ode.fast <- function(t, x, params) {
  X <- x[1:params[["numpatch"]]]
  C <- x[(params[["numpatch"]] + 1):length(x)]

  k <- as.vector(t(X * params[["H"]]) %*% params[["pij"]] /
                   (t(params[["H"]]) %*% params[["pij"]]))

  dC <- (t(params[["m"]]) * params[["a"]]^2 * params[["b"]] * params[["c"]] *
           exp(-params[["mu"]] * params[["tau"]]) * k /
           (params[["a"]] * params[["c"]] * k + params[["mu"]])) %*%
    t(params[["pij"]]) * (1 - X)

  dX <- dC - (params[["r"]] * X)

  return(list(c(dX, dC)))
}

# Analytical mosquito density
malaria.ode.residence.analytical <- function(Ivector, Hvector, Pmatrix, a, b, c, mu, r, tau) {
  Gvector <- function(Xvector, r) Xvector * r / (1 - Xvector)
  Fvector <- function(Xvector, Hvector, Pmatrix, a, b, c, mu) {
    k <- sapply(1:length(Xvector), function(i)
      sum(Pmatrix[, i] * Xvector * Hvector) / sum(Pmatrix[, i] * Hvector))
    return(b * c * k / (a * c * k / mu + 1))
  }
  xvector <- Ivector / r
  gvector <- Gvector(xvector, r)
  fvector <- Fvector(xvector, Hvector, Pmatrix, a, b, c, mu)
  fmatrix <- diag(fvector)
  Cvector <- solve(Pmatrix %*% fmatrix) %*% gvector
  m <- Cvector * mu / a / a / exp(-mu * tau)
  return(m)
}

# Root function for equilibrium detection
rootfun <- function(t, x, params) {
  dstate <- unlist(malaria.ode.fast(t, x, params))[1:params[["numpatch"]]]
  return(sum(abs(dstate)) - 1e-13)
}

# --- Parameters ---
a <- 0.3
b <- 0.1
c <- 0.214
r <- 1 / 150
mu <- 1 / 10
tau <- 10

# --- Synthetic 3-patch data ---
numpatch <- 3

# Population sizes
hvector <- c(5000, 10000, 8000)

# Incidence rates (per person per day)
ivector <- c(0.001, 0.003, 0.002)

# Mobility matrix (rows=residence, cols=destination; rows sum to 1)
pij <- matrix(c(
  0.85, 0.10, 0.05,
  0.08, 0.80, 0.12,
  0.06, 0.09, 0.85
), nrow = 3, byrow = TRUE)

# --- Solve for mosquito density ---
m <- malaria.ode.residence.analytical(ivector, hvector, pij, a, b, c, mu, r, tau)
m[m < 0] <- 1e-10
m <- as.vector(m)
cat("Analytical mosquito density (m):", round(m, 4), "\n")

# --- Run to equilibrium ---
paras <- list(numpatch = numpatch, c = c, b = b, a = a, mu = mu,
              tau = tau, r = r, pij = pij, H = hvector, m = m)

xstart <- c(rep(0.0001, numpatch), rep(0, numpatch))

cat("Running ODE to equilibrium...\n")
out_equm <- as.data.frame(ode(xstart, 1:(5e5), malaria.ode.fast, paras, rootfun = rootfun))
cat("Equilibrium reached at time step:", nrow(out_equm), "\n")

xequm_prev <- unlist(out_equm[nrow(out_equm) - 1, 2:(numpatch + 1)])
cat("Equilibrium prevalence:", round(xequm_prev, 6), "\n")

# --- Perturbation: set m=0 in each patch, one at a time ---
xequm <- unlist(c(out_equm[nrow(out_equm) - 1, 2:(numpatch + 1)],
                   xstart[(numpatch + 1):(numpatch * 2)]))

# --- Perturbation: set m=0 in each patch, one at a time ---
cat("\nRunning perturbation experiments...\n")
perturbation_results <- matrix(NA, nrow = numpatch, ncol = numpatch)
perturbation_outs <- list()
for (i in 1:numpatch) {
  paras_temp <- paras
  paras_temp$m[i] <- 0
  out_temp <- as.data.frame(ode(xequm, 1:(5e5), malaria.ode.fast, paras_temp, rootfun = rootfun))
  perturbation_outs[[i]] <- out_temp
  if (nrow(out_temp) > 2) {
    perturbation_results[i, ] <- unlist(
      out_temp[nrow(out_temp) - 1, (numpatch + 2):ncol(out_temp)] -
        out_temp[nrow(out_temp) - 2, (numpatch + 2):ncol(out_temp)])
  } else {
    perturbation_results[i, ] <- rep(-1, numpatch)
  }
  cat(sprintf("  Patch %d removed: new incidence = %s\n",
              i, paste(round(perturbation_results[i, ], 6), collapse = ", ")))
}

# --- Compute metrics (from make_output_csv.R) ---
# R0 with movement
R0 <- (a * b / mu) * (m * a * exp(-tau * mu) / r)

# R0 without movement (single-patch formula)
m_noMov <- (ivector * (a * c * ivector / r + mu)) /
  (a^2 * b * c * exp(-mu * tau) * ivector / r * (1 - ivector / r))
R0_noMov <- (a * b / mu) * (m_noMov * a * exp(-tau * mu) / r)

# Proportion of imported infections (from Cij matrix)
X_eq <- xequm_prev
K <- colSums(t(pij) * X_eq * hvector) / colSums(t(pij) * hvector)
Cij <- t((t(pij) * m * a^2 * b * c * exp(-tau * mu) * K) / (a * c * K + mu))
Cij <- Cij / rowSums(Cij)
prop_imported <- rowSums(Cij - diag(diag(Cij)))

# Source/sink scores
source_score <- rowSums(hvector * ivector * t(Cij - diag(diag(Cij))))
sink_score <- hvector * ivector * prop_imported

# ============================================================
# PLOTS
# ============================================================
patch_names <- paste("Patch", 1:numpatch)
pdf("demo_sim_plots.pdf", width = 10, height = 8)

# --- 1. Prevalence time series to equilibrium ---
prev_df <- data.frame(
  time = out_equm$time,
  out_equm[, 2:(numpatch + 1)]
)
names(prev_df)[2:(numpatch + 1)] <- patch_names
prev_long <- reshape(prev_df, direction = "long", varying = patch_names,
                     v.names = "prevalence", timevar = "patch",
                     times = patch_names)
print(
  ggplot(prev_long, aes(x = time, y = prevalence, color = patch)) +
    geom_line(linewidth = 0.8) +
    labs(title = "Prevalence dynamics to equilibrium",
         x = "Time (days)", y = "Prevalence", color = "Patch") +
    theme_minimal()
)

# --- 2. R0 with vs without movement ---
r0_df <- data.frame(patch = patch_names,
                     with_movement = R0,
                     without_movement = R0_noMov)
r0_long <- reshape(r0_df, direction = "long",
                   varying = c("with_movement", "without_movement"),
                   v.names = "R0", timevar = "type",
                   times = c("With movement", "Without movement"))
print(
  ggplot(r0_long, aes(x = patch, y = R0, fill = type)) +
    geom_col(position = "dodge") +
    labs(title = "R0 with and without human movement",
         x = NULL, y = "R0", fill = NULL) +
    theme_minimal()
)

# --- 3. Proportion imported infections ---
print(
  ggplot(data.frame(patch = patch_names, imported = prop_imported),
         aes(x = patch, y = imported)) +
    geom_col(fill = "steelblue") +
    labs(title = "Proportion of infections from imported sources",
         x = NULL, y = "Proportion imported") +
    ylim(0, 1) +
    theme_minimal()
)

# --- 4. Source vs sink scores ---
ss_df <- data.frame(patch = patch_names, source = source_score, sink = sink_score)
ss_long <- reshape(ss_df, direction = "long", varying = c("source", "sink"),
                   v.names = "score", timevar = "type",
                   times = c("Source", "Sink"))
print(
  ggplot(ss_long, aes(x = patch, y = score, fill = type)) +
    geom_col(position = "dodge") +
    labs(title = "Source and sink scores by patch",
         x = NULL, y = "Score", fill = NULL) +
    theme_minimal()
)

# --- 5. Perturbation impact: prevalence time series after removing each patch ---
for (i in 1:numpatch) {
  out_p <- perturbation_outs[[i]]
  p_df <- data.frame(time = out_p[, 1], out_p[, 2:(numpatch + 1)])
  names(p_df)[2:(numpatch + 1)] <- patch_names
  p_long <- reshape(p_df, direction = "long", varying = patch_names,
                    v.names = "prevalence", timevar = "patch",
                    times = patch_names)
  print(
    ggplot(p_long, aes(x = time, y = prevalence, color = patch)) +
      geom_line(linewidth = 0.8) +
      labs(title = sprintf("Prevalence after removing mosquitoes in %s", patch_names[i]),
           x = "Time (days)", y = "Prevalence", color = "Patch") +
      theme_minimal()
  )
}

# --- 6. Incidence reduction heatmap ---
equm_inc <- unlist(out_equm[nrow(out_equm) - 1, (numpatch + 2):(2 * numpatch + 1)] -
                     out_equm[nrow(out_equm) - 2, (numpatch + 2):(2 * numpatch + 1)])
reduction <- 1 - sweep(perturbation_results, 2, equm_inc, "/")
heat_df <- expand.grid(removed = patch_names, affected = patch_names)
heat_df$reduction <- as.vector(reduction)
print(
  ggplot(heat_df, aes(x = affected, y = removed, fill = reduction)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.1f%%", reduction * 100)), size = 4) +
    scale_fill_gradient(low = "white", high = "firebrick", labels = scales::percent) +
    labs(title = "Incidence reduction when mosquitoes removed from a patch",
         x = "Affected patch", y = "Mosquitoes removed in", fill = "Reduction") +
    theme_minimal()
)

dev.off()
cat("\nPlots saved to demo_sim_plots.pdf\n")
cat("Done.\n")
