# Comparing methods to identify avoidable ED visits using the MIMIC-IV-ED database

This repository holds the analysis for a study of the MIMIC-IV-ED 2.2 database. The aim was to compare how three algorithms used to define and identify "potentially avoidable" emergency department visits (Diagnosis, Resources and Triage-Acuity) differ in the visits, patients and conditions they select. The background, methods and results are described in full in the accompanying paper.

## Instructions
To reproduce the analysis, follow these steps in order.

1. Clone (or download as a zip) this repository.
    - The analysis was run in R 4.5.2 (any R 4.5 should work).
    - The necessary R packages are installed and loaded with the `pacman` package at the start of each notebook.

2. Build the data with the [MIMICED](https://github.com/James-G-Wrightson/MIMICED.git) repository, which is included here as a submodule in the `MIMICED` folder.
    - Instructions for creating the data are in that repository's [README](https://github.com/James-G-Wrightson/MIMICED/blob/main/README.md).
    - The Diagnosis (NYU ED) algorithm needs four third-party code-list files (two NYU lists and two appendices from Johnston et al. 2017) that are not redistributed. The MIMICED README says where to download each one, and the data notebook stops with instructions if any is missing.
    - The presenting-complaint clustering, with its choice of k from the silhouette and stability across random starts (`MIMICED/2_chiefcomp.ipynb`), runs in Python. `MIMICED/pyproject.toml` and `uv.lock` pin the environment: run `uv sync`, then register the kernel as described in the MIMICED README.

3. Run the [main analysis notebook](ANALYSIS/3_descriptive.ipynb). It produces every table and figure for the analysis sample of eligible ED visits, including the race-category mapping (Table S10), the Diagnosis-algorithm source summary (Table S11) the agreement statistics beyond kappa (Table S12) and the presenting-complaint cluster tables (Tables S22–S26).
    - Because patients can contribute more than one visit, the confidence intervals on means and percentages are cluster-robust at the patient level (intercept-only GEE with robust sandwich standard errors, with a patient-level bootstrap as fallback). Those helpers live in [ANALYSIS/ci_helpers.R](ANALYSIS/ci_helpers.R), which every notebook that computes intervals sources at the top.
    - Figure 1 is the participant flow diagram. Its section derives every count from the raw data rather than typing any into labels, and checks the attribution against the analysis sample before drawing anything. It needs the raw MIMIC-IV-ED and hosp files, as described in the MIMICED README.
    - Figures are written as .png, .svg and .pdf, and tables as .docx.

4. Run the sensitivity notebooks in the [ANALYSIS](ANALYSIS/) folder, in any order. These respond to peer-review comments and check how far the results depend on the choices made in the main analysis.
    - `R1_acuity.ipynb` examines the visits excluded from the analysis sample: it characterizes the excluded visits against the retained ones, applies the three algorithms to every raw visit in MIMIC-IV-ED (425,087) to show what including the excluded visits would change, and describes the missing data, focused on the triage acuity score. It reads only the data build's outputs (`ed_join_cc.parquet` and `ed_no_diagnosis.parquet`) and opens by checking its counts against the main analysis.
    - `R2_visits.ipynb` restricts the analysis to one visit per patient, checking that patients with many visits do not drive the results.
    - The presenting-complaint cluster tables (every cluster at k = 75, 50 and 100, and Table 3 rebuilt at k = 50 and 100; Tables S22–S26) are written by the main analysis notebook from the files `MIMICED/2_chiefcomp.ipynb` produces; that notebook also draws the supplement figure of the silhouette and stability by k (Figure S6).
    - `R7_coggan.ipynb` is a sensitivity analysis for the way complaints are grouped: it applies the published keyword dictionary of Coggan et al. (53 categories, written for MIMIC-IV-ED) to the raw complaint text instead of clustering, and repeats the presenting-complaint table of the paper with those categories plus an Uncategorised group (Table S29).
    - `R6_esi.ipynb` is the ESI-threshold sensitivity analysis: Table S13 compares three Triage-Acuity thresholds (ESI 5 only, ESI 4–5, ESI 3–5) in one row each, then every threshold-dependent table and figure of the main analysis is repeated with Triage-Acuity defined as ESI 5 only, with the main notebook's own code (Table S14 agreement, Figure S4 UpSet, Figure S5 Venn, Tables S15–S19 characteristics, common complaints and diagnoses, disposition). It opens with the same count check.
    - Each notebook reads the data created in step 2 directly and writes its tables (.docx) and figures (.png, .svg and .pdf) into the `ANALYSIS` folder, prefixed `R1_`, `R2_`, `R6_` and `R7_`. Superseded notebooks are kept in `archive/`, described in `archive/README.md`.

## Reviewer responses
`reviewer_answers_round1.md` and `reviewer_answers_round2.md` hold the working answers to the two rounds of peer review. `ANALYSIS/round2_changes_by_comment.md` explains, for each round-2 comment, where the change is in the code, how the method works and the references behind it.

## Recorded package versions
`pacman` installs whichever package versions are current on the day, so the analysis is not pinned by default. `renv.lock` records a combination verified to work, captured on R 4.5.2. To install those exact versions into a project-local library, run `renv::restore()` from this folder. This is optional; the notebooks run normally without it.

One pin in that lockfile matters in particular. **patchwork must be 1.3.1 or newer.** The main notebook assembles Figure 1 from two panels and applies a shared theme with the `&` operator. ggplot2 4.0 changed its internals, and patchwork 1.3.0 and earlier cannot handle that combination, failing with `Can't find method for generic '&'`. Every other cell runs fine; only the figure is affected.
