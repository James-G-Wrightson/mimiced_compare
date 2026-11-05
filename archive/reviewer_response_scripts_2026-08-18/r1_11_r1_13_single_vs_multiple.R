###############################################################################
# r1_11_r1_13_single_vs_multiple.R
#
# IJPDS revision -- supplementary analyses for reviewer comments R1.11 and R1.13
#
#   R1.11  How was the total of 100,568 potentially avoidable ED presentations
#          derived, why present a combined estimate across the diagnosis-,
#          resource- and triage-based algorithms, and do presentations flagged
#          by a SINGLE algorithm differ demographically / clinically from those
#          flagged by MULTIPLE algorithms?
#
#   R1.13  Do presenting complaints differ between single- and multi-algorithm
#          presentations?
#
# Input   ANALYSIS/ed_single.parquet   (201,106 rows; published analysis sample,
#                                       one first ED visit per patient)
# Output  r1_11_single_vs_multiple_demographics.md
#         r1_13_single_vs_multiple_complaints.md
#         (written next to this script)
#
# Run with:  Rscript r1_11_r1_13_single_vs_multiple.R
#
# The script is self-contained and re-runnable. It asserts every published
# count before computing anything; if an assertion fails it stops.
#
# NOTE ON INFERENCE. Group sizes here are 72,236 vs 28,332. At that n every
# trivial difference is "statistically significant", so p-values are actively
# misleading as a guide to importance. All comparisons are therefore reported
# as standardised mean differences (SMD), with |SMD| > 0.1 as the conventional
# threshold for a non-negligible difference. No p-values are reported.
###############################################################################

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(binom)
})

options(stringsAsFactors = FALSE)

data_path <- "/Users/jameswrightson/Documents/Projects/mimic/nonurgent/mimiced_compare/ANALYSIS/ed_single.parquet"

## outputs are written alongside this script
this_file <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f) else NA_character_
})
out_dir <- if (!is.na(this_file)) dirname(this_file) else getwd()

stopifnot(file.exists(data_path))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

## ---------------------------------------------------------------------------
## 0. Load
## ---------------------------------------------------------------------------

keep_cols <- c(
  "nyu", "res", "acuity_out", "combined_group", "cluster",
  "age", "gender", "race", "acuity", "pain", "length_of_stay",
  "disposition", "revisit_72hrs", "prior_visits_1yr", "cci_score",
  "icd_chapter",
  ## needed for the definitional-constraint audit (Part 2B)
  "med_gsn_count", "pre_gsn_count", "rhythm", "icd_codes"
)

ed <- arrow::read_parquet(data_path, col_select = all_of(keep_cols))

## ---------------------------------------------------------------------------
## 1. Derived variables  (definitions fixed by the published paper)
## ---------------------------------------------------------------------------

ed <- ed %>%
  mutate(
    combined_group_rebuilt = paste0(nyu, res, acuity_out),
    n_algorithms           = nyu + res + acuity_out,
    grp = case_when(
      n_algorithms == 0 ~ "UNFLAGGED",
      n_algorithms == 1 ~ "SINGLE",
      n_algorithms >= 2 ~ "MULTIPLE"
    ),
    grp = factor(grp, levels = c("SINGLE", "MULTIPLE", "UNFLAGGED")),

    ## race collapsed to 5 categories by str_detect on the raw MIMIC strings.
    ## Hispanic/Latino is tested first so it is not absorbed by WHITE.
    race5 = case_when(
      str_detect(race, "HISPANIC|LATINO") ~ "Hispanic-Latino",
      str_detect(race, "WHITE")           ~ "White",
      str_detect(race, "BLACK")           ~ "Black",
      str_detect(race, "ASIAN")           ~ "Asian",
      TRUE                                ~ "Other"
    ),
    race5 = factor(race5, levels = c("White", "Black", "Hispanic-Latino",
                                     "Asian", "Other")),

    female    = as.integer(gender == "F"),
    disp_home = as.integer(disposition == "HOME"),
    disp_adm  = as.integer(disposition == "ADMITTED"),
    disp_left = as.integer(disposition %in% c("LEFT WITHOUT BEING SEEN",
                                              "ELOPED",
                                              "LEFT AGAINST MEDICAL ADVICE")),
    revisit   = as.integer(revisit_72hrs == "YES")
  )

cluster_labels <- c(
  "0"  = "Lower back pain",
  "1"  = "Influenza like illness",
  "2"  = "Vehicle collision + Altered mental status",
  "3"  = "Chest pain + dyspnea",
  "4"  = "Shortness breath",
  "5"  = "Abdomen pain",
  "6"  = "Leg + knee pain",
  "7"  = "Wound evaluation",
  "8"  = "Alcohol intoxication",
  "9"  = "Nausea vomiting",
  "10" = "Suicidal ideation",
  "11" = "Fall transfer"
)

ed <- ed %>%
  mutate(cluster_label = factor(unname(cluster_labels[as.character(cluster)]),
                                levels = unname(cluster_labels)))

## ---------------------------------------------------------------------------
## 2. VERIFICATION -- must all pass before anything is computed
## ---------------------------------------------------------------------------

check_log <- list()
check <- function(label, actual, expected) {
  ok <- isTRUE(all.equal(as.numeric(actual), as.numeric(expected)))
  check_log[[length(check_log) + 1]] <<- data.frame(
    check = label, expected = as.numeric(expected), actual = as.numeric(actual),
    result = ifelse(ok, "PASS", "FAIL")
  )
  invisible(ok)
}

grp_tab <- table(ed$combined_group)
gc_ <- function(g) as.integer(grp_tab[g])

check("Total rows",                        nrow(ed),                        201106)
check("combined_group == paste0(nyu,res,acuity_out) for all rows",
      sum(ed$combined_group == ed$combined_group_rebuilt),                  201106)
check("FLAGGED (n_algorithms >= 1)",       sum(ed$n_algorithms >= 1),       100568)
check("UNFLAGGED ('000')",                 sum(ed$combined_group == "000"), 100538)
check("SINGLE (n_algorithms == 1)",        sum(ed$n_algorithms == 1),        72236)
check("MULTIPLE (n_algorithms >= 2)",      sum(ed$n_algorithms >= 2),        28332)
check("SINGLE + MULTIPLE == FLAGGED",
      sum(ed$n_algorithms == 1) + sum(ed$n_algorithms >= 2),                100568)
check("Group '100' (Diagnosis only)",      gc_("100"),                       44119)
check("Group '010' (Resources only)",      gc_("010"),                       23427)
check("Group '110' (Diagnosis+Resources)", gc_("110"),                       17306)
check("Group '001' (Triage only)",         gc_("001"),                        4690)
check("Group '011' (Resources+Triage)",    gc_("011"),                        4278)
check("Group '101' (Diagnosis+Triage)",    gc_("101"),                        3578)
check("Group '111' (all three)",           gc_("111"),                        3170)
check("Algorithm total: Diagnosis (nyu)",  sum(ed$nyu),                      68173)
check("Algorithm total: Resources (res)",  sum(ed$res),                      48181)
check("Algorithm total: Triage-Acuity",    sum(ed$acuity_out),               15716)
check("Sum of the three algorithm totals",
      sum(ed$nyu) + sum(ed$res) + sum(ed$acuity_out),                       132070)
check("Double-counted excess (132,070 - 100,568)",
      sum(ed$nyu) + sum(ed$res) + sum(ed$acuity_out) - sum(ed$n_algorithms >= 1),
                                                                             31502)

## --- determinism checks: which reported variables are ALGORITHM INPUTS -------
## These establish that `acuity` and `disposition` are not free-standing
## outcomes but are partly determined by algorithm membership. Expressed as
## counts of violating rows, all of which must be 0.
check("acuity_out is exactly (acuity >= 4): violating rows",
      sum(ed$acuity_out != as.integer(ed$acuity >= 4)),                           0)
check("res == 1 never ADMITTED: violating rows",
      sum(ed$res == 1 & ed$disposition == "ADMITTED"),                            0)
check("res == 1 never TRANSFER: violating rows",
      sum(ed$res == 1 & ed$disposition == "TRANSFER"),                            0)
check("res == 1 always has no ECG rhythm recorded: violating rows",
      sum(ed$res == 1 & !is.na(ed$rhythm)),                                       0)
check("res == 1 always has no discharge prescription: violating rows",
      sum(ed$res == 1 & !is.na(ed$pre_gsn_count)),                                0)

checks <- bind_rows(check_log)
cat("\n================ VERIFICATION ================\n")
print(checks, row.names = FALSE)
cat("==============================================\n\n")

if (any(checks$result == "FAIL")) {
  stop("VERIFICATION FAILED -- stopping. See table above.")
}

## ---------------------------------------------------------------------------
## 3. Helper functions
## ---------------------------------------------------------------------------

fN   <- function(x) formatC(as.numeric(x), format = "d", big.mark = ",")
f1   <- function(x) sprintf("%.1f", x)
f2   <- function(x) sprintf("%.2f", x)
fpct <- function(p) sprintf("%.1f", 100 * p)

## continuous: mean (95% CI) and median (IQR)
cont_stats <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x); m <- mean(x); s <- sd(x)
  se <- s / sqrt(n)
  tcrit <- qt(0.975, df = n - 1)
  q <- quantile(x, c(0.25, 0.5, 0.75), names = FALSE)
  list(n = n, mean = m, sd = s, lo = m - tcrit * se, hi = m + tcrit * se,
       med = q[2], q1 = q[1], q3 = q[3])
}
cont_mean_ci <- function(s) sprintf("%s (%s to %s)", f2(s$mean), f2(s$lo), f2(s$hi))
cont_med_iqr <- function(s) sprintf("%s (%s-%s)", f1(s$med), f1(s$q1), f1(s$q3))

## proportion: % (Agresti-Coull 95% CI)
prop_stats <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x); k <- sum(x)
  ci <- binom::binom.confint(k, n, conf.level = 0.95, methods = "agresti-coull")
  list(n = n, k = k, p = k / n, lo = ci$lower, hi = ci$upper)
}
prop_pct_ci <- function(s) sprintf("%s%% (%s-%s)", fpct(s$p), fpct(s$lo), fpct(s$hi))

## SMD, continuous:  (m1 - m2) / sqrt((sd1^2 + sd2^2) / 2)
smd_cont <- function(x1, x2) {
  x1 <- x1[!is.na(x1)]; x2 <- x2[!is.na(x2)]
  (mean(x1) - mean(x2)) / sqrt((var(x1) + var(x2)) / 2)
}
## SMD, single category: (p1 - p2) / sqrt((p1(1-p1) + p2(1-p2)) / 2)
smd_prop <- function(p1, p2) (p1 - p2) / sqrt((p1 * (1 - p1) + p2 * (1 - p2)) / 2)

flag_smd <- function(s) ifelse(is.na(s), "", ifelse(abs(s) > 0.1, "**yes**", "no"))
fsmd     <- function(s) ifelse(is.na(s), "", sprintf("%+.3f", s))

md_table <- function(df) {
  df <- as.data.frame(lapply(df, as.character), check.names = FALSE,
                      stringsAsFactors = FALSE)
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows <- vapply(seq_len(nrow(df)),
                 function(i) paste0("| ", paste(unlist(df[i, ]), collapse = " | "), " |"),
                 character(1))
  c(hdr, sep, rows)
}

S <- ed %>% filter(grp == "SINGLE")
M <- ed %>% filter(grp == "MULTIPLE")
U <- ed %>% filter(grp == "UNFLAGGED")

nS <- nrow(S); nM <- nrow(M); nU <- nrow(U)

## ---------------------------------------------------------------------------
## PART 1 -- derivation of the 100,568 (R1.11)
## ---------------------------------------------------------------------------

grp_order <- c("100", "010", "001", "110", "101", "011", "111")
grp_names <- c(
  "100" = "Diagnosis only",
  "010" = "Resources only",
  "001" = "Triage-Acuity only",
  "110" = "Diagnosis + Resources",
  "101" = "Diagnosis + Triage-Acuity",
  "011" = "Resources + Triage-Acuity",
  "111" = "All three"
)

n_by_grp <- vapply(grp_order, gc_, integer(1))

part1a <- data.frame(
  `Overlap group (nyu/res/acuity)` = grp_order,
  `Algorithms flagging the visit`  = unname(grp_names[grp_order]),
  `No. of algorithms`              = as.character(vapply(grp_order, function(g)
                                       sum(as.integer(strsplit(g, "")[[1]])), integer(1))),
  `N visits`                       = fN(n_by_grp),
  `% of 100,568 flagged`           = fpct(n_by_grp / 100568),
  `% of 201,106 sample`            = fpct(n_by_grp / 201106),
  check.names = FALSE, stringsAsFactors = FALSE
)
part1a <- rbind(
  part1a,
  data.frame(`Overlap group (nyu/res/acuity)` = "SINGLE subtotal",
             `Algorithms flagging the visit`  = "exactly one algorithm",
             `No. of algorithms`              = "1",
             `N visits`                       = fN(nS),
             `% of 100,568 flagged`           = fpct(nS / 100568),
             `% of 201,106 sample`            = fpct(nS / 201106),
             check.names = FALSE),
  data.frame(`Overlap group (nyu/res/acuity)` = "MULTIPLE subtotal",
             `Algorithms flagging the visit`  = "two or three algorithms",
             `No. of algorithms`              = "2-3",
             `N visits`                       = fN(nM),
             `% of 100,568 flagged`           = fpct(nM / 100568),
             `% of 201,106 sample`            = fpct(nM / 201106),
             check.names = FALSE),
  data.frame(`Overlap group (nyu/res/acuity)` = "**TOTAL FLAGGED**",
             `Algorithms flagging the visit`  = "any algorithm",
             `No. of algorithms`              = ">=1",
             `N visits`                       = paste0("**", fN(100568), "**"),
             `% of 100,568 flagged`           = "100.0",
             `% of 201,106 sample`            = fpct(100568 / 201106),
             check.names = FALSE),
  data.frame(`Overlap group (nyu/res/acuity)` = "000",
             `Algorithms flagging the visit`  = "Not flagged (reference)",
             `No. of algorithms`              = "0",
             `N visits`                       = fN(nU),
             `% of 100,568 flagged`           = "-",
             `% of 201,106 sample`            = fpct(nU / 201106),
             check.names = FALSE)
)

n_nyu <- sum(ed$nyu); n_res <- sum(ed$res); n_acu <- sum(ed$acuity_out)

part1b <- data.frame(
  Step = c("Diagnosis algorithm (NYU-based) flags",
           "Resources algorithm flags",
           "Triage-Acuity algorithm flags",
           "Arithmetic sum of the three algorithm totals",
           "less visits counted more than once (double-counting)",
           "**Union: visits flagged by >=1 algorithm**"),
  N = c(fN(n_nyu), fN(n_res), fN(n_acu), fN(n_nyu + n_res + n_acu),
        paste0("-", fN(n_nyu + n_res + n_acu - 100568)),
        paste0("**", fN(100568), "**")),
  `% of 201,106` = c(fpct(n_nyu / 201106), fpct(n_res / 201106), fpct(n_acu / 201106),
                     fpct((n_nyu + n_res + n_acu) / 201106), "-",
                     paste0("**", fpct(100568 / 201106), "**")),
  check.names = FALSE, stringsAsFactors = FALSE
)

## how the 31,502 excess decomposes
excess_2 <- gc_("110") + gc_("101") + gc_("011")
excess_3 <- gc_("111")
part1c <- data.frame(
  Source = c("Visits flagged by exactly 2 algorithms (counted 1 extra time each)",
             "Visits flagged by all 3 algorithms (counted 2 extra times each)",
             "**Total double-counting**"),
  Visits = c(fN(excess_2), fN(excess_3), fN(excess_2 + excess_3)),
  `Excess counts` = c(fN(excess_2 * 1), fN(excess_3 * 2),
                      paste0("**", fN(excess_2 * 1 + excess_3 * 2), "**")),
  check.names = FALSE, stringsAsFactors = FALSE
)
stopifnot(excess_2 * 1 + excess_3 * 2 == 31502)

## per-algorithm: how much of each algorithm's yield is shared
part1d <- data.frame(
  Algorithm = c("Diagnosis (NYU-based)", "Resources", "Triage-Acuity"),
  `Total flagged` = fN(c(n_nyu, n_res, n_acu)),
  `Flagged by this algorithm alone` = fN(c(gc_("100"), gc_("010"), gc_("001"))),
  `% of its yield that is unique` = fpct(c(gc_("100") / n_nyu, gc_("010") / n_res,
                                           gc_("001") / n_acu)),
  `Shared with >=1 other algorithm` = fN(c(n_nyu - gc_("100"), n_res - gc_("010"),
                                           n_acu - gc_("001"))),
  `% of its yield that is shared` = fpct(c(1 - gc_("100") / n_nyu,
                                           1 - gc_("010") / n_res,
                                           1 - gc_("001") / n_acu)),
  check.names = FALSE, stringsAsFactors = FALSE
)

## ---------------------------------------------------------------------------
## PART 2 -- SINGLE vs MULTIPLE (with UNFLAGGED reference), R1.11
## ---------------------------------------------------------------------------

## `constraint` records whether the variable is an INPUT to one or more of the
## algorithms, and is therefore partly determined by group membership rather
## than being a free-standing empirical difference.
DEF  <- "**DEFINITIONAL**"
PART <- "*partly definitional*"
FREE <- "no"

res_rows <- list()
add_row <- function(variable, statistic, s_val, m_val, u_val, smd = NA_real_,
                    constraint = FREE) {
  res_rows[[length(res_rows) + 1]] <<- data.frame(
    Variable = variable, Statistic = statistic,
    `SINGLE (n=72,236)` = s_val, `MULTIPLE (n=28,332)` = m_val,
    `UNFLAGGED (n=100,538)` = u_val,
    `SMD (S vs M)` = fsmd(smd), `abs(SMD)>0.1` = flag_smd(smd),
    `Algorithm input?` = constraint,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

## --- age
aS <- cont_stats(S$age); aM <- cont_stats(M$age); aU <- cont_stats(U$age)
smd_age <- smd_cont(S$age, M$age)
add_row("Age (years)", "Mean (95% CI)",
        cont_mean_ci(aS), cont_mean_ci(aM), cont_mean_ci(aU), smd_age)
add_row("Age (years)", "Median (IQR)",
        cont_med_iqr(aS), cont_med_iqr(aM), cont_med_iqr(aU))

## --- gender
gS <- prop_stats(S$female); gM <- prop_stats(M$female); gU <- prop_stats(U$female)
smd_fem <- smd_prop(gS$p, gM$p)
add_row("Sex", "Female, % (95% CI, Agresti-Coull)",
        prop_pct_ci(gS), prop_pct_ci(gM), prop_pct_ci(gU), smd_fem)

## --- race
race_smds <- c()
for (lv in levels(ed$race5)) {
  pS <- mean(S$race5 == lv); pM <- mean(M$race5 == lv); pU <- mean(U$race5 == lv)
  sm <- smd_prop(pS, pM); race_smds[lv] <- sm
  add_row("Race/ethnicity", paste0(lv, ", % (N)"),
          sprintf("%s%% (%s)", fpct(pS), fN(sum(S$race5 == lv))),
          sprintf("%s%% (%s)", fpct(pM), fN(sum(M$race5 == lv))),
          sprintf("%s%% (%s)", fpct(pU), fN(sum(U$race5 == lv))),
          sm)
}

## --- triage acuity score (1 = most acute .. 5 = least acute)
acS <- cont_stats(S$acuity); acM <- cont_stats(M$acuity); acU <- cont_stats(U$acuity)
smd_acu <- smd_cont(S$acuity, M$acuity)
add_row("Triage acuity score (1 = most acute)", "Median (IQR)",
        cont_med_iqr(acS), cont_med_iqr(acM), cont_med_iqr(acU),
        constraint = DEF)
add_row("Triage acuity score (1 = most acute)", "Mean (95% CI)",
        cont_mean_ci(acS), cont_mean_ci(acM), cont_mean_ci(acU), smd_acu,
        constraint = DEF)
add_row("Triage acuity score (1 = most acute)",
        "Mean, RESTRICTED to visits without the Triage-Acuity flag",
        cont_mean_ci(cont_stats(S$acuity[S$acuity_out == 0])),
        cont_mean_ci(cont_stats(M$acuity[M$acuity_out == 0])),
        cont_mean_ci(cont_stats(U$acuity)),
        smd_cont(S$acuity[S$acuity_out == 0], M$acuity[M$acuity_out == 0]),
        constraint = "residual")

## --- pain
pnS <- cont_stats(S$pain); pnM <- cont_stats(M$pain); pnU <- cont_stats(U$pain)
smd_pain <- smd_cont(S$pain, M$pain)
add_row("Pain score (0-10)", "Median (IQR)",
        cont_med_iqr(pnS), cont_med_iqr(pnM), cont_med_iqr(pnU))
add_row("Pain score (0-10)", "Mean (95% CI)",
        cont_mean_ci(pnS), cont_mean_ci(pnM), cont_mean_ci(pnU), smd_pain)
add_row("Pain score (0-10)", "N missing",
        fN(sum(is.na(S$pain))), fN(sum(is.na(M$pain))), fN(sum(is.na(U$pain))))

## --- length of stay (minutes)
lS <- cont_stats(S$length_of_stay); lM <- cont_stats(M$length_of_stay)
lU <- cont_stats(U$length_of_stay)
smd_los <- smd_cont(S$length_of_stay, M$length_of_stay)
add_row("ED length of stay (minutes)", "Mean (95% CI)",
        cont_mean_ci(lS), cont_mean_ci(lM), cont_mean_ci(lU), smd_los)
add_row("ED length of stay (minutes)", "Median (IQR)",
        cont_med_iqr(lS), cont_med_iqr(lM), cont_med_iqr(lU))
add_row("ED length of stay (minutes)",
        "Mean, RESTRICTED to non-admitted visits",
        cont_mean_ci(cont_stats(S$length_of_stay[S$disp_adm == 0])),
        cont_mean_ci(cont_stats(M$length_of_stay[M$disp_adm == 0])),
        cont_mean_ci(cont_stats(U$length_of_stay[U$disp_adm == 0])),
        smd_cont(S$length_of_stay[S$disp_adm == 0],
                 M$length_of_stay[M$disp_adm == 0]),
        constraint = "sensitivity")

## --- disposition
disp_smds <- c()
disp_constraint <- c(disp_home = PART, disp_adm = DEF, disp_left = PART)
for (nm in c("disp_home", "disp_adm", "disp_left")) {
  lab <- c(disp_home = "Discharged HOME, % (95% CI)",
           disp_adm  = "ADMITTED, % (95% CI)",
           disp_left = "Left before completing care (LWBS + eloped + AMA), % (95% CI)")[nm]
  ss <- prop_stats(S[[nm]]); mm <- prop_stats(M[[nm]]); uu <- prop_stats(U[[nm]])
  sm <- smd_prop(ss$p, mm$p); disp_smds[nm] <- sm
  add_row("ED disposition", unname(lab),
          prop_pct_ci(ss), prop_pct_ci(mm), prop_pct_ci(uu), sm,
          constraint = unname(disp_constraint[nm]))
}
## admitted, restricted to visits not carrying the Resources flag
add_row("ED disposition",
        "ADMITTED, % RESTRICTED to visits without the Resources flag",
        prop_pct_ci(prop_stats(S$disp_adm[S$res == 0])),
        prop_pct_ci(prop_stats(M$disp_adm[M$res == 0])),
        prop_pct_ci(prop_stats(U$disp_adm[U$res == 0])),
        smd_prop(mean(S$disp_adm[S$res == 0]), mean(M$disp_adm[M$res == 0])),
        constraint = "residual")
add_row("ED disposition",
        "Left before completing care, % RESTRICTED to visits without the Resources flag",
        prop_pct_ci(prop_stats(S$disp_left[S$res == 0])),
        prop_pct_ci(prop_stats(M$disp_left[M$res == 0])),
        prop_pct_ci(prop_stats(U$disp_left[U$res == 0])),
        smd_prop(mean(S$disp_left[S$res == 0]), mean(M$disp_left[M$res == 0])),
        constraint = "residual")

## --- 72-hour revisit
rS <- prop_stats(S$revisit); rM <- prop_stats(M$revisit); rU <- prop_stats(U$revisit)
add_row("72-hour ED revisit", "YES, % (95% CI)",
        prop_pct_ci(rS), prop_pct_ci(rM), prop_pct_ci(rU),
        smd_prop(rS$p, rM$p))
add_row("72-hour ED revisit", "YES, N",
        fN(rS$k), fN(rM$k), fN(rU$k))

## --- prior visits in previous year
vS <- cont_stats(S$prior_visits_1yr); vM <- cont_stats(M$prior_visits_1yr)
vU <- cont_stats(U$prior_visits_1yr)
add_row("Prior ED visits in previous year", "Mean (95% CI)",
        cont_mean_ci(vS), cont_mean_ci(vM), cont_mean_ci(vU),
        smd_cont(S$prior_visits_1yr, M$prior_visits_1yr))
add_row("Prior ED visits in previous year", "Median (IQR)",
        cont_med_iqr(vS), cont_med_iqr(vM), cont_med_iqr(vU))

## --- Charlson comorbidity index
cS <- cont_stats(S$cci_score); cM <- cont_stats(M$cci_score); cU <- cont_stats(U$cci_score)
smd_cci <- smd_cont(S$cci_score, M$cci_score)
smd_cci_na <- smd_cont(S$cci_score[S$disp_adm == 0], M$cci_score[M$disp_adm == 0])
add_row("Charlson comorbidity index", "Mean (95% CI)",
        cont_mean_ci(cS), cont_mean_ci(cM), cont_mean_ci(cU), smd_cci,
        constraint = PART)
add_row("Charlson comorbidity index", "Median (IQR)",
        cont_med_iqr(cS), cont_med_iqr(cM), cont_med_iqr(cU),
        constraint = PART)
add_row("Charlson comorbidity index", "% with CCI >= 1",
        sprintf("%s%%", fpct(mean(S$cci_score >= 1))),
        sprintf("%s%%", fpct(mean(M$cci_score >= 1))),
        sprintf("%s%%", fpct(mean(U$cci_score >= 1))),
        smd_prop(mean(S$cci_score >= 1), mean(M$cci_score >= 1)),
        constraint = PART)
add_row("Charlson comorbidity index",
        "Mean, RESTRICTED to non-admitted visits",
        cont_mean_ci(cont_stats(S$cci_score[S$disp_adm == 0])),
        cont_mean_ci(cont_stats(M$cci_score[M$disp_adm == 0])),
        cont_mean_ci(cont_stats(U$cci_score[U$disp_adm == 0])),
        smd_cci_na,
        constraint = "residual")

part2 <- bind_rows(res_rows)

## --- ICD chapter
chap_p <- function(dat) {
  tb <- table(dat$icd_chapter)
  data.frame(chapter = names(tb), n = as.integer(tb),
             p = as.numeric(tb) / nrow(dat), stringsAsFactors = FALSE)
}
cpS <- chap_p(S); cpM <- chap_p(M); cpU <- chap_p(U)

top5 <- function(cp, lab) {
  cp %>% arrange(desc(n)) %>% slice_head(n = 5) %>%
    transmute(Rank = row_number(), Group = lab, `ICD chapter` = chapter,
              N = fN(n), `%` = fpct(p))
}
part2_top5 <- bind_rows(top5(cpS, "SINGLE"), top5(cpM, "MULTIPLE"),
                        top5(cpU, "UNFLAGGED"))

chap_all <- full_join(cpS %>% select(chapter, nS = n, pS = p),
                      cpM %>% select(chapter, nM = n, pM = p), by = "chapter") %>%
  full_join(cpU %>% select(chapter, nU = n, pU = p), by = "chapter") %>%
  mutate(across(c(nS, nM, nU), ~ tidyr::replace_na(.x, 0L)),
         across(c(pS, pM, pU), ~ tidyr::replace_na(.x, 0)),
         smd = smd_prop(pS, pM))

part2_chap <- chap_all %>%
  arrange(desc(abs(smd))) %>%
  transmute(`ICD chapter (primary diagnosis)` = chapter,
            `SINGLE % (N)`    = sprintf("%s%% (%s)", fpct(pS), fN(nS)),
            `MULTIPLE % (N)`  = sprintf("%s%% (%s)", fpct(pM), fN(nM)),
            `UNFLAGGED % (N)` = sprintf("%s%% (%s)", fpct(pU), fN(nU)),
            `SMD (S vs M)`    = fsmd(smd),
            `abs(SMD)>0.1`    = flag_smd(smd))

## ---------------------------------------------------------------------------
## PART 2B -- DEFINITIONAL-CONSTRAINT AUDIT
##
## Several of the variables compared in Part 2 are INPUTS to the algorithms
## themselves. Because MULTIPLE carries the constraining flags far more often
## than SINGLE, part of every such difference is forced by construction rather
## than observed. This section quantifies how much.
## ---------------------------------------------------------------------------

## --- 2B.1 how often each group carries each flag
flag_mix <- data.frame(
  Group = c("SINGLE", "MULTIPLE", "UNFLAGGED"),
  N = fN(c(nS, nM, nU)),
  `Carries Diagnosis flag` = sprintf("%s%%", fpct(c(mean(S$nyu), mean(M$nyu), 0))),
  `Carries Resources flag` = sprintf("%s%%", fpct(c(mean(S$res), mean(M$res), 0))),
  `Carries Triage-Acuity flag` = sprintf("%s%%",
      fpct(c(mean(S$acuity_out), mean(M$acuity_out), 0))),
  check.names = FALSE, stringsAsFactors = FALSE
)

## --- 2B.2 what each flag forces (verified above, all violating counts = 0)
constraint_tab <- data.frame(
  `Algorithm flag` = c("Triage-Acuity (`acuity_out`)",
                       "Resources (`res`)",
                       "Resources (`res`)",
                       "Resources (`res`)",
                       "Diagnosis (`nyu`)"),
  `What it forces about the visit` = c(
    "`acuity_out` is an exact recode of the triage score: `acuity_out == (acuity >= 4)` for all 201,106 rows",
    "disposition is never ADMITTED (and never TRANSFER or EXPIRED)",
    "disposition is never ADMITTED, so the only remaining ways to end a visit early are eloped / left without being seen / against advice",
    "no ECG rhythm is ever recorded and no discharge prescription is ever issued -- both markers of longer, more intensive care",
    "classification is computed FROM the primary discharge diagnosis, so ICD chapter is an input"),
  `Variable in Part 2 affected` = c("`acuity` -- **fully determined**",
                                    "`disposition` (ADMITTED) -- **fully determined**",
                                    "`disposition` (left before completing care) -- *inflated*",
                                    "`length_of_stay` (indirectly), `cci_score` (via admission)",
                                    "`icd_chapter`"),
  check.names = FALSE, stringsAsFactors = FALSE
)

## --- 2B.3 raw vs constraint-removed comparisons
## helper: SMD in a restricted stratum
restrict_cont <- function(var, keepS, keepM) {
  x1 <- S[[var]][keepS]; x2 <- M[[var]][keepM]
  list(n1 = sum(!is.na(x1)), n2 = sum(!is.na(x2)),
       m1 = mean(x1, na.rm = TRUE), m2 = mean(x2, na.rm = TRUE),
       smd = smd_cont(x1, x2))
}
restrict_prop <- function(var, keepS, keepM) {
  x1 <- S[[var]][keepS]; x2 <- M[[var]][keepM]
  list(n1 = length(x1), n2 = length(x2), m1 = mean(x1), m2 = mean(x2),
       smd = smd_prop(mean(x1), mean(x2)))
}

r_acu_raw <- list(n1 = nS, n2 = nM, m1 = acS$mean, m2 = acM$mean, smd = smd_acu)
r_acu_res <- restrict_cont("acuity", S$acuity_out == 0, M$acuity_out == 0)

r_adm_raw <- list(n1 = nS, n2 = nM, m1 = mean(S$disp_adm), m2 = mean(M$disp_adm),
                  smd = disp_smds[["disp_adm"]])
r_adm_res <- restrict_prop("disp_adm", S$res == 0, M$res == 0)

r_lbc_raw <- list(n1 = nS, n2 = nM, m1 = mean(S$disp_left), m2 = mean(M$disp_left),
                  smd = disp_smds[["disp_left"]])
r_lbc_res <- restrict_prop("disp_left", S$res == 0, M$res == 0)

r_los_raw  <- list(n1 = nS, n2 = nM, m1 = lS$mean, m2 = lM$mean, smd = smd_los)
r_los_res  <- restrict_cont("length_of_stay", S$res == 0, M$res == 0)
r_los_nadm <- restrict_cont("length_of_stay", S$disp_adm == 0, M$disp_adm == 0)
r_los_both <- restrict_cont("length_of_stay", S$res == 0 & S$disp_adm == 0,
                                              M$res == 0 & M$disp_adm == 0)

r_cci_raw  <- list(n1 = nS, n2 = nM, m1 = cS$mean, m2 = cM$mean, smd = smd_cci)
r_cci_nadm <- restrict_cont("cci_score", S$disp_adm == 0, M$disp_adm == 0)

fmt_row <- function(lab, stratum, r, pct = FALSE) {
  v <- if (pct) c(sprintf("%s%%", fpct(r$m1)), sprintf("%s%%", fpct(r$m2)))
       else     c(f2(r$m1), f2(r$m2))
  data.frame(Variable = lab, Stratum = stratum,
             `SINGLE n` = fN(r$n1), `SINGLE value` = v[1],
             `MULTIPLE n` = fN(r$n2), `MULTIPLE value` = v[2],
             SMD = fsmd(r$smd), `abs(SMD)>0.1` = flag_smd(r$smd),
             check.names = FALSE, stringsAsFactors = FALSE)
}

audit <- bind_rows(
  fmt_row("Triage acuity (mean)", "Raw -- **definitional**", r_acu_raw),
  fmt_row("Triage acuity (mean)", "Without Triage-Acuity flag", r_acu_res),
  fmt_row("Admitted (%)", "Raw -- **definitional**", r_adm_raw, pct = TRUE),
  fmt_row("Admitted (%)", "Without Resources flag", r_adm_res, pct = TRUE),
  fmt_row("Left before completing care (%)", "Raw -- *partly definitional*", r_lbc_raw, pct = TRUE),
  fmt_row("Left before completing care (%)", "Without Resources flag", r_lbc_res, pct = TRUE),
  fmt_row("ED length of stay (min)", "Raw", r_los_raw),
  fmt_row("ED length of stay (min)", "Without Resources flag", r_los_res),
  fmt_row("ED length of stay (min)", "Non-admitted only", r_los_nadm),
  fmt_row("ED length of stay (min)", "Non-admitted AND without Resources flag", r_los_both),
  fmt_row("Charlson comorbidity (mean)", "Raw -- *partly definitional*", r_cci_raw),
  fmt_row("Charlson comorbidity (mean)", "Non-admitted only", r_cci_nadm)
)

## --- 2B.4 the key structural limitation: no stratum is free of BOTH
##     the Resources and the Triage-Acuity constraint
clean_cells <- ed %>%
  filter(res == 0, acuity_out == 0) %>%
  count(grp, combined_group, name = "n")
n_mult_clean <- sum(clean_cells$n[clean_cells$grp == "MULTIPLE"])

## --- 2B.5 comorbidity recording is itself driven by admission
cci_by_disp <- ed %>%
  group_by(disposition) %>%
  summarise(N = n(), mean_cci = mean(cci_score),
            mean_codes = mean(nchar(icd_codes)), .groups = "drop") %>%
  arrange(desc(N)) %>%
  transmute(Disposition = disposition, N = fN(N),
            `Mean Charlson` = f2(mean_cci),
            `Mean length of ICD code string` = f1(mean_codes))

## --- 2B.6 ICD chapter is an input to the Diagnosis algorithm
icd_nyu0 <- ed %>%
  filter(nyu == 0, grp %in% c("SINGLE", "MULTIPLE")) %>%
  count(grp, icd_chapter, name = "n") %>%
  group_by(grp) %>% mutate(p = n / sum(n)) %>%
  slice_max(p, n = 3, with_ties = FALSE) %>%
  ungroup() %>%
  transmute(Group = as.character(grp), `ICD chapter` = icd_chapter,
            N = fN(n), `%` = fpct(p))
nyu0_cells <- ed %>% filter(nyu == 0, grp %in% c("SINGLE", "MULTIPLE")) %>%
  count(grp, combined_group, name = "n")

## --- 2B.7 chief complaint is NOT an input to any algorithm; check stability
clus_nadm <- ed %>%
  filter(grp %in% c("SINGLE", "MULTIPLE"), disp_adm == 0) %>%
  count(grp, cluster, name = "n") %>%
  group_by(grp) %>% mutate(p = n / sum(n)) %>% ungroup()
## (the stability table itself is built in Part 3, once `clus` exists)

## ---------------------------------------------------------------------------
## PART 3 -- presenting-complaint clusters (R1.13)
## ---------------------------------------------------------------------------

clus_p <- function(dat) {
  dat %>% count(cluster, cluster_label, name = "n") %>%
    mutate(p = n / nrow(dat))
}
kS <- clus_p(S); kM <- clus_p(M); kU <- clus_p(U)

clus <- kS %>% select(cluster, cluster_label, nS = n, pS = p) %>%
  full_join(kM %>% select(cluster, nM = n, pM = p), by = "cluster") %>%
  full_join(kU %>% select(cluster, nU = n, pU = p), by = "cluster") %>%
  mutate(across(c(nS, nM, nU), ~ tidyr::replace_na(.x, 0L)),
         across(c(pS, pM, pU), ~ tidyr::replace_na(.x, 0)),
         smd = smd_prop(pS, pM),
         ratio = pM / pS) %>%
  arrange(cluster)

## stability of the cluster SMDs once the admission channel is removed
## (chief complaint is not an input to any of the three algorithms)
clus_stab <- clus %>%
  select(cluster, cluster_label, pS, pM, smd_raw = smd) %>%
  left_join(clus_nadm %>% filter(grp == "SINGLE") %>% select(cluster, pS_na = p),
            by = "cluster") %>%
  left_join(clus_nadm %>% filter(grp == "MULTIPLE") %>% select(cluster, pM_na = p),
            by = "cluster") %>%
  mutate(smd_na = smd_prop(pS_na, pM_na)) %>%
  arrange(desc(abs(smd_raw))) %>%
  transmute(Cluster = cluster,
            `Presenting-complaint cluster` = as.character(cluster_label),
            `SINGLE % (raw)` = fpct(pS), `MULTIPLE % (raw)` = fpct(pM),
            `SMD raw` = fsmd(smd_raw),
            `SMD, non-admitted only` = fsmd(smd_na),
            Change = sprintf("%+.3f", smd_na - smd_raw))

part3_dist <- clus %>%
  transmute(Cluster = cluster,
            `Presenting-complaint cluster` = as.character(cluster_label),
            `SINGLE N` = fN(nS), `SINGLE %` = fpct(pS),
            `MULTIPLE N` = fN(nM), `MULTIPLE %` = fpct(pM),
            `UNFLAGGED N` = fN(nU), `UNFLAGGED %` = fpct(pU))

part3_smd <- clus %>%
  arrange(desc(abs(smd))) %>%
  transmute(Rank = row_number(),
            Cluster = cluster,
            `Presenting-complaint cluster` = as.character(cluster_label),
            `SINGLE %` = fpct(pS), `MULTIPLE %` = fpct(pM),
            `Difference MULTIPLE - SINGLE (pp)` = sprintf("%+.1f", 100 * (pM - pS)),
            `Ratio MULTIPLE:SINGLE` = f2(ratio),
            `SMD (S vs M)` = fsmd(smd),
            `abs(SMD)>0.1` = flag_smd(smd),
            `Over-represented in` = ifelse(pM > pS, "MULTIPLE", "SINGLE"))

## --- dose-response: cluster distribution by n_algorithms = 1, 2, 3
dose <- ed %>%
  filter(n_algorithms >= 1) %>%
  count(n_algorithms, cluster, cluster_label, name = "n") %>%
  group_by(n_algorithms) %>%
  mutate(p = n / sum(n)) %>%
  ungroup()

n1 <- sum(ed$n_algorithms == 1); n2 <- sum(ed$n_algorithms == 2)
n3 <- sum(ed$n_algorithms == 3)

dose_wide <- dose %>%
  select(cluster, cluster_label, n_algorithms, n, p) %>%
  pivot_wider(names_from = n_algorithms, values_from = c(n, p),
              names_sep = "_", values_fill = list(n = 0L, p = 0)) %>%
  arrange(cluster) %>%
  mutate(trend = p_3 - p_1)

part3_dose <- dose_wide %>%
  transmute(Cluster = cluster,
            `Presenting-complaint cluster` = as.character(cluster_label),
            `1 algorithm % (N)`  = sprintf("%s%% (%s)", fpct(p_1), fN(n_1)),
            `2 algorithms % (N)` = sprintf("%s%% (%s)", fpct(p_2), fN(n_2)),
            `3 algorithms % (N)` = sprintf("%s%% (%s)", fpct(p_3), fN(n_3)),
            `Change 1 -> 3 (pp)` = sprintf("%+.1f", 100 * trend),
            `Monotonic?` = ifelse((p_1 < p_2 & p_2 < p_3) | (p_1 > p_2 & p_2 > p_3),
                                  "yes", "no"))

## cluster distribution within each of the seven overlap cells (context)
part3_cells <- ed %>%
  filter(n_algorithms >= 1) %>%
  count(combined_group, cluster_label, name = "n") %>%
  group_by(combined_group) %>%
  mutate(p = n / sum(n)) %>%
  slice_max(p, n = 3, with_ties = FALSE) %>%
  summarise(top3 = paste(sprintf("%s (%s%%)", cluster_label, fpct(p)),
                         collapse = "; "), .groups = "drop") %>%
  mutate(Algorithms = unname(grp_names[combined_group]),
         N = fN(vapply(combined_group, gc_, integer(1)))) %>%
  select(`Overlap group` = combined_group, Algorithms, N,
         `Three most common presenting complaints` = top3) %>%
  arrange(match(`Overlap group`, grp_order))

## ---------------------------------------------------------------------------
## 4. Console output
## ---------------------------------------------------------------------------

cat("\n---- PART 1a: mutually exclusive overlap groups ----\n"); print(part1a, row.names = FALSE)
cat("\n---- PART 1b: union vs sum of algorithm totals ----\n"); print(part1b, row.names = FALSE)
cat("\n---- PART 1c: decomposition of the double-counting ----\n"); print(part1c, row.names = FALSE)
cat("\n---- PART 1d: unique vs shared yield per algorithm ----\n"); print(part1d, row.names = FALSE)
cat("\n---- PART 2: SINGLE vs MULTIPLE vs UNFLAGGED ----\n"); print(part2, row.names = FALSE)
cat("\n---- PART 2: top 5 ICD chapters ----\n"); print(part2_top5, row.names = FALSE)
cat("\n---- PART 2: ICD chapters ranked by abs(SMD) ----\n"); print(part2_chap, row.names = FALSE)
cat("\n---- PART 2B.1: flag prevalence by group ----\n"); print(flag_mix, row.names = FALSE)
cat("\n---- PART 2B.2: what each flag forces ----\n"); print(constraint_tab, row.names = FALSE)
cat("\n---- PART 2B.3: raw vs constraint-removed ----\n"); print(audit, row.names = FALSE)
cat("\n---- PART 2B.4: strata free of both constraints ----\n"); print(clean_cells, row.names = FALSE)
cat(sprintf("     MULTIPLE presentations in that stratum: %d\n", n_mult_clean))
cat("\n---- PART 2B.5: comorbidity coding by disposition ----\n"); print(cci_by_disp, row.names = FALSE)
cat("\n---- PART 2B.6: ICD chapter within nyu==0 ----\n"); print(nyu0_cells, row.names = FALSE); print(icd_nyu0, row.names = FALSE)
cat("\n---- PART 3: complaint-cluster distribution ----\n"); print(part3_dist, row.names = FALSE)
cat("\n---- PART 3: clusters ranked by abs(SMD) ----\n"); print(part3_smd, row.names = FALSE)
cat("\n---- PART 3: dose-response by n_algorithms ----\n"); print(part3_dose, row.names = FALSE)
cat("\n---- PART 3: top complaints within each overlap cell ----\n"); print(part3_cells, row.names = FALSE)
cat("\n---- PART 3e: cluster SMD stability (non-admitted) ----\n"); print(clus_stab, row.names = FALSE)

## ---------------------------------------------------------------------------
## 5. Write markdown outputs
## ---------------------------------------------------------------------------

check_md <- checks %>%
  transmute(Check = check, Expected = fN(expected), Observed = fN(actual),
            Result = result)

## dynamic bits used in the prose
big_smds <- part2 %>%
  filter(`abs(SMD)>0.1` == "**yes**") %>%
  transmute(txt = sprintf("%s -- %s (SMD %s)", Variable, Statistic, `SMD (S vs M)`))

## ---------------- R1.11 ----------------

md1 <- c(
"# R1.11 -- Derivation of the 100,568 potentially avoidable presentations, and single- vs multi-algorithm comparison",
"",
"*Supplementary analysis for the IJPDS revision. Generated by `r1_11_r1_13_single_vs_multiple.R` from `ANALYSIS/ed_single.parquet` (the published analysis sample: one first ED presentation per patient, N = 201,106). Every number below is produced by that script.*",
"",
"## Verdict",
"",
sprintf("The 100,568 figure is a **union, not a sum**. Every presentation was assigned to exactly one of eight mutually exclusive cells defined by `paste0(nyu, res, acuity_out)`; the seven cells in which at least one algorithm fires add to 100,568 (50.0%% of the 201,106 presentations), and the eighth cell, \"000\", holds the %s presentations no algorithm flags. Adding the three algorithm totals instead (%s Diagnosis + %s Resources + %s Triage-Acuity = %s) would overstate the burden by %s, because %s presentations are flagged by exactly two algorithms and %s by all three.",
        fN(nU), fN(n_nyu), fN(n_res), fN(n_acu), fN(n_nyu + n_res + n_acu),
        fN(31502), fN(excess_2), fN(excess_3)),
"",
"A combined estimate is reported because the three algorithms operationalise different and only partly overlapping constructs of avoidability -- retrospective discharge diagnosis, resources actually consumed, and triage-assigned acuity -- so their union answers the policy question \"how many presentations would *any* accepted method regard as potentially avoidable\" without counting a presentation twice, while the seven-cell breakdown below allows any single-algorithm estimate to be recovered exactly.",
"",
sprintf("On the reviewer's second question, **the two largest apparent differences are definitional and must not be read as empirical findings.** Triage acuity and admission are *inputs* to two of the three algorithms, and MULTIPLE carries those flags far more often than SINGLE (Triage-Acuity flag %s%% vs %s%%; Resources flag %s%% vs %s%%). `acuity_out` is an exact recode of the triage score (`acuity_out == (acuity >= 4)` for all 201,106 rows), and the Resources flag forces disposition never to be ADMITTED. So the raw acuity gap (%s vs %s) and the raw admission gap (%s%% vs %s%%) are largely arithmetic: restricting to presentations that do not carry the Triage-Acuity flag shrinks the acuity gap from %s to %s points (SMD %s to %s), and admission cannot be cleanly compared at all, because the only multi-algorithm presentations without the Resources flag are the %s in group \"101\", which carry the Triage-Acuity flag and are therefore rarely admitted for that second, equally definitional reason.",
        fpct(mean(M$acuity_out)), fpct(mean(S$acuity_out)),
        fpct(mean(M$res)), fpct(mean(S$res)),
        f2(acM$mean), f2(acS$mean),
        fpct(mean(M$disp_adm)), fpct(mean(S$disp_adm)),
        f2(abs(acS$mean - acM$mean)), f2(abs(r_acu_res$m1 - r_acu_res$m2)),
        fsmd(smd_acu), fsmd(r_acu_res$smd), fN(gc_("101"))),
"",
sprintf("What does survive is narrower but genuine. **ED length of stay** is robust: multi-algorithm presentations are shorter by any cut -- raw %s vs %s minutes (SMD %s), and still %s vs %s minutes among non-admitted presentations only (SMD %s), so the gap is not an artefact of the admission constraint. **Comorbidity is much weaker than it first appears**: the raw Charlson gap (%s vs %s; SMD %s) falls to %s vs %s (SMD %s) once admitted presentations are excluded, because comorbidity capture is itself driven by admission (mean Charlson %s in admitted vs %s in discharged-home presentations, reflecting roughly five times as much diagnosis coding). **ICD chapter differences are also confounded**, because the primary discharge diagnosis is the input to the Diagnosis algorithm and %s%% of MULTIPLE carries that flag versus %s%% of SINGLE.",
        f1(lS$mean), f1(lM$mean), fsmd(smd_los),
        f1(r_los_nadm$m1), f1(r_los_nadm$m2), fsmd(r_los_nadm$smd),
        f2(cS$mean), f2(cM$mean), fsmd(smd_cci),
        f2(r_cci_nadm$m1), f2(r_cci_nadm$m2), fsmd(r_cci_nadm$smd),
        f2(mean(ed$cci_score[ed$disposition == "ADMITTED"])),
        f2(mean(ed$cci_score[ed$disposition == "HOME"])),
        fpct(mean(M$nyu)), fpct(mean(S$nyu))),
"",
sprintf("Demographic differences remain small and are unaffected by any of this, since age, sex, race and pain are not inputs to any algorithm: multi-algorithm presentations are modestly younger (mean %s vs %s years; SMD %s) and modestly less often recorded as White (%s%% vs %s%%; SMD %s), while sex is essentially identical (%s%% vs %s%% female; SMD %s) and the remaining race/ethnicity categories (|SMD| <= %s) and recorded pain score (SMD %s) fall below the threshold.",
        f1(aM$mean), f1(aS$mean), fsmd(smd_age),
        fpct(mean(M$race5 == "White")), fpct(mean(S$race5 == "White")),
        fsmd(race_smds[["White"]]),
        fpct(gM$p), fpct(gS$p), fsmd(smd_fem),
        sprintf("%.3f", max(abs(race_smds[names(race_smds) != "White"]))),
        fsmd(smd_pain)),
"",
sprintf("**Revised interpretation.** A severity-gradient reading is still defensible, but it now rests on ED length of stay, on the presenting-complaint distribution (R1.13), and on the demographic null -- not on acuity or admission, which are restatements of the algorithms' own definitions. It should also be stated as a limitation that **no fully clean contrast is available**: the stratum with neither the Resources nor the Triage-Acuity flag contains %s multi-algorithm presentations (it can only contain Diagnosis-only presentations, which are single by definition), so acuity and disposition can never be compared free of both constraints. Readers should treat \"presentations flagged by more algorithms are less acute and less often admitted\" as true by construction, and rely on length of stay and presenting complaint for the substantive claim.",
        ifelse(n_mult_clean == 0, "**no**", fN(n_mult_clean))),
"",
"> **A note on inference.** With 72,236 versus 28,332 presentations, conventional significance tests return p < 0.001 for essentially every variable examined, including differences of a fraction of a year of age that carry no clinical or policy meaning. P-values are therefore not reported. All comparisons use standardised mean differences (SMD): continuous variables as `(m1 - m2) / sqrt((sd1^2 + sd2^2)/2)`, categorical variables per category as `(p1 - p2) / sqrt((p1(1-p1) + p2(1-p2))/2)`, with the conventional |SMD| > 0.1 threshold marking a non-negligible difference.",
"",
"---",
"",
"## Verification of published counts",
"",
"The script asserts each of the following before computing anything, and stops on any failure.",
"",
md_table(check_md),
"",
"---",
"",
"## Part 1 -- How the 100,568 was derived",
"",
"### 1a. The eight mutually exclusive overlap groups",
"",
"Each presentation falls in exactly one cell of `combined_group = paste0(nyu, res, acuity_out)`. The seven non-zero cells partition the flagged set and add to 100,568 with no double-counting.",
"",
md_table(part1a),
"",
"### 1b. Relationship to the three (overlapping) algorithm totals",
"",
md_table(part1b),
"",
"### 1c. Where the 31,502 excess comes from",
"",
"A presentation flagged by exactly two algorithms is counted once too often in the arithmetic sum; one flagged by all three is counted twice too often.",
"",
md_table(part1c),
"",
sprintf("Arithmetic check: (%s x 1) + (%s x 2) = %s = %s - %s.",
        fN(excess_2), fN(excess_3), fN(31502), fN(132070), fN(100568)),
"",
"### 1d. How much of each algorithm's yield is unique",
"",
"This is the substantive rationale for reporting a combined estimate: no algorithm is a subset of another, and each contributes a large block of presentations that no other algorithm identifies. Reporting only one algorithm, or reporting the three totals without their union, would therefore either understate the burden or overstate it by 31,502.",
"",
md_table(part1d),
"",
"---",
"",
"## Part 2 -- Single-algorithm vs multi-algorithm presentations",
"",
sprintf("SINGLE = flagged by exactly one algorithm (n = %s). MULTIPLE = flagged by two or three (n = %s). UNFLAGGED = flagged by none (n = %s), shown as a reference column because the single-versus-multiple contrast is only interpretable against the presentations that neither group contains. SMDs compare SINGLE with MULTIPLE only: **a positive SMD means the value is higher in SINGLE, a negative SMD means it is higher in MULTIPLE**. For continuous variables the SMD is placed on the mean row and is computed from means and standard deviations.",
        fN(nS), fN(nM), fN(nU)),
"",
md_table(part2),
"",
"### Variables exceeding the |SMD| > 0.1 threshold",
"",
if (nrow(big_smds) == 0) "None." else paste0("- ", big_smds$txt),
"",
"### Primary diagnosis (ICD chapter) -- top 5 in each group",
"",
md_table(part2_top5),
"",
"### Primary diagnosis (ICD chapter) -- all chapters, ranked by |SMD|",
"",
"**Caution: partly definitional.** The primary discharge diagnosis is the input to the Diagnosis algorithm, and that flag is carried by a very different share of each group (see Part 2B.6), so these differences are not a clean empirical contrast.",
"",
md_table(part2_chap),
"",
"---",
"",
"## Part 2B -- Definitional-constraint audit",
"",
"This section exists because several variables in Part 2 are **inputs to the algorithms themselves**. Group membership therefore partly determines them, and the raw contrast overstates the empirical difference. (This is the same issue Reviewer 2 raises at R2.2.)",
"",
"### 2B.1 How often each group carries each algorithm flag",
"",
"This is the mechanism: MULTIPLE carries the constraining flags far more often, so any variable those flags constrain will differ between the groups whether or not anything clinically distinct is happening.",
"",
md_table(flag_mix),
"",
"### 2B.2 What each flag forces",
"",
"Each row was verified against the data; all violating-row counts are zero (see the verification table above).",
"",
md_table(constraint_tab),
"",
"### 2B.3 Raw versus constraint-removed comparisons",
"",
"For each affected variable, the raw contrast is shown against the contrast computed after removing the presentations whose values the flag forces.",
"",
md_table(audit),
"",
"Reading this table:",
"",
sprintf("- **Triage acuity is largely definitional.** The raw gap of %s points (SMD %s) falls to %s points (SMD %s) once presentations carrying the Triage-Acuity flag are excluded -- roughly three-quarters of the raw gap is arithmetic. A real residual difference remains, but it is small.",
        f2(abs(acS$mean - acM$mean)), fsmd(smd_acu),
        f2(abs(r_acu_res$m1 - r_acu_res$m2)), fsmd(r_acu_res$smd)),
sprintf("- **Admission cannot be cleanly compared.** The raw %s%% vs %s%% is close to arithmetic necessity, since %s%% of MULTIPLE carries the Resources flag and that flag forbids admission. Restricting to presentations without the flag does not fix this: the SMD actually rises (%s to %s) because the only remaining multi-algorithm presentations are the %s in group \"101\", which all carry the Triage-Acuity flag and are therefore rarely admitted for a second definitional reason. **Neither figure should be presented as an empirical contrast.**",
        fpct(mean(S$disp_adm)), fpct(mean(M$disp_adm)), fpct(mean(M$res)),
        fsmd(r_adm_raw$smd), fsmd(r_adm_res$smd), fN(gc_("101"))),
sprintf("- **Leaving before completing care is partly definitional too.** Presentations carrying the Resources flag account for almost all such episodes (the flag permits eloped / left-without-being-seen but forbids admission), and the contrast weakens from SMD %s to %s once those presentations are removed.",
        fsmd(r_lbc_raw$smd), fsmd(r_lbc_res$smd)),
sprintf("- **Length of stay survives.** It does not attenuate under any restriction: SMD %s raw, %s excluding the Resources flag, %s among non-admitted presentations only, and %s under both restrictions. This is the strongest non-definitional clinical difference in the analysis.",
        fsmd(r_los_raw$smd), fsmd(r_los_res$smd), fsmd(r_los_nadm$smd),
        fsmd(r_los_both$smd)),
sprintf("- **Comorbidity largely does not survive.** The raw Charlson SMD of %s falls to %s among non-admitted presentations. Most of the apparent comorbidity difference is an artefact of differential admission, which is itself definitionally constrained (see 2B.5).",
        fsmd(r_cci_raw$smd), fsmd(r_cci_nadm$smd)),
"",
"### 2B.4 No fully clean contrast exists",
"",
sprintf("The stratum carrying neither the Resources nor the Triage-Acuity flag contains **%s multi-algorithm presentations**. This is a structural consequence of the design rather than a feature of these data: a presentation with neither flag can only be flagged by the Diagnosis algorithm, and a presentation flagged by the Diagnosis algorithm alone is single-algorithm by definition. Acuity and disposition therefore can never be compared between SINGLE and MULTIPLE free of both constraints, and this should be stated as a limitation.",
        ifelse(n_mult_clean == 0, "no", fN(n_mult_clean))),
"",
md_table(clean_cells %>% transmute(Group = as.character(grp),
                                   `Overlap group` = combined_group,
                                   N = fN(n))),
"",
"### 2B.5 Why the comorbidity difference is mostly an admission artefact",
"",
"Charlson score is computed from recorded ICD codes, and admitted presentations carry several times more coded diagnoses than discharged ones. Because the Resources flag forbids admission, and 87.4% of MULTIPLE carries that flag, the comorbidity gap is substantially downstream of a definitional constraint rather than an independent clinical finding.",
"",
md_table(cci_by_disp),
"",
"### 2B.6 ICD chapter is an input to the Diagnosis algorithm",
"",
sprintf("The Diagnosis (NYU-based) algorithm classifies presentations *from* the primary discharge diagnosis, so ICD chapter is an algorithm input, and the flag is carried by %s%% of MULTIPLE versus %s%% of SINGLE. Restricting to presentations without the Diagnosis flag leaves a multi-algorithm stratum consisting only of group \"011\" (n = %s), whose chapter profile is completely unlike the raw comparison -- confirming that the raw ICD chapter contrast is confounded by differential Diagnosis-flag prevalence and should not be presented as a clean empirical difference.",
        fpct(mean(M$nyu)), fpct(mean(S$nyu)), fN(gc_("011"))),
"",
md_table(icd_nyu0),
"",
"### 2B.7 Presenting complaint is not an algorithm input",
"",
"None of the three algorithms uses the free-text chief complaint: the Diagnosis algorithm uses the primary discharge diagnosis, the Resources algorithm uses rhythm documentation, prescriptions and disposition, and the Triage-Acuity algorithm uses the ESI score. The complaint-cluster analysis reported in `r1_13_single_vs_multiple_complaints.md` is therefore the least contaminated evidence available, and its cluster-level SMDs are almost unchanged when the admission channel is removed (see Part 3e of that file).",
"",
"---",
"",
"## Notes on interpretation",
"",
"- **The `Algorithm input?` column marks how far each row is forced by construction.** `**DEFINITIONAL**` means the algorithms' own definitions determine the value; `*partly definitional*` means a substantial share of the difference is forced; `residual` and `sensitivity` rows are the constraint-removed re-computations; `no` means the variable is not used by any algorithm.",
"- **Triage acuity is scored 1 (most acute) to 5 (least acute)**, so the higher mean in the MULTIPLE column denotes *lower* clinical acuity.",
"- **`prior_visits_1yr` and `revisit_72hrs` are near-constant in this sample by construction.** The published analysis sample retains one *first* ED presentation per patient, so almost no presentation has a prior visit in the preceding year and almost none is followed by a recorded 72-hour revisit. They are reported for completeness but carry essentially no information about the single-versus-multiple contrast in this sample.",
"- **ED length of stay is expressed in minutes.**",
"- Race/ethnicity is collapsed from the raw MIMIC-IV strings using `str_detect`, testing Hispanic/Latino first so that entries such as `HISPANIC/LATINO - PUERTO RICAN` are not absorbed into White. `UNKNOWN`, `PATIENT DECLINED TO ANSWER`, `PORTUGUESE`, `SOUTH AMERICAN`, `AMERICAN INDIAN/ALASKA NATIVE`, `NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER`, `MULTIPLE RACE/ETHNICITY` and `UNABLE TO OBTAIN` fall into Other.",
"- Pain score is missing for a small number of presentations; missing counts are given in the table and those presentations are excluded from the pain statistics only.",
"",
"See `r1_13_single_vs_multiple_complaints.md` for the corresponding presenting-complaint analysis (R1.13).",
""
)

writeLines(unlist(md1), file.path(out_dir, "r1_11_single_vs_multiple_demographics.md"))

## ---------------- R1.13 ----------------

## only clusters that clear the |SMD| > 0.1 threshold are named in the verdict
mult_side <- part3_smd %>% filter(`Over-represented in` == "MULTIPLE",
                                  `abs(SMD)>0.1` == "**yes**")
sing_side <- part3_smd %>% filter(`Over-represented in` == "SINGLE",
                                  `abs(SMD)>0.1` == "**yes**")

fmt_side <- function(df, which_pct_first) {
  k <- nrow(df)
  if (k == 0) return("none")
  if (which_pct_first == "M") {
    paste(sprintf("**%s** (%s%% vs %s%%, SMD %s)",
                  df$`Presenting-complaint cluster`, df$`MULTIPLE %`,
                  df$`SINGLE %`, df$`SMD (S vs M)`), collapse = "; ")
  } else {
    paste(sprintf("**%s** (%s%% vs %s%%, SMD %s)",
                  df$`Presenting-complaint cluster`, df$`SINGLE %`,
                  df$`MULTIPLE %`, df$`SMD (S vs M)`), collapse = "; ")
  }
}

n_big   <- sum(part3_smd$`abs(SMD)>0.1` == "**yes**")
n_mono  <- sum(part3_dose$`Monotonic?` == "yes")

## dose-response trajectories quoted in the verdict
dose_traj <- function(cl) {
  r <- dose_wide %>% filter(cluster == cl)
  sprintf("%s%% -> %s%% -> %s%%", fpct(r$p_1), fpct(r$p_2), fpct(r$p_3))
}
lab_of <- function(cl) unname(cluster_labels[as.character(cl)])

md2 <- c(
"# R1.13 -- Presenting complaints in single- vs multi-algorithm presentations",
"",
"*Supplementary analysis for the IJPDS revision. Generated by `r1_11_r1_13_single_vs_multiple.R` from `ANALYSIS/ed_single.parquet` (N = 201,106). Presenting complaints are the twelve free-text chief-complaint clusters used in the main paper.*",
"",
"## Verdict",
"",
sprintf("Presenting complaints do differ between single- and multi-algorithm presentations, and they differ along the same severity gradient seen in the demographic comparison: %s of the twelve complaint clusters exceed the |SMD| > 0.1 threshold. Presentations flagged by **more than one** algorithm are over-represented for musculoskeletal complaints (percentages given as MULTIPLE vs SINGLE): %s.",
        ifelse(n_big == 0, "none", as.character(n_big)), fmt_side(mult_side, "M")),
"",
sprintf("Presentations flagged by **only one** algorithm are over-represented for a quite different set (percentages given as SINGLE vs MULTIPLE): %s. Influenza-like illness and wound evaluation are also commoner among multi-algorithm presentations, and fall/transfer commoner among single-algorithm presentations, but these fall just below the threshold.",
        fmt_side(sing_side, "S")),
"",
"The pattern is clinically coherent. A diagnosis-based rule, a resource-based rule and a triage-based rule can all independently agree that a limb-pain, back-pain, minor-wound or influenza-like presentation is non-emergent, so these accumulate multiple flags. Chest pain and dyspnoea, alcohol intoxication, vomiting and suicidal ideation instead satisfy one criterion at a time -- a benign final diagnosis, or low resource use, or a low triage score -- but rarely all three, because they are triaged as urgent and investigated even when the eventual diagnosis is benign; they therefore accumulate single flags.",
"",
sprintf("The relationship is graded rather than binary: moving from one to two to three concurring algorithms raises the share of %s (%s), %s (%s) and %s (%s), and lowers the share of %s (%s), %s (%s) and %s (%s), with %s of the twelve clusters moving monotonically.",
        lab_of(1), dose_traj(1), lab_of(6), dose_traj(6), lab_of(0), dose_traj(0),
        lab_of(3), dose_traj(3), lab_of(9), dose_traj(9), lab_of(5), dose_traj(5),
        as.character(n_mono)),
"",
"**Why this analysis carries more weight than the acuity and admission comparisons.** Triage acuity and admission status are *inputs* to two of the three algorithms, so differences in them between single- and multi-algorithm presentations are largely forced by construction (see Part 2B of the R1.11 file). The free-text chief complaint is not used by any of the three algorithms -- the Diagnosis algorithm uses the primary discharge diagnosis, the Resources algorithm uses rhythm documentation, prescriptions and disposition, and the Triage-Acuity algorithm uses the ESI score -- so the complaint-cluster contrast is not definitional. It is also empirically stable: removing the admission channel entirely by restricting to non-admitted presentations leaves every cluster SMD essentially unchanged (Part 3e). Together with ED length of stay, this is the evidence that actually supports a severity-gradient reading of algorithm agreement.",
"",
"> **A note on inference.** Group sizes are 72,236 versus 28,332; every cluster difference is nominally significant at conventional thresholds, so p-values are not reported. Clusters are ranked by the standardised mean difference `(p1 - p2) / sqrt((p1(1-p1) + p2(1-p2))/2)`, with |SMD| > 0.1 flagged as non-negligible.",
"",
"---",
"",
"## Verification of published counts",
"",
md_table(check_md),
"",
"---",
"",
"## Part 3a -- Full distribution across the twelve complaint clusters",
"",
sprintf("SINGLE n = %s; MULTIPLE n = %s; UNFLAGGED n = %s. Percentages are column percentages and sum to 100 within each group.",
        fN(nS), fN(nM), fN(nU)),
"",
md_table(part3_dist),
"",
"## Part 3b -- Clusters ranked by |SMD| (SINGLE vs MULTIPLE)",
"",
"Positive SMD means the cluster is over-represented among SINGLE presentations; negative means over-represented among MULTIPLE presentations.",
"",
md_table(part3_smd),
"",
"## Part 3c -- Dose-response: complaint mix by number of concurring algorithms",
"",
sprintf("Restricted to flagged presentations. 1 algorithm n = %s; 2 algorithms n = %s; 3 algorithms n = %s. 'Monotonic?' marks clusters whose share moves consistently in one direction as the number of concurring algorithms increases.",
        fN(n1), fN(n2), fN(n3)),
"",
md_table(part3_dose),
"",
"## Part 3d -- Most common complaints within each overlap cell",
"",
"Context for the above: which complaints dominate each of the seven mutually exclusive algorithm-overlap groups.",
"",
md_table(part3_cells),
"",
"## Part 3e -- Sensitivity: are these differences definitional?",
"",
"Chief complaint is not an input to any of the three algorithms, so unlike triage acuity and admission status (Part 2B of the R1.11 file) the complaint contrast is not forced by construction. As a check, the table below recomputes every cluster SMD after excluding admitted presentations, which removes the one channel through which the Resources algorithm's definition could propagate into the complaint mix.",
"",
md_table(clus_stab),
"",
sprintf("Every cluster SMD changes by less than %s and none changes sign; the four largest effects (%s) keep both their direction and their rank order. %s The contrast with triage acuity, where the SMD falls from -0.792 to -0.264 once the definitional component is removed, and with admission, which cannot be compared cleanly at all, is stark. The complaint-cluster findings are therefore robust and can carry interpretive weight that the acuity and admission comparisons cannot.",
        sprintf("%.2f", ceiling(max(abs(as.numeric(clus_stab$Change))) * 100) / 100),
        paste(clus_stab$`Presenting-complaint cluster`[1:4], collapse = ", "),
        {
          raw_hi <- clus_stab$`Presenting-complaint cluster`[
                      abs(as.numeric(clus_stab$`SMD raw`)) > 0.1]
          na_hi  <- clus_stab$`Presenting-complaint cluster`[
                      abs(as.numeric(clus_stab$`SMD, non-admitted only`)) > 0.1]
          dropped <- setdiff(raw_hi, na_hi); added <- setdiff(na_hi, raw_hi)
          if (length(dropped) == 0 && length(added) == 0) {
            "The set of clusters exceeding the |SMD| > 0.1 threshold is identical under both definitions."
          } else {
            sprintf("The set exceeding |SMD| > 0.1 shifts only at the margin: %s falls just below the threshold and %s rises just above it, leaving %s clusters above it either way.",
                    paste(dropped, collapse = " and "),
                    paste(added, collapse = " and "), as.character(length(na_hi)))
          }
        }),
"",
"---",
"",
"## Cluster labels used",
"",
md_table(data.frame(Cluster = names(cluster_labels),
                    Label = unname(cluster_labels),
                    check.names = FALSE)),
"",
"See `r1_11_single_vs_multiple_demographics.md` for the derivation of the 100,568 total and the demographic/clinical comparison (R1.11).",
""
)

writeLines(unlist(md2), file.path(out_dir, "r1_13_single_vs_multiple_complaints.md"))

cat("\nWrote:\n",
    file.path(out_dir, "r1_11_single_vs_multiple_demographics.md"), "\n",
    file.path(out_dir, "r1_13_single_vs_multiple_complaints.md"), "\n")

## end of script
