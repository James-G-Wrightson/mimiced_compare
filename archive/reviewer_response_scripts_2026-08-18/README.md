# Supplementary analyses for the IJPDS round-1 response

Six reviewer questions needed new computation. This folder holds the results and the
scripts that produced them. Each script re-runs standalone and asserts the published
numbers before computing anything new, so a wrong cohort fails loudly instead of quietly.

Data is read by absolute path from `MIMICED/ed_join_cc.parquet` (424,707 visits, all
labels) and `ANALYSIS/ed_single.parquet` (201,106, the published analysis sample).
Nothing here modifies the published notebooks, tables or figures.

| Question | Results | Script |
|---|---|---|
| R1.4 excluded vs retained visits | `r1_04_excluded_vs_retained.md` | `r1_04_excluded_vs_retained.R` |
| R1.5 visits per patient | `r1_05_visits_per_patient.md` | `r1_05_r2_01_repeat_visits.R` |
| R2.1 all-visit sensitivity analysis | `r2_01_sensitivity_all_visits.md` | same as above |
| R1.11 single vs multiple algorithms | `r1_11_single_vs_multiple_demographics.md` | `r1_11_r1_13_single_vs_multiple.R` |
| R1.13 presenting complaints | `r1_13_single_vs_multiple_complaints.md` | same as above |
| R1.18 discharge against medical advice | `r1_18_dama_disposition.md` | `r1_18_dama_disposition.R` |

Verification totals: R1.4 6/6 passed, R1.5+R2.1 19/19, R1.11+R1.13 24/24, R1.18 13/13.

## Two cautions that apply across the whole folder

**Standardised differences, not p-values.** Group sizes run from 28,332 to 417,723. At
those sizes every comparison is statistically significant and a p-value carries no
information about whether a difference matters. All comparisons use standardised mean
differences with the conventional |SMD| > 0.1 threshold. This is stated in each file.

**The definitional trap.** Triage acuity and admission status are *inputs* to two of the
three algorithms, so comparisons between groups defined by algorithm membership partly
restate the algorithms' own construction. Reviewer 2 raised this for Table 2 (comment
R2.2); it recurs throughout the single-vs-multiple analysis and is marked explicitly there.
Any difference in acuity, admission, or anything driven by admission must be checked
against its restricted version before it is offered to a reviewer as a finding.

## Findings that change the manuscript, not just the response letter

1. **The published Cohen's kappa confidence intervals are wrong.** `psych::cohen.kappa()`
   returns `$confid` as a 2x3 matrix. The notebook indexes it `confid[1]` and `confid[2]`,
   which under R's column-major order are both from the *lower bound* column. The reported
   "upper" limit is the lower limit repeated — visible in the stored notebook output, where
   `ci_lower` and `ci_upper` are identical in all three rows. Point estimates are
   unaffected. Correct indexing is `confid[1,1]` and `confid[1,3]`.

2. **The Methods exclusion counts do not match the code.** See `../../reviewer_answers_round1.md`.

3. **"Discharged home" misdescribes the Resources group.** The algorithm excludes only
   ADMITTED, TRANSFER and EXPIRED, so it also flags patients who left without being seen,
   eloped, or left against medical advice.
