# Reviewer answers — what the existing code and results already tell us

Written from the committed notebooks, their stored outputs, the saved tables, and
`ANALYSIS_NOTES.md`. Nothing was re-run. Where a number came from a small direct
lookup in an existing data file rather than from a stored output, it says so.

Statuses: **Answered** = the number or fact exists now. **Partly** = some of it exists,
the rest needs new code. **Needs computation** = nothing usable exists yet.

---

## The cohort numbers everything else hangs on

All four of these come from stored notebook outputs.

| Stage | Visits | Removed | Source |
|---|---|---|---|
| Raw `edstays` in MIMIC-IV-ED v2.2 | 425,087 | — | raw file line count |
| No discharge diagnosis recorded | 424,707 | 380 | `1_mimic_data.ipynb` cell 7 comment; confirmed by label totals |
| No triage acuity, age or race | 417,723 | 6,984 | `3_descriptive.ipynb` cells 4–5 |
| First visit per patient only | **201,106** | 216,617 | `3_descriptive.ipynb` cells 6, 8 |

Of the 6,984 dropped at stage 3, **6,934 were missing a triage acuity score**
(1.63% of 424,707, from `1_mimic_data.ipynb` cell 38) and the remaining **50 were
missing age**.

**Proportion of the raw extract retained: 47.3%** (201,106 / 425,087).

### A problem to fix before the response letter goes out

`ANALYSIS_NOTES.md` flags this and I confirmed it. The manuscript's Methods reportedly
exclude under-18s (n = 4,372) and missing age (n = 76). Neither matches the code. The
notebook has **one** exclusion line — missing acuity, age or race — and in the data there
are **zero** patients under 18 and **50** with missing age. The 6,934 figure for missing
triage is right; the other two appear to be left over from an earlier data build.

Three reviewer questions (R1.4, R1.7, R1.10) ask for exactly these counts. Answering them
with the correct numbers means correcting the Methods at the same time.

---

## R1.4 — Justifying the exclusion of visits with no triage score

**Partly answered.**

Available now:

- **6,934 visits (1.63%) had no triage acuity score.** A further 50 were missing age.
- **All 6,934 had usable diagnosis and resource data.** This follows from the code, and it
  is the strongest form of the reviewer's concern, so it is worth stating plainly:
  - Every one of the 424,707 rows has a primary diagnosis code by construction — the 380
    visits without one were already removed at the previous stage. So the Diagnosis
    algorithm was computable for all 6,934.
  - The Resources algorithm is built with `case_when(... ~ 1, TRUE ~ 0)`, which assigns a
    0 or 1 to every row and never returns missing. So it too was computable for all 6,934.
  - Only the Triage-Acuity algorithm returns `NA` when acuity is missing.

  So these visits were dropped because one of three algorithms could not be computed, not
  because the data were unusable.

Still needed: whether the 6,934 differ systematically from the retained visits
(demographics, diagnosis mix, disposition). That is a comparison that has never been run.

---

## R1.5 — Rationale for first visit per patient; patients vs visits

**Partly answered.**

- Before the restriction: **417,723 visits from 201,106 distinct patients**
  (mean 2.08 visits per patient).
- After: **201,106 visits = 201,106 patients**, one each.
- **216,617 repeat visits were dropped** — 51.0% of the 424,707.

So the unit of analysis is unambiguous: one visit per patient, and the two counts are
identical by construction. `ANALYSIS_NOTES.md` puts it well — "201,106 visits" is really
201,106 patients, each contributing their index presentation.

Still needed: the distribution of visits per patient (how many patients had 1, 2, 3, 10+
visits), which speaks directly to the reviewer's point about frequent users.

---

## R1.6 — How the three definitions were operationalised

**Fully answered from the code.** All three are built at the end of `1_mimic_data.ipynb`.

**Diagnosis (`nyu`, cell 65).** Takes `primary_code` — the first-listed discharge diagnosis
— and looks it up in the NYU ED algorithm spreadsheets, extended with the Johnstone et al.
supplementary code lists. Each code carries probabilities across categories. The visit is
flagged when P(non-emergent) + P(emergent but primary-care treatable) > 0.5.

Coverage is complete: I checked the built file and **no visit has a missing `nyu` value**,
so every primary code matched the lookup. No visit is flagged by default.

**Resources (`res`, cell 67).** Flagged when all four hold:
1. disposition is not ADMITTED, TRANSFER or EXPIRED;
2. no heart rhythm recorded at the last vital-signs check (a proxy for "not kept under
   observation" — it is not a direct field);
3. no medication dispensed in the ED (`pre_gsn_count` missing);
4. did not die that day.

**Triage-Acuity (`acuity_out`, cell 69).** Flagged when the triage Emergency Severity
Index score is 4 or 5. Returns missing when acuity is missing — which is what drives the
exclusion in R1.4.

**Direct answer to the reviewer's question:** no, the study does not assume every
presentation meets one of the criteria. The three are independent tests, and a visit can
fail all three. **100,538 visits (50.0%) were flagged by none of them.** That is the
complement of the 100,568 in Table 2.

---

## R1.7 — Participant flow diagram

**Answered — all counts exist** (see the table at the top). The diagram itself still needs
drawing. Four boxes: 425,087 → 424,707 → 417,723 → 201,106, with the three exclusions
(380 / 6,984 / 216,617) branching off. Correct the Methods text at the same time.

---

## R1.8 — Source and assignment of ICD codes

**Answered from the code, except for one part that is a documentation question.**

**Which source table.** Two, chosen per visit (`1_mimic_data.ipynb` cell 7):
- Visits **not** admitted: `mimic-iv-ed-2.2/ed/diagnosis.csv.gz` (the ED module).
- Visits **admitted** (a `hadm_id` is present): `hosp/diagnoses_icd.csv.gz`, joined to
  `hosp/d_icd_diagnoses.csv.gz` for the descriptions.

That switch matters and is worth stating in the paper — an admitted visit is labelled from
the hospital's discharge coding, not the ED's.

**Primary diagnosis or all diagnoses.** All recorded diagnoses are pulled and concatenated
into `icd_codes`, ordered by sequence number. But the Diagnosis algorithm uses
**`primary_code` only** — `str_extract(icd_codes, "^[^,]*")`, the first code in the
sequence. So the answer is: **the primary diagnosis alone drives the classification.**
The full code list is used only for the Charlson Comorbidity Index.

Still needed (not a code question): who assigns the codes in MIMIC-IV-ED — clinicians,
trained coders, or administrative staff. That has to come from the MIMIC-IV-ED
documentation, not from this repo.

---

## R1.9 — Unique patients in the final cohort

**Fully answered. 201,106 unique `subject_id`s** — identical to the visit count, because
each patient contributes exactly one visit. Table 1's header already reads N = 201,106;
it just needs relabelling as patients as well as visits.

---

## R1.10 — Per-stage exclusions, biggest impact, proportion retained

**Fully answered.**

- Counts per stage: the table at the top.
- **The first-visit restriction had by far the greatest impact: 216,617 records**, against
  6,934 for missing triage and 380 for missing diagnosis. It removes roughly 31 times more
  data than the triage exclusion the reviewer focused on.
- **47.3% of the original dataset remains.**

---

## R1.11 — Derivation of the 100,568, and single vs multiple algorithms

**Partly answered.**

The 100,568 is the **union** — every visit flagged by at least one algorithm, i.e. every
visit whose `combined_group` is not "000". It is the sum of the seven overlap groups
(`3_descriptive.ipynb` cells 14, 16):

44,119 + 23,427 + 17,306 + 4,690 + 4,278 + 3,578 + 3,170 = **100,568**

It is *not* the sum of the three algorithm totals. Those are 68,173 + 48,181 + 15,716 =
132,070, which double-counts 31,502 visits caught by more than one algorithm.

Splitting it as the reviewer asks:

| | Visits | % of the 100,568 |
|---|---|---|
| Flagged by exactly one algorithm | 72,236 | 71.8% |
| Flagged by two or more | 28,332 | 28.2% |

Still needed: the demographic and clinical comparison of those two collapsed groups.
Table 2a has all seven groups separately, so the ingredients are there, but the collapsed
1-vs-2+ figures have not been computed. Worth noting the notebook already creates an
`only_one_algorithm` variable (cell 31) and then never uses it — the split was anticipated.

---

## R1.12 — How multi-algorithm visits were classified

**Fully answered from the code.** Both approaches are used, in different places, which is
probably why the reviewer asked.

`combined_group = paste0(nyu, res, acuity_out)` creates **eight mutually exclusive cells**
("000" through "111").

- **Table 1** reports each algorithm's *full* total, so a visit meeting two definitions is
  counted in **both** columns. This is why the column totals exceed 100,568.
- **Tables 2 and 3, and Figure 1B**, use the **mutually exclusive** seven groups. A visit
  appears in exactly one column.
- **Figure 1A** uses a third scheme — a priority hierarchy: all Diagnosis visits (68,173),
  then Resources-but-not-Diagnosis (27,705), then Acuity-but-neither (4,690). These sum to
  100,568 without overlap.

The response should say explicitly that Table 1 is overlapping and Tables 2–3 are not.

---

## R1.13 — Presenting complaints, single vs multiple algorithms

**Partly answered.** Table 3a already gives the top three complaint clusters for each of
the seven mutually exclusive groups, so the pattern is visible:

- Single-algorithm groups look quite different from each other — Diagnosis-only leads with
  abdominal pain (19.1%), Resources-only with wound evaluation (22.8%), Acuity-only with
  wound evaluation (36.1%) and leg/knee pain (26.2%).
- Multi-algorithm groups concentrate harder on minor injury — Resources+Acuity is 41.3%
  wound evaluation and 26.1% leg/knee pain; Diagnosis+Acuity is 31.5% lower back pain.

A clean single-vs-multiple contrast still needs computing, but it would be a
re-aggregation of data already in Table 3a rather than anything new.

---

## R1.18 — Discharge against medical advice

**Partly answered, and the answer is substantive.**

DAMA **is** identifiable. `disposition` in MIMIC-IV-ED has eight values. Counts across all
424,707 visits (direct lookup in `ed_join_cc.parquet`):

| Disposition | Visits | Of which flagged by Resources |
|---|---|---|
| HOME | 241,439 | 81,343 |
| ADMITTED | 157,940 | 0 |
| TRANSFER | 7,018 | 0 |
| LEFT WITHOUT BEING SEEN | 6,139 | 6,005 |
| ELOPED | 5,666 | 3,464 |
| OTHER | 4,254 | 1,805 |
| LEFT AGAINST MEDICAL ADVICE | 1,879 | 747 |
| EXPIRED | 372 | 0 |

The important finding for the reviewer: **these visits are included, not excluded, and the
Resources algorithm actively flags them as potentially avoidable.** The algorithm only
rules out ADMITTED, TRANSFER and EXPIRED. So someone who left without ever being seen
satisfies all four Resources criteria automatically — no admission, no rhythm recorded, no
medication dispensed, did not die — and is counted as a potentially avoidable visit.

`ANALYSIS_NOTES.md` records the equivalent figures within the analysis sample: 2,546 left
without being seen, 1,246 eloped, 329 DAMA and 818 other, **4,939 visits — about 10% of
the Resources group**, several of whom never received care at all.

This is a genuine limitation of the Resources algorithm as implemented, and the paper's
wording that these patients "were discharged home" is not accurate.

Still needed: the total DAMA count within the 201,106 analytic sample, and how the
Diagnosis and Triage-Acuity algorithms classify those visits.

---

## R2.1 — Repeat visits excluded, and a sensitivity analysis

**Partly answered.** The count is **216,617 repeat visits excluded** (see R1.5).

The sensitivity analysis — re-running all three algorithms on all 417,723 eligible visits
— has not been done. It is straightforward, though: all three labels already exist on
every row of `ed_join_cc.parquet`, so it needs no re-labelling, only re-tabulation.

---

## R2.2 — The Resources algorithm excludes admissions by construction

**Fully answered, and the reviewer is correct.**

The code is `!disposition %in% c("ADMITTED","TRANSFER","EXPIRED")`. An admitted visit can
never be flagged by Resources. The crosstab above confirms it empirically: 0 of 157,940
admitted visits are flagged.

Marking up Table 2a, two rows are definitional rather than empirical:

**The "Admitted" row.** Definitional (forced to 0) for every group containing Resources:

| Group | Admitted | Status |
|---|---|---|
| Diagnosis | 22.6% | empirical |
| Resource | 0.0% | **definitional** |
| Acuity | 3.6% | empirical |
| Diagnosis+Resources | 0.0% | **definitional** |
| Resources+Acuity | 0.0% | **definitional** |
| Diagnosis+Acuity | 1.5% | empirical |
| All three | 0.0% | **definitional** |

**The "Acuity" row is definitional throughout**, and this seems not to have been noticed.
Triage acuity is the input to one of the algorithms, so every group containing Acuity is
forced to a median of 4 (the algorithm requires a score above 3), and every group without
it is capped at 3. The row reads 3, 3, 4, 3, 4, 4, 4 — that pattern is arithmetic, not a
finding.

Two further rows are **partly** constrained and should be described carefully rather than
flagged outright:

- **"Home"** is inflated for Resources groups because admission, transfer and death are
  excluded — but it is not 100%, because left-without-being-seen, eloped, DAMA and other
  remain in. The exact value is empirical; the direction is definitional.
- **"Length of stay"** is pushed down for Resources groups, since the algorithm requires no
  medication dispensed and no rhythm recorded — both markers of longer, more involved care.

---

## R2.3 — Justifying k = 12, and the n-gram procedure

**Answered, but the honest answer is not the convenient one.**

Both plots are still stored in `2_chiefcomp.ipynb`, so nothing needs re-running.

**How many PCA components.** Cell 13 plots cumulative explained variance across 100
components against a 90% reference line. The curve crosses 90% at roughly 80 components,
which is the value used. That choice is well supported.

**How k was chosen.** Cell 16 runs k-means for k = 2 to 19 and plots inertia. I looked at
the stored plot: **the curve declines smoothly with no distinct elbow.** It flattens
slightly around k = 13–14 and again at 16–17, but there is no point at which k = 12 stands
out. The procedure was run and documented; it simply did not produce a sharp answer, and
k = 12 was a pragmatic choice.

Given that, the reviewer's own suggested framing is the right one, and I would take it:
**state that the clustering is illustrative rather than inferential.** Describe the elbow
method as having been run without identifying a decisive k, and justify 12 on
interpretability — the clusters map onto recognisable presenting complaints (abdominal
pain, chest pain, wound evaluation, suicidal ideation), which is what the analysis needs
them for. Re-running with silhouette scores is possible, but it is unlikely to vindicate
12 specifically and risks weakening a claim that is easier to defend by scoping it down.

**The n-gram extraction** is fully documented in cell 22 and needs no further work:
`CountVectorizer` over the cleaned complaint text, bigrams and trigrams
(`ngram_range=(2,3)`), the 20 most frequent retained per cluster, of which the top 10 are
printed. The cleaning step beforehand expands a hand-written dictionary of MIMIC
abbreviations (sob → shortness of breath, abd → abdomen, etoh → alcohol intoxication),
strips laterality and non-alphabetic characters, and removes English stopwords. Cluster
sizes and the top 10 n-grams for all 12 clusters are in the stored output.

---

## Summary

| ID | Status |
|---|---|
| R1.6, R1.7, R1.8, R1.9, R1.10, R1.12, R2.2, R2.3 | **Answered** — no new computation |
| R1.4, R1.5, R1.11, R1.13, R1.18, R2.1 | **Now also answered** — see below |

**Update.** The six that needed computation have been completed. Results and re-runnable
scripts are in `ANALYSIS/reviewer_response/`, indexed by that folder's `README.md`. Every
script asserts the published numbers before computing anything new; all verification
checks passed (6/6, 19/19, 24/24, 13/13).

All fourteen questions in the "Needs analysis" section are now answerable. Nothing required
touching the raw MIMIC files or re-running the data build.
