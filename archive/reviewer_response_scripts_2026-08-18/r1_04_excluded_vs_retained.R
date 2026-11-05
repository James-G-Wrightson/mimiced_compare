# ---------------------------------------------------------------------------
# Reviewer response R1.4 (IJPDS revision)
#
#   "The exclusion of 6,934 visits without an assigned triage acuity score
#    requires further justification ... Please clarify the reasons for the
#    missing triage scores, whether excluded records differed systematically
#    from included visits, and the potential impact (selection bias) of their
#    exclusion."
#
# Input : MIMICED/ed_join_cc.parquet  (424,707 ED visits, before any exclusion)
# Output: r1_04_excluded_vs_retained.md (written next to this script, and to
#         ANALYSIS/reviewer_response/ in the main checkout)
#
# The analysis notebook (ANALYSIS/3_descriptive.ipynb) applies exactly one
# exclusion to the built dataset:
#     filter(!is.na(acuity) & !is.na(age) & !is.na(race))
# EXCLUDED = the 6,984 rows failing that filter
# RETAINED = the 417,723 rows passing it
#
# Run:  Rscript r1_04_excluded_vs_retained.R
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
})

options(dplyr.summarise.inform = FALSE)

root    <- "/Users/jameswrightson/Documents/Projects/mimic/nonurgent/mimiced_compare"
data_fp <- file.path(root, "MIMICED", "ed_join_cc.parquet")

script_dir <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) == 1) normalizePath(dirname(f)) else normalizePath(getwd())
})
canonical_dir <- file.path(root, "ANALYSIS", "reviewer_response")
out_dirs      <- unique(c(script_dir, canonical_dir))
for (d in out_dirs) dir.create(d, showWarnings = FALSE, recursive = TRUE)

ed <- read_parquet(data_fp) |>
  mutate(
    keep_row  = !is.na(acuity) & !is.na(age) & !is.na(race),
    group     = if_else(keep_row, "Retained", "Excluded"),
    miss_acu  = is.na(acuity),
    miss_age  = is.na(age),
    miss_race = is.na(race)
  )

# ---------------------------------------------------------------------------
# 1. VERIFICATION CHECKS  (script halts if any fail)
# ---------------------------------------------------------------------------

n_total        <- nrow(ed)
n_excluded     <- sum(!ed$keep_row)
n_retained     <- sum(ed$keep_row)
n_miss_acu     <- sum(ed$miss_acu)
n_agerace_only <- sum(!ed$keep_row & !ed$miss_acu)

checks <- tibble::tribble(
  ~check,                                     ~expected, ~observed,
  "Total rows",                               424707L,   as.integer(n_total),
  "EXCLUDED rows",                            6984L,     as.integer(n_excluded),
  "RETAINED rows",                            417723L,   as.integer(n_retained),
  "EXCLUDED + RETAINED == total",             424707L,   as.integer(n_excluded + n_retained),
  "Rows with is.na(acuity)",                  6934L,     as.integer(n_miss_acu),
  "Rows failing on age/race but NOT acuity",  50L,       as.integer(n_agerace_only)
) |>
  mutate(result = if_else(expected == observed, "PASS", "FAIL"))

cat("\n== VERIFICATION CHECKS ==\n")
print(as.data.frame(checks), row.names = FALSE)

if (any(checks$result == "FAIL")) {
  stop("Verification check(s) FAILED - see table above. Halting before analysis.")
}

n_excluded_total <- n_excluded
n_retained_total <- n_retained
n_miss_acu_total <- n_miss_acu

# ---------------------------------------------------------------------------
# 2. HELPERS
# ---------------------------------------------------------------------------

# Standardised mean difference for a proportion (excluded vs retained)
smd_prop <- function(p1, p2) {
  out <- (p1 - p2) / sqrt((p1 * (1 - p1) + p2 * (1 - p2)) / 2)
  out[!is.finite(out)] <- 0
  out
}

# Standardised mean difference for a continuous variable
smd_cont <- function(m1, s1, m2, s2) {
  out <- (m1 - m2) / sqrt((s1^2 + s2^2) / 2)
  out[!is.finite(out)] <- 0
  out
}

fmt_n  <- function(x) formatC(as.numeric(x), format = "d", big.mark = ",")
# "<0.1" rather than a misleading "0.0" for small but non-zero percentages
fmt_p  <- function(x) ifelse(x > 0 & 100 * x < 0.05, "<0.1", sprintf("%.1f", 100 * x))
fmt_p2 <- function(x) sprintf("%.2f", 100 * x)
fmt_sm <- function(x) sprintf("%+.3f", x)
flagit <- function(x) if_else(abs(x) > 0.1, "**yes**", "no")

# pipes must be escaped inside markdown table cells
SMD_HDR <- "\\|SMD\\| > 0.1"

# Categorical comparison: excluded vs retained with per-level SMD.
# NAs are kept as an explicit level; denominators are the full group N.
cat_compare <- function(df, var, missing_label = "(missing)",
                        order_by = c("excluded", "level")) {
  order_by <- match.arg(order_by)
  v <- df[[var]]
  v <- if_else(is.na(v), missing_label, as.character(v))
  tab <- tibble(level = v, group = df$group) |>
    count(group, level) |>
    pivot_wider(names_from = group, values_from = n, values_fill = 0L)
  if (!"Excluded" %in% names(tab)) tab$Excluded <- 0L
  if (!"Retained" %in% names(tab)) tab$Retained <- 0L
  tab <- tab |>
    mutate(
      n_excluded = .data[["Excluded"]],
      n_retained = .data[["Retained"]],
      p_excluded = n_excluded / n_excluded_total,
      p_retained = n_retained / n_retained_total,
      smd        = smd_prop(p_excluded, p_retained)
    ) |>
    select(level, n_excluded, p_excluded, n_retained, p_retained, smd)
  if (order_by == "excluded") arrange(tab, desc(n_excluded)) else arrange(tab, level)
}

cont_row <- function(df, var, label) {
  s <- df |>
    group_by(group) |>
    summarise(
      n_obs  = sum(!is.na(.data[[var]])),
      n_miss = sum(is.na(.data[[var]])),
      mean   = mean(.data[[var]], na.rm = TRUE),
      sd     = sd(.data[[var]], na.rm = TRUE),
      median = median(.data[[var]], na.rm = TRUE),
      q1     = quantile(.data[[var]], 0.25, na.rm = TRUE),
      q3     = quantile(.data[[var]], 0.75, na.rm = TRUE),
      .groups = "drop"
    )
  e <- s |> filter(group == "Excluded")
  r <- s |> filter(group == "Retained")
  tibble(
    variable = label,
    n_obs_ex = e$n_obs, n_miss_ex = e$n_miss,
    mean_ex  = e$mean, sd_ex = e$sd, med_ex = e$median, q1_ex = e$q1, q3_ex = e$q3,
    n_obs_re = r$n_obs, n_miss_re = r$n_miss,
    mean_re  = r$mean, sd_re = r$sd, med_re = r$median, q1_re = r$q1, q3_re = r$q3,
    smd      = smd_cont(e$mean, e$sd, r$mean, r$sd)
  )
}

md_table <- function(header, rows) {
  c(paste0("| ", paste(header, collapse = " | "), " |"),
    paste0("| ", paste(rep("---", length(header)), collapse = " | "), " |"),
    rows)
}

# ---------------------------------------------------------------------------
# 3. DERIVED VARIABLES (race collapsed exactly as in 3_descriptive.ipynb)
# ---------------------------------------------------------------------------

ed <- ed |>
  mutate(
    race_grp = case_when(
      is.na(race)                  ~ NA_character_,
      str_detect(race, "WHITE")    ~ "White",
      str_detect(race, "BLACK")    ~ "Black",
      str_detect(race, "HISPANIC") ~ "Hispanic/Latino",
      str_detect(race, "ASIAN")    ~ "Asian",
      TRUE                         ~ "Other"
    ),
    gender_lab = case_when(
      gender == "M" ~ "Male",
      gender == "F" ~ "Female",
      TRUE          ~ NA_character_
    ),
    race_unidentified = !is.na(race) &
      race %in% c("UNKNOWN", "UNABLE TO OBTAIN", "PATIENT DECLINED TO ANSWER")
  )

# ---------------------------------------------------------------------------
# A. WHY ARE THE TRIAGE SCORES MISSING?
# ---------------------------------------------------------------------------

# A1. which field(s) were missing among the 6,984 excluded
miss_pattern <- ed |>
  filter(!keep_row) |>
  mutate(pattern = case_when(
     miss_acu &  miss_age &  miss_race ~ "acuity + age + race",
     miss_acu &  miss_age & !miss_race ~ "acuity + age",
     miss_acu & !miss_age &  miss_race ~ "acuity + race",
     miss_acu & !miss_age & !miss_race ~ "acuity only",
    !miss_acu &  miss_age &  miss_race ~ "age + race",
    !miss_acu &  miss_age & !miss_race ~ "age only",
    !miss_acu & !miss_age &  miss_race ~ "race only",
    TRUE ~ "other"
  )) |>
  count(pattern, sort = TRUE) |>
  mutate(pct = n / n_excluded_total)

# A2. was a triage assessment performed at all?
triage_fields <- c("temperature", "heartrate", "resprate", "o2sat", "sbp", "dbp", "pain")

triage_completeness <- ed |>
  mutate(
    n_vitals_present = rowSums(!is.na(across(all_of(triage_fields)))),
    no_vitals        = n_vitals_present == 0,
    no_cc            = is.na(chiefcomplaint) | str_trim(chiefcomplaint) == "",
    strata = if_else(miss_acu,
                     sprintf("No acuity score (n = %s)", fmt_n(n_miss_acu_total)),
                     sprintf("Acuity recorded (n = %s)", fmt_n(n_total - n_miss_acu_total)))
  ) |>
  group_by(strata) |>
  summarise(
    n           = n(),
    p_no_vitals = mean(no_vitals),
    mean_vitals = mean(n_vitals_present),
    p_no_hr     = mean(is.na(heartrate)),
    p_no_pain   = mean(is.na(pain)),
    p_no_cc     = mean(no_cc),
    .groups = "drop"
  ) |>
  arrange(desc(str_detect(strata, "^No acuity")))

p_no_vitals_missacu <- triage_completeness |>
  filter(str_detect(strata, "^No acuity")) |> pull(p_no_vitals)

# A3-A5. missing-acuity rate by disposition / arrival transport / year
rate_by <- function(var) {
  ed |>
    mutate(lvl = if_else(is.na(.data[[var]]), "(missing)", as.character(.data[[var]]))) |>
    group_by(lvl) |>
    summarise(n_all = n(), n_miss_acu = sum(miss_acu), .groups = "drop") |>
    mutate(rate = n_miss_acu / n_all,
           share_of_missing = n_miss_acu / n_miss_acu_total) |>
    arrange(desc(n_miss_acu))
}

acu_by_dispo     <- rate_by("disposition")
acu_by_transport <- rate_by("arrival_transport")

acu_by_year_raw <- ed |>
  group_by(in_year) |>
  summarise(n_all = n(), n_miss_acu = sum(miss_acu), .groups = "drop") |>
  mutate(rate = n_miss_acu / n_all)

acu_by_decade <- ed |>
  mutate(decade = sprintf("%d-%d", floor(in_year / 10) * 10, floor(in_year / 10) * 10 + 9)) |>
  group_by(decade) |>
  summarise(n_all = n(), n_miss_acu = sum(miss_acu), .groups = "drop") |>
  mutate(rate = n_miss_acu / n_all, share_of_missing = n_miss_acu / n_miss_acu_total) |>
  arrange(decade)

# annual-rate range restricted to reasonably sized years, so the range is not
# driven by the sparse first/last shifted years
year_rate_range <- acu_by_year_raw |> filter(n_all >= 1000) |> pull(rate) |> range()

# ---------------------------------------------------------------------------
# B. EXCLUDED vs RETAINED
# ---------------------------------------------------------------------------

cont_tbl <- bind_rows(
  cont_row(ed, "age",            "Age (years)"),
  cont_row(ed, "length_of_stay", "ED length of stay (minutes)"),
  cont_row(ed, "cci_score",      "Charlson comorbidity index")
)

gender_tbl    <- cat_compare(ed, "gender_lab")
race_tbl      <- cat_compare(ed, "race_grp")
dispo_tbl     <- cat_compare(ed, "disposition")
transport_tbl <- cat_compare(ed, "arrival_transport")
icd_tbl_full  <- cat_compare(ed, "icd_chapter")
icd_tbl       <- icd_tbl_full |> slice_head(n = 10)

# raw race strings among the excluded, to explain the "Other" category
race_raw_excluded <- ed |>
  filter(!keep_row) |>
  count(race, sort = TRUE, name = "n_excluded") |>
  mutate(p_excluded = n_excluded / n_excluded_total) |>
  slice_head(n = 8)

unident <- ed |>
  group_by(group) |>
  summarise(n = n(), n_unid = sum(race_unidentified), .groups = "drop") |>
  mutate(p = n_unid / n)
p_unid_ex <- unident |> filter(group == "Excluded") |> pull(p)
p_unid_re <- unident |> filter(group == "Retained") |> pull(p)

# ---------------------------------------------------------------------------
# C. WERE DIAGNOSIS AND RESOURCE DATA STILL AVAILABLE FOR THE EXCLUDED?
# ---------------------------------------------------------------------------

avail <- ed |>
  group_by(group) |>
  summarise(
    n          = n(),
    code_avail = sum(!is.na(primary_code)),
    nyu_avail  = sum(!is.na(nyu)),
    nyu_flag   = sum(nyu == 1, na.rm = TRUE),
    res_avail  = sum(!is.na(res)),
    res_flag   = sum(res == 1, na.rm = TRUE),
    acu_avail  = sum(!is.na(acuity_out)),
    acu_flag   = sum(acuity_out == 1, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    p_code      = code_avail / n,
    p_nyu_avail = nyu_avail / n,
    p_res_avail = res_avail / n,
    p_acu_avail = acu_avail / n,
    rate_nyu    = nyu_flag / nyu_avail,
    rate_res    = res_flag / res_avail,
    rate_acu    = if_else(acu_avail > 0, acu_flag / acu_avail, NA_real_)
  )

av_ex <- avail |> filter(group == "Excluded")
av_re <- avail |> filter(group == "Retained")

smd_nyu_rate <- smd_prop(av_ex$rate_nyu, av_re$rate_nyu)
smd_res_rate <- smd_prop(av_ex$rate_res, av_re$rate_res)

# ---------------------------------------------------------------------------
# D. POTENTIAL IMPACT ON THE REPORTED FINDINGS
# ---------------------------------------------------------------------------

impact <- tibble(
  algorithm = c("Diagnosis (`nyu`)", "Resources (`res`)"),
  denom_pub = c(av_re$nyu_avail, av_re$res_avail),
  flag_pub  = c(av_re$nyu_flag,  av_re$res_flag),
  denom_ex  = c(av_ex$nyu_avail, av_ex$res_avail),
  flag_ex   = c(av_ex$nyu_flag,  av_ex$res_flag)
) |>
  mutate(
    pct_pub   = flag_pub / denom_pub,
    pct_ex    = flag_ex / denom_ex,
    denom_all = denom_pub + denom_ex,
    flag_all  = flag_pub + flag_ex,
    pct_all   = flag_all / denom_all,
    delta_pp  = 100 * (pct_all - pct_pub),
    delta_n   = flag_all - flag_pub
  )

share_excluded <- n_excluded_total / n_total

# scalars quoted in the prose (all traceable to the objects above)
get_dispo  <- function(x, col) acu_by_dispo     |> filter(lvl == x) |> pull({{ col }})
get_transp <- function(x, col) acu_by_transport |> filter(lvl == x) |> pull({{ col }})

share_admitted  <- get_dispo("ADMITTED", share_of_missing)
rate_expired    <- get_dispo("EXPIRED", rate)
share_ambulance <- get_transp("ambulance", share_of_missing)
share_heli      <- get_transp("helicopter", share_of_missing)
rate_heli       <- get_transp("helicopter", rate)
p_injury_ex     <- icd_tbl_full |> filter(level == "Injury and poisoning") |> pull(p_excluded)
p_injury_re     <- icd_tbl_full |> filter(level == "Injury and poisoning") |> pull(p_retained)
smd_age         <- cont_tbl$smd[cont_tbl$variable == "Age (years)"]
smd_cci         <- cont_tbl$smd[cont_tbl$variable == "Charlson comorbidity index"]

# reference scale: the gap between the two algorithms' own estimates, in pp
algo_gap_pp <- 100 * (impact$pct_pub[1] - impact$pct_pub[2])

# ---------------------------------------------------------------------------
# 4. BUILD MARKDOWN
# ---------------------------------------------------------------------------

big_smds <- bind_rows(
  cont_tbl      |> transmute(variable, level = "-", smd),
  gender_tbl    |> transmute(variable = "Sex", level, smd),
  race_tbl      |> transmute(variable = "Race", level, smd),
  dispo_tbl     |> transmute(variable = "Disposition", level, smd),
  transport_tbl |> transmute(variable = "Arrival transport", level, smd),
  icd_tbl       |> transmute(variable = "ICD chapter", level, smd)
) |>
  filter(abs(smd) > 0.1) |>
  arrange(desc(abs(smd)))

L <- character(0)
add <- function(...) L <<- c(L, ...)

add("# R1.4 - Did the excluded visits differ systematically from the retained visits?",
    "",
    "Supplementary analysis for the IJPDS revision. Produced by",
    "`ANALYSIS/reviewer_response/r1_04_excluded_vs_retained.R` from",
    "`MIMICED/ed_join_cc.parquet` (424,707 ED visits, before any analysis exclusion).",
    "Every number below is emitted by that script.",
    "")

add("## Verdict", "")
add(sprintf(paste0(
  "**Yes, the excluded visits differ systematically from the retained ones - but in the opposite ",
  "direction to the one that would threaten the findings. They are sicker, not more trivial.** The ",
  "%s excluded visits are %s%% of all attendances, and %s of them (%s%%) are excluded solely because ",
  "triage acuity is missing. The acuity score is missing because the triage assessment was never ",
  "carried out or recorded, not because a recorded score was lost: %s%% of these visits have none of ",
  "the seven triage vital signs, and the group is dominated by patients taken straight to ",
  "resuscitation or trauma care - %s%% arrived by ambulance and %s%% by helicopter (%s%% of *all* ",
  "helicopter arrivals in MIMIC-IV-ED lack an acuity score), %s%% were admitted, %s%% of all in-ED ",
  "deaths in the dataset have no acuity score, and %s%% carry an injury or poisoning primary ",
  "diagnosis versus %s%% of retained visits. Every imbalance above the conventional |SMD| > 0.1 sits ",
  "on this severity / mode-of-arrival axis (arrival transport, disposition, injury and circulatory ",
  "diagnoses, sex, and the UNKNOWN / UNABLE-TO-OBTAIN race category that unidentified critically ill ",
  "patients fall into); age (SMD %s) and Charlson comorbidity (SMD %s) are close, and nothing ",
  "suggests that low-acuity attendances were selectively dropped. The reviewer is right that ",
  "diagnosis and resource-use data survive for these encounters - both labels are computable for all ",
  "%s of them (see the caveat on `res` in section C) - but their flag rates are far *lower* than in ",
  "the retained cohort (Diagnosis %s%% vs %s%%; Resources %s%% vs %s%%), so putting them back would ",
  "move the Diagnosis estimate from %s%% to %s%% (%s pp) and the Resources estimate from %s%% to ",
  "%s%% (%s pp) - changes roughly %.0f and %.0f times smaller than the %s pp gap between the ",
  "Diagnosis and Resources estimates that the paper reports. With n = 424,707 every one of these ",
  "contrasts is 'statistically significant' at any conventional threshold, which is exactly why ",
  "standardised mean differences and not p-values are reported below: the p-values here carry no ",
  "information about whether the exclusion matters."),
  fmt_n(n_excluded_total), fmt_p(share_excluded),
  fmt_n(n_miss_acu_total), fmt_p(n_miss_acu_total / n_excluded_total),
  fmt_p(p_no_vitals_missacu),
  fmt_p(share_ambulance), fmt_p(share_heli), fmt_p(rate_heli),
  fmt_p(share_admitted), fmt_p(rate_expired),
  fmt_p(p_injury_ex), fmt_p(p_injury_re),
  fmt_sm(smd_age), fmt_sm(smd_cci),
  fmt_n(n_excluded_total),
  fmt_p(av_ex$rate_nyu), fmt_p(av_re$rate_nyu),
  fmt_p(av_ex$rate_res), fmt_p(av_re$rate_res),
  fmt_p2(impact$pct_pub[1]), fmt_p2(impact$pct_all[1]), sprintf("%+.2f", impact$delta_pp[1]),
  fmt_p2(impact$pct_pub[2]), fmt_p2(impact$pct_all[2]), sprintf("%+.2f", impact$delta_pp[2]),
  algo_gap_pp / abs(impact$delta_pp[1]), algo_gap_pp / abs(impact$delta_pp[2]),
  sprintf("%.1f", algo_gap_pp)
), "")

add("## Verification checks", "")
add(md_table(c("Check", "Expected", "Observed", "Result"),
             sprintf("| %s | %s | %s | %s |", checks$check, fmt_n(checks$expected),
                     fmt_n(checks$observed), checks$result)))
add("")

# ---------------- A ----------------
add("## A. Why are the triage scores missing?",
    "",
    "### A1. Which field was missing (n = 6,984 excluded visits)",
    "")
add(md_table(c("Missingness pattern", "n", "% of excluded"),
             sprintf("| %s | %s | %s |", miss_pattern$pattern, fmt_n(miss_pattern$n),
                     fmt_p(miss_pattern$pct))))
add("",
    sprintf(paste0("Missing acuity is effectively the entire exclusion: %s of the %s excluded visits ",
                   "(%s%%) fail the filter because `acuity` is missing, and only %d fail because `age` is ",
                   "missing while a triage score was present. No visit is excluded for missing race. The ",
                   "three criteria therefore do not compound - there is one exclusion, not three."),
            fmt_n(n_miss_acu_total), fmt_n(n_excluded_total),
            fmt_p(n_miss_acu_total / n_excluded_total), n_agerace_only),
    "")

add("### A2. Was a triage assessment performed at all?",
    "",
    "Triage acuity (Emergency Severity Index) is assigned during the nursing triage assessment. If",
    "that assessment never took place, no acuity score exists - and neither do the other triage",
    "observations. The table contrasts completeness of the *other* triage fields for visits with and",
    "without an acuity score.",
    "")
add(md_table(c("Group", "n", "No vital signs at all (%)", "Mean no. of 7 triage vitals recorded",
               "Heart rate missing (%)", "Pain score missing (%)", "Chief complaint missing (%)"),
             sprintf("| %s | %s | %s | %.2f | %s | %s | %s |",
                     triage_completeness$strata, fmt_n(triage_completeness$n),
                     fmt_p(triage_completeness$p_no_vitals), triage_completeness$mean_vitals,
                     fmt_p(triage_completeness$p_no_hr), fmt_p(triage_completeness$p_no_pain),
                     fmt_p(triage_completeness$p_no_cc))))
add("",
    sprintf(paste0("This is the substantive explanation the reviewer asked for. Visits without an acuity ",
                   "score are visits with no triage record at all: on average %.2f of the 7 triage vital ",
                   "signs are present, against %.2f for the rest of the cohort. A chief complaint is still ",
                   "almost always captured, so these are complete ED encounters rather than empty records ",
                   "- the triage *step* was bypassed."),
            triage_completeness$mean_vitals[1], triage_completeness$mean_vitals[2]),
    "")

add("### A3. Missing acuity by disposition",
    "",
    "`Rate` = proportion of visits *within that disposition* with no acuity score.",
    "`Share` = proportion of *all* missing-acuity visits contributed by that disposition.",
    "")
add(md_table(c("Disposition", "All visits (n)", "Missing acuity (n)", "Rate (%)", "Share of missing (%)"),
             sprintf("| %s | %s | %s | %s | %s |", acu_by_dispo$lvl, fmt_n(acu_by_dispo$n_all),
                     fmt_n(acu_by_dispo$n_miss_acu), fmt_p(acu_by_dispo$rate),
                     fmt_p(acu_by_dispo$share_of_missing))))
add("",
    sprintf(paste0("The concentration is in **admitted** visits (%s%% of all missing-acuity visits), ",
                   "**death in the ED** (%s%% of all EXPIRED visits in MIMIC-IV-ED have no acuity score) ",
                   "and the administrative **OTHER** disposition (%s%% rate). Crucially it is *not* in ",
                   "left-without-being-seen, eloped or left-against-medical-advice: those three ",
                   "dispositions together contribute only %s%% of missing-acuity visits, and their ",
                   "missing-acuity rates (%s%%, %s%%, %s%%) sit at or below the cohort average of %s%%. ",
                   "A 'patient left before assessment' explanation is therefore *not* supported by the ",
                   "data; the pattern points the other way."),
            fmt_p(share_admitted), fmt_p(rate_expired), fmt_p(get_dispo("OTHER", rate)),
            fmt_p(sum(acu_by_dispo$share_of_missing[str_detect(acu_by_dispo$lvl, "LEFT|ELOPED")])),
            fmt_p(get_dispo("LEFT WITHOUT BEING SEEN", rate)),
            fmt_p(get_dispo("ELOPED", rate)),
            fmt_p(get_dispo("LEFT AGAINST MEDICAL ADVICE", rate)),
            fmt_p(n_miss_acu_total / n_total)),
    "")

add("### A4. Missing acuity by arrival transport", "")
add(md_table(c("Arrival transport", "All visits (n)", "Missing acuity (n)", "Rate (%)", "Share of missing (%)"),
             sprintf("| %s | %s | %s | %s | %s |", acu_by_transport$lvl, fmt_n(acu_by_transport$n_all),
                     fmt_n(acu_by_transport$n_miss_acu), fmt_p(acu_by_transport$rate),
                     fmt_p(acu_by_transport$share_of_missing))))
add("",
    sprintf(paste0("Helicopter arrivals - the highest-acuity transport mode in the dataset - lose their ",
                   "acuity score %s%% of the time, ambulance arrivals %s%% of the time, and walk-in ",
                   "arrivals only %s%% of the time. This is the signature of pre-hospital patients being ",
                   "taken directly into the resuscitation or trauma bay rather than through the triage ",
                   "desk."),
            fmt_p(rate_heli), fmt_p(get_transp("ambulance", rate)), fmt_p(get_transp("walk in", rate))),
    "")

add("### A5. Missing acuity by year of arrival",
    "",
    "MIMIC dates are shifted into the future by a per-patient offset, so `in_year` is not a real",
    sprintf("calendar year; it spans %d-%d over %d distinct values. Years are collapsed to decades here.",
            min(acu_by_year_raw$in_year), max(acu_by_year_raw$in_year), nrow(acu_by_year_raw)),
    "")
add(md_table(c("Shifted-year decade", "All visits (n)", "Missing acuity (n)", "Rate (%)", "Share of missing (%)"),
             sprintf("| %s | %s | %s | %s | %s |", acu_by_decade$decade, fmt_n(acu_by_decade$n_all),
                     fmt_n(acu_by_decade$n_miss_acu), fmt_p(acu_by_decade$rate),
                     fmt_p(acu_by_decade$share_of_missing))))
add("",
    sprintf(paste0("There is **no temporal concentration and no discontinuity**: across every shifted ",
                   "year with at least 1,000 visits the missing-acuity rate stays within a narrow band ",
                   "(%s%% to %s%%), declining gently from roughly %s%% in the earliest shifted decade to ",
                   "%s%% in the latest, which is consistent with gradually improving triage ",
                   "documentation. The missingness is not an artefact of one data-collection era or of a ",
                   "single system change, and no single year contributes more than a small fraction of ",
                   "the total."),
            fmt_p(year_rate_range[1]), fmt_p(year_rate_range[2]),
            fmt_p(acu_by_decade$rate[1]),
            fmt_p(acu_by_decade$rate[max(which(acu_by_decade$n_all >= 5000))])),
    "")

# ---------------- B ----------------
add("## B. Excluded vs retained, side by side",
    "",
    "SMD = standardised mean difference (excluded - retained), computed as",
    "`(mean1-mean2)/sqrt((sd1^2+sd2^2)/2)` for continuous variables and",
    "`(p1-p2)/sqrt((p1(1-p1)+p2(1-p2))/2)` for each category of a categorical variable.",
    "|SMD| > 0.1 is the conventional threshold for a meaningful imbalance.",
    "",
    "**P-values are deliberately not reported.** With n = 424,707 even a difference of no practical",
    "consequence is 'statistically significant', so significance testing would misrepresent the size",
    "and the importance of these differences.",
    "")

add("### B1. Continuous variables", "")
add(md_table(c("Variable", "Excluded mean (SD)", "Excluded median [IQR]", "Retained mean (SD)",
               "Retained median [IQR]", "SMD", SMD_HDR),
             sprintf("| %s | %.1f (%.1f) | %.0f [%.0f-%.0f] | %.1f (%.1f) | %.0f [%.0f-%.0f] | %s | %s |",
                     cont_tbl$variable,
                     cont_tbl$mean_ex, cont_tbl$sd_ex, cont_tbl$med_ex, cont_tbl$q1_ex, cont_tbl$q3_ex,
                     cont_tbl$mean_re, cont_tbl$sd_re, cont_tbl$med_re, cont_tbl$q1_re, cont_tbl$q3_re,
                     fmt_sm(cont_tbl$smd), flagit(cont_tbl$smd))))
add("",
    sprintf(paste0("Age is itself part of the exclusion rule, so the excluded-group age statistics use ",
                   "the %s excluded visits that do have an age (%d have none). Length of stay is ",
                   "available for %s excluded and %s retained visits; the Charlson index is complete in ",
                   "both groups. The shorter ED stay among the excluded (median %.0f vs %.0f minutes) is ",
                   "consistent with rapid transfer out of the ED to theatre, ICU or the mortuary, not ",
                   "with a brief minor-injury attendance."),
            fmt_n(cont_tbl$n_obs_ex[1]), cont_tbl$n_miss_ex[1],
            fmt_n(cont_tbl$n_obs_ex[2]), fmt_n(cont_tbl$n_obs_re[2]),
            cont_tbl$med_ex[2], cont_tbl$med_re[2]),
    "")

cat_block <- function(title, tab, note = NULL) {
  add(paste0("### ", title), "")
  add(md_table(c("Category", "Excluded n", "Excluded %", "Retained n", "Retained %", "SMD", SMD_HDR),
               sprintf("| %s | %s | %s | %s | %s | %s | %s |",
                       tab$level, fmt_n(tab$n_excluded), fmt_p(tab$p_excluded),
                       fmt_n(tab$n_retained), fmt_p(tab$p_retained),
                       fmt_sm(tab$smd), flagit(tab$smd))))
  if (!is.null(note)) add("", note)
  add("")
}

cat_block("B2. Sex", gender_tbl,
          "The male excess is consistent with the trauma-heavy composition of the excluded group.")

cat_block("B3. Race, collapsed exactly as in Table 1", race_tbl,
          sprintf(paste0("The apparent 'Other' excess is largely an artefact of unidentified patients: ",
                         "%s%% of excluded visits carry a race value of UNKNOWN, UNABLE TO OBTAIN or ",
                         "PATIENT DECLINED TO ANSWER, against %s%% of retained visits, and those strings ",
                         "collapse into 'Other'. The raw values among the excluded are:"),
                  fmt_p(p_unid_ex), fmt_p(p_unid_re)))
add(md_table(c("Raw `race` value (top 8, excluded group)", "n", "% of excluded"),
             sprintf("| %s | %s | %s |", race_raw_excluded$race, fmt_n(race_raw_excluded$n_excluded),
                     fmt_p(race_raw_excluded$p_excluded))))
add("",
    "No visit is excluded for a missing `race` value - race is recorded for every visit in the built",
    "dataset, sometimes as UNKNOWN - so there is no `(missing)` row in the table above.",
    "")

cat_block("B4. Disposition (all 8 categories)", dispo_tbl)
cat_block("B5. Arrival transport", transport_tbl)
cat_block("B6. ICD chapter of the primary diagnosis (top 10 by frequency in the excluded group)", icd_tbl,
          sprintf(paste0("Percentages are of the whole group (excluded n = %s, retained n = %s), so these ",
                         "ten rows do not sum to 100%%. Every visit in both groups has a primary diagnosis ",
                         "code and an assigned ICD chapter."),
                  fmt_n(n_excluded_total), fmt_n(n_retained_total)))

add("### B7. Every imbalance exceeding |SMD| > 0.1", "")
if (nrow(big_smds) == 0) {
  add("No variable or category reached |SMD| > 0.1.", "")
} else {
  add(md_table(c("Variable", "Category", "SMD"),
               sprintf("| %s | %s | %s |", big_smds$variable, big_smds$level, fmt_sm(big_smds$smd))))
  add("",
      sprintf(paste0("Read as a set, these are not %d independent imbalances. They are one imbalance - ",
                     "excluded visits are high-acuity pre-hospital arrivals, disproportionately trauma, ",
                     "who were admitted or died - expressed across correlated variables."),
              nrow(big_smds)),
      "")
}

# ---------------- C ----------------
add("## C. Were diagnosis and resource-utilisation data still available for the excluded visits?",
    "",
    "This is the reviewer's specific concern, and the answer is yes. The Diagnosis (NYU/Billings)",
    "algorithm needs only the primary discharge diagnosis code; the Resources algorithm needs only",
    "disposition, medication and rhythm-monitoring records. Neither requires a triage score. The",
    "Triage-Acuity algorithm, by construction, cannot be computed without one.",
    "")
add(md_table(c("Data element",
               sprintf("Excluded (n = %s)", fmt_n(n_excluded_total)),
               sprintf("Retained (n = %s)", fmt_n(n_retained_total))),
             c(sprintf("| Primary diagnosis code present | %s (%s%%) | %s (%s%%) |",
                       fmt_n(av_ex$code_avail), fmt_p(av_ex$p_code),
                       fmt_n(av_re$code_avail), fmt_p(av_re$p_code)),
               sprintf("| Computable **Diagnosis** label (`nyu` non-missing) | %s (%s%%) | %s (%s%%) |",
                       fmt_n(av_ex$nyu_avail), fmt_p(av_ex$p_nyu_avail),
                       fmt_n(av_re$nyu_avail), fmt_p(av_re$p_nyu_avail)),
               sprintf("| Computable **Resources** label (`res` non-missing) | %s (%s%%) | %s (%s%%) |",
                       fmt_n(av_ex$res_avail), fmt_p(av_ex$p_res_avail),
                       fmt_n(av_re$res_avail), fmt_p(av_re$p_res_avail)),
               sprintf("| Computable **Triage-Acuity** label (`acuity_out` non-missing) | %s (%s%%) | %s (%s%%) |",
                       fmt_n(av_ex$acu_avail), fmt_p(av_ex$p_acu_avail),
                       fmt_n(av_re$acu_avail), fmt_p(av_re$p_acu_avail)))))
add("",
    sprintf(paste0("The %s excluded visits with a computable Triage-Acuity label are exactly the %d visits ",
                   "excluded for missing age rather than missing acuity - an internal consistency check."),
            fmt_n(av_ex$acu_avail), n_agerace_only),
    "")
add("Flag rates among the visits where each label is computable:", "")
add(md_table(c("Algorithm", "Excluded: flagged / computable (%)", "Retained: flagged / computable (%)",
               "SMD", SMD_HDR),
             c(sprintf("| Diagnosis (`nyu`) | %s / %s (%s%%) | %s / %s (%s%%) | %s | %s |",
                       fmt_n(av_ex$nyu_flag), fmt_n(av_ex$nyu_avail), fmt_p(av_ex$rate_nyu),
                       fmt_n(av_re$nyu_flag), fmt_n(av_re$nyu_avail), fmt_p(av_re$rate_nyu),
                       fmt_sm(smd_nyu_rate), flagit(smd_nyu_rate)),
               sprintf("| Resources (`res`) | %s / %s (%s%%) | %s / %s (%s%%) | %s | %s |",
                       fmt_n(av_ex$res_flag), fmt_n(av_ex$res_avail), fmt_p(av_ex$rate_res),
                       fmt_n(av_re$res_flag), fmt_n(av_re$res_avail), fmt_p(av_re$rate_res),
                       fmt_sm(smd_res_rate), flagit(smd_res_rate)))))
add("",
    paste0("Both algorithms flag the excluded visits *less* often than the retained ones, which is what ",
           "the composition described in section A predicts: these are severe, admitted, trauma-heavy ",
           "encounters that neither algorithm would call potentially avoidable."),
    "",
    paste0("*Caveat, stated openly.* `res` is never missing by construction: the Resources algorithm ",
           "treats the absence of a medication or rhythm-monitoring record as evidence that no ED ",
           "resource was used, so it always returns 0 or 1 and cannot distinguish 'no resource used' ",
           "from 'resource use not documented'. That is a property of the algorithm rather than of this ",
           "exclusion, and it applies identically to both groups."),
    "")

# ---------------- D ----------------
add("## D. Potential impact on the reported findings",
    "",
    "Counterfactual: retain all 424,707 visits and label them with the two algorithms that can be",
    "computed without a triage score.",
    "")
add(md_table(c("Algorithm", "As analysed: flagged / N (%)", "Excluded visits added: flagged / N (%)",
               "Counterfactual, all visits: flagged / N (%)", "Change (percentage points)"),
             sprintf("| %s | %s / %s (%s%%) | %s / %s (%s%%) | %s / %s (%s%%) | %s |",
                     impact$algorithm,
                     fmt_n(impact$flag_pub), fmt_n(impact$denom_pub), fmt_p2(impact$pct_pub),
                     fmt_n(impact$flag_ex),  fmt_n(impact$denom_ex),  fmt_p2(impact$pct_ex),
                     fmt_n(impact$flag_all), fmt_n(impact$denom_all), fmt_p2(impact$pct_all),
                     sprintf("%+.2f", impact$delta_pp))))
add("",
    sprintf(paste0("The excluded visits are %s%% of all attendances, which caps the arithmetic influence ",
                   "of any exclusion-related bias. Restoring them adds %s flagged visits to the Diagnosis ",
                   "algorithm and %s to the Resources algorithm, shifting the two estimates by %s and %s ",
                   "percentage points respectively - in both cases *downwards*, so the published figures ",
                   "if anything over- rather than under-state the avoidable-visit burden. The ",
                   "Triage-Acuity algorithm cannot be evaluated on the %s missing-acuity visits under any ",
                   "assumption, so a three-way comparison of algorithm agreement requires a common ",
                   "denominator of visits on which all three are computable. That, and not a judgement ",
                   "about data quality, is the reason for the exclusion."),
            fmt_p(share_excluded),
            fmt_n(impact$delta_n[1]), fmt_n(impact$delta_n[2]),
            sprintf("%+.2f", impact$delta_pp[1]), sprintf("%+.2f", impact$delta_pp[2]),
            fmt_n(n_miss_acu_total)),
    "")

add("## Summary for the response letter", "")
add(sprintf(paste0(
  "1. **Reason for the missing scores.** Acuity is missing because the nursing triage assessment was ",
  "never carried out or never recorded, not because a score was lost. %s%% of these visits have no ",
  "triage vital sign at all, and they are concentrated in ambulance and helicopter arrivals taken ",
  "straight to resuscitation or trauma care."),
  fmt_p(p_no_vitals_missacu)), "")
add(sprintf(paste0(
  "2. **Do they differ systematically?** Yes, on the severity and mode-of-arrival axis - that is the ",
  "mechanism and it is expected. Excluded visits are more often ambulance arrivals (%s%% vs %s%%), ",
  "more often admitted (%s%% vs %s%%), more often fatal, more often injury-related (%s%% vs %s%%) and ",
  "more often male (%s%% vs %s%%). Age (SMD %s), Charlson comorbidity (SMD %s) and most diagnosis ",
  "chapters are close."),
  fmt_p(transport_tbl$p_excluded[transport_tbl$level == "ambulance"]),
  fmt_p(transport_tbl$p_retained[transport_tbl$level == "ambulance"]),
  fmt_p(dispo_tbl$p_excluded[dispo_tbl$level == "ADMITTED"]),
  fmt_p(dispo_tbl$p_retained[dispo_tbl$level == "ADMITTED"]),
  fmt_p(p_injury_ex), fmt_p(p_injury_re),
  fmt_p(gender_tbl$p_excluded[gender_tbl$level == "Male"]),
  fmt_p(gender_tbl$p_retained[gender_tbl$level == "Male"]),
  fmt_sm(smd_age), fmt_sm(smd_cci)), "")
add(sprintf(paste0(
  "3. **Selection-bias risk.** Low, and quantified. The excluded visits are far less likely to be ",
  "flagged as potentially avoidable by either computable algorithm (Diagnosis %s%% vs %s%%; Resources ",
  "%s%% vs %s%%), so their removal cannot have manufactured the between-algorithm disagreement the ",
  "paper reports; adding them back changes the two estimates by %s and %s percentage points."),
  fmt_p(av_ex$rate_nyu), fmt_p(av_re$rate_nyu), fmt_p(av_ex$rate_res), fmt_p(av_re$rate_res),
  sprintf("%+.2f", impact$delta_pp[1]), sprintf("%+.2f", impact$delta_pp[2])), "")
add(paste0(
  "4. **Caveat we should state openly in the manuscript.** Because the excluded visits are ",
  "disproportionately severe, our estimates should not be read as applying to the high-acuity ",
  "pre-hospital subgroup that bypasses triage. Directionally, including that subgroup would lower ",
  "the estimated share of potentially avoidable visits, not raise it."), "")

for (d in out_dirs) {
  fp <- file.path(d, "r1_04_excluded_vs_retained.md")
  writeLines(L, fp)
  cat("\nWrote:", fp, "\n")
}

# ---------------------------------------------------------------------------
# 5. CONSOLE ECHO (audit trail)
# ---------------------------------------------------------------------------
cat("\n== A1 missingness pattern ==\n");   print(as.data.frame(miss_pattern), row.names = FALSE)
cat("\n== A2 triage completeness ==\n");   print(as.data.frame(triage_completeness), row.names = FALSE)
cat("\n== A3 by disposition ==\n");        print(as.data.frame(acu_by_dispo), row.names = FALSE)
cat("\n== A4 by arrival transport ==\n");  print(as.data.frame(acu_by_transport), row.names = FALSE)
cat("\n== A5 by decade ==\n");             print(as.data.frame(acu_by_decade), row.names = FALSE)
cat("\n== A5 annual rate range (years with >= 1000 visits) ==\n"); print(year_rate_range)
cat("\n== B1 continuous ==\n");            print(as.data.frame(cont_tbl), row.names = FALSE)
cat("\n== B2 sex ==\n");                   print(as.data.frame(gender_tbl), row.names = FALSE)
cat("\n== B3 race ==\n");                  print(as.data.frame(race_tbl), row.names = FALSE)
cat("\n== B3 raw race (excluded) ==\n");   print(as.data.frame(race_raw_excluded), row.names = FALSE)
cat("\n== B4 disposition ==\n");           print(as.data.frame(dispo_tbl), row.names = FALSE)
cat("\n== B5 arrival transport ==\n");     print(as.data.frame(transport_tbl), row.names = FALSE)
cat("\n== B6 icd chapter (top 10) ==\n");  print(as.data.frame(icd_tbl), row.names = FALSE)
cat("\n== B7 |SMD| > 0.1 ==\n");           print(as.data.frame(big_smds), row.names = FALSE)
cat("\n== C availability ==\n");           print(as.data.frame(avail), row.names = FALSE)
cat("\n== D impact ==\n");                 print(as.data.frame(impact), row.names = FALSE)
