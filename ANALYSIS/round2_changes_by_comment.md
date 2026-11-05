# Round-2 reviewer comments: where each change lives in the code

One section per comment. Each section says what was asked, where the change is (file, cell, output file), how the method works, and the references behind it. Cell numbers are zero-based positions in the notebook's cell list (the first cell is cell 0), which is what `jupyter nbconvert` and the notebook JSON use; headings in the notebooks are given alongside so the cells can be found by eye. The references are collected at the end; the entries marked "verify" are given from memory and should be checked against the source before they go into the manuscript.

Notation for the agreement measures: for two binary flags on the same visits, `a` is the number of visits flagged by both, `b` by the first only, `c` by the second only, `d` by neither, and `n = a + b + c + d`.

---

## Comment 1. Kappa depends on prevalence; report percent agreement or a prevalence-adjusted kappa alongside it

### Where

| What | File | Location | Output |
|---|---|---|---|
| The function that computes every agreement measure | `ANALYSIS/ci_helpers.R` | `agreement_boot_ci()` (comment block from line 126, function at lines 144–183) | — |
| Main analysis, three algorithm pairs | `ANALYSIS/3_descriptive.ipynb` | cell 43, under "# Agreement (Kappa)" | `ANALYSIS/table_S12.docx` (Supplemental Table S12) |
| One-visit-per-patient cohort | `ANALYSIS/R2_visits.ipynb` | cell 26, under "## Table S9" | `ANALYSIS/R2_visits_table_S9.docx` (columns added to the existing kappa table) |
| ESI-threshold sensitivity (kappa, p_pos and p_neg against each other algorithm for each threshold) | `ANALYSIS/R6_esi.ipynb` | cell 12, under "# Summary across thresholds" | `ANALYSIS/R6_esi_table_S13.docx` |

### What the function does

`agreement_boot_ci(r1, r2, id)` takes two 0/1 vectors (one element per visit) and the patient id. It builds the four cells of the 2×2 agreement table for every visit, sums them per patient with `rowsum()`, and then computes every measure from the cell totals:

| Measure | Formula in the code | Name and meaning |
|---|---|---|
| `p1`, `p2` | `(a + b) / n`, `(a + c) / n` | Prevalence of each flag |
| `po` | `(a + d) / n` | Percent (observed) agreement: the share of visits on which the two algorithms agree, whether both flag or neither flags |
| `kappa` | `(po − pe) / (1 − pe)`, with `pe = p1·p2 + (1 − p1)(1 − p2)` | Cohen's kappa [1]: observed agreement corrected for the agreement expected if the two flags were independent with their observed prevalences |
| `pabak` | `2·po − 1` | Prevalence-adjusted bias-adjusted kappa, Byrt, Bishop and Carlin 1993 [2]. It is the kappa that would be obtained if both flags had a prevalence of 50% and no bias between raters, which removes the dependence of kappa on prevalence. Algebraically it is a linear rescaling of percent agreement, so it carries no information beyond `po` but puts it on the kappa scale |
| `psa` | `2a / (2a + b + c)` | Positive specific agreement, p_pos in Cicchetti and Feinstein 1990 [4] (the "proportion of specific agreement" of Fleiss 1975 [27]): the probability that, given one algorithm flags a visit, the other does too. It ignores the `d` cell, so it is not inflated by the many visits neither algorithm flags |
| `nsa` | `2d / (2d + b + c)` | Negative specific agreement, p_neg in the same paper: the probability that, given one algorithm does not flag a visit, the other does not either |
| `pi` | `(a − d) / n` | Prevalence index [2,5]: how far the sample is from 50% prevalence. A value near −1 means almost every visit is unflagged by both, which is when kappa is most depressed |

**Why these measures were chosen.** Kappa falls when prevalence is far from 50% even if raw agreement is high, which is the reviewer's point: the first of the two "kappa paradoxes" described by Feinstein and Cicchetti [3]. Percent agreement answers the first half of the request and PABAK is the standard prevalence-adjusted kappa. The companion paper by Cicchetti and Feinstein [4] argues that no single summary index resolves the paradoxes and recommends that kappa "should always be accompanied by separate individual values of p_pos and p_neg" (their abstract and conclusions, pp. 551 and 557), the two being analogous to sensitivity and specificity. Both are reported. Positive specific agreement answers the question the paper is really asking (when one algorithm says "avoidable", does the other?) and is the measure that stays low here; negative specific agreement is high for every pair and shows where the high percent agreement and PABAK come from. Cicchetti and Feinstein call these "proportionate positive and negative agreement"; "specific agreement" is Fleiss's term [27].

**Confidence intervals.** The patient is the sampling unit, because patients contribute more than one visit. The function resamples patients with replacement (`B = 2000`, seed `20260825`, constants at the top of `ci_helpers.R`), recomputes every measure from the resampled cell totals, and takes the 2.5th and 97.5th percentiles (the percentile bootstrap [6], applied to clustered data by resampling whole clusters [7]). With one visit per patient (the Table S9 cohort) this is an ordinary bootstrap. `kappa_boot_ci()` is a thin wrapper that returns only the kappa part.

### Numbers reported (analysis sample, N = 417,723)

| Pair | Percent agreement | Kappa | PABAK | p_pos | p_neg | Prevalence index |
|---|---|---|---|---|---|---|
| Diagnosis vs Triage-Acuity | 63.7 | 0.048 | 0.275 | 0.161 | 0.769 | −0.568 |
| Diagnosis vs Resources | 61.8 | 0.096 | 0.236 | 0.344 | 0.731 | −0.418 |
| Resources vs Triage-Acuity | 77.5 | 0.135 | 0.549 | 0.227 | 0.868 | −0.708 |

All with 95% CIs in Table S12. The kappas are those of the main analysis. In the one-visit cohort (Table S9) the values are close: p_pos 0.161 / 0.352 / 0.233 and p_neg 0.779 / 0.736 / 0.855.

### Manuscript text affected

Methods (analysis paragraph: the added measures and why), Results (agreement sentence now says agreement on which visits were potentially avoidable was poor, and reports kappa, percent agreement, PABAK, negative and positive specific agreement for each pair, pointing to Table S12), Discussion (limitation sentence: good agreement on the unflagged visits, poor on the flagged ones). The wording is in `reviewer_answers_round2.md`, section R2-1.

---

## Comment 2. The number of presenting-complaint clusters was chosen by the elbow method alone; report a validity measure or a stability check

### Where

| What | File | Location | Output |
|---|---|---|---|
| Reproducible Python environment | `MIMICED/pyproject.toml`, `MIMICED/uv.lock`, `MIMICED/requirements.txt` | — | kernel "mimiced (uv)", Python 3.12.13 |
| Clustering pipeline, scan of k, choice of k = 75, automatic names, sensitivity labels | `MIMICED/2_chiefcomp.ipynb` (rewritten 22 Oct 2026) | §3.1 cleaning; §3.2 embeddings (cached, with their row order); §3.3 PCA; §3.4 validity scan; §3.5 stability scan and Figure 2; §3.6 the k = 75 clustering and names; §3.7 k = 50 and 100 | `chiefcomp_clustered.parquet` (with `cluster_name`), `chiefcomp_clustered_k50.parquet`, `chiefcomp_clustered_k100.parquet`, `chiefcomp_cluster_names.csv`, `chiefcomp_validity_k.csv`, `chiefcomp_stability.csv`, `chiefcomp_ref_labels.npz`, `chiefcomp_validity_k.png` |
| Archived original run (k = 12, unseeded PCA; not used) | `MIMICED/archive_k12/` | — | old notebook, labels, pickle, k = 8/14 files |
| Supplement figure | `MIMICED/2_chiefcomp.ipynb` §3.5 | Figure 3 (silhouette and stability by k; the supplement figure and the response-to-reviewers figure) | `chiefcomp_figure_3_silhouette_stability.{png,svg,pdf}` |
| Supplement tables | `ANALYSIS/3_descriptive.ipynb`, last section | Tables S22–S24 (cluster lists at k = 75, 50, 100); Tables S25–S26 (Table 3 rebuilt at k = 50 and 100) | `table_S22..S26.docx` |
| Main tables with the new labels | `ANALYSIS/3_descriptive.ipynb` (Table 3), `ANALYSIS/R2_visits.ipynb` (one-visit complaints table) | cluster names now read from the parquet | `table_3a.docx`, `table_3b.docx`, `R2_visits_table_S7.docx` |
| Sensitivity: keyword dictionary instead of clustering | `ANALYSIS/R7_coggan.ipynb` (new) | whole notebook | `R7_coggan_table_S29.docx` |
| Manuscript-formatted copies for pasting | `ANALYSIS/round2_tables_k75.docx` (built by a script from the notebooks' outputs; Table 3 and the one-visit table are the manuscript's own tables with the cells refilled) | — | — |

### What was done, step by step

**The original clustering could not be reproduced, and why.** The paper's k = 12 labels came from a run that left the PCA step unseeded (for a matrix of this size scikit-learn uses a randomised SVD solver) and recorded no package versions. With the original embeddings recovered from its pickle, re-created embeddings match to within 5 × 10⁻⁶ and k-means is deterministic given its input, but two unseeded PCA fits on identical embeddings give k = 12 solutions that agree only at ARI 0.48, and the stored labels against a seeded refit agree at ARI 0.51. That run is archived in `MIMICED/archive_k12/` and no longer used.

**The pipeline, now seeded and cached.** The same cleaning, the same model (`pritamdeka/BioBERT-mnli-snli-scinli-scitail-mednli-stsb`, a BioBERT model [8] fine-tuned in the Sentence-BERT framework [9]), `PCA(n_components=80, random_state=42)` and `KMeans(k, random_state=42, n_init=10)` [10, 14]. The embeddings are cached with the stay_id order they were computed in (`chiefcomp_embeddings_stay_id.npy`); the notebook puts the data in that order before using any cache and checks the cleaned text against the text the vectors were computed from. Every slow step is cached, so the notebook runs in a few minutes with the caches present and regenerates everything from the raw data without them.

**Validity index.** For each k from 2 to 19 and 20 to 100 in steps of 5: inertia (the elbow quantity [15]) and the silhouette (Rousseeuw 1987 [16]) on five fixed samples of 20,000 complaints, mean ± SD. Interpretation bands from Kaufman and Rousseeuw 1990 [17] (the 1987 paper [16], verified against the PDF on 22 Oct 2026, defines the score and reads values only qualitatively; the numeric bands are in the 1990 book, not yet verified against the text). Result: the silhouette rises without a maximum from 0.08 at k = 2 to 0.41 at k = 100, crossing 0.25 at about k = 26; it never reaches 0.51 ("reasonable"). Inertia has no elbow; the knee rule returns a different k for every range it is given (10 on 2–19, 30 on 2–100). Figure S6 (Figure 3 of `2_chiefcomp.ipynb`); values in `chiefcomp_validity_k.csv`.

**Stability across random starts.** For k = 2 to 19, 25, 30, 40, 50, 60, 75, 90 and 100: 20 refits with random starts 0–19 compared with the seed-42 fit by the ARI [11]; bands from Steinley 2004 [18] (verified against the PDF on 22 Oct 2026: p. 392, offered as "heuristics for determining the quality of cluster recovery", i.e. agreement with a known partition; we apply them to agreement between random starts and say so in the figure caption). Result: ARI 1.00 and 0.95 at k = 2 and 3, a collapse to 0.40–0.48 at k = 4–9, a step to about 0.6 at k = 10, then a steady climb with narrowing spread: medians 0.67 (k = 25), 0.70 (30), 0.71 (40), 0.74 (50), 0.79 (60), 0.80 (75), 0.82 (90), 0.83 (100). Figure S6; values in `chiefcomp_stability.csv`.

**Choice of k.** Neither index peaks, so k is not read off a curve. It is the smallest k on the scan at which the solution is reproducible to the "good" standard (median ARI ≥ 0.80) while the silhouette is above the 0.25 floor: **k = 75** (k = 60 is 0.79). Stability on its own is not a selector with a sample this large (Ben-David, von Luxburg and Pál 2006 [19]; von Luxburg 2010 [20]), which is why the silhouette floor is required as well and why the clusters are described as descriptive groupings with soft boundaries.

**Names.** Each cluster is labelled with its most common cleaned complaint string, in sentence case, with the token "cc" dropped because it abbreviates the field name (chief complaint) rather than describing anything (so the cluster of "unknown cc" entries is named "Unknown"); the second string is appended if two clusters share a top string. No name is written by hand. Table S22 lists all 75 with their top three strings and shares; 28 of the 75 have a second string at 10% or more of the cluster, visible in that table.

**Sensitivity.** (a) k = 50 and k = 100, the grid neighbours, with Table 3 rebuilt per exclusive combination (Tables S25–S26; cluster lists S23–S24). (b) The published keyword dictionary of Coggan et al. [28] (53 categories written for MIMIC-IV-ED, applied as published minus its Transfer category, with an Uncategorised group for the 13.1% of visits matching nothing) in place of clustering, Table 3 rebuilt (Table S29). The two sensitivity routes and the main analysis agree on every column's leading presentations.

### Findings that changed the manuscript

- Table 3 and the one-visit complaints table (supplement) are rebuilt at k = 75: the Triage-Acuity columns now read finger laceration, ankle pain and knee pain; Resources reads alcohol intoxication first; the Diagnosis columns read nausea/vomiting and abdomen pain; All reads rash, laceration and wound evaluation. The paper's former "Wound evaluation" cluster (18% of visits, of which 7% said wound evaluation) no longer exists.
- Methods: clustering paragraph rewritten (seeded pipeline, scan of k, choice rule, automatic names, k = 50/100 and dictionary sensitivity analyses). Results: Table 3 text. Discussion: limitation on separation (silhouette weak at every k) and the descriptive status of the clusters. Wording in `reviewer_answers_round2.md`, section R2-2.
- Supplement numbering (S22–S26, S29, Figure S6; S20, S21, S27 and S28 were dropped on 22 Oct, and `R5_clusters.ipynb` was retired into `2_chiefcomp.ipynb` and `3_descriptive.ipynb`) is provisional until both revision streams are merged.

---

## Comment 3. Test an alternative ESI threshold for the Triage-Acuity algorithm

### Where

| What | File | Location | Output |
|---|---|---|---|
| Main definition of the flag | `MIMICED/1_mimic_data.ipynb` | cell 71: `acuity_out = 1` when `acuity > 3`, `0` when `acuity < 4`, `NA` when acuity is missing | column `acuity_out` in `ed_join_cc.parquet` |
| Alternative definitions | `ANALYSIS/R6_esi.ipynb` | cell 3: `acuity_5 = acuity == 5`, `acuity_345 = acuity >= 3`, on the same eligibility filter as the main analysis | — |
| Count check against the main analysis | `R6_esi.ipynb` | cell 8, "## Check" (417,723 visits, 209,429 flagged, 29,545 Triage-Acuity under ESI 4–5) | printed PASS/FAIL, `stopifnot` |
| Summary across thresholds | `R6_esi.ipynb` | cell 12 | `R6_esi_table_S13.docx` |
| Headline sentence per threshold (ESI 3–5 appears here and in Table S13 only) | `R6_esi.ipynb` | cell 14 | — |
| ESI 5 only, main analysis repeated | `R6_esi.ipynb` | cells 15–46, in the order of `3_descriptive.ipynb`: number identified (cell 18), agreement (cells 20–22), Figure S4 (cells 24–30), Figure S5 (cell 32), Table S15 (cells 34–35), S16 (cell 37), S17 (cells 39–40), S18 (cell 42), S19 (cell 44) | `R6_esi_table_S14..S19.docx`, `R6_esi_figure_S4.{png,svg,pdf}`, `R6_esi_figure_S5.{png,svg,pdf}` |

Mapping to the main analysis: Table S12 → S14; Figure 2 → Figure S4; Figure S1 → Figure S5; Table 2a → S15; Table 2b → S16; Table 3a → S17; Table 3b → S18; Table S2 → S19. Figure 1, Table 1, Table S1, S10 and S11 do not depend on the threshold and are not repeated.

### How it works

The Emergency Severity Index (ESI) [22] is a five-level triage scale where 1 is the most urgent and 5 the least. The main analysis labels ESI 4 and 5 as potentially avoidable. The notebook keeps the Diagnosis and Resources flags unchanged, replaces the Triage-Acuity flag (`acuity_out`) with ESI 5 only, rebuilds the exclusive-combination code (`combined_group`, three digits for Diagnosis, Resources, Triage-Acuity), and then runs the main notebook's own cells on that data object, changing only file names and table titles. Means and percentages use the GEE helpers from `ci_helpers.R` (intercept-only generalised estimating equation with a robust sandwich variance, Liang and Zeger 1986 [23], via `geepack` [24]); agreement measures (Cohen's kappa, positive and negative specific agreement, prevalence index) use `agreement_boot_ci()` as in Comment 1. Each algorithm combination keeps its Figure 2 colour, matched by name rather than by position, because the combinations fall in a different order under ESI 5.

Two deliberate differences from the main code, commented in place, are needed because the ESI 5 combinations are small (153, 157 and 260 visits): medians print a decimal only when a quartile is not a whole number (the main code assumes whole numbers), and third-place ties in the ranked tables are broken by order of appearance (`with_ties = FALSE`).

The looser threshold, ESI 3–5, flags 61% of visits and is not a usable avoidable-visit definition; it appears as one row of Table S13 and one headline sentence so the direction of change is on record.

### Headline numbers

| Definition | Triage-Acuity flagged | Also Diagnosis | Also Resources | All three | Triage-Acuity only | ≥1 algorithm |
|---|---|---|---|---|---|---|
| ESI 5 only | 1,098 (0.3%) | 62.4% | 71.8% | 48.1% | 13.9% | 48.2% |
| ESI 4–5 (main) | 29,545 (7.1%) | 49.0% | 46.9% | 23.3% | 27.4% | 50.1% |
| ESI 3–5 | 254,415 (60.9%) | 45.6% | 28.0% | 13.9% | 40.3% | 72.8% |

Overlaps are percentages of the Triage-Acuity-flagged visits under that definition. Under ESI 5 only, Triage-Acuity becomes close to a subset of the other two algorithms: kappa against Diagnosis 0.004 and against Resources 0.012 (Table S14), with positive specific agreement of 0.9% and 1.7%, because almost nothing is flagged. The 153 visits flagged by Triage-Acuity alone are younger (mean age 42.6), mostly injuries (56.2% of discharge diagnoses), and 90.8% go home (Tables S15, S17, S19). Complaint rows in Tables S17 and S18 use the cluster names stored in `chiefcomp_clustered.parquet` (`cluster_name`, the most common cleaned complaint in each of the 75 clusters), as the main Table 3 now does.

### Manuscript text affected

Methods (third sensitivity analysis), Results (new paragraph), Discussion (the sentence describing a median ESI of 3 as "higher than" the 4/5 cut-off was wrong in direction, since a lower ESI is more urgent, and is rewritten; a limitation on the cut-off is added). Wording in `reviewer_answers_round2.md`, section R2-3.

---

## Comment 4. Give the race categories and the grouping rule

### Where

| What | File | Location | Output |
|---|---|---|---|
| The grouping rule as used in Table 1 | `ANALYSIS/3_descriptive.ipynb` | cell 30 (`table_1_data`) | — |
| The mapping table | `ANALYSIS/3_descriptive.ipynb` | cell 32, under "## Table S10" | `ANALYSIS/table_S10.docx` |

### How it works

MIMIC-IV-ED records self-reported race as free labels; 33 distinct labels occur in the analysis sample. The rule in cell 30 is a `case_when` on substrings: a label containing WHITE is White, containing BLACK is Black, containing HISPANIC is Hispanic/Latino, containing ASIAN is Asian, and anything else is Other. Cell 32 applies the same rule to every raw label, counts visits per label, and writes one row per label with its group, count and percentage. It then checks with `stopifnot` that the group totals equal Table 1's race counts, so the supplement cannot drift from the main table.

By this rule, Other contains the labels OTHER, UNKNOWN, PATIENT DECLINED TO ANSWER, UNABLE TO OBTAIN, MULTIPLE RACE/ETHNICITY, PORTUGUESE, SOUTH AMERICAN, AMERICAN INDIAN/ALASKA NATIVE and NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER, each 0.3% of visits or fewer. Group sizes: White 58.0%, Black 22.0%, Hispanic/Latino 8.2%, Asian 4.4%, Other 7.4%.

### Manuscript text affected

Table 1 footnote 2 now names the 33 categories, the keyword rule and Supplemental Table S10.

---

## Comment 5. Provide the per-code probability mapping used by the Diagnosis algorithm

### Where

| What | File | Location | Output |
|---|---|---|---|
| File check with download instructions | `MIMICED/1_mimic_data.ipynb` | cell 2 | stops the notebook, naming each missing file, its source and target path |
| Reading and combining the code lists | `MIMICED/1_mimic_data.ipynb` | cell 64 | the combined lookup `nyu` |
| Matching visits and setting the flag | `MIMICED/1_mimic_data.ipynb` | cell 65 | column `nyu` in `ed_join_cc.parquet` |
| Source summary, counts only | `MIMICED/1_mimic_data.ipynb` | cell 67, under "### Summary of the Diagnosis (NYU ED) lookup" | `MIMICED/nyu_source_summary.csv` |
| Supplementary table from that csv | `ANALYSIS/3_descriptive.ipynb` | cell 34, under "## Table S11" | `ANALYSIS/table_S11.docx` |
| Download instructions | `MIMICED/README.md` | section "Required external files (download manually)" | — |
| Keeping the files out of git | `MIMICED/.gitignore` | `*.xlsx`, `hesr12638-sup-*.txt` | — |

### How it works

The per-code probabilities are third-party work and are not redistributed: the NYU ED algorithm code lists (Billings et al. [25]; ICD-9 list dated 23 June 2015, ICD-10 list dated 4 February 2025) and the extension by Johnston et al. 2017 [26] (Appendix S6 for ICD-9, Appendix S7 for ICD-10). Instead the code is made reproducible from the cited files:

- Cell 2 lists every required file and stops with per-file instructions if any is missing.
- Cell 64 reads the two NYU workbooks and the two Johnston tab-separated appendices, keeps the probability columns (non-emergent; emergent but primary-care treatable; emergent, ED care needed, preventable; emergent, ED care needed, not preventable; alcohol; drug; injury; psychiatric; unclassified), removes from the NYU lists every code that also appears in the Johnston lists for the same ICD version (`anti_join`), and stacks the rest with the Johnston rows (`bind_rows`). So where a code is in both, the Johnston probabilities are used. The Johnston columns `edcnpa` and `edcnnpa` are mapped to the NYU names `ed_prevent` and `ed_needed` respectively.
- Cell 65 joins each visit's primary discharge diagnosis to the lookup by exact code and ICD version, and sets `nyu = 1` when non-emergent plus emergent-primary-care-treatable exceeds 0.5.
- Cell 67 writes counts only: rows read from each file (NYU ICD-10 75,242; NYU ICD-9 14,613; Johnston ICD-9 7,443; Johnston ICD-10 47,132), NYU codes replaced by Johnston rows (6,663 ICD-9; all 47,132 ICD-10 Johnston codes replace NYU rows, so for ICD-10 the extension changes probabilities rather than coverage), the combined lookup size (15,393 ICD-9 and 75,242 ICD-10 codes, no duplicates), and the study's distinct primary codes matched by each source (4,316 ICD-9 and 8,331 ICD-10 codes, every one matched; 72,995 visits classified by NYU-original rows and 351,712 by Johnston rows).

### Manuscript text affected

Methods (Diagnosis-algorithm paragraph now names the files and versions, the override rule, exact matching, the 0.5 threshold and the README), Data availability (code lists available from their authors), and the reference to the chapter-level table corrected from "Table S8" to Supplemental Table S1. Wording in `reviewer_answers_round2.md`, section R2-5.

---

## Not a reviewer item: Johnston column names corrected

While answering Comment 5, cell 64 was found to map the Johnston column `edcnpa` (ED care needed, preventable/avoidable) to `ed_needed` and `edcnnpa` (not preventable) to `ed_prevent`, the reverse of the NYU rows. Neither column feeds the `nyu` flag or any analysis, so no result changed; the mapping was corrected, `ed_join_cc.parquet` was rebuilt, and the flag totals were confirmed unchanged (151,604 Diagnosis, 93,364 Resources, 29,552 Triage-Acuity over the 424,707 diagnosed visits). Cell 74 now compares the pipeline output with the file on disk on every run and stops if they differ, with a switch to rewrite the file deliberately.

---

## References

Entries marked (verify) are cited from memory and should be checked before use.

1. Cohen J. A coefficient of agreement for nominal scales. Educational and Psychological Measurement. 1960;20(1):37–46.
2. Byrt T, Bishop J, Carlin JB. Bias, prevalence and kappa. Journal of Clinical Epidemiology. 1993;46(5):423–429. (verify)
3. Feinstein AR, Cicchetti DV. High agreement but low kappa: I. The problems of two paradoxes. Journal of Clinical Epidemiology. 1990;43(6):543–549. doi:10.1016/0895-4356(90)90158-L. PMID 2348207.
4. Cicchetti DV, Feinstein AR. High agreement but low kappa: II. Resolving the paradoxes. Journal of Clinical Epidemiology. 1990;43(6):551–558. doi:10.1016/0895-4356(90)90159-M. PMID 2189948. The formulas p_pos = 2a/(2a+b+c) and p_neg = 2d/(2d+b+c) are on pp. 554 and 556; the recommendation to report both with kappa is in the abstract and the conclusions (p. 557).
5. Sim J, Wright CC. The kappa statistic in reliability studies: use, interpretation, and sample size requirements. Physical Therapy. 2005;85(3):257–268. (verify)
6. Efron B, Tibshirani RJ. An Introduction to the Bootstrap. New York: Chapman and Hall; 1993.
7. Field CA, Welsh AH. Bootstrapping clustered data. Journal of the Royal Statistical Society: Series B. 2007;69(3):369–390. (verify)
8. Lee J, Yoon W, Kim S, Kim D, Kim S, So CH, Kang J. BioBERT: a pre-trained biomedical language representation model for biomedical text mining. Bioinformatics. 2020;36(4):1234–1240.
9. Reimers N, Gurevych I. Sentence-BERT: sentence embeddings using Siamese BERT-networks. Proceedings of EMNLP-IJCNLP 2019:3982–3992.
10. Pedregosa F, et al. Scikit-learn: machine learning in Python. Journal of Machine Learning Research. 2011;12:2825–2830.
11. Hubert L, Arabie P. Comparing partitions. Journal of Classification. 1985;2(1):193–218.
12. Strehl A, Ghosh J. Cluster ensembles: a knowledge reuse framework for combining multiple partitions. Journal of Machine Learning Research. 2002;3:583–617.
13. Kuhn HW. The Hungarian method for the assignment problem. Naval Research Logistics Quarterly. 1955;2(1–2):83–97.
14. Arthur D, Vassilvitskii S. k-means++: the advantages of careful seeding. Proceedings of the 18th ACM-SIAM Symposium on Discrete Algorithms. 2007:1027–1035.
15. Thorndike RL. Who belongs in the family? Psychometrika. 1953;18(4):267–276. (verify; the usual citation for the elbow method)
16. Rousseeuw PJ. Silhouettes: a graphical aid to the interpretation and validation of cluster analysis. Journal of Computational and Applied Mathematics. 1987;20:53–65.
17. Kaufman L, Rousseeuw PJ. Finding Groups in Data: An Introduction to Cluster Analysis. New York: Wiley; 1990. (silhouette interpretation thresholds, chapter 2; verify page)
18. Steinley D. Properties of the Hubert–Arabie adjusted Rand index. Psychological Methods. 2004;9(3):386–396. doi:10.1037/1082-989X.9.3.386. (verify)
19. Ben-David S, von Luxburg U, Pál D. A sober look at clustering stability. In: Lugosi G, Simon HU, eds. Learning Theory (COLT 2006). Lecture Notes in Computer Science 4005. Berlin: Springer; 2006:5–19. (verify)
20. von Luxburg U. Clustering stability: an overview. Foundations and Trends in Machine Learning. 2010;2(3):235–274. doi:10.1561/2200000008. (verify)
21. Spärck Jones K. A statistical interpretation of term specificity and its application in retrieval. Journal of Documentation. 1972;28(1):11–21.
22. Gilboy N, Tanabe P, Travers D, Rosenau AM. Emergency Severity Index (ESI): A Triage Tool for Emergency Department Care, Version 4. Implementation Handbook 2012 Edition. AHRQ Publication No. 12-0014. Rockville, MD: Agency for Healthcare Research and Quality; 2011. (verify edition)
23. Liang KY, Zeger SL. Longitudinal data analysis using generalized linear models. Biometrika. 1986;73(1):13–22.
24. Højsgaard S, Halekoh U, Yan J. The R package geepack for generalized estimating equations. Journal of Statistical Software. 2006;15(2):1–11.
25. Billings J, Parikh N, Mijanovich T. Emergency department use in New York City: a substitute for primary care? Issue Brief (Commonwealth Fund). 2000;(433):1–5. (verify; use whichever NYU reference the manuscript already cites)
26. Johnston KJ, Allen L, Melanson TA, Pitts SR. A "patch" to the NYU Emergency Department Visit Algorithm. Health Services Research. 2017;52(4):1264–1276. doi:10.1111/1475-6773.12638.
27. Fleiss JL. Measuring agreement between two judges on the presence or absence of a trait. Biometrics. 1975;31(3):651–659. (verify; cited as reference 11 of [4])
28. Coggan H, et al. Demographic factors associated with triage acuity, admission and length of stay during adult emergency department visits. arXiv:2503.22781 (2025). Code: github.com/hcoggan/mimic-iv-ed, `mimic-chief-complaint.r`. (verify)
