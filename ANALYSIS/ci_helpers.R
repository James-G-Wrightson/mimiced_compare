# - Cluster-aware confidence intervals -
#
# Patients can contribute more than one visit, so intervals that assume
# independent observations are too narrow. Every function here clusters on the
# patient (subject_id): proportions and means use an intercept-only GEE with a
# robust sandwich variance (geepack), and the bootstrap resamples patients,
# keeping all of a sampled patient's visits together. Sourced by the analysis
# notebooks after their pacman::p_load() call — the tidyverse must be attached
# first, because these functions call tibble, arrange, n_distinct and friends
# unqualified. Keep any change here in sync with every notebook that sources it.
#
# The method is described in the "Clustered confidence intervals" section of
# ANALYSIS/3_descriptive.ipynb, whose self-check cell compares these intervals
# with naive, sandwich and bootstrap alternatives.

BOOT_B    <- 2000
# the bootstrap functions call set.seed() for reproducibility, which also
# resets the caller's RNG state — run them before any cell that needs its own
# random draws
BOOT_SEED <- 20260825

# Cluster bootstrap of a ratio sum(num)/sum(den). Per-patient sums are
# precomputed with rowsum(), so each replicate is an index sample plus two
# column sums. Percentile limits. Fallback for the GEE functions below and
# usable directly for any ratio.
# Args: num, den = numeric vectors, one element per visit; id = patient id.
# Used by gee_prop_ci() and gee_mean_ci() when the logit fit degenerates.
boot_ratio_ci <- function(num, den, id, B = BOOT_B, seed = BOOT_SEED) {
  ps <- rowsum(cbind(num, den), group = id)
  set.seed(seed)
  reps <- replicate(B, {
    i  <- sample.int(nrow(ps), replace = TRUE)
    cs <- colSums(ps[i, , drop = FALSE])
    cs[[1]] / cs[[2]]
  })
  c(
    est = sum(num) / sum(den),
    lo  = quantile(reps, 0.025, names = FALSE),
    hi  = quantile(reps, 0.975, names = FALSE)
  )
}

# Marginal proportion (0-1 scale) with a patient-clustered 95% CI:
# intercept-only logistic GEE, working independence, robust sandwich SE,
# interval formed on the logit scale and back-transformed. Falls back to the
# cluster bootstrap when the proportion is 0 or 1 (degenerate logit) or there
# are fewer than 40 patients (sandwich SEs unreliable).
# Args: y = logical or 0/1 vector, one element per visit; id = patient id.
gee_prop_ci <- function(y, id) {
  ok <- !is.na(y)
  y  <- as.numeric(y[ok])
  id <- id[ok]
  p  <- mean(y)
  if (p <= 0 || p >= 1 || n_distinct(id) < 40) {
    return(boot_ratio_ci(y, rep(1, length(y)), id))
  }
  d   <- tibble(y = y, id = id) |> arrange(id)
  fit <- geepack::geeglm(
    y ~ 1,
    id = id, data = d,
    family = binomial("logit"), corstr = "independence"
  )
  ci <- coef(fit)[[1]] + c(0, -1, 1) * qnorm(0.975) * sqrt(vcov(fit)[1, 1])
  set_names(plogis(ci), c("est", "lo", "hi"))
}

# Marginal mean with a patient-clustered 95% CI: same GEE as gee_prop_ci()
# but gaussian with an identity link, so no back-transform. NA values dropped.
# Args: x = numeric vector, one element per visit; id = patient id.
gee_mean_ci <- function(x, id) {
  ok <- !is.na(x)
  x  <- x[ok]
  id <- id[ok]
  if (n_distinct(id) < 40) {
    return(boot_ratio_ci(x, rep(1, length(x)), id))
  }
  d   <- tibble(x = x, id = id) |> arrange(id)
  fit <- geepack::geeglm(
    x ~ 1,
    id = id, data = d,
    family = gaussian(), corstr = "independence"
  )
  ci <- coef(fit)[[1]] + c(0, -1, 1) * qnorm(0.975) * sqrt(vcov(fit)[1, 1])
  set_names(ci, c("est", "lo", "hi"))
}

# Clustered versions of the notebooks' prop_fn()/summarise_mean(), with the
# same "estimate [lower-upper]" cell format.
# Args: x = indicator (prop) or numeric (mean) vector; id = patient id.
prop_fn_cl <- function(x, id) {
  ci <- gee_prop_ci(x, id)
  sprintf("%.1f [%.1f-%.1f]", ci[["est"]] * 100, ci[["lo"]] * 100, ci[["hi"]] * 100)
}

mean_fn_cl <- function(x, id, digits = 1) {
  ci <- gee_mean_ci(x, id)
  fmt <- sprintf("%%.%df [%%.%df-%%.%df]", digits, digits, digits)
  sprintf(fmt, ci[["est"]], ci[["lo"]], ci[["hi"]])
}

# Two-group marginal difference with a patient-clustered 95% CI and Wald test:
# GEE of y on the group indicator, gaussian identity, so the coefficient is a
# risk difference for 0/1 outcomes and a mean difference for continuous ones.
# Returns c(est, lo, hi, z, p) on the scale of y; est is the second group
# level minus the first.
# Args: y = outcome vector; group = two-level factor or logical; id = patient id.
gee_diff_ci <- function(y, group, id) {
  ok    <- !is.na(y) & !is.na(group)
  d     <- tibble(y = as.numeric(y[ok]), g = group[ok], id = id[ok]) |> arrange(id)
  fit   <- geepack::geeglm(
    y ~ g,
    id = id, data = d,
    family = gaussian(), corstr = "independence"
  )
  est <- coef(fit)[[2]]
  se  <- sqrt(vcov(fit)[2, 2])
  c(
    est = est,
    lo  = est - qnorm(0.975) * se,
    hi  = est + qnorm(0.975) * se,
    z   = est / se,
    p   = 2 * pnorm(-abs(est / se))
  )
}

# Agreement between two binary raters with patient-clustered bootstrap CIs.
# The four cells of the 2x2 agreement table (a = both flagged, b = flagged by
# r1 only, c = flagged by r2 only, d = neither) are summed per patient with
# rowsum(), and every measure is recomputed algebraically from the resampled
# cell totals in each replicate, so the whole bootstrap is a few seconds. With
# one visit per patient this reduces to an ordinary bootstrap. Measures, all
# on the 0-1 scale:
#   p1, p2  prevalence of each flag, (a+b)/n and (a+c)/n
#   po      percent agreement, (a+d)/n
#   kappa   Cohen's kappa, (po-pe)/(1-pe), pe = p1*p2 + (1-p1)*(1-p2)
#   pabak   prevalence- and bias-adjusted kappa, 2*po - 1
#   psa     positive specific agreement, 2a/(2a+b+c)
#   nsa     negative specific agreement, 2d/(2d+b+c)
#   pi      prevalence index, (a-d)/n
# Percentile limits.
# Args: r1, r2 = 0/1 vectors, one element per visit; id = patient id.
# Returns a one-row tibble: the cell counts a, b, c, d and n, then for each
# measure the estimate (<measure>) and limits (<measure>_lo, <measure>_hi).
agreement_boot_ci <- function(r1, r2, id, B = BOOT_B, seed = BOOT_SEED) {
  cells <- cbind(r1 * r2, r1 * (1 - r2), (1 - r1) * r2, (1 - r1) * (1 - r2))
  ps    <- rowsum(cells, group = id)
  stats <- function(cs) {
    a  <- cs[[1]]
    b  <- cs[[2]]
    c  <- cs[[3]]
    d  <- cs[[4]]
    n  <- a + b + c + d
    po <- (a + d) / n
    p1 <- (a + b) / n
    p2 <- (a + c) / n
    pe <- p1 * p2 + (1 - p1) * (1 - p2)
    c(
      p1    = p1,
      p2    = p2,
      po    = po,
      kappa = (po - pe) / (1 - pe),
      pabak = 2 * po - 1,
      psa   = 2 * a / (2 * a + b + c),
      nsa   = 2 * d / (2 * d + b + c),
      pi    = (a - d) / n
    )
  }
  set.seed(seed)
  reps <- replicate(B, {
    stats(colSums(ps[sample.int(nrow(ps), replace = TRUE), , drop = FALSE]))
  })
  cs  <- colSums(ps)
  est <- stats(cs)
  lo  <- apply(reps, 1, quantile, probs = 0.025, names = FALSE)
  hi  <- apply(reps, 1, quantile, probs = 0.975, names = FALSE)
  out <- c(
    a = cs[[1]], b = cs[[2]], c = cs[[3]], d = cs[[4]], n = sum(cs),
    unlist(map(names(est), \(m) {
      set_names(c(est[[m]], lo[[m]], hi[[m]]), paste0(m, c("", "_lo", "_hi")))
    }))
  )
  as_tibble(as.list(out))
}

# Cohen's kappa for two binary raters with a patient-clustered bootstrap CI.
# Thin wrapper around agreement_boot_ci() for cells that need only kappa.
# Args: r1, r2 = 0/1 vectors, one element per visit; id = patient id.
# Returns c(kappa, lo, hi).
kappa_boot_ci <- function(r1, r2, id, B = BOOT_B, seed = BOOT_SEED) {
  ag <- agreement_boot_ci(r1, r2, id, B = B, seed = seed)
  c(kappa = ag$kappa, lo = ag$kappa_lo, hi = ag$kappa_hi)
}
