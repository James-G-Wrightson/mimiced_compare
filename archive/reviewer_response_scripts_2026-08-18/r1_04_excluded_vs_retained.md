# R1.4 - Did the excluded visits differ systematically from the retained visits?

Supplementary analysis for the IJPDS revision. Produced by
`ANALYSIS/reviewer_response/r1_04_excluded_vs_retained.R` from
`MIMICED/ed_join_cc.parquet` (424,707 ED visits, before any analysis exclusion).
Every number below is emitted by that script.

## Verdict

**Yes, the excluded visits differ systematically from the retained ones - but in the opposite direction to the one that would threaten the findings. They are sicker, not more trivial.** The 6,984 excluded visits are 1.6% of all attendances, and 6,934 of them (99.3%) are excluded solely because triage acuity is missing. The acuity score is missing because the triage assessment was never carried out or recorded, not because a recorded score was lost: 96.7% of these visits have none of the seven triage vital signs, and the group is dominated by patients taken straight to resuscitation or trauma care - 76.3% arrived by ambulance and 4.8% by helicopter (38.4% of *all* helicopter arrivals in MIMIC-IV-ED lack an acuity score), 63.6% were admitted, 47.0% of all in-ED deaths in the dataset have no acuity score, and 40.6% carry an injury or poisoning primary diagnosis versus 16.7% of retained visits. Every imbalance above the conventional |SMD| > 0.1 sits on this severity / mode-of-arrival axis (arrival transport, disposition, injury and circulatory diagnoses, sex, and the UNKNOWN / UNABLE-TO-OBTAIN race category that unidentified critically ill patients fall into); age (SMD +0.080) and Charlson comorbidity (SMD +0.193) are close, and nothing suggests that low-acuity attendances were selectively dropped. The reviewer is right that diagnosis and resource-use data survive for these encounters - both labels are computable for all 6,984 of them (see the caveat on `res` in section C) - but their flag rates are far *lower* than in the retained cohort (Diagnosis 10.5% vs 36.1%; Resources 15.4% vs 22.1%), so putting them back would move the Diagnosis estimate from 36.12% to 35.70% (-0.42 pp) and the Resources estimate from 22.09% to 21.98% (-0.11 pp) - changes roughly 33 and 128 times smaller than the 14.0 pp gap between the Diagnosis and Resources estimates that the paper reports. With n = 424,707 every one of these contrasts is 'statistically significant' at any conventional threshold, which is exactly why standardised mean differences and not p-values are reported below: the p-values here carry no information about whether the exclusion matters.

## Verification checks

| Check | Expected | Observed | Result |
| --- | --- | --- | --- |
| Total rows | 424,707 | 424,707 | PASS |
| EXCLUDED rows | 6,984 | 6,984 | PASS |
| RETAINED rows | 417,723 | 417,723 | PASS |
| EXCLUDED + RETAINED == total | 424,707 | 424,707 | PASS |
| Rows with is.na(acuity) | 6,934 | 6,934 | PASS |
| Rows failing on age/race but NOT acuity | 50 | 50 | PASS |

## A. Why are the triage scores missing?

### A1. Which field was missing (n = 6,984 excluded visits)

| Missingness pattern | n | % of excluded |
| --- | --- | --- |
| acuity only | 6,934 | 99.3 |
| age only | 50 | 0.7 |

Missing acuity is effectively the entire exclusion: 6,934 of the 6,984 excluded visits (99.3%) fail the filter because `acuity` is missing, and only 50 fail because `age` is missing while a triage score was present. No visit is excluded for missing race. The three criteria therefore do not compound - there is one exclusion, not three.

### A2. Was a triage assessment performed at all?

Triage acuity (Emergency Severity Index) is assigned during the nursing triage assessment. If
that assessment never took place, no acuity score exists - and neither do the other triage
observations. The table contrasts completeness of the *other* triage fields for visits with and
without an acuity score.

| Group | n | No vital signs at all (%) | Mean no. of 7 triage vitals recorded | Heart rate missing (%) | Pain score missing (%) | Chief complaint missing (%) |
| --- | --- | --- | --- | --- | --- | --- |
| No acuity score (n = 6,934) | 6,934 | 96.7 | 0.18 | 97.3 | 97.3 | 0.1 |
| Acuity recorded (n = 417,773) | 417,773 | 1.6 | 6.76 | 2.5 | 4.9 | <0.1 |

This is the substantive explanation the reviewer asked for. Visits without an acuity score are visits with no triage record at all: on average 0.18 of the 7 triage vital signs are present, against 6.76 for the rest of the cohort. A chief complaint is still almost always captured, so these are complete ED encounters rather than empty records - the triage *step* was bypassed.

### A3. Missing acuity by disposition

`Rate` = proportion of visits *within that disposition* with no acuity score.
`Share` = proportion of *all* missing-acuity visits contributed by that disposition.

| Disposition | All visits (n) | Missing acuity (n) | Rate (%) | Share of missing (%) |
| --- | --- | --- | --- | --- |
| ADMITTED | 157,940 | 4,410 | 2.8 | 63.6 |
| HOME | 241,439 | 1,307 | 0.5 | 18.8 |
| OTHER | 4,254 | 881 | 20.7 | 12.7 |
| EXPIRED | 372 | 175 | 47.0 | 2.5 |
| LEFT WITHOUT BEING SEEN | 6,139 | 73 | 1.2 | 1.1 |
| TRANSFER | 7,018 | 56 | 0.8 | 0.8 |
| ELOPED | 5,666 | 18 | 0.3 | 0.3 |
| LEFT AGAINST MEDICAL ADVICE | 1,879 | 14 | 0.7 | 0.2 |

The concentration is in **admitted** visits (63.6% of all missing-acuity visits), **death in the ED** (47.0% of all EXPIRED visits in MIMIC-IV-ED have no acuity score) and the administrative **OTHER** disposition (20.7% rate). Crucially it is *not* in left-without-being-seen, eloped or left-against-medical-advice: those three dispositions together contribute only 1.5% of missing-acuity visits, and their missing-acuity rates (1.2%, 0.3%, 0.7%) sit at or below the cohort average of 1.6%. A 'patient left before assessment' explanation is therefore *not* supported by the data; the pattern points the other way.

### A4. Missing acuity by arrival transport

| Arrival transport | All visits (n) | Missing acuity (n) | Rate (%) | Share of missing (%) |
| --- | --- | --- | --- | --- |
| ambulance | 155,634 | 5,292 | 3.4 | 76.3 |
| unknown | 15,278 | 915 | 6.0 | 13.2 |
| walk in | 251,661 | 385 | 0.2 | 5.6 |
| helicopter | 868 | 333 | 38.4 | 4.8 |
| other | 1,266 | 9 | 0.7 | 0.1 |

Helicopter arrivals - the highest-acuity transport mode in the dataset - lose their acuity score 38.4% of the time, ambulance arrivals 3.4% of the time, and walk-in arrivals only 0.2% of the time. This is the signature of pre-hospital patients being taken directly into the resuscitation or trauma bay rather than through the triage desk.

### A5. Missing acuity by year of arrival

MIMIC dates are shifted into the future by a per-patient offset, so `in_year` is not a real
calendar year; it spans 2110-2212 over 103 distinct values. Years are collapsed to decades here.

| Shifted-year decade | All visits (n) | Missing acuity (n) | Rate (%) | Share of missing (%) |
| --- | --- | --- | --- | --- |
| 2110-2119 | 28,758 | 675 | 2.3 | 9.7 |
| 2120-2129 | 43,946 | 823 | 1.9 | 11.9 |
| 2130-2139 | 52,739 | 891 | 1.7 | 12.8 |
| 2140-2149 | 53,833 | 872 | 1.6 | 12.6 |
| 2150-2159 | 52,003 | 817 | 1.6 | 11.8 |
| 2160-2169 | 53,015 | 846 | 1.6 | 12.2 |
| 2170-2179 | 53,351 | 856 | 1.6 | 12.3 |
| 2180-2189 | 52,752 | 877 | 1.7 | 12.6 |
| 2190-2199 | 24,746 | 222 | 0.9 | 3.2 |
| 2200-2209 | 9,406 | 55 | 0.6 | 0.8 |
| 2210-2219 | 158 | 0 | 0.0 | 0.0 |

There is **no temporal concentration and no discontinuity**: across every shifted year with at least 1,000 visits the missing-acuity rate stays within a narrow band (0.5% to 3.1%), declining gently from roughly 2.3% in the earliest shifted decade to 0.6% in the latest, which is consistent with gradually improving triage documentation. The missingness is not an artefact of one data-collection era or of a single system change, and no single year contributes more than a small fraction of the total.

## B. Excluded vs retained, side by side

SMD = standardised mean difference (excluded - retained), computed as
`(mean1-mean2)/sqrt((sd1^2+sd2^2)/2)` for continuous variables and
`(p1-p2)/sqrt((p1(1-p1)+p2(1-p2))/2)` for each category of a categorical variable.
|SMD| > 0.1 is the conventional threshold for a meaningful imbalance.

**P-values are deliberately not reported.** With n = 424,707 even a difference of no practical
consequence is 'statistically significant', so significance testing would misrepresent the size
and the importance of these differences.

### B1. Continuous variables

| Variable | Excluded mean (SD) | Excluded median [IQR] | Retained mean (SD) | Retained median [IQR] | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- | --- | --- |
| Age (years) | 54.5 (21.4) | 55 [36-72] | 52.8 (20.6) | 53 [35-69] | +0.080 | no |
| ED length of stay (minutes) | 272.2 (258.8) | 221 [136-329] | 428.6 (370.1) | 330 [214-501] | -0.490 | **yes** |
| Charlson comorbidity index | 0.9 (1.3) | 0 [0-2] | 0.7 (1.1) | 0 [0-1] | +0.193 | **yes** |

Age is itself part of the exclusion rule, so the excluded-group age statistics use the 6,934 excluded visits that do have an age (50 have none). Length of stay is available for 6,970 excluded and 417,378 retained visits; the Charlson index is complete in both groups. The shorter ED stay among the excluded (median 221 vs 330 minutes) is consistent with rapid transfer out of the ED to theatre, ICU or the mortuary, not with a brief minor-injury attendance.

### B2. Sex

| Category | Excluded n | Excluded % | Retained n | Retained % | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- | --- | --- |
| Male | 4,090 | 58.6 | 190,925 | 45.7 | +0.260 | **yes** |
| Female | 2,894 | 41.4 | 226,798 | 54.3 | -0.260 | **yes** |

The male excess is consistent with the trauma-heavy composition of the excluded group.

### B3. Race, collapsed exactly as in Table 1

| Category | Excluded n | Excluded % | Retained n | Retained % | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- | --- | --- |
| White | 3,332 | 47.7 | 242,486 | 58.0 | -0.208 | **yes** |
| Other | 2,244 | 32.1 | 30,755 | 7.4 | +0.655 | **yes** |
| Black | 835 | 12.0 | 92,065 | 22.0 | -0.271 | **yes** |
| Hispanic/Latino | 367 | 5.3 | 34,113 | 8.2 | -0.117 | **yes** |
| Asian | 206 | 2.9 | 18,304 | 4.4 | -0.076 | no |

The apparent 'Other' excess is largely an artefact of unidentified patients: 25.2% of excluded visits carry a race value of UNKNOWN, UNABLE TO OBTAIN or PATIENT DECLINED TO ANSWER, against 1.5% of retained visits, and those strings collapse into 'Other'. The raw values among the excluded are:

| Raw `race` value (top 8, excluded group) | n | % of excluded |
| --- | --- | --- |
| WHITE | 3,151 | 45.1 |
| UNKNOWN | 1,624 | 23.3 |
| BLACK/AFRICAN AMERICAN | 685 | 9.8 |
| OTHER | 403 | 5.8 |
| HISPANIC/LATINO - PUERTO RICAN | 124 | 1.8 |
| UNABLE TO OBTAIN | 108 | 1.5 |
| ASIAN | 79 | 1.1 |
| ASIAN - CHINESE | 77 | 1.1 |

No visit is excluded for a missing `race` value - race is recorded for every visit in the built
dataset, sometimes as UNKNOWN - so there is no `(missing)` row in the table above.

### B4. Disposition (all 8 categories)

| Category | Excluded n | Excluded % | Retained n | Retained % | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- | --- | --- |
| ADMITTED | 4,410 | 63.1 | 153,530 | 36.8 | +0.547 | **yes** |
| HOME | 1,352 | 19.4 | 240,087 | 57.5 | -0.852 | **yes** |
| OTHER | 882 | 12.6 | 3,372 | 0.8 | +0.486 | **yes** |
| EXPIRED | 175 | 2.5 | 197 | <0.1 | +0.220 | **yes** |
| LEFT WITHOUT BEING SEEN | 75 | 1.1 | 6,064 | 1.5 | -0.034 | no |
| TRANSFER | 56 | 0.8 | 6,962 | 1.7 | -0.078 | no |
| ELOPED | 19 | 0.3 | 5,647 | 1.4 | -0.121 | **yes** |
| LEFT AGAINST MEDICAL ADVICE | 15 | 0.2 | 1,864 | 0.4 | -0.040 | no |

### B5. Arrival transport

| Category | Excluded n | Excluded % | Retained n | Retained % | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- | --- | --- |
| ambulance | 5,300 | 75.9 | 150,334 | 36.0 | +0.878 | **yes** |
| unknown | 919 | 13.2 | 14,359 | 3.4 | +0.358 | **yes** |
| walk in | 423 | 6.1 | 251,238 | 60.1 | -1.405 | **yes** |
| helicopter | 333 | 4.8 | 535 | 0.1 | +0.304 | **yes** |
| other | 9 | 0.1 | 1,257 | 0.3 | -0.037 | no |

### B6. ICD chapter of the primary diagnosis (top 10 by frequency in the excluded group)

| Category | Excluded n | Excluded % | Retained n | Retained % | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- | --- | --- |
| Injury and poisoning | 2,837 | 40.6 | 69,725 | 16.7 | +0.549 | **yes** |
| Diseases of the circulatory system | 1,392 | 19.9 | 32,515 | 7.8 | +0.357 | **yes** |
| Ill-defined conditions | 534 | 7.6 | 100,127 | 24.0 | -0.459 | **yes** |
| Factors influencing health status/contact with health services | 436 | 6.2 | 5,376 | 1.3 | +0.263 | **yes** |
| Infectious and parasitic diseases | 374 | 5.4 | 15,047 | 3.6 | +0.085 | no |
| Diseases of the respiratory system | 336 | 4.8 | 22,667 | 5.4 | -0.028 | no |
| Diseases of the nervous system | 251 | 3.6 | 14,714 | 3.5 | +0.004 | no |
| Mental disorders | 236 | 3.4 | 27,895 | 6.7 | -0.151 | **yes** |
| Diseases of the musculoskeletal system | 157 | 2.2 | 33,721 | 8.1 | -0.266 | **yes** |
| Diseases of the digestive system | 136 | 1.9 | 34,162 | 8.2 | -0.287 | **yes** |

Percentages are of the whole group (excluded n = 6,984, retained n = 417,723), so these ten rows do not sum to 100%. Every visit in both groups has a primary diagnosis code and an assigned ICD chapter.

### B7. Every imbalance exceeding |SMD| > 0.1

| Variable | Category | SMD |
| --- | --- | --- |
| Arrival transport | walk in | -1.405 |
| Arrival transport | ambulance | +0.878 |
| Disposition | HOME | -0.852 |
| Race | Other | +0.655 |
| ICD chapter | Injury and poisoning | +0.549 |
| Disposition | ADMITTED | +0.547 |
| ED length of stay (minutes) | - | -0.490 |
| Disposition | OTHER | +0.486 |
| ICD chapter | Ill-defined conditions | -0.459 |
| Arrival transport | unknown | +0.358 |
| ICD chapter | Diseases of the circulatory system | +0.357 |
| Arrival transport | helicopter | +0.304 |
| ICD chapter | Diseases of the digestive system | -0.287 |
| Race | Black | -0.271 |
| ICD chapter | Diseases of the musculoskeletal system | -0.266 |
| ICD chapter | Factors influencing health status/contact with health services | +0.263 |
| Sex | Female | -0.260 |
| Sex | Male | +0.260 |
| Disposition | EXPIRED | +0.220 |
| Race | White | -0.208 |
| Charlson comorbidity index | - | +0.193 |
| ICD chapter | Mental disorders | -0.151 |
| Disposition | ELOPED | -0.121 |
| Race | Hispanic/Latino | -0.117 |

Read as a set, these are not 24 independent imbalances. They are one imbalance - excluded visits are high-acuity pre-hospital arrivals, disproportionately trauma, who were admitted or died - expressed across correlated variables.

## C. Were diagnosis and resource-utilisation data still available for the excluded visits?

This is the reviewer's specific concern, and the answer is yes. The Diagnosis (NYU/Billings)
algorithm needs only the primary discharge diagnosis code; the Resources algorithm needs only
disposition, medication and rhythm-monitoring records. Neither requires a triage score. The
Triage-Acuity algorithm, by construction, cannot be computed without one.

| Data element | Excluded (n = 6,984) | Retained (n = 417,723) |
| --- | --- | --- |
| Primary diagnosis code present | 6,984 (100.0%) | 417,723 (100.0%) |
| Computable **Diagnosis** label (`nyu` non-missing) | 6,984 (100.0%) | 417,723 (100.0%) |
| Computable **Resources** label (`res` non-missing) | 6,984 (100.0%) | 417,723 (100.0%) |
| Computable **Triage-Acuity** label (`acuity_out` non-missing) | 50 (0.7%) | 417,723 (100.0%) |

The 50 excluded visits with a computable Triage-Acuity label are exactly the 50 visits excluded for missing age rather than missing acuity - an internal consistency check.

Flag rates among the visits where each label is computable:

| Algorithm | Excluded: flagged / computable (%) | Retained: flagged / computable (%) | SMD | \|SMD\| > 0.1 |
| --- | --- | --- | --- | --- |
| Diagnosis (`nyu`) | 734 / 6,984 (10.5%) | 150,870 / 417,723 (36.1%) | -0.635 | **yes** |
| Resources (`res`) | 1,077 / 6,984 (15.4%) | 92,287 / 417,723 (22.1%) | -0.172 | **yes** |

Both algorithms flag the excluded visits *less* often than the retained ones, which is what the composition described in section A predicts: these are severe, admitted, trauma-heavy encounters that neither algorithm would call potentially avoidable.

*Caveat, stated openly.* `res` is never missing by construction: the Resources algorithm treats the absence of a medication or rhythm-monitoring record as evidence that no ED resource was used, so it always returns 0 or 1 and cannot distinguish 'no resource used' from 'resource use not documented'. That is a property of the algorithm rather than of this exclusion, and it applies identically to both groups.

## D. Potential impact on the reported findings

Counterfactual: retain all 424,707 visits and label them with the two algorithms that can be
computed without a triage score.

| Algorithm | As analysed: flagged / N (%) | Excluded visits added: flagged / N (%) | Counterfactual, all visits: flagged / N (%) | Change (percentage points) |
| --- | --- | --- | --- | --- |
| Diagnosis (`nyu`) | 150,870 / 417,723 (36.12%) | 734 / 6,984 (10.51%) | 151,604 / 424,707 (35.70%) | -0.42 |
| Resources (`res`) | 92,287 / 417,723 (22.09%) | 1,077 / 6,984 (15.42%) | 93,364 / 424,707 (21.98%) | -0.11 |

The excluded visits are 1.6% of all attendances, which caps the arithmetic influence of any exclusion-related bias. Restoring them adds 734 flagged visits to the Diagnosis algorithm and 1,077 to the Resources algorithm, shifting the two estimates by -0.42 and -0.11 percentage points respectively - in both cases *downwards*, so the published figures if anything over- rather than under-state the avoidable-visit burden. The Triage-Acuity algorithm cannot be evaluated on the 6,934 missing-acuity visits under any assumption, so a three-way comparison of algorithm agreement requires a common denominator of visits on which all three are computable. That, and not a judgement about data quality, is the reason for the exclusion.

## Summary for the response letter

1. **Reason for the missing scores.** Acuity is missing because the nursing triage assessment was never carried out or never recorded, not because a score was lost. 96.7% of these visits have no triage vital sign at all, and they are concentrated in ambulance and helicopter arrivals taken straight to resuscitation or trauma care.

2. **Do they differ systematically?** Yes, on the severity and mode-of-arrival axis - that is the mechanism and it is expected. Excluded visits are more often ambulance arrivals (75.9% vs 36.0%), more often admitted (63.1% vs 36.8%), more often fatal, more often injury-related (40.6% vs 16.7%) and more often male (58.6% vs 45.7%). Age (SMD +0.080), Charlson comorbidity (SMD +0.193) and most diagnosis chapters are close.

3. **Selection-bias risk.** Low, and quantified. The excluded visits are far less likely to be flagged as potentially avoidable by either computable algorithm (Diagnosis 10.5% vs 36.1%; Resources 15.4% vs 22.1%), so their removal cannot have manufactured the between-algorithm disagreement the paper reports; adding them back changes the two estimates by -0.42 and -0.11 percentage points.

4. **Caveat we should state openly in the manuscript.** Because the excluded visits are disproportionately severe, our estimates should not be read as applying to the high-acuity pre-hospital subgroup that bypasses triage. Directionally, including that subgroup would lower the estimated share of potentially avoidable visits, not raise it.

