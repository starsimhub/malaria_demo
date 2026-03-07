library(deSolve)

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

cat("\nRunning perturbation experiments...\n")
for (i in 1:numpatch) {
  paras_temp <- paras
  paras_temp$m[i] <- 0
  out_temp <- ode(xequm, 1:(5e5), malaria.ode.fast, paras_temp, rootfun = rootfun)
  if (nrow(out_temp) > 2) {
    inc <- out_temp[nrow(out_temp) - 1, (numpatch + 2):ncol(out_temp)] -
      out_temp[nrow(out_temp) - 2, (numpatch + 2):ncol(out_temp)]
  } else {
    inc <- rep(-1, numpatch)
  }
  cat(sprintf("  Patch %d removed: new incidence = %s\n",
              i, paste(round(inc, 6), collapse = ", ")))
}

cat("\nDone.\n")
