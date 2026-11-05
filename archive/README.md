# Archive

Superseded work. Nothing here is deleted, and nothing here is read by the published
notebooks in `ANALYSIS/`.

## `sensitivity_2026-08-20/`

The round-1 sensitivity analyses, archived 20 August 2026 because the approach was
being reworked. Was `sensitivity/` at the repository root.

| File stem | Question it addressed |
|---|---|
| `s1_missing_triage` | Visits dropped for having no triage acuity score |
| `s2_repeat_visits` | Repeat visits, and the all-visit sensitivity analysis |
| `s3_algorithm_agreement` | Visits flagged by one algorithm vs several |
| `s4_disposition` | Discharge against medical advice, and other dispositions |

Each stem has its notebook plus the tables and figures it wrote.

Replaced by `ANALYSIS/R1_acuity.ipynb` for the missing-acuity question (`s1`), by
`ANALYSIS/R2_visits.ipynb` for the repeat-visits question (`s2`), by the
`R3_agreement.ipynb` notebook (now archived below) for the algorithm-agreement question
(`s3`), and by the `R4_disposition.ipynb` notebook (now archived below) for the disposition
question (`s4`).

## `R3_agreement_2026-08-26/`

The algorithm-agreement notebook and its three tables, moved out of `ANALYSIS/` on
26 August 2026 when the round-1 response notebooks were consolidated: the response now
carries the pairwise kappas in `ANALYSIS/R2_visits.ipynb` and the agreement statistics in
`ANALYSIS/3_descriptive.ipynb`, so this notebook is no longer part of the published set.

## `R4_disposition_2026-08-26/`

The disposition notebook, moved out of `ANALYSIS/` on 26 August 2026. Its final table
(disposition mix within each algorithm combination, patient-clustered CIs) now lives in
`ANALYSIS/3_descriptive.ipynb` as Table S2, rebuilt there from the same data, so the
notebook and its saved tables were retired. Its outputs were deleted rather than archived.

## `reviewer_response_scripts_2026-08-18/`

The first attempt at the same four questions, written as standalone R scripts with
markdown write-ups rather than notebooks. Superseded two days later by the `s1`-`s4`
notebooks above, and archived alongside them. Was `ANALYSIS/reviewer_response/`.

Its own `README.md` lists three findings that affect the manuscript rather than just the
response letter. Those still stand and are worth re-reading before the next revision.

## Getting anything back

The sensitivity files are tracked, so `git mv` them back, or:

```bash
git checkout HEAD -- sensitivity
```

The reviewer-response scripts were never tracked; move the folder back by hand.
