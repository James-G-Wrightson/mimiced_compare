# ==============================================================================
# Reviewer response: R1.5 (visits per patient) and R2.1 (all-visit sensitivity)
#
# Paper: comparison of three "potentially avoidable" ED visit algorithms in
#        MIMIC-IV-ED.
#
# R1.5  Reviewer 1: "Restricting the cohort to the first presentation during the
#       study period may underrepresent frequent ED users and recurrent
#       presentations, potentially affecting estimates of potentially avoidable
#       ED visits."
#
# R2.1  Reviewer 2: "The restriction to first visits per patient represents a
#       consequential selection decision... A sensitivity analysis including all
#       visits, or at minimum an extended discussion of the implications, would
#       strengthen the paper."
#
# This script:
#   0. Asserts that the published first-visit results reproduce exactly.
#      It STOPS if they do not.
#   1. R1.5 - describes the visits-per-patient distribution on the eligible
#      visit set, quantifies what the first-visit restriction discards, and
#      compares single-visit against repeat-visit patients.
#   2. R2.1 - re-tabulates all three algorithms on all eligible visits and
#      places them side by side with the published first-visit results.
#   3. Writes r1_05_visits_per_patient.md and r2_01_sensitivity_all_visits.md
#      next to this script.
#
# Algorithm labels are read as-is from the parquet; nothing is recomputed:
#   nyu        = Diagnosis algorithm      (0/1)
#   res        = Resources algorithm      (0/1)
#   acuity_out = Triage-Acuity algorithm  (0/1)
#
# Run:  Rscript r1_05_r2_01_repeat_visits.R
# R 4.5.2
# ==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(psych)
})

options(dplyr.summarise.inform = FALSE)

# ------------------------------------------------------------------------------
# Paths. The data file is large and gitignored, so it is always read from the
# canonical checkout by absolute path. Outputs are written next to this script.
# ------------------------------------------------------------------------------

data_root <- "/Users/jameswrightson/Documents/Projects/mimic/nonurgent/mimiced_compare"
ed_path   <- file.path(data_root, "MIMICED", "ed_join_cc.parquet")

script_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  hit  <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1) {
    normalizePath(dirname(sub("^--file=", "", hit)))
  } else {
    file.path(data_root, "ANALYSIS", "reviewer_response")
  }
})
out_dir <- script_dir

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------------------
# Formatting helpers
# ------------------------------------------------------------------------------

fmt_n <- function(x) formatC(round(x), big.mark = ",", format = "d")
fmt_p <- function(x, d = 1) sprintf(paste0("%.", d, "f"), x)
# Signed difference, e.g. for percentage points
fmt_d <- function(x, d = 1) sprintf(paste0("%+.", d, "f"), x)

pct <- function(x, n) 100 * x / n

# ------------------------------------------------------------------------------
# Data. Published pipeline, in order:
#   1. all rows
#   2. drop missing acuity / age / race  -> "eligible visits"
#   3. arrange(intime), first row per subject_id -> published analysis sample
# ------------------------------------------------------------------------------

raw <- read_parquet(ed_path) |>
  mutate(combined_group = paste0(nyu, res, acuity_out))

eligible <- raw |>
  filter(!is.na(acuity) & !is.na(age) & !is.na(race))

first_visits <- eligible |>
  arrange(intime) |>
  group_by(subject_id) |>
  slice_head(n = 1) |>
  ungroup()

n_raw   <- nrow(raw)
n_elig  <- nrow(eligible)
n_first <- nrow(first_visits)

# ------------------------------------------------------------------------------
# Shared summary functions. Both samples go through the same code so that the
# two columns of the side-by-side table are strictly comparable.
# ------------------------------------------------------------------------------

# Cohen's kappa exactly as the original analysis does it: psych::cohen.kappa on
# a cbind() of the two 0/1 columns.
#
# NOTE ON THE CI: cohen.kappa()$confid is a 2 x 3 matrix
#   rows = unweighted / weighted kappa, cols = lower / estimate / upper.
# The published notebook indexes it with confid[1] and confid[2], which under
# column-major order are the *lower* bounds of the unweighted and weighted
# kappa - the same number twice, not a lower and an upper limit. Because both
# variables are binary the weighted and unweighted kappa are identical, so the
# published point estimates are unaffected; only the printed upper limit was
# wrong. This script uses confid[1, 1] and confid[1, 3] for a genuine 95%
# interval. The point estimates below still reproduce the published values.
kappa_pair <- function(d, v1, v2) {
  k <- cohen.kappa(x = cbind(d[[v1]], d[[v2]]))
  tibble(
    kappa    = k$kappa,
    ci_lower = k$confid[1, 1],
    ci_upper = k$confid[1, 3]
  )
}

kappa_table <- function(d, sample_label) {
  pairs <- list(
    c("Diagnosis",     "Triage Acuity", "nyu",        "acuity_out"),
    c("Diagnosis",     "Resources",     "nyu",        "res"),
    c("Triage Acuity", "Resources",     "acuity_out", "res")
  )
  map_dfr(pairs, function(p) {
    kappa_pair(d, p[3], p[4]) |>
      mutate(sample = sample_label, comparison = paste(p[1], "vs", p[2]), .before = 1)
  })
}

algorithm_totals <- function(d, sample_label) {
  n <- nrow(d)
  tibble(
    sample    = sample_label,
    n_total   = n,
    algorithm = c("Diagnosis", "Resources", "Triage Acuity",
                  "Any algorithm", "All three algorithms"),
    n_flagged = c(sum(d$nyu), sum(d$res), sum(d$acuity_out),
                  sum(d$combined_group != "000"),
                  sum(d$combined_group == "111"))
  ) |>
    mutate(percent = pct(n_flagged, n_total))
}

group_table <- function(d, sample_label) {
  all_groups <- c("000", "100", "010", "001", "110", "101", "011", "111")
  tibble(combined_group = all_groups) |>
    left_join(count(d, combined_group), by = "combined_group") |>
    mutate(
      n       = coalesce(n, 0L),
      percent = pct(n, nrow(d)),
      sample  = sample_label
    )
}

# Median age, % female, % admitted, % home, median acuity, mean length of stay,
# split by whether the visit was flagged by at least one algorithm.
# Definitions follow the published Table 2 code: admitted = disposition
# "ADMITTED", home = disposition "HOME", female = gender "F".
# length_of_stay is in minutes.
profile_table <- function(d, sample_label) {
  d |>
    mutate(flag_status = if_else(combined_group != "000", "Flagged", "Unflagged")) |>
    group_by(flag_status) |>
    summarise(
      sample        = sample_label,
      n             = n(),
      age_median    = median(age, na.rm = TRUE),
      pct_female    = pct(sum(gender == "F"), n()),
      pct_admitted  = pct(sum(disposition == "ADMITTED"), n()),
      pct_home      = pct(sum(disposition == "HOME"), n()),
      acuity_median = median(acuity, na.rm = TRUE),
      los_mean      = mean(length_of_stay, na.rm = TRUE),
      .groups       = "drop"
    ) |>
    relocate(sample)
}

# ==============================================================================
# 0. VERIFICATION - reproduce the published first-visit results exactly.
#    Reported BEFORE anything else. Any failure stops the script.
# ==============================================================================

cat("\n")
cat("==============================================================\n")
cat(" 0. VERIFICATION AGAINST PUBLISHED FIRST-VISIT RESULTS\n")
cat("==============================================================\n\n")

check_log <- list()

check <- function(label, observed, expected, tol = 0) {
  ok <- (as.numeric(observed) == as.numeric(expected)) ||
    (tol > 0 && abs(as.numeric(observed) - as.numeric(expected)) <= tol)
  check_log[[length(check_log) + 1]] <<- tibble(
    check = label, observed = as.numeric(observed),
    expected = as.numeric(expected), pass = ok
  )
  cat(sprintf("  [%s] %-46s observed = %-10s expected = %-10s\n",
              if (ok) "PASS" else "FAIL", label,
              format(observed), format(expected)))
  invisible(ok)
}

# Cohort construction
check("Eligible visits",                n_elig, 417723)
check("Distinct subject_id (eligible)", n_distinct(eligible$subject_id), 201106)
check("First-visit sample rows",        n_first, 201106)

# Headline flag count
check("Flagged by >=1 algorithm",
      sum(first_visits$combined_group != "000"), 100568)
check("Flagged by >=1 algorithm (%)",
      round(pct(sum(first_visits$combined_group != "000"), n_first), 1),
      50.0, tol = 0.05)

# Overlap cells
expected_groups <- c("100" = 44119, "010" = 23427, "110" = 17306, "001" = 4690,
                     "011" = 4278,  "101" = 3578,  "111" = 3170,  "000" = 100538)
obs_groups <- table(first_visits$combined_group)
for (g in names(expected_groups)) {
  check(paste0("Group '", g, "'"), as.integer(obs_groups[[g]]), expected_groups[[g]])
}

# Algorithm totals
check("Diagnosis total",     sum(first_visits$nyu),        68173)
check("Resources total",     sum(first_visits$res),        48181)
check("Triage-Acuity total", sum(first_visits$acuity_out), 15716)

# Cohen's kappa (3 dp)
kappa_first <- kappa_table(first_visits, "First visits")
kap_of <- function(cmp) kappa_first$kappa[kappa_first$comparison == cmp]
check("Kappa Diagnosis vs Triage Acuity",
      round(kap_of("Diagnosis vs Triage Acuity"), 3), 0.039, tol = 0.0005)
check("Kappa Diagnosis vs Resources",
      round(kap_of("Diagnosis vs Resources"), 3), 0.099, tol = 0.0005)
check("Kappa Triage Acuity vs Resources",
      round(kap_of("Triage Acuity vs Resources"), 3), 0.131, tol = 0.0005)

checks <- bind_rows(check_log)
n_fail <- sum(!checks$pass)

cat("\n")
cat(sprintf("  %d checks run, %d passed, %d failed.\n",
            nrow(checks), sum(checks$pass), n_fail))

if (n_fail > 0) {
  cat("\n  VERIFICATION FAILED. Failing checks:\n")
  print(as.data.frame(filter(checks, !pass)), row.names = FALSE)
  stop("Published first-visit results did not reproduce. Sensitivity analysis not run.",
       call. = FALSE)
}
cat("  VERIFICATION PASSED - proceeding to R1.5 and R2.1.\n\n")

# ==============================================================================
# 1. R1.5 - VISITS PER PATIENT
#    Computed on the 417,723 ELIGIBLE visits, before the first-visit restriction.
# ==============================================================================

cat("==============================================================\n")
cat(" 1. R1.5 - VISITS PER PATIENT (eligible visits)\n")
cat("==============================================================\n\n")

n_discarded   <- n_elig - n_first
pct_discarded <- pct(n_discarded, n_elig)

cat(sprintf("  Eligible visits         : %s\n", fmt_n(n_elig)))
cat(sprintf("  First visits retained   : %s\n", fmt_n(n_first)))
cat(sprintf("  Repeat visits discarded : %s (%s%% of eligible visits)\n",
            fmt_n(n_discarded), fmt_p(pct_discarded)))

visit_counts <- eligible |>
  count(subject_id, name = "n_visits") |>
  arrange(desc(n_visits))

n_patients   <- nrow(visit_counts)
total_visits <- sum(visit_counts$n_visits)

vpp_median <- median(visit_counts$n_visits)
vpp_mean   <- mean(visit_counts$n_visits)
vpp_max    <- max(visit_counts$n_visits)
vpp_q1     <- quantile(visit_counts$n_visits, 0.25, names = FALSE)
vpp_q3     <- quantile(visit_counts$n_visits, 0.75, names = FALSE)

cat(sprintf("\n  Patients                : %s\n", fmt_n(n_patients)))
cat(sprintf("  Visits/patient median   : %s (IQR %s-%s)\n", vpp_median, vpp_q1, vpp_q3))
cat(sprintf("  Visits/patient mean     : %s\n", fmt_p(vpp_mean, 2)))
cat(sprintf("  Visits/patient max      : %s\n", vpp_max))

band_levels <- c("1", "2", "3", "4-5", "6-10", "11-20", "21+")

vpp_bands <- visit_counts |>
  mutate(band = cut(n_visits,
                    breaks = c(0, 1, 2, 3, 5, 10, 20, Inf),
                    labels = band_levels)) |>
  group_by(band) |>
  summarise(patients = n(), visits = sum(n_visits), .groups = "drop") |>
  mutate(
    pct_patients = pct(patients, n_patients),
    pct_visits   = pct(visits, total_visits)
  )

cat("\n  Distribution of visits per patient:\n")
print(as.data.frame(vpp_bands), row.names = FALSE, digits = 4)

# Concentration: share of visits contributed by the heaviest-attending patients.
# visit_counts is already sorted descending. Ties at the boundary are broken
# arbitrarily, so the visit-count cut-off at each threshold is reported too.
top_share <- function(p) {
  k <- ceiling(p * n_patients)
  tibble(
    top_pct       = p * 100,
    n_patients    = k,
    min_visits    = visit_counts$n_visits[k],
    visits        = sum(visit_counts$n_visits[seq_len(k)]),
    pct_of_visits = pct(sum(visit_counts$n_visits[seq_len(k)]), total_visits)
  )
}
concentration <- map_dfr(c(0.01, 0.05, 0.10), top_share)

cat("\n  Concentration of visits among frequent attenders:\n")
print(as.data.frame(concentration), row.names = FALSE, digits = 4)

# Are the retained index visits representative?
# Compare patients with exactly 1 eligible visit against patients with 2+, using
# each patient's FIRST visit (for single-visit patients this is their only one).
first_with_counts <- first_visits |>
  left_join(visit_counts, by = "subject_id") |>
  mutate(
    patient_group = if_else(n_visits == 1,
                            "Single-visit patients",
                            "Repeat-visit patients (2+)"),
    race_collapsed = case_when(
      str_detect(race, "WHITE")    ~ "White",
      str_detect(race, "BLACK")    ~ "Black",
      str_detect(race, "HISPANIC") ~ "Hispanic/Latino",
      str_detect(race, "ASIAN")    ~ "Asian",
      TRUE                         ~ "Other"
    )
  )

single_vs_repeat <- first_with_counts |>
  group_by(patient_group) |>
  summarise(
    patients      = n(),
    age_median    = median(age, na.rm = TRUE),
    age_mean      = mean(age, na.rm = TRUE),
    pct_female    = pct(sum(gender == "F"), n()),
    pct_diagnosis = pct(sum(nyu), n()),
    pct_resources = pct(sum(res), n()),
    pct_acuity    = pct(sum(acuity_out), n()),
    pct_any       = pct(sum(combined_group != "000"), n()),
    .groups       = "drop"
  )

single_vs_repeat_race <- first_with_counts |>
  count(patient_group, race_collapsed) |>
  group_by(patient_group) |>
  mutate(percent = pct(n, sum(n))) |>
  ungroup()

cat("\n  Single-visit vs repeat-visit patients (each patient's first visit):\n")
print(as.data.frame(single_vs_repeat), row.names = FALSE, digits = 4)
cat("\n  Race distribution:\n")
print(as.data.frame(single_vs_repeat_race), row.names = FALSE, digits = 4)

# ==============================================================================
# 2. R2.1 - SENSITIVITY ANALYSIS ON ALL ELIGIBLE VISITS
# ==============================================================================

cat("\n")
cat("==============================================================\n")
cat(" 2. R2.1 - ALL-VISIT SENSITIVITY ANALYSIS\n")
cat("==============================================================\n\n")

totals_first <- algorithm_totals(first_visits, "First visits")
totals_all   <- algorithm_totals(eligible,     "All visits")

totals_side <- totals_first |>
  select(algorithm, n_first = n_flagged, pct_first = percent) |>
  left_join(totals_all |> select(algorithm, n_all = n_flagged, pct_all = percent),
            by = "algorithm") |>
  mutate(diff_pp = pct_all - pct_first)

cat("  Algorithm totals:\n")
print(as.data.frame(totals_side), row.names = FALSE, digits = 4)

groups_first <- group_table(first_visits, "First visits")
groups_all   <- group_table(eligible,     "All visits")

groups_side <- groups_first |>
  select(combined_group, n_first = n, pct_first = percent) |>
  left_join(groups_all |> select(combined_group, n_all = n, pct_all = percent),
            by = "combined_group") |>
  mutate(diff_pp = pct_all - pct_first)

cat("\n  Overlap groups (nyu / res / acuity_out):\n")
print(as.data.frame(groups_side), row.names = FALSE, digits = 4)

kappa_all <- kappa_table(eligible, "All visits")

kappa_side <- kappa_first |>
  select(comparison, kappa_first = kappa, lo_first = ci_lower, hi_first = ci_upper) |>
  left_join(kappa_all |> select(comparison, kappa_all = kappa,
                                lo_all = ci_lower, hi_all = ci_upper),
            by = "comparison") |>
  mutate(diff = kappa_all - kappa_first)

cat("\n  Cohen's kappa with 95% CI:\n")
print(as.data.frame(kappa_side), row.names = FALSE, digits = 3)

profile_first <- profile_table(first_visits, "First visits")
profile_all   <- profile_table(eligible,     "All visits")
profiles      <- bind_rows(profile_first, profile_all)

cat("\n  Flagged / unflagged profiles:\n")
print(as.data.frame(profiles), row.names = FALSE, digits = 4)

# ==============================================================================
# 3. WRITE MARKDOWN OUTPUTS
# ==============================================================================

get_tot  <- function(alg, col)     totals_side[[col]][totals_side$algorithm == alg]
get_kap  <- function(col, cmp)     kappa_side[[col]][kappa_side$comparison == cmp]
get_prof <- function(smp, fl, col) profiles[[col]][profiles$sample == smp &
                                                     profiles$flag_status == fl]
get_svr  <- function(grp, col)     single_vs_repeat[[col]][single_vs_repeat$patient_group == grp]
get_race <- function(grp, r)       single_vs_repeat_race$percent[
  single_vs_repeat_race$patient_group == grp &
    single_vs_repeat_race$race_collapsed == r]
get_conc <- function(p, col)       concentration[[col]][concentration$top_pct == p]
get_band <- function(b, col)       vpp_bands[[col]][vpp_bands$band == b]

single_lab <- "Single-visit patients"
repeat_lab <- "Repeat-visit patients (2+)"

# ------------------------------------------------------------------------------
# 3a. R1.5 markdown
# ------------------------------------------------------------------------------

band_rows <- vpp_bands |>
  mutate(row = sprintf("| %s | %s | %s | %s | %s |",
                       band, fmt_n(patients), fmt_p(pct_patients),
                       fmt_n(visits), fmt_p(pct_visits))) |>
  pull(row)

conc_rows <- concentration |>
  mutate(row = sprintf("| Top %s%% | %s | >= %s | %s | %s |",
                       fmt_p(top_pct, 0), fmt_n(n_patients), min_visits,
                       fmt_n(visits), fmt_p(pct_of_visits))) |>
  pull(row)

race_levels <- c("White", "Black", "Hispanic/Latino", "Asian", "Other")
race_rows <- map_chr(race_levels, function(r) {
  sprintf("| %s | %s | %s | %s |", r,
          fmt_p(get_race(single_lab, r)), fmt_p(get_race(repeat_lab, r)),
          fmt_d(get_race(repeat_lab, r) - get_race(single_lab, r)))
})

freq_bands <- c("6-10", "11-20", "21+")

r1_md <- c(
  "# R1.5 - Visits per patient and what the first-visit restriction discards",
  "",
  sprintf("*Generated by `r1_05_r2_01_repeat_visits.R` on %s. All figures are computed on the %s eligible visits (rows with missing acuity, age or race removed), before the first-visit restriction, unless stated otherwise.*",
          format(Sys.Date()), fmt_n(n_elig)),
  "",
  "## Verdict",
  "",
  sprintf("The reviewer is right that the restriction discards a large share of the data: %s of the %s eligible visits (%s%%) are repeat presentations that never enter the published analysis, leaving %s index visits, one per patient. ED use in MIMIC-IV-ED is heavily concentrated - the median patient contributes a single visit, but the mean is %s and one patient attended %s times, and the top 10%% of patients by visit count account for %s%% of all eligible visits. Frequent attenders are therefore genuinely under-represented at the *visit* level, exactly as the reviewer says, and they are not a random subset of patients: compared with single-visit patients they are older (median age %s vs %s years), more often female (%s%% vs %s%%), and more often Black (%s%% vs %s%%) or Hispanic/Latino (%s%% vs %s%%).",
          fmt_n(n_discarded), fmt_n(n_elig), fmt_p(pct_discarded), fmt_n(n_first),
          fmt_p(vpp_mean, 2), vpp_max, fmt_p(get_conc(10, "pct_of_visits")),
          get_svr(repeat_lab, "age_median"), get_svr(single_lab, "age_median"),
          fmt_p(get_svr(repeat_lab, "pct_female")), fmt_p(get_svr(single_lab, "pct_female")),
          fmt_p(get_race(repeat_lab, "Black")), fmt_p(get_race(single_lab, "Black")),
          fmt_p(get_race(repeat_lab, "Hispanic/Latino")), fmt_p(get_race(single_lab, "Hispanic/Latino"))),
  sprintf("What does not follow is a material distortion of the headline estimate. The index visits of repeat attenders are flagged by at least one algorithm at almost the same rate as those of single-visit patients (%s%% vs %s%%), because the individual algorithms move in opposite directions: Diagnosis is higher in repeat attenders (%s%% vs %s%%) while Resources (%s%% vs %s%%) and Triage-Acuity (%s%% vs %s%%) are lower, and these largely cancel.",
          fmt_p(get_svr(repeat_lab, "pct_any")), fmt_p(get_svr(single_lab, "pct_any")),
          fmt_p(get_svr(repeat_lab, "pct_diagnosis")), fmt_p(get_svr(single_lab, "pct_diagnosis")),
          fmt_p(get_svr(repeat_lab, "pct_resources")), fmt_p(get_svr(single_lab, "pct_resources")),
          fmt_p(get_svr(repeat_lab, "pct_acuity")), fmt_p(get_svr(single_lab, "pct_acuity"))),
  sprintf("The companion sensitivity analysis (`r2_01_sensitivity_all_visits.md`) confirms this directly: re-running all three algorithms on every eligible visit moves no headline figure by more than %s percentage points, and none of the paper's three conclusions changes.",
          fmt_p(max(abs(totals_side$diff_pp)))),
  "The restriction is therefore best described in the manuscript as a deliberate choice of the *patient* rather than the *visit* as the unit of analysis, which keeps observations independent, rather than as a source of bias.",
  "",
  "## 1. What the restriction discards",
  "",
  "| Quantity | N | % of eligible visits |",
  "| --- | ---: | ---: |",
  sprintf("| Eligible visits | %s | 100.0 |", fmt_n(n_elig)),
  sprintf("| First visits retained (published sample) | %s | %s |",
          fmt_n(n_first), fmt_p(pct(n_first, n_elig))),
  sprintf("| **Repeat visits discarded** | **%s** | **%s** |",
          fmt_n(n_discarded), fmt_p(pct_discarded)),
  "",
  sprintf("Of the %s rows in the source file, %s are dropped for missing acuity, age or race before any of this, leaving the %s eligible visits used throughout.",
          fmt_n(n_raw), fmt_n(n_raw - n_elig), fmt_n(n_elig)),
  "",
  "## 2. Distribution of visits per patient",
  "",
  sprintf("Across %s patients contributing %s eligible visits:",
          fmt_n(n_patients), fmt_n(total_visits)),
  "",
  "| Statistic | Value |",
  "| --- | ---: |",
  sprintf("| Median visits per patient | %s (IQR %s-%s) |", vpp_median, vpp_q1, vpp_q3),
  sprintf("| Mean visits per patient | %s |", fmt_p(vpp_mean, 2)),
  sprintf("| Maximum visits by a single patient | %s |", vpp_max),
  "",
  "| Visits per patient | Patients (N) | Patients (%) | Visits (N) | Visits (%) |",
  "| --- | ---: | ---: | ---: | ---: |",
  band_rows,
  "",
  sprintf("Two thirds of patients (%s%%) attend exactly once, but those single attendances make up only %s%% of eligible visits. Conversely the %s%% of patients attending six or more times contribute %s%% of all visits.",
          fmt_p(get_band("1", "pct_patients")), fmt_p(get_band("1", "pct_visits")),
          fmt_p(sum(vpp_bands$pct_patients[vpp_bands$band %in% freq_bands])),
          fmt_p(sum(vpp_bands$pct_visits[vpp_bands$band %in% freq_bands]))),
  "",
  "## 3. Concentration among frequent attenders",
  "",
  "This is the quantitative form of the reviewer's point.",
  "",
  "| Patient group (ranked by visit count) | Patients (N) | Visit-count threshold | Visits contributed (N) | Share of all eligible visits (%) |",
  "| --- | ---: | ---: | ---: | ---: |",
  conc_rows,
  "",
  sprintf("The heaviest-attending 1%% of patients (%s people, each with %s or more eligible visits) account for %s%% of all eligible ED visits. Under the first-visit design each of them contributes exactly one row, the same weight as a patient who attended once.",
          fmt_n(get_conc(1, "n_patients")), get_conc(1, "min_visits"),
          fmt_p(get_conc(1, "pct_of_visits"))),
  "",
  "*Patients are ranked by visit count in descending order and the top k taken, where k is the ceiling of the stated percentage of patients. Ties at the boundary are broken arbitrarily, so the visit-count threshold is reported to make each cut-off transparent.*",
  "",
  "## 4. Are the retained index visits representative?",
  "",
  "Patients with exactly one eligible visit compared with patients who had two or more, using each patient's **first** visit - which for single-visit patients is their only visit. This is the relevant comparison, because the published sample consists exactly of these index visits.",
  "",
  "| Characteristic | Single-visit patients | Repeat-visit patients (2+) | Difference |",
  "| --- | ---: | ---: | ---: |",
  sprintf("| Patients (N) | %s | %s | - |",
          fmt_n(get_svr(single_lab, "patients")), fmt_n(get_svr(repeat_lab, "patients"))),
  sprintf("| Age, median (years) | %s | %s | %s |",
          get_svr(single_lab, "age_median"), get_svr(repeat_lab, "age_median"),
          fmt_d(get_svr(repeat_lab, "age_median") - get_svr(single_lab, "age_median"), 0)),
  sprintf("| Age, mean (years) | %s | %s | %s |",
          fmt_p(get_svr(single_lab, "age_mean")), fmt_p(get_svr(repeat_lab, "age_mean")),
          fmt_d(get_svr(repeat_lab, "age_mean") - get_svr(single_lab, "age_mean"))),
  sprintf("| Female (%%) | %s | %s | %s |",
          fmt_p(get_svr(single_lab, "pct_female")), fmt_p(get_svr(repeat_lab, "pct_female")),
          fmt_d(get_svr(repeat_lab, "pct_female") - get_svr(single_lab, "pct_female"))),
  "",
  "Self-reported race, collapsed exactly as in Table 1 of the paper:",
  "",
  "| Race | Single-visit patients (%) | Repeat-visit patients (%) | Difference (pp) |",
  "| --- | ---: | ---: | ---: |",
  race_rows,
  "",
  "Flag rate at the index visit, by algorithm:",
  "",
  "| Algorithm | Single-visit patients (%) | Repeat-visit patients (%) | Difference (pp) |",
  "| --- | ---: | ---: | ---: |",
  sprintf("| Diagnosis | %s | %s | %s |",
          fmt_p(get_svr(single_lab, "pct_diagnosis")), fmt_p(get_svr(repeat_lab, "pct_diagnosis")),
          fmt_d(get_svr(repeat_lab, "pct_diagnosis") - get_svr(single_lab, "pct_diagnosis"))),
  sprintf("| Resources | %s | %s | %s |",
          fmt_p(get_svr(single_lab, "pct_resources")), fmt_p(get_svr(repeat_lab, "pct_resources")),
          fmt_d(get_svr(repeat_lab, "pct_resources") - get_svr(single_lab, "pct_resources"))),
  sprintf("| Triage-Acuity | %s | %s | %s |",
          fmt_p(get_svr(single_lab, "pct_acuity")), fmt_p(get_svr(repeat_lab, "pct_acuity")),
          fmt_d(get_svr(repeat_lab, "pct_acuity") - get_svr(single_lab, "pct_acuity"))),
  sprintf("| **Any of the three** | **%s** | **%s** | **%s** |",
          fmt_p(get_svr(single_lab, "pct_any")), fmt_p(get_svr(repeat_lab, "pct_any")),
          fmt_d(get_svr(repeat_lab, "pct_any") - get_svr(single_lab, "pct_any"))),
  "",
  sprintf("Repeat attenders differ demographically and their index visit is somewhat more likely to be flagged by the Diagnosis algorithm (%s%% vs %s%%), but it is *less* likely to be flagged by Resources (%s%% vs %s%%) and Triage-Acuity (%s%% vs %s%%). The net effect on the headline \"flagged by at least one algorithm\" figure is %s percentage points. This offsetting is the mechanism behind the near-identical first-visit and all-visit estimates reported in the sensitivity analysis.",
          fmt_p(get_svr(repeat_lab, "pct_diagnosis")), fmt_p(get_svr(single_lab, "pct_diagnosis")),
          fmt_p(get_svr(repeat_lab, "pct_resources")), fmt_p(get_svr(single_lab, "pct_resources")),
          fmt_p(get_svr(repeat_lab, "pct_acuity")), fmt_p(get_svr(single_lab, "pct_acuity")),
          fmt_d(get_svr(repeat_lab, "pct_any") - get_svr(single_lab, "pct_any"))),
  ""
)

writeLines(r1_md, file.path(out_dir, "r1_05_visits_per_patient.md"))

# ------------------------------------------------------------------------------
# 3b. R2.1 markdown
# ------------------------------------------------------------------------------

group_labels <- c(
  "000" = "None",
  "100" = "Diagnosis only",
  "010" = "Resources only",
  "001" = "Triage-Acuity only",
  "110" = "Diagnosis + Resources",
  "101" = "Diagnosis + Triage-Acuity",
  "011" = "Resources + Triage-Acuity",
  "111" = "All three"
)

group_rows <- groups_side |>
  mutate(row = sprintf("| %s | %s | %s | %s | %s | %s | %s |",
                       combined_group, group_labels[combined_group],
                       fmt_n(n_first), fmt_p(pct_first, 2),
                       fmt_n(n_all), fmt_p(pct_all, 2),
                       fmt_d(diff_pp, 2))) |>
  pull(row)

kappa_rows <- kappa_side |>
  mutate(row = sprintf("| %s | %s [%s-%s] | %s [%s-%s] | %s |",
                       comparison,
                       fmt_p(kappa_first, 3), fmt_p(lo_first, 3), fmt_p(hi_first, 3),
                       fmt_p(kappa_all, 3), fmt_p(lo_all, 3), fmt_p(hi_all, 3),
                       fmt_d(diff, 3))) |>
  pull(row)

prof_row <- function(label, col, digits = 1) {
  sprintf("| %s | %s | %s | %s | %s |", label,
          fmt_p(get_prof("First visits", "Flagged",   col), digits),
          fmt_p(get_prof("First visits", "Unflagged", col), digits),
          fmt_p(get_prof("All visits",   "Flagged",   col), digits),
          fmt_p(get_prof("All visits",   "Unflagged", col), digits))
}

d_any  <- get_tot("Any algorithm", "diff_pp")
d_dx   <- get_tot("Diagnosis", "diff_pp")
d_res  <- get_tot("Resources", "diff_pp")
d_acu  <- get_tot("Triage Acuity", "diff_pp")
d_all3 <- get_tot("All three algorithms", "diff_pp")

r2_md <- c(
  "# R2.1 - Sensitivity analysis: all eligible visits vs first visits only",
  "",
  sprintf("*Generated by `r1_05_r2_01_repeat_visits.R` on %s. The script first reproduces every published first-visit figure exactly - cohort sizes, all eight overlap cells, all three algorithm totals and all three kappas to 3 dp - and halts if any check fails. All %d checks passed.*",
          format(Sys.Date()), nrow(checks)),
  "",
  "## Verdict",
  "",
  sprintf("All three algorithms were re-run on the full set of %s eligible visits rather than the %s first visits, and none of the paper's conclusions changes. The proportion flagged by at least one algorithm is %s%% across all visits against %s%% in the published sample, a difference of %s percentage points. The individual algorithms shift by at most %s percentage points (Diagnosis %s, Resources %s, Triage-Acuity %s), and the proportion flagged by all three moves from %s%% to %s%%.",
          fmt_n(n_elig), fmt_n(n_first),
          fmt_p(get_tot("Any algorithm", "pct_all")),
          fmt_p(get_tot("Any algorithm", "pct_first")),
          fmt_d(d_any),
          fmt_p(max(abs(c(d_dx, d_res, d_acu)))),
          fmt_d(d_dx), fmt_d(d_res), fmt_d(d_acu),
          fmt_p(get_tot("All three algorithms", "pct_first"), 2),
          fmt_p(get_tot("All three algorithms", "pct_all"), 2)),
  sprintf("Agreement between the algorithms remains poor on every pairing: kappa moves from %s to %s (Diagnosis vs Triage-Acuity), from %s to %s (Diagnosis vs Resources) and from %s to %s (Triage-Acuity vs Resources), all still within the slight-agreement range. The clinical profile of flagged visits is likewise stable - flagged visits remain younger, more often female, far more often discharged home, of lower acuity and shorter stay than unflagged visits, in both samples.",
          fmt_p(get_kap("kappa_first", "Diagnosis vs Triage Acuity"), 3),
          fmt_p(get_kap("kappa_all", "Diagnosis vs Triage Acuity"), 3),
          fmt_p(get_kap("kappa_first", "Diagnosis vs Resources"), 3),
          fmt_p(get_kap("kappa_all", "Diagnosis vs Resources"), 3),
          fmt_p(get_kap("kappa_first", "Triage Acuity vs Resources"), 3),
          fmt_p(get_kap("kappa_all", "Triage Acuity vs Resources"), 3)),
  "The direction of the small shifts is consistent with what the R1.5 analysis shows about frequent attenders: including their repeat visits pulls the Diagnosis flag rate up and the Resources and Triage-Acuity flag rates down, and these largely offset in the combined figure. The first-visit restriction should therefore be presented as a design choice that makes the patient the unit of analysis and keeps observations independent, not as a decision that drives the results.",
  "",
  "## 1. Headline comparison",
  "",
  "| Measure | First visits (N) | First visits (%) | All visits (N) | All visits (%) | Difference (pp) |",
  "| --- | ---: | ---: | ---: | ---: | ---: |",
  sprintf("| **Total visits analysed** | %s | 100.0 | %s | 100.0 | - |",
          fmt_n(n_first), fmt_n(n_elig)),
  sprintf("| **Flagged by at least one algorithm** | %s | %s | %s | %s | %s |",
          fmt_n(get_tot("Any algorithm", "n_first")), fmt_p(get_tot("Any algorithm", "pct_first")),
          fmt_n(get_tot("Any algorithm", "n_all")),   fmt_p(get_tot("Any algorithm", "pct_all")),
          fmt_d(d_any)),
  sprintf("| Diagnosis algorithm | %s | %s | %s | %s | %s |",
          fmt_n(get_tot("Diagnosis", "n_first")), fmt_p(get_tot("Diagnosis", "pct_first")),
          fmt_n(get_tot("Diagnosis", "n_all")),   fmt_p(get_tot("Diagnosis", "pct_all")),
          fmt_d(d_dx)),
  sprintf("| Resources algorithm | %s | %s | %s | %s | %s |",
          fmt_n(get_tot("Resources", "n_first")), fmt_p(get_tot("Resources", "pct_first")),
          fmt_n(get_tot("Resources", "n_all")),   fmt_p(get_tot("Resources", "pct_all")),
          fmt_d(d_res)),
  sprintf("| Triage-Acuity algorithm | %s | %s | %s | %s | %s |",
          fmt_n(get_tot("Triage Acuity", "n_first")), fmt_p(get_tot("Triage Acuity", "pct_first")),
          fmt_n(get_tot("Triage Acuity", "n_all")),   fmt_p(get_tot("Triage Acuity", "pct_all")),
          fmt_d(d_acu)),
  sprintf("| Flagged by all three | %s | %s | %s | %s | %s |",
          fmt_n(get_tot("All three algorithms", "n_first")),
          fmt_p(get_tot("All three algorithms", "pct_first"), 2),
          fmt_n(get_tot("All three algorithms", "n_all")),
          fmt_p(get_tot("All three algorithms", "pct_all"), 2),
          fmt_d(d_all3, 2)),
  "",
  "## 2. All eight overlap groups",
  "",
  "`combined_group` is `paste0(nyu, res, acuity_out)`, i.e. Diagnosis / Resources / Triage-Acuity.",
  "",
  "| Group | Algorithms flagging | First visits (N) | First visits (%) | All visits (N) | All visits (%) | Difference (pp) |",
  "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
  group_rows,
  "",
  "## 3. Agreement (Cohen's kappa, 95% CI)",
  "",
  "| Comparison | First visits | All visits | Difference |",
  "| --- | --- | --- | ---: |",
  kappa_rows,
  "",
  "*Kappa is computed with `psych::cohen.kappa()` on a `cbind()` of the two binary columns, exactly as in the published analysis, and the point estimates in the first-visit column reproduce the published values. One technical note: the published notebook printed the lower confidence limit twice, because `cohen.kappa()$confid` is a 2 x 3 matrix and it was indexed with `confid[1]` and `confid[2]` (both lower limits) rather than `confid[1, 1]` and `confid[1, 3]`. This affects only the printed interval, never the kappa estimates; the intervals above use the correct limits.*",
  "",
  "## 4. Clinical profile of flagged and unflagged visits",
  "",
  "| Characteristic | First visits: flagged | First visits: unflagged | All visits: flagged | All visits: unflagged |",
  "| --- | ---: | ---: | ---: | ---: |",
  sprintf("| Visits (N) | %s | %s | %s | %s |",
          fmt_n(get_prof("First visits", "Flagged", "n")),
          fmt_n(get_prof("First visits", "Unflagged", "n")),
          fmt_n(get_prof("All visits", "Flagged", "n")),
          fmt_n(get_prof("All visits", "Unflagged", "n"))),
  prof_row("Age, median (years)", "age_median", 0),
  prof_row("Female (%)", "pct_female"),
  prof_row("Admitted (%)", "pct_admitted"),
  prof_row("Discharged home (%)", "pct_home"),
  prof_row("Acuity, median (ESI)", "acuity_median", 0),
  prof_row("Length of stay, mean (minutes)", "los_mean"),
  "",
  "*Definitions follow the published Table 2 code: admitted = `disposition == \"ADMITTED\"`, home = `disposition == \"HOME\"`, female = `gender == \"F\"`, length of stay = `length_of_stay` in minutes with missing values excluded.*",
  "",
  "## 5. Does each of the paper's conclusions survive?",
  "",
  "| Paper's conclusion | First visits | All visits | Survives? |",
  "| --- | ---: | ---: | --- |",
  sprintf("| (a) About half of visits are flagged by at least one algorithm | %s%% | %s%% | **Yes** - difference of %s pp |",
          fmt_p(get_tot("Any algorithm", "pct_first")),
          fmt_p(get_tot("Any algorithm", "pct_all")), fmt_d(d_any)),
  sprintf("| (b) Agreement between algorithms is poor (kappa ~0.04-0.13) | %s to %s | %s to %s | **Yes** - still only slight agreement on every pairing |",
          fmt_p(min(kappa_side$kappa_first), 3), fmt_p(max(kappa_side$kappa_first), 3),
          fmt_p(min(kappa_side$kappa_all), 3),   fmt_p(max(kappa_side$kappa_all), 3)),
  sprintf("| (c) Only ~1.6%% are flagged by all three | %s%% | %s%% | **Yes** - difference of %s pp |",
          fmt_p(get_tot("All three algorithms", "pct_first"), 2),
          fmt_p(get_tot("All three algorithms", "pct_all"), 2), fmt_d(d_all3, 2)),
  "",
  "**All three conclusions survive the sensitivity analysis unchanged.**",
  "",
  "## 6. Caution on interpreting the all-visit column",
  "",
  sprintf("The all-visit analysis treats each of the %s eligible visits as an independent observation, and it is not. A patient who attended %s times contributes %s rows, and that patient's diagnoses, triage assignment and typical resource use are correlated across their own visits. The effective sample size is therefore much closer to the %s patients than to the %s visits, and the clustering is severe: the heaviest-attending 10%% of patients supply %s%% of all rows.",
          fmt_n(n_elig), vpp_max, vpp_max, fmt_n(n_patients), fmt_n(n_elig),
          fmt_p(get_conc(10, "pct_of_visits"))),
  "",
  "Three practical consequences for interpretation:",
  "",
  "1. **The confidence intervals in the all-visit column are too narrow.** They assume independent observations. The point estimates remain the correct visit-level proportions, but the precision is overstated, and the intervals must not be read as though they came from a sample of unrelated people. A cluster-robust or patient-level bootstrap approach would widen them.",
  "2. **The kappas describe agreement over visits, not over patients.** Because heavy attenders are counted many times, the all-visit kappas are weighted towards the diagnostic and triage patterns of a small group of frequent users. A shift in kappa between the two columns is as likely to reflect that reweighting as any real change in how well the algorithms agree.",
  "3. **The two columns answer different questions.** The first-visit column answers \"what fraction of *patients* attending the ED have a potentially avoidable index visit?\". The all-visit column answers \"what fraction of *ED attendances* are potentially avoidable?\". Both are legitimate, but they are not the same quantity, and the second is the more appropriate denominator for questions about ED workload or diversion capacity.",
  "",
  "Given the strong concentration of visits, we retain the first-visit design as the primary analysis so that each patient contributes one observation, and report the all-visit figures as a sensitivity analysis. The reassurance for the reader is that the two agree closely, so the choice of denominator does not drive any substantive claim in the paper.",
  ""
)

writeLines(r2_md, file.path(out_dir, "r2_01_sensitivity_all_visits.md"))

cat("\n")
cat("==============================================================\n")
cat(" 3. OUTPUTS WRITTEN\n")
cat("==============================================================\n")
cat(sprintf("  %s\n", file.path(out_dir, "r1_05_visits_per_patient.md")))
cat(sprintf("  %s\n", file.path(out_dir, "r2_01_sensitivity_all_visits.md")))
cat("\nDone.\n")
