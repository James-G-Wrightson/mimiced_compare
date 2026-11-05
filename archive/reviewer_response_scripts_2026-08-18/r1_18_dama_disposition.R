# =============================================================================
# R1.18 -- Discharge against medical advice (DAMA) and other "left before
#          completing care" presentations in the MIMIC-IV-ED analysis sample
#
# Reviewer question: were DAMA presentations included, excluded, or identifiable
# in the dataset, and how were they classified by the three algorithms?
#
# Input : ANALYSIS/ed_single.parquet  (201,106 first ED visits, 90 cols)
# Output: reviewer_response/r1_18_dama_disposition.md  (written next to this script)
#
# R 4.5.2. Requires arrow, dplyr, tidyr, stringr, purrr, binom.
# Re-runnable end-to-end; all verification assertions are at the top and the
# script stops rather than continuing if any check fails.
# =============================================================================

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr)
  library(stringr); library(purrr); library(binom)
})

DATA_PATH <- "/Users/jameswrightson/Documents/Projects/mimic/nonurgent/mimiced_compare/ANALYSIS/ed_single.parquet"

# Write the report alongside this script wherever the repo is checked out.
script_dir <- local({
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) dirname(normalizePath(sub("^--file=", "", a[1]))) else getwd()
})
OUT_MD <- file.path(script_dir, "r1_18_dama_disposition.md")

d <- read_parquet(DATA_PATH)

# -----------------------------------------------------------------------------
# 0. VERIFICATION -- script stops if any check fails
# -----------------------------------------------------------------------------
checks <- list()
chk <- function(label, condition, observed) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = label, observed = as.character(observed),
    result = if (isTRUE(condition)) "PASS" else "FAIL"
  )
  if (!isTRUE(condition)) stop("VERIFICATION FAILED: ", label, " -- observed: ", observed)
  invisible(TRUE)
}

# Check 1 -- sample size
chk("1. Total rows == 201,106", nrow(d) == 201106, format(nrow(d), big.mark = ","))

# Check 2 -- algorithm totals
n_res <- sum(d$res == 1); n_nyu <- sum(d$nyu == 1); n_ac <- sum(d$acuity_out == 1)
chk("2a. res == 1 total == 48,181",        n_res == 48181, format(n_res, big.mark = ","))
chk("2b. nyu == 1 total == 68,173",        n_nyu == 68173, format(n_nyu, big.mark = ","))
chk("2c. acuity_out == 1 total == 15,716", n_ac  == 15716, format(n_ac,  big.mark = ","))

# Check 3 -- disposition composition of the Resources-flagged group
res_disp <- table(d$disposition[d$res == 1])
gv <- function(x) if (x %in% names(res_disp)) as.integer(res_disp[[x]]) else 0L
n_lwbs_res <- gv("LEFT WITHOUT BEING SEEN"); n_elop_res <- gv("ELOPED")
n_dama_res <- gv("LEFT AGAINST MEDICAL ADVICE"); n_oth_res <- gv("OTHER")
n_incompl_res <- n_lwbs_res + n_elop_res + n_dama_res + n_oth_res
chk("3a. res==1 & LEFT WITHOUT BEING SEEN == 2,546",   n_lwbs_res == 2546, n_lwbs_res)
chk("3b. res==1 & ELOPED == 1,246",                    n_elop_res == 1246, n_elop_res)
chk("3c. res==1 & LEFT AGAINST MEDICAL ADVICE == 329", n_dama_res == 329,  n_dama_res)
chk("3d. res==1 & OTHER == 818",                       n_oth_res  == 818,  n_oth_res)
chk("3e. combined non-HOME/non-admitted == 4,939",     n_incompl_res == 4939, n_incompl_res)
chk("3f. that group is ~10% of the Resources group",
    abs(100 * n_incompl_res / n_res - 10.25) < 0.5,
    sprintf("%.2f%%", 100 * n_incompl_res / n_res))

# Check 4 -- exclusion list is watertight
dispo_list <- c("ADMITTED", "TRANSFER", "EXPIRED")
n_bad <- sum(d$res == 1 & d$disposition %in% dispo_list)
chk("4. No ADMITTED/TRANSFER/EXPIRED visit has res == 1", n_bad == 0, n_bad)

# Check 5 (supplementary) -- reconstruct the published `res` rule exactly, to
# confirm that among eligible dispositions res is IDENTICAL to
# "no rhythm recorded AND no medication dispensed AND alive that day".
res_rebuilt <- as.integer(!d$disposition %in% dispo_list &
                          is.na(d$rhythm) & is.na(d$pre_gsn_count) &
                          d$dead_on_day == "No")
chk("5. Published res reproduced exactly from the coded rule",
    all(res_rebuilt == d$res), sprintf("%d mismatches", sum(res_rebuilt != d$res)))

# Check 6 (supplementary) -- headline "flagged by at least one" figure
n_any <- sum(d$nyu == 1 | d$res == 1 | d$acuity_out == 1)
chk("6. Flagged by >=1 algorithm == 100,568", n_any == 100568, format(n_any, big.mark = ","))

verif <- bind_rows(checks)
cat("\n== VERIFICATION ==\n"); print(verif, row.names = FALSE)
if (any(verif$result == "FAIL")) stop("Stopping: verification failed.")

# -----------------------------------------------------------------------------
# 1. DERIVED VARIABLES
# -----------------------------------------------------------------------------
LBCC_DISP <- c("LEFT WITHOUT BEING SEEN", "ELOPED", "LEFT AGAINST MEDICAL ADVICE")

cluster_labels <- c(
  "0 Lower back pain", "1 Influenza like illness",
  "2 Vehicle collision + Altered mental status", "3 Chest pain + dyspnea",
  "4 Shortness breath", "5 Abdomen pain", "6 Leg + knee pain",
  "7 Wound evaluation", "8 Alcohol intoxication", "9 Nausea vomiting",
  "10 Suicidal ideation", "11 Fall transfer")

d <- d |>
  mutate(
    lbcc      = disposition %in% LBCC_DISP,           # left before completing care
    cluster_l = cluster_labels[cluster + 1],
    race5 = case_when(
      str_detect(race, "WHITE")    ~ "White",
      str_detect(race, "BLACK")    ~ "Black",
      str_detect(race, "HISPANIC") ~ "Hispanic/Latino",
      str_detect(race, "ASIAN")    ~ "Asian",
      TRUE                         ~ "Other"),
    no_rhythm = is.na(rhythm),
    no_med    = is.na(pre_gsn_count),
    no_either = is.na(rhythm) & is.na(pre_gsn_count))

N_TOT <- nrow(d)

# -----------------------------------------------------------------------------
# 2. HELPERS
# -----------------------------------------------------------------------------
fm <- function(x) format(round(x), big.mark = ",", trim = TRUE)
pc <- function(x, dp = 1) sprintf(paste0("%.", dp, "f"), x)
smd_flag <- function(s) ifelse(abs(s) > 0.1, sprintf("**%+.3f**", s), sprintf("%+.3f", s))

# SMDs exactly as specified in the brief
smd_cont <- function(x1, x2) {
  m1 <- mean(x1, na.rm = TRUE); m2 <- mean(x2, na.rm = TRUE)
  s1 <- sd(x1,  na.rm = TRUE);  s2 <- sd(x2,  na.rm = TRUE)
  (m1 - m2) / sqrt((s1^2 + s2^2) / 2)
}
smd_cat <- function(p1, p2) (p1 - p2) / sqrt((p1 * (1 - p1) + p2 * (1 - p2)) / 2)

wilson <- function(x, n) {
  ci <- binom.confint(x, n, methods = "wilson")
  sprintf("%.1f-%.1f", 100 * ci$lower, 100 * ci$upper)
}

md_table <- function(df, align = NULL) {
  df <- as.data.frame(lapply(df, as.character), stringsAsFactors = FALSE,
                      check.names = FALSE)
  if (is.null(align)) align <- c("l", rep("r", ncol(df) - 1))
  sep <- vapply(align, function(a) if (a == "l") ":---" else "---:", "")
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("| ", paste(sep, collapse = " | "), " |"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

md <- character(0)
add <- function(...) md <<- c(md, ...)

# -----------------------------------------------------------------------------
# 3. PART A -- disposition composition of the analysis sample
# -----------------------------------------------------------------------------
tabA <- d |>
  count(disposition, name = "N") |>
  mutate(pct = 100 * N / N_TOT,
         status = case_when(
           disposition %in% dispo_list ~ "Excluded from Resources by rule",
           disposition %in% LBCC_DISP  ~ "Eligible (left before completing care)",
           disposition == "HOME"       ~ "Eligible (completed visit, discharged)",
           TRUE                        ~ "Eligible (destination not specified)")) |>
  arrange(desc(N))

n_dama <- tabA$N[tabA$disposition == "LEFT AGAINST MEDICAL ADVICE"]
n_lwbs <- tabA$N[tabA$disposition == "LEFT WITHOUT BEING SEEN"]
n_elop <- tabA$N[tabA$disposition == "ELOPED"]
n_lbcc <- sum(d$lbcc)
n_excl <- sum(tabA$N[tabA$disposition %in% dispo_list])

# -----------------------------------------------------------------------------
# 4. PART B -- how each algorithm classifies each disposition
# -----------------------------------------------------------------------------
tabB <- d |>
  group_by(disposition) |>
  summarise(N = n(),
            nyu_n = sum(nyu == 1), res_n = sum(res == 1), ac_n = sum(acuity_out == 1),
            any_n = sum(nyu == 1 | res == 1 | acuity_out == 1), .groups = "drop") |>
  mutate(nyu_p = 100 * nyu_n / N, res_p = 100 * res_n / N,
         ac_p  = 100 * ac_n  / N, any_p = 100 * any_n / N,
         res_ci = wilson(res_n, N)) |>
  arrange(desc(N))

getp <- function(dsp, col) tabB[[col]][tabB$disposition == dsp]

# -----------------------------------------------------------------------------
# 5. PART C -- the left-before-completing-care group and the mechanism
# -----------------------------------------------------------------------------
n_lbcc_res   <- sum(d$lbcc & d$res == 1)
pct_lbcc_res <- 100 * n_lbcc_res / n_res

grp_of <- function(g) switch(g,
  LBCC     = d |> filter(lbcc),
  DAMA     = d |> filter(disposition == "LEFT AGAINST MEDICAL ADVICE"),
  LWBS     = d |> filter(disposition == "LEFT WITHOUT BEING SEEN"),
  ELOPED   = d |> filter(disposition == "ELOPED"),
  OTHER    = d |> filter(disposition == "OTHER"),
  HOME     = d |> filter(disposition == "HOME"),
  ADMITTED = d |> filter(disposition == "ADMITTED"))

H <- grp_of("HOME"); A <- grp_of("DAMA"); L <- grp_of("LBCC")
W <- grp_of("LWBS"); E <- grp_of("ELOPED"); AD <- grp_of("ADMITTED")

mech_row <- function(g) {
  x <- grp_of(g)
  data.frame(Group = g, N = fm(nrow(x)),
             `No rhythm recorded (%)`      = pc(100 * mean(x$no_rhythm), 2),
             `No medication dispensed (%)` = pc(100 * mean(x$no_med), 2),
             `Both missing (%)`            = pc(100 * mean(x$no_either), 2),
             `Resources flagged (%)`       = pc(100 * mean(x$res), 2),
             check.names = FALSE)
}
tabC1 <- bind_rows(lapply(c("LWBS", "ELOPED", "DAMA", "LBCC", "HOME", "OTHER", "ADMITTED"), mech_row))

los_row <- function(g) {
  x <- grp_of(g); q <- quantile(x$length_of_stay, c(.25, .5, .75), na.rm = TRUE)
  data.frame(Group = g, N = fm(nrow(x)),
             `Median LOS, min` = fm(q[2]),
             `IQR, min` = paste0(fm(q[1]), "-", fm(q[3])),
             `Median LOS, h` = pc(q[2] / 60, 1),
             `Median triage ESI` = median(x$acuity, na.rm = TRUE),
             `Mean triage ESI` = pc(mean(x$acuity, na.rm = TRUE), 2),
             `ESI 1-2 (%)` = pc(100 * mean(x$acuity <= 2), 1),
             `ESI 4-5 (%)` = pc(100 * mean(x$acuity >= 4), 1),
             check.names = FALSE)
}
tabC2 <- bind_rows(lapply(c("LWBS", "ELOPED", "DAMA", "LBCC", "HOME", "ADMITTED"), los_row))

# Resources flag rate within triage strata -- the acuity-matched comparison
tabC3 <- d |>
  filter(disposition %in% c("HOME", LBCC_DISP)) |>
  mutate(g = case_when(disposition == "HOME" ~ "HOME",
                       disposition == "LEFT WITHOUT BEING SEEN" ~ "LWBS",
                       disposition == "ELOPED" ~ "ELOPED",
                       TRUE ~ "DAMA")) |>
  group_by(g, acuity) |>
  summarise(N = n(), res_p = 100 * mean(res), .groups = "drop") |>
  mutate(cell = paste0(pc(res_p, 1), "% (n=", fm(N), ")")) |>
  select(g, acuity, cell) |>
  pivot_wider(names_from = g, values_from = cell) |>
  arrange(acuity) |>
  mutate(across(everything(), ~ ifelse(is.na(.x), "-", as.character(.x)))) |>
  select(`Triage ESI` = acuity, HOME, LWBS, ELOPED, DAMA)

res_by_esi <- function(x, esi) 100 * mean(x$res[x$acuity == esi])

# -----------------------------------------------------------------------------
# 6. PART D -- clinical / demographic distinctiveness vs HOME
# -----------------------------------------------------------------------------
cont_row <- function(v, label, dp = 2) {
  f <- function(x) sprintf("%.*f (%.*f) / %s", dp, mean(x[[v]], na.rm = TRUE),
                           dp, sd(x[[v]], na.rm = TRUE), fm(median(x[[v]], na.rm = TRUE)))
  data.frame(Variable = label, HOME = f(H), DAMA = f(A),
             `SMD DAMA` = smd_flag(smd_cont(A[[v]], H[[v]])), LBCC = f(L),
             `SMD LBCC` = smd_flag(smd_cont(L[[v]], H[[v]])), check.names = FALSE)
}
bin_row <- function(f, label) {
  pH <- mean(f(H)); pA <- mean(f(A)); pL <- mean(f(L))
  data.frame(Variable = label,
             HOME = sprintf("%s (%s%%)", fm(sum(f(H))), pc(100 * pH, 2)),
             DAMA = sprintf("%s (%s%%)", fm(sum(f(A))), pc(100 * pA, 2)),
             `SMD DAMA` = smd_flag(smd_cat(pA, pH)),
             LBCC = sprintf("%s (%s%%)", fm(sum(f(L))), pc(100 * pL, 2)),
             `SMD LBCC` = smd_flag(smd_cat(pL, pH)), check.names = FALSE)
}

tabD <- bind_rows(
  cont_row("age", "Age, mean (SD) / median", 1),
  bin_row(function(x) x$gender == "F", "Female"),
  bin_row(function(x) x$race5 == "White",           "Race: White"),
  bin_row(function(x) x$race5 == "Black",           "Race: Black"),
  bin_row(function(x) x$race5 == "Hispanic/Latino", "Race: Hispanic/Latino"),
  bin_row(function(x) x$race5 == "Asian",           "Race: Asian"),
  bin_row(function(x) x$race5 == "Other",           "Race: Other/unknown"),
  cont_row("cci_score", "Charlson index, mean (SD) / median", 2),
  bin_row(function(x) x$cci_score >= 1, "Charlson index >= 1"),
  bin_row(function(x) x$revisit_72hrs == "YES", "72-hour revisit"),
  cont_row("prior_visits_1yr", "Prior ED visits, 1 yr, mean (SD) / median", 3),
  cont_row("acuity", "Triage ESI, mean (SD) / median", 2),
  cont_row("length_of_stay", "ED length of stay, min, mean (SD) / median", 1))

# Race sensitivity: how much of the LBCC "Other" excess is unrecorded ethnicity
unk <- c("UNKNOWN", "UNABLE TO OBTAIN", "PATIENT DECLINED TO ANSWER")
race_unknown <- data.frame(
  Group = c("HOME", "DAMA", "LBCC"),
  `Race recorded as UNKNOWN (%)` = c(pc(100 * mean(H$race == "UNKNOWN"), 2),
                                     pc(100 * mean(A$race == "UNKNOWN"), 2),
                                     pc(100 * mean(L$race == "UNKNOWN"), 2)),
  `UNKNOWN / unable / declined (%)` = c(pc(100 * mean(H$race %in% unk), 2),
                                        pc(100 * mean(A$race %in% unk), 2),
                                        pc(100 * mean(L$race %in% unk), 2)),
  check.names = FALSE)

top_k <- function(x, ref, col, k = 5) {
  tb <- table(x[[col]]); props <- sort(prop.table(tb), decreasing = TRUE)
  nms <- names(props)[seq_len(min(k, length(props)))]
  data.frame(Category = nms,
             N = fm(as.integer(tb[nms])),
             `% of group` = pc(100 * as.numeric(prop.table(tb)[nms]), 2),
             `% of HOME`  = pc(100 * as.numeric(prop.table(table(ref[[col]]))[nms]), 2),
             SMD = vapply(nms, function(nm)
               smd_flag(smd_cat(mean(x[[col]] == nm), mean(ref[[col]] == nm))), ""),
             check.names = FALSE, row.names = NULL)
}
tabD_cl_dama <- top_k(A, H, "cluster_l");  tabD_cl_lbcc <- top_k(L, H, "cluster_l")
tabD_ic_dama <- top_k(A, H, "icd_chapter"); tabD_ic_lbcc <- top_k(L, H, "icd_chapter")

pdiff <- function(x, ref, col, val) c(100 * mean(x[[col]] == val), 100 * mean(ref[[col]] == val),
                                      smd_cat(mean(x[[col]] == val), mean(ref[[col]] == val)))

# -----------------------------------------------------------------------------
# 7. PART E -- impact on the Resources estimate
# -----------------------------------------------------------------------------
res_adj   <- ifelse(d$lbcc, 0L, as.integer(d$res))     # LBCC made ineligible
n_res_adj <- sum(res_adj)
n_any_adj <- sum(d$nyu == 1 | res_adj == 1 | d$acuity_out == 1)
n_lost    <- n_any - n_any_adj                         # LBCC flagged by Resources alone

d2 <- d |> filter(!lbcc)                               # LBCC removed from sample
n2 <- nrow(d2)
n2_any <- sum(d2$nyu == 1 | d2$res == 1 | d2$acuity_out == 1)

np <- function(n, den) sprintf("%s (%s%%)", fm(n), pc(100 * n / den, 2))

tabE <- data.frame(
  Scenario = c("Published analysis",
               "LBCC ineligible for Resources (sample unchanged)",
               "LBCC removed from the sample entirely"),
  Denominator = c(fm(N_TOT), fm(N_TOT), fm(n2)),
  `Diagnosis (NYU)` = c(np(n_nyu, N_TOT), np(n_nyu, N_TOT), np(sum(d2$nyu), n2)),
  Resources = c(np(n_res, N_TOT), np(n_res_adj, N_TOT), np(sum(d2$res), n2)),
  `Triage-Acuity` = c(np(n_ac, N_TOT), np(n_ac, N_TOT), np(sum(d2$acuity_out), n2)),
  `Flagged by >=1` = c(np(n_any, N_TOT), np(n_any_adj, N_TOT), np(n2_any, n2)),
  check.names = FALSE)

n_lbcc_res_only <- sum(d$lbcc & d$res == 1 & d$nyu == 0 & d$acuity_out == 0)
n_lbcc_res_also <- sum(d$lbcc & d$res == 1 & (d$nyu == 1 | d$acuity_out == 1))

# -----------------------------------------------------------------------------
# 8. WRITE MARKDOWN REPORT
# -----------------------------------------------------------------------------
add("# R1.18 -- Discharge against medical advice and other presentations that left before completing care",
    "",
    sprintf("Generated by `r1_18_dama_disposition.R` from `ANALYSIS/ed_single.parquet` (n = %s first ED visits per patient). All verification checks passed.",
            fm(N_TOT)),
    "")

add("## Verdict", "",
    sprintf("DAMA is directly identifiable in MIMIC-IV-ED and these presentations **were included** in the analysis sample: the `disposition` field records %s visits (%s%% of the %s analysed) as LEFT AGAINST MEDICAL ADVICE, alongside %s LEFT WITHOUT BEING SEEN and %s ELOPED, giving %s visits (%s%%) that ended before care was completed.",
            fm(n_dama), pc(100 * n_dama / N_TOT, 2), fm(N_TOT), fm(n_lwbs), fm(n_elop),
            fm(n_lbcc), pc(100 * n_lbcc / N_TOT, 2)),
    sprintf("None were excluded by any of the three algorithms -- the Resources rule excludes only ADMITTED, TRANSFER and EXPIRED, so every incomplete-care visit remained eligible to be labelled potentially avoidable, and %s of them (%s%% of the %s-visit Resources group) were so labelled.",
            fm(n_lbcc_res), pc(pct_lbcc_res, 1), fm(n_res)),
    sprintf("The mechanism is the one the reviewer suspects: Resources flags a visit when no cardiac rhythm was charted and no medication was dispensed, and patients who leave before treatment satisfy both conditions by construction -- %s%% of LEFT WITHOUT BEING SEEN visits have neither recorded versus %s%% of completed HOME discharges, so %s%% of LWBS visits are flagged as potentially avoidable against %s%% of HOME visits.",
            pc(100 * mean(W$no_either), 1), pc(100 * mean(H$no_either), 1),
            pc(getp("LEFT WITHOUT BEING SEEN", "res_p"), 1), pc(getp("HOME", "res_p"), 1)),
    sprintf("Lower urgency does not explain it: the incomplete-care group has a triage distribution essentially identical to HOME (mean ESI %s vs %s, median 3 in both), while DAMA patients are *more* urgent (mean ESI %s, %s%% triaged ESI 1-2 vs %s%%), older and more comorbid (mean age %s vs %s years, SMD %+.2f; Charlson >= 1 in %s%% vs %s%%, SMD %+.2f) -- yet %s%% of DAMA visits are still flagged by Resources.",
            pc(mean(L$acuity), 2), pc(mean(H$acuity), 2), pc(mean(A$acuity), 2),
            pc(100 * mean(A$acuity <= 2), 1), pc(100 * mean(H$acuity <= 2), 1),
            pc(mean(A$age), 1), pc(mean(H$age), 1), smd_cont(A$age, H$age),
            pc(100 * mean(A$cci_score >= 1), 1), pc(100 * mean(H$cci_score >= 1), 1),
            smd_cat(mean(A$cci_score >= 1), mean(H$cci_score >= 1)),
            pc(getp("LEFT AGAINST MEDICAL ADVICE", "res_p"), 1)),
    sprintf("Within every triage stratum the incomplete-care groups are flagged far more often than HOME patients of the same acuity (at ESI 3: LWBS %s%% and ELOPED %s%% vs HOME %s%%), confirming that the Resources flag is partly measuring *non-receipt of care* rather than *low resource need* -- a genuine construct-validity weakness, not merely a labelling quibble.",
            pc(res_by_esi(W, 3), 1), pc(res_by_esi(E, 3), 1), pc(res_by_esi(H, 3), 1)),
    sprintf("The effect on the headline is real but bounded: making these visits ineligible reduces Resources from %s (%s%%) to %s (%s%%) and the \"flagged by at least one algorithm\" total from %s (%s%%) to %s (%s%%), a fall of %s visits -- so the substantive conclusions survive, but the paper's description of the Resources group as patients \"discharged home\" is inaccurate and should be corrected.",
            fm(n_res), pc(100 * n_res / N_TOT, 2), fm(n_res_adj), pc(100 * n_res_adj / N_TOT, 2),
            fm(n_any), pc(100 * n_any / N_TOT, 2), fm(n_any_adj), pc(100 * n_any_adj / N_TOT, 2),
            fm(n_lost)),
    "")

add("## Verification", "",
    md_table(verif |> transmute(Check = check, Observed = observed, Result = result),
             align = c("l", "r", "l")),
    "",
    "Checks 5 and 6 are supplementary. Check 5 rebuilds `res` from the published rule and finds zero mismatches across all 201,106 rows, which establishes that among dispositions the rule leaves eligible, `res` is *identical* to \"no rhythm charted AND no medication dispensed AND alive that day\".",
    "")

add("## A. Is DAMA identifiable, and how common?", "",
    sprintf("`disposition` takes eight values and is complete for all %s visits (no missing). DAMA is directly identifiable as `LEFT AGAINST MEDICAL ADVICE`: **N = %s (%s%% of the sample)**. Two further categories capture departure before care was completed (LEFT WITHOUT BEING SEEN, ELOPED); `OTHER` is an unspecified destination.",
            fm(N_TOT), fm(n_dama), pc(100 * n_dama / N_TOT, 2)),
    "",
    md_table(tabA |> transmute(Disposition = disposition, N = fm(N), `%` = pc(pct, 2),
                               `Treatment under the Resources rule` = status),
             align = c("l", "r", "r", "l")),
    "",
    sprintf("Only ADMITTED, TRANSFER and EXPIRED (%s visits, %s%%) are removed by the Resources exclusion list. The remaining five categories -- %s visits (%s%%) -- all remain eligible to be flagged.",
            fm(n_excl), pc(100 * n_excl / N_TOT, 2),
            fm(N_TOT - n_excl), pc(100 * (N_TOT - n_excl) / N_TOT, 2)),
    "")

add("## B. How each algorithm classifies each disposition", "",
    "Flag rate = % of visits in that disposition category labelled potentially avoidable. The 95% CI (Wilson) is shown for the Resources column, the one at issue.",
    "",
    md_table(tabB |> transmute(
      Disposition = disposition, N = fm(N),
      `Diagnosis n` = fm(nyu_n), `Diagnosis %` = pc(nyu_p, 1),
      `Resources n` = fm(res_n), `Resources %` = pc(res_p, 1), `Resources 95% CI` = res_ci,
      `Triage-Acuity n` = fm(ac_n), `Triage-Acuity %` = pc(ac_p, 1),
      `>=1 algorithm %` = pc(any_p, 1))),
    "",
    sprintf("The Resources flag is near-automatic for LEFT WITHOUT BEING SEEN (%s%%, 95%% CI %s) and strongly elevated for ELOPED (%s%%) and DAMA (%s%%), against %s%% for completed HOME discharges. The Diagnosis and Triage-Acuity algorithms show no comparable gradient -- Triage-Acuity flags LWBS (%s%%) and HOME (%s%%) at similar rates -- which localises the problem to the Resources definition rather than to the sample.",
            pc(getp("LEFT WITHOUT BEING SEEN", "res_p"), 1), getp("LEFT WITHOUT BEING SEEN", "res_ci"),
            pc(getp("ELOPED", "res_p"), 1), pc(getp("LEFT AGAINST MEDICAL ADVICE", "res_p"), 1),
            pc(getp("HOME", "res_p"), 1),
            pc(getp("LEFT WITHOUT BEING SEEN", "ac_p"), 1), pc(getp("HOME", "ac_p"), 1)),
    "")

add("## C. The \"left before completing care\" (LBCC) group", "",
    sprintf("LBCC = LEFT WITHOUT BEING SEEN + ELOPED + LEFT AGAINST MEDICAL ADVICE = **%s visits (%s%% of the sample)**. Of these, %s are flagged by Resources, which is **%s%% of the %s-visit Resources group**. Adding the %s flagged `OTHER` visits gives %s (%s%%) of the Resources group that were not discharged home after a completed visit.",
            fm(n_lbcc), pc(100 * n_lbcc / N_TOT, 2), fm(n_lbcc_res), pc(pct_lbcc_res, 2), fm(n_res),
            fm(n_oth_res), fm(n_incompl_res), pc(100 * n_incompl_res / n_res, 2)),
    "",
    "### C1. Mechanism -- both Resources criteria are satisfied by non-treatment", "",
    md_table(tabC1), "",
    sprintf("The medication field is the discriminating one. %s%% of LWBS visits have no medication dispensed against %s%% of HOME visits (SMD %+.2f), and %s%% have neither field recorded against %s%% of HOME visits. ELOPED sits between the two (%s%% both missing). DAMA is the mildest case (%s%% both missing) because these patients were usually registered, triaged and partly worked up before leaving -- yet that still exceeds HOME by %s percentage points.",
            pc(100 * mean(W$no_med), 1), pc(100 * mean(H$no_med), 1),
            smd_cat(mean(W$no_med), mean(H$no_med)),
            pc(100 * mean(W$no_either), 1), pc(100 * mean(H$no_either), 1),
            pc(100 * mean(E$no_either), 1), pc(100 * mean(A$no_either), 1),
            pc(100 * mean(A$no_either) - 100 * mean(H$no_either), 1)),
    "",
    sprintf("The rhythm criterion contributes almost nothing on its own: rhythm is unrecorded in %s%% of HOME visits and %s%% of ADMITTED visits, so it separates neither minor from major presentations nor treated from untreated ones. Effectively, Resources = \"no medication dispensed\".",
            pc(100 * mean(H$no_rhythm), 1), pc(100 * mean(AD$no_rhythm), 1)),
    "",
    "### C2. Length of stay and triage acuity", "",
    md_table(tabC2), "",
    sprintf("LBCC visits are much shorter than HOME visits (median %s vs %s minutes; ADMITTED %s), consistent with premature departure. But triage acuity is **not** lower: median ESI is 3 in both LBCC and HOME, and mean ESI is %s in LBCC vs %s in HOME (SMD %+.3f -- indistinguishable). DAMA specifically is clearly *more* urgent than HOME (median ESI 2, mean %s, SMD %+.3f) and has a *longer* median stay (%s vs %s minutes). The \"low acuity\" reading of the Resources flag therefore fails for this group.",
            fm(median(L$length_of_stay, na.rm = TRUE)), fm(median(H$length_of_stay, na.rm = TRUE)),
            fm(median(AD$length_of_stay, na.rm = TRUE)),
            pc(mean(L$acuity), 2), pc(mean(H$acuity), 2), smd_cont(L$acuity, H$acuity),
            pc(mean(A$acuity), 2), smd_cont(A$acuity, H$acuity),
            fm(median(A$length_of_stay, na.rm = TRUE)), fm(median(H$length_of_stay, na.rm = TRUE))),
    "",
    "### C3. Resources flag rate within triage strata", "",
    "If the Resources flag tracked genuine low resource need, its rate should be similar for HOME and LBCC patients triaged at the same acuity. It is not.",
    "",
    md_table(tabC3), "",
    sprintf("The gap holds at every ESI level carrying meaningful volume (ESI 1 contains only 1 LWBS and 52 ELOPED visits and is uninformative). Among ESI 3 patients -- the modal category -- %s%% of LWBS, %s%% of ELOPED and %s%% of DAMA visits are flagged versus %s%% of HOME visits. Even among ESI 2 patients, %s%% of LWBS visits are flagged against %s%% of HOME. This is direct evidence that the flag is driven by whether treatment was received, not by how much treatment was needed.",
            pc(res_by_esi(W, 3), 1), pc(res_by_esi(E, 3), 1), pc(res_by_esi(A, 3), 1),
            pc(res_by_esi(H, 3), 1), pc(res_by_esi(W, 2), 1), pc(res_by_esi(H, 2), 1)),
    "")

add("## D. Are these patients clinically distinct?", "",
    sprintf("Comparisons are against completed HOME discharges (n = %s). Standardised mean differences are reported rather than p-values: with %s HOME visits against %s DAMA visits, conventional tests are governed by sample size and would return p < 0.001 for differences of no clinical consequence, whereas the SMD is independent of n and directly interpretable as the size of the imbalance. **Bold** marks |SMD| > 0.1.",
            fm(nrow(H)), fm(nrow(H)), fm(nrow(A))),
    "",
    "Continuous variables are mean (SD) / median; binary variables are n (%).",
    "",
    md_table(tabD), "",
    sprintf("DAMA patients are a distinct population: %s years older on average than HOME patients (SMD %+.3f), more comorbid (Charlson >= 1 in %s%% vs %s%%, SMD %+.3f), more often male (%s%% female vs %s%%, SMD %+.3f) and more acutely triaged (SMD %+.3f). The pooled LBCC group is dominated numerically by LWBS and so looks slightly younger, healthier and much shorter-stay; its apparent excess of \"Other/unknown\" ethnicity (SMD %+.3f) is largely an artefact of incomplete registration rather than a real case-mix difference:",
            pc(mean(A$age) - mean(H$age), 1), smd_cont(A$age, H$age),
            pc(100 * mean(A$cci_score >= 1), 1), pc(100 * mean(H$cci_score >= 1), 1),
            smd_cat(mean(A$cci_score >= 1), mean(H$cci_score >= 1)),
            pc(100 * mean(A$gender == "F"), 1), pc(100 * mean(H$gender == "F"), 1),
            smd_cat(mean(A$gender == "F"), mean(H$gender == "F")),
            smd_cont(A$acuity, H$acuity),
            smd_cat(mean(L$race5 == "Other"), mean(H$race5 == "Other"))),
    "",
    md_table(race_unknown), "",
    sprintf("`revisit_72hrs` and `prior_visits_1yr` carry almost no information here: the analysis sample is restricted to one first visit per patient, so only %s visits in the whole sample are 72-hour revisits and %s%% have zero prior visits. Downstream utilisation of DAMA patients -- the reviewer's substantive interest -- cannot be assessed in this sample and would require the full multi-visit file.",
            fm(sum(d$revisit_72hrs == "YES")), pc(100 * mean(d$prior_visits_1yr == 0), 1)),
    "",
    "### D1. Top 5 complaint clusters", "",
    "**DAMA vs HOME**", "", md_table(tabD_cl_dama), "",
    "**LBCC vs HOME**", "", md_table(tabD_cl_lbcc), "",
    local({
      a <- pdiff(A, H, "cluster_l", "3 Chest pain + dyspnea")
      b <- pdiff(A, H, "cluster_l", "4 Shortness breath")
      cl <- pdiff(L, H, "cluster_l", "8 Alcohol intoxication")
      sprintf("DAMA presentations concentrate in cardiorespiratory complaints -- chest pain + dyspnoea (%s%% vs %s%% of HOME, SMD %+.3f) and shortness of breath (%s%% vs %s%%, SMD %+.3f) -- exactly the presentations for which leaving early carries risk, and exactly the presentations a resource-based measure should not be calling avoidable. LBCC as a whole is shifted towards alcohol intoxication (%s%% vs %s%%, SMD %+.3f).",
              pc(a[1], 2), pc(a[2], 2), a[3], pc(b[1], 2), pc(b[2], 2), b[3],
              pc(cl[1], 2), pc(cl[2], 2), cl[3])
    }),
    "",
    "### D2. Top 5 ICD chapters", "",
    "**DAMA vs HOME**", "", md_table(tabD_ic_dama), "",
    "**LBCC vs HOME**", "", md_table(tabD_ic_lbcc), "",
    local({
      i1 <- pdiff(A, H, "icd_chapter", "Ill-defined conditions")
      i2 <- pdiff(L, H, "icd_chapter", "Ill-defined conditions")
      j1 <- pdiff(A, H, "icd_chapter", "Injury and poisoning")
      j2 <- pdiff(L, H, "icd_chapter", "Injury and poisoning")
      sprintf("Both groups are heavily over-represented in ill-defined conditions (DAMA %s%%, LBCC %s%%, vs HOME %s%%; SMD %+.3f and %+.3f) and under-represented in injury and poisoning (SMD %+.3f and %+.3f). Ill-defined coding is itself a consequence of an incomplete work-up, so the same interruption that empties the medication field also pushes these visits towards the diagnoses the Diagnosis algorithm treats as non-emergent.",
              pc(i1[1], 1), pc(i2[1], 1), pc(i1[2], 1), i1[3], i2[3], j1[3], j2[3])
    }),
    "")

add("## E. Impact on the Resources estimate", "",
    "Two ways of removing the dependency. Scenario 2 adds the three LBCC dispositions to the Resources exclusion list, leaving the sample and the other two algorithms untouched -- the like-for-like sensitivity analysis. Scenario 3 removes LBCC visits from the sample altogether, which changes every denominator.",
    "",
    md_table(tabE), "",
    sprintf("- Resources falls from **%s (%s%%)** to **%s (%s%%)**, a reduction of %s visits (%s%% relative).",
            fm(n_res), pc(100 * n_res / N_TOT, 2), fm(n_res_adj), pc(100 * n_res_adj / N_TOT, 2),
            fm(n_res - n_res_adj), pc(100 * (n_res - n_res_adj) / n_res, 1)),
    sprintf("- The headline \"flagged by at least one algorithm\" falls from **%s (%s%%)** to **%s (%s%%)**, a reduction of only %s visits, because %s of the %s LBCC visits flagged by Resources are also flagged by the Diagnosis or Triage-Acuity algorithm and remain in the total; %s were flagged by Resources alone.",
            fm(n_any), pc(100 * n_any / N_TOT, 2), fm(n_any_adj), pc(100 * n_any_adj / N_TOT, 2),
            fm(n_lost), fm(n_lbcc_res_also), fm(n_lbcc_res), fm(n_lbcc_res_only)),
    sprintf("- Under the stricter scenario 3 the sample becomes %s visits, Resources becomes %s (%s%%) and \"at least one\" becomes %s (%s%%).",
            fm(n2), fm(sum(d2$res)), pc(100 * mean(d2$res), 2), fm(n2_any), pc(100 * n2_any / n2, 2)),
    "",
    sprintf("So about one in twelve Resources-flagged visits (%s%%) is a patient who never completed care, and %s%% of the Resources total is attributable to them. The overall conclusion -- that a large minority of ED attendances are labelled potentially avoidable, and that the three algorithms agree poorly -- is not overturned. But the Resources estimate is inflated by patients whose records are empty because they left, not because their need was low.",
            pc(pct_lbcc_res, 1), pc(100 * (n_res - n_res_adj) / n_res, 1)),
    "")

add("## Implications for the manuscript", "",
    "1. The statement that Resources-flagged patients were \"discharged home\" is not accurate and should be replaced with an explicit statement of the exclusion list (ADMITTED, TRANSFER, EXPIRED) and of which dispositions remain eligible.",
    sprintf("2. DAMA is identifiable (N = %s) and was included, as were LWBS (N = %s) and ELOPED (N = %s). This belongs in the methods.",
            fm(n_dama), fm(n_lwbs), fm(n_elop)),
    "3. The scenario-2 sensitivity analysis above is the natural addition: it is a one-line change to the rule and shows both the direction and the magnitude of the bias.",
    "4. The construct-validity limitation should be named directly -- the Resources algorithm cannot distinguish \"needed few resources\" from \"received no resources\", so its flag is partly a marker of care interruption. This also bears on generalisability: the flag rate will track a department's LWBS rate, which varies widely with crowding.",
    "5. Downstream utilisation of DAMA patients cannot be studied in this first-visit-only sample; that would need the full multi-visit file.",
    "")

writeLines(md, OUT_MD)
cat("\nWritten:", OUT_MD, "\n")
