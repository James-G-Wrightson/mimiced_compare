# Working answers to the round-2 reviewer comments

Questions are in `reviewer_questions_round2.md`. Each answer below is filled in only once
the number or table it cites has been verified against a stored notebook output. Final
letter is produced from this file (pandoc) into `Paper/IJPDS/round2/`.

Decisions already made (James, 20 Oct 2026):
- ESI sensitivity: ESI 5 only is presented first and carries at least equal weight;
  ESI 3-5 second.
- Clusters: re-run embeddings, report silhouette and seed stability; an alternative-k
  sensitivity analysis will be added after reviewing the validity curves.
- NYU / Johnston per-code probabilities are third-party work and are not redistributed.
  README gives download instructions; the notebook checks for the files.

## R2-1. Agreement statistics

Status: Step 3 delivered and verified 20 Oct 2026 (recomputed from ed_join_cc.parquet by the
orchestrator; every cell matches).

Source: ANALYSIS/ci_helpers.R `agreement_boot_ci()`; ANALYSIS/3_descriptive.ipynb cell 41 ->
ANALYSIS/table_S12.docx; ANALYSIS/R2_visits.ipynb cell 26 -> R2_visits_table_S9.docx.
Kappas unchanged: 0.048 [0.046-0.050], 0.096 [0.092-0.100], 0.135 [0.131-0.138].

Table S12 (N = 417,723):
| Pair | Flagged first n (%) | Flagged second n (%) | Both | % agreement [CI] | kappa [CI] | PSA % [CI] | NSA % [CI] | Prev. index |
|---|---|---|---|---|---|---|---|---|
| Diagnosis vs Triage-Acuity | 150,870 (36.1) | 29,545 (7.1) | 14,484 | 63.7 [63.5-63.9] | 0.048 [0.046-0.050] | 16.1 [15.8-16.3] | 76.9 [76.7-77.0] | -0.568 |
| Diagnosis vs Resources | 150,870 (36.1) | 92,287 (22.1) | 41,820 | 61.8 [61.6-62.0] | 0.096 [0.092-0.100] | 34.4 [34.1-34.7] | 73.1 [72.9-73.2] | -0.418 |
| Resources vs Triage-Acuity | 92,287 (22.1) | 29,545 (7.1) | 13,845 | 77.5 [77.3-77.7] | 0.135 [0.131-0.138] | 22.7 [22.4-23.1] | 86.8 [86.7-86.9] | -0.708 |

Table S9 one-visit cohort additions: % agreement 65.0 / 62.5 / 75.6; PSA 16.1 / 35.2 / 23.3%;
NSA 77.9 / 73.6 / 85.5% (same pair order).

Interpretation for the letter: percent agreement is moderate-to-high (62-78%) mainly because
both flags are 0 for most visits (prevalence index strongly negative); negative specific
agreement is 73-87%, but positive specific agreement stays low (16-34%): when one algorithm flags a visit the other usually does not. So kappa understates chance-corrected agreement, but the
substantive conclusion (the algorithms select largely different visits) stands.
Note: gt writes a Word caption "Table 1:" prefix before the title in each docx.

### Reply

Comment 1

In the Results, under the agreement section, the Cohen's Kappa values are interpreted as showing poor agreement between algorithms. Given the large differences in prevalence between algorithms, kappa can be low even when raw agreement is reasonably high. Please report percent agreement or a prevalence adjusted kappa alongside Cohen's Kappa, or note this limitation when interpreting the values.

Thank you for this suggestion. We agree that Cohen's kappa depends on prevalence, and the three algorithms identified very different proportions of visits (Diagnosis 36.1%, Resources 22.1%, Triage-Acuity 7.1%). For each pair of algorithms we now report, alongside Cohen's kappa, percent agreement and, as recommended by Cicchetti and Feinstein, the positive and negative specific agreement, all with patient-cluster bootstrap confidence intervals (new Supplemental Table S12). We did not add a prevalence-adjusted kappa (PABAK): it equals twice percent agreement minus one, so it repeats the percent agreement in another scale and, as Cicchetti and Feinstein note, does not resolve the paradox. The same measures for the one-visit-per-patient sensitivity analysis are given in Supplemental Table S9.

These measures change how the agreement should be described, although not the conclusion. Percent agreement was 61.8% to 77.5%, because most visits were identified by neither algorithm in each pair: negative specific agreement, the percentage of the visits one algorithm does not identify that the other does not identify either, was 73.1% to 86.8%. Positive specific agreement, the percentage of the visits one algorithm identifies as potentially avoidable that the other identifies too, was low (16.1% to 34.4%). The algorithms therefore agree well on which visits are not potentially avoidable and poorly on which are, and we have reworded the Results and Discussion to say this rather than describing agreement as poor overall. The conclusion that the algorithms select largely different visits stands, because it concerns the visits they identify.

We have added the following to the Analysis section of the Methods:

"Because kappa depends on the prevalence of each classification, and the algorithms identified very different proportions of visits, we also report percent agreement, and the positive and negative specific agreement [Cicchetti and Feinstein 1990]: the percentage of the visits identified as potentially avoidable by one algorithm that the other also identifies, and the percentage of the visits not identified by one algorithm that the other does not identify either."

The agreement sentence in the Results now reads:

"Agreement between the algorithms on which visits were potentially avoidable was poor (Supplemental Table S12). The Cohen's Kappa values were small (Diagnosis x Resources = 0.096 [0.092-0.100], Diagnosis x Triage-Acuity = 0.048 [0.046-0.050], Resources x Triage-Acuity = 0.135 [0.131-0.138]). Percent agreement was higher (61.8% [61.6-62.0], 63.7% [63.5-63.9] and 77.5% [77.3-77.7], respectively), because most visits were not identified as potentially avoidable by either algorithm in each pair: negative specific agreement was 73.1% [72.9-73.2], 76.9% [76.7-77.0] and 86.8% [86.7-86.9]. Positive specific agreement was low (34.4% [34.1-34.7], 16.1% [15.8-16.3] and 22.7% [22.4-23.1]): a visit identified as potentially avoidable by one algorithm was usually not identified by the other."

We have also added the following to the limitations in the Discussion:

"Cohen's Kappa depends on the prevalence of each classification, and the algorithms identified very different proportions of visits (7.1% to 36.1%); we therefore also report percent agreement and the positive and negative specific agreement (Supplemental Table S12). These show that the algorithms agreed well on which visits were not potentially avoidable but poorly on which were, and it is the latter that matters when comparing them."

## R2-2. Number of presenting-complaint clusters

Status: Step 5a/5b delivered and verified 20 Oct 2026 (orchestrator recomputed the
reproducibility ARI independently: identical, 0.6055). Decision (James, 20 Oct 2026):
alternative-k sensitivity at k = 8 and k = 14; keep the stored 12 labels as the main result;
report reproducibility and stability openly.

Source: MIMICED/2b_chiefcomp_validity.ipynb (kernel "mimiced (uv)"; pyproject.toml + uv.lock);
outputs chiefcomp_validity_k.csv, chiefcomp_stability.csv, chiefcomp_validity_k.png.
Environment: uv lock/sync succeeded with all pins intact (numpy 1.26.4, scipy 1.13.1,
transformers 4.51.3, torch 2.5.1, scikit-learn 1.3.0); Python 3.12.13.

Reproducibility: refit KMeans(12, seed 42, n_init 10) on re-made embeddings vs stored labels:
ARI 0.61, NMI 0.73, best one-to-one match 71.6%. Original environment's versions were never
recorded, so exact regeneration is impossible.

Validity (k = 2-19): inertia no elbow; silhouette rises monotonically 0.08 -> 0.21 (0.165 at
k = 12), all low; Davies-Bouldin falls stepwise (drop at 8-10, shelf 10-12 = 2.33, drop to
2.16/2.11 at 13/14, min 2.07 at 18); Calinski-Harabasz falls throughout. No index singles
out 12.

Stability (median ARI): seed-pairwise 0.52 (k10) 0.55 (k11) 0.56 (k12) 0.57 (k13) 0.57 (k14);
vs seed 42: 0.53/0.57/0.59/0.61/0.60; 80% bootstrap vs full: 0.62/0.57/0.57/0.61/0.65.
The 0.61 reproducibility sits inside the seed-to-seed range, so the gap is ordinary k-means
instability on weakly structured text, not an embedding change.

Reply line: the clusters are illustrative groupings used only to describe common presenting
complaints; k = 12 chosen for interpretability; validity indices and stability reported
(new supplementary figure + table); sensitivity analysis at k = 8 and k = 14 shows whether
the top complaints per algorithm change (Step 5d done, see below).

Alternative-k sensitivity (Step 5d, verified 20 Oct 2026; ANALYSIS/R5_clusters.ipynb ->
R5_clusters_table_S25..S28.docx; keyword tables S22-S24; names agreed by James):
- k = 8 names: 0 Nausea vomiting + suicidal ideation; 1 Dyspnea + weakness + dizziness;
  2 Wound evaluation + seizure + rash; 3 Fall; 4 Chest pain + headache + fever; 5 Leg + knee
  pain; 6 Alcohol intoxication + vehicle collision; 7 Abdomen + back pain.
- k = 14 names: 0 Dyspnea + weakness + dizziness; 1 Transfers, abnormal results + unknown
  complaint; 2 Back + neck + shoulder pain; 3 Wound evaluation + hand injury; 4 Suicidal
  ideation + altered mental status + syncope; 5 Chest pain; 6 Influenza like illness + fever
  + rash; 7 Headache + eye, ear and dental pain; 8 Fall; 9 Nausea vomiting; 10 Abdomen pain;
  11 Leg + knee pain; 12 Alcohol intoxication; 13 Vehicle collision.
- Per-algorithm top-3 (share of that algorithm's flagged visits):
  k=12 Diagnosis: Abdomen pain 17.1 / Lower back pain 12.9 / Vehicle collision+AMS 12.1;
       Resources: Wound evaluation 20.5 / Vehicle collision+AMS 13.2 / Leg+knee 9.6;
       Triage-Acuity: Wound evaluation 28.7 / Leg+knee 21.6 / Lower back 19.8.
  k=8  Diagnosis: Chest pain+headache+fever 28.3 / Abdomen+back pain 21.7 / Dyspnea+weakness+dizziness 16.8;
       Resources: Wound eval+seizure+rash 21.7 / Dyspnea+weakness+dizziness 20.8 / Chest pain+headache+fever 20.3;
       Triage-Acuity: Wound eval+seizure+rash 33.8 / Chest pain+headache+fever 24.0 / Leg+knee 22.2.
  k=14 Diagnosis: Abdomen pain 17.2 / Dyspnea+weakness+dizziness 14.2 / Back+neck+shoulder 10.0;
       Resources: Dyspnea+weakness+dizziness 14.6 / Transfers, abnormal results+unknown 13.3 / Leg+knee 9.6;
       Triage-Acuity: Leg+knee 21.4 / Wound eval+hand injury 20.6 / Transfers... 13.1.
- Key honest finding: the paper's "Wound evaluation" cluster (77,687 visits) is a mixed
  cluster; at k = 14, 67% of it goes to "Transfers, abnormal results + unknown complaint"
  and only 23% to "Wound evaluation + hand injury". So the paper's statement that wound
  evaluation is the top complaint for Resources and Triage-Acuity depends on that cluster's
  composition; under k = 14 the top complaints for Triage-Acuity are leg/knee pain and
  wound/hand injury, and for Resources a general-medical cluster. The pattern that
  Triage-Acuity selects minor injuries/musculoskeletal visits, and Diagnosis abdominal
  pain, holds at every k. Say this plainly in the reply and soften "wound evaluation"
  wording in the manuscript where it is used as a headline.

### Reply

Comment 2

In the Analysis section, the number of clusters for presenting complaint text was chosen using the elbow method alone. Please report a quantitative cluster validity measure, such as a silhouette score, or a stability check across random initializations, to support the choice of 12 clusters.

Thank you for this comment. We have now computed three validity indices (the silhouette score, the Davies–Bouldin index and the Calinski–Harabasz index) for k = 2 to 19, and assessed stability across random starts and random 80% subsamples using the adjusted Rand index (ARI) (new Supplemental Tables S20–S21 and Supplemental Figure S6).

The results do not support any single number of clusters. The within-cluster sum of squares shows no clear elbow. The silhouette score rises steadily with k, from 0.08 at k = 2 to 0.21 at k = 19 (0.165 at k = 12), and is low throughout. The Davies–Bouldin index falls in steps, with a plateau from k = 10 to 12, and the Calinski–Harabasz index falls throughout. Stability is moderate: the median ARI between random starts is 0.52 to 0.57 for k = 10 to 14 (0.56 at k = 12). We also found that refitting k-means to re-created embeddings reproduced the clusters used in the paper only partly (ARI 0.61), because the software versions originally used were not recorded. This value lies within the ordinary variation between random starts. The software environment is now pinned in the online code, and we report this in the limitations.

We therefore no longer present the choice of 12 clusters as data-driven. The clusters are illustrative groupings, used only to describe common presenting complaints, and we chose k = 12 because it gave groups that could be named and interpreted. To test whether our descriptive results depend on this choice, we repeated the analysis with k = 8 and k = 14 (Supplemental Tables S22–S28). The names and order of the most common clusters changed, but the pattern held at every k: a wound evaluation cluster and leg and knee pain were among the three most common complaints for the Triage-Acuity algorithm, and abdominal pain among the two most common for the Diagnosis algorithm. The analysis also showed that one named cluster was heterogeneous: with k = 14, 67% of the visits in our "Wound evaluation" cluster moved to a cluster of transfers, abnormal results and unknown complaints, and only 23% to a wound evaluation and hand injury cluster. We now state this in the Results and in the Table 3 footnote.

The clustering text in the Methods now reads:

"For the free-text within 'presenting complaint', we generated sentence embeddings using the BioBERT sentence-transformer, which were then reduced with principal component analysis (80 components) and clustered using k-means clustering. The k-means within-cluster sum of squares showed no clear elbow, so we also computed the silhouette score, the Davies–Bouldin index and the Calinski–Harabasz index for k = 2 to 19, and assessed the stability of the clusters across random starts and random 80% subsamples using the adjusted Rand index (Supplemental Tables S20–S21, Supplemental Figure S6). No index identified a single best number of clusters, and the clusters were only moderately stable between random starts (median adjusted Rand index 0.56 at k = 12). We therefore treat the clusters as illustrative groupings, used only to describe common presenting complaints, and chose k = 12 because it gave groups that could be named and interpreted. Representative n-grams were extracted from each cluster and summarized for interpretability (Supplemental Table S22)."

We have added a fourth sensitivity analysis to the Methods:

"In the fourth, we repeated the presenting-complaint clustering with k = 8 and k = 14 and compared the most common presenting complaints of the visits identified by each algorithm."

And the following to the Results:

"When the presenting complaints were clustered with k = 8 or k = 14, the names and order of the most common complaint clusters changed, but the pattern was similar: at every k, a wound evaluation cluster and leg and knee pain were among the three most common complaints of visits identified by the Triage-Acuity algorithm, and abdominal pain was among the two most common complaints of visits identified by the Diagnosis algorithm (Supplemental Tables S25–S28). However, the ‘Wound evaluation’ cluster was heterogeneous: with k = 14, 67% of its visits were assigned to a cluster of transfers, abnormal results and unknown complaints, and 23% to a wound evaluation and hand injury cluster (Supplemental Tables S22–S24)."

And the following to the limitations:

"The presenting-complaint clusters were only moderately stable between random starts (median adjusted Rand index 0.56 at k = 12), and refitting k-means to re-created embeddings reproduced the clusters used in this paper only partly (adjusted Rand index 0.61), because the software versions originally used were not recorded; the software environment is now pinned in the online code. The clusters should therefore be read as illustrative groupings rather than distinct types of presenting complaint."

## R2-3. ESI threshold sensitivity analysis

Status: Step 4 delivered 20 Oct 2026; every count and agreement statistic verified by
orchestrator recomputation from ed_join_cc.parquet. Column order matches Table 2a/S2 (000 first, then 100, 010, 001, 110, 011, 101, 111); verified by orchestrator. Shares below 0.05% shown to two decimals (TA-only and Diagnosis+TA under ESI 5: 0.04%).
Source: ANALYSIS/R6_esi.ipynb -> R6_esi_table_S13..S19.docx, R6_esi_figure_S4 (ESI 5 only)
and _S5 (ESI 3-5). Provisional numbering; final in Step 7.

ESI in analysis sample (417,723): 1 = 23,991 (5.7%); 2 = 139,317 (33.4%); 3 = 224,870
(53.8%); 4 = 28,447 (6.8%); 5 = 1,098 (0.3%).

Table S13 summary (overlaps as % of Triage-Acuity-flagged visits under that definition):
| Definition | TA flagged | Also Diagnosis | Also Resources | All three | TA only | >=1 algorithm |
|---|---|---|---|---|---|---|
| ESI 5 only | 1,098 (0.3%) | 685 (62.4) | 788 (71.8) | 528 (48.1) | 153 (13.9) | 201,490 (48.2%) |
| ESI 4-5 (main) | 29,545 (7.1%) | 14,484 (49.0) | 13,845 (46.9) | 6,876 (23.3) | 8,092 (27.4) | 209,429 (50.1%) |
| ESI 3-5 | 254,415 (60.9%) | 115,934 (45.6) | 71,292 (28.0) | 35,386 (13.9) | 102,575 (40.3) | 303,912 (72.8%) |

| Definition | vs Diagnosis kappa / PSA % / NSA % | vs Resources kappa / PSA % / NSA % |
|---|---|---|
| ESI 5 only | 0.004 [0.003-0.004] / 0.9 [0.8-1.0] / 78.0 [77.8-78.1] | 0.012 [0.011-0.013] / 1.7 [1.6-1.8] / 87.6 [87.5-87.8] |
| ESI 4-5 | 0.048 [0.046-0.050] / 16.1 [15.8-16.3] / 76.9 [76.7-77.0] | 0.135 [0.131-0.138] / 22.7 [22.4-23.1] / 86.8 [86.7-86.9] |
| ESI 3-5 | 0.217 [0.214-0.220] / 57.2 [57.0-57.5] / 59.7 [59.4-59.9] | 0.129 [0.126-0.131] / 41.1 [40.8-41.4] / 58.2 [58.0-58.5] |

Section A, ESI 5 only (presented first): combinations 100 108,893; 010 50,207; 001 153;
110 41,292; 011 260; 101 157; 111 528; 000 216,233. TA-only (n=153): median age 39
[27-56], female 47.7%, median LOS 155 min. All three (n=528): age 35 [24-52], female 45.5%,
LOS 84 min. Top complaints TA-only: Wound evaluation 62.7%, Lower back pain 13.7%, Leg +
knee pain 9.2%. Reading: ESI 5 is rare (0.3%) and is mostly ALSO picked up by the other
algorithms (62% by Diagnosis, 72% by Resources, 48% by all three), i.e. the strict threshold
makes Triage-Acuity a near-subset of the others, dominated by wound checks.

Section B, ESI 3-5: combinations 100 28,502; 010 14,561; 001 102,575; 110 6,434;
011 35,906; 101 80,548; 111 35,386; 000 113,811. TA-only (n=102,575): age 54 [36-68],
female 53.8%, LOS 366 min. All three (n=35,386): age 44 [28-60], female 57.9%, LOS 209 min.
Top complaints TA-only: Wound evaluation 19.5%, Abdomen pain 16.2%, Leg + knee pain 10.3%.
Reading: including ESI 3 flags 61% of all visits, 40% of them flagged by Triage-Acuity
alone, older and longer-staying; agreement with Diagnosis rises (kappa 0.22, PSA 0.57) only
because the flag becomes so common; negative specific agreement falls to 58-60%.

Discussion fix: the sentence saying the median ESI of 3 is "higher than" the 4/5 cut-off
must be reworded (on ESI, 3 is more urgent, i.e. a lower number).

### Reply

Comment 3

In the Methods, under the Triage-Acuity algorithm description, visits with ESI 4 or 5 are classified as potentially avoidable. Since the Discussion notes that visits identified by the other two algorithms had a median acuity of 3, close to this cutoff, please test an alternate ESI threshold as a sensitivity analysis to see how much the overlap and characteristics change.

Thank you for this suggestion. We have added a sensitivity analysis in which the Triage-Acuity algorithm is redefined in two ways: a stricter definition (ESI 5 only) and a broader definition (ESI 3 to 5). The Diagnosis and Resources algorithms are unchanged. Supplemental Table S13 compares the three thresholds; Supplemental Tables S14-S16 and Supplemental Figure S4 give the counts, characteristics, common presenting complaints and diagnoses, and UpSet plot for ESI 5 only, and Supplemental Tables S17-S19 and Supplemental Figure S5 give the same for ESI 3 to 5.

With ESI 5 only, the Triage-Acuity algorithm identified 1,098 visits (0.3%). Most of these were also identified by the other algorithms: 685 (62.4%) by Diagnosis, 788 (71.8%) by Resources and 528 (48.1%) by all three, and only 153 (13.9%) by Triage-Acuity alone. Under this definition Triage-Acuity becomes close to a subset of the other two algorithms.

With ESI 3 to 5, the Triage-Acuity algorithm identified 254,415 visits (60.9%), of which 102,575 (40.3%) were identified by Triage-Acuity alone. These visits were older (median age 54 years) and stayed longer in the ED (median 366 minutes) than the visits identified by all three algorithms (44 years; 209 minutes). Agreement with Diagnosis rose (kappa 0.217, positive specific agreement 57.2%), but only because the classification became so common, and negative specific agreement fell to 59.7% with Diagnosis and 58.2% with Resources.

The overlap between the algorithms therefore depends strongly on the threshold, and none of the thresholds we tested reconciled the three algorithms. We have added the following to the sensitivity analyses in the Methods:

"In the third, we redefined the Triage-Acuity algorithm using two alternative ESI thresholds, labelling as potentially avoidable only visits with an ESI of 5 (a stricter definition) or visits with an ESI of 3, 4 or 5 (a broader definition), and repeated the comparison of the three algorithms."

And the following paragraph to the Results:

"The number of visits identified by the Triage-Acuity algorithm, and its overlap with the other algorithms, depended strongly on the ESI threshold (Supplemental Table S13). When only visits with an ESI of 5 were labelled as potentially avoidable, the Triage-Acuity algorithm identified 1,098 visits (0.3%). Of these, 685 (62.4%) were also identified by the Diagnosis algorithm, 788 (71.8%) by the Resources algorithm and 528 (48.1%) by all three algorithms; only 153 (13.9%) were identified by the Triage-Acuity algorithm alone (Supplemental Tables S14-S16, Supplemental Figure S4). When visits with an ESI of 3 to 5 were labelled as potentially avoidable, the Triage-Acuity algorithm identified 254,415 visits (60.9%), of which 102,575 (40.3%) were identified by the Triage-Acuity algorithm alone (Supplemental Tables S17-S19, Supplemental Figure S5). These visits were older (median age 54 [36-68] years) and had a longer length of stay (median 366 minutes) than visits identified by all three algorithms (44 [28-60] years; 209 minutes). Under this broader definition, agreement with the Diagnosis algorithm increased (Cohen's Kappa = 0.217 [0.214-0.220], positive specific agreement = 57.2% [57.0-57.5]), while negative specific agreement fell to 59.7% [59.4-59.9] with the Diagnosis algorithm and 58.2% [58.0-58.5] with the Resources algorithm. The proportion of visits identified by at least one algorithm was 48.2% with ESI 5 only, 50.1% with ESI 4 or 5, and 72.8% with ESI 3 to 5."

In checking the Discussion sentence you refer to, we noticed that it described the median ESI of 3 as "higher than" the 4/5 cut-off. On the ESI a lower score is more urgent, so we have corrected the sentence and extended it to interpret the new results:

"In our analysis, the median triage acuity score for potentially avoidable visits identified with either the Diagnosis or Resources algorithms was 3/5, one level more urgent than the scores (4/5) typically used as the cut-off for the Triage-Acuity algorithm. Our sensitivity analysis showed that the overlap between the Triage-Acuity algorithm and the other algorithms depends strongly on this cut-off, but that none of the thresholds we tested reconciled the three algorithms (Supplemental Table S13). When only ESI 5 visits were labelled as potentially avoidable, the Triage-Acuity algorithm identified very few visits (0.3%), most of which were also identified by the Diagnosis or Resources algorithms, so that it became close to a subset of them. When ESI 3 visits were included, it identified 60.9% of all visits, and 40.3% of these were not identified by either of the other algorithms."

We have also added to the limitations:

"The Triage-Acuity algorithm also depends on the choice of ESI cut-off: we used the common ESI 4 or 5 definition, and other cut-offs changed both the number of visits it identified and its overlap with the other algorithms (Supplemental Table S13)."

## R2-4. Race category mapping

Status: Step 1 delivered and verified 20 Oct 2026.
Source: ANALYSIS/3_descriptive.ipynb cell 32 -> ANALYSIS/table_S10.docx. 33 raw categories,
417,723 visits; counts per group match Table 1 (stopifnot).
Groups: White 242,486 (58.0); Black 92,065 (22.0); Hispanic/Latino 34,113 (8.2);
Asian 18,304 (4.4); Other 30,755 (7.4). Rule: keyword match on WHITE/BLACK/HISPANIC/ASIAN;
everything else Other, which includes OTHER, UNKNOWN, PORTUGUESE, SOUTH AMERICAN, AMERICAN
INDIAN/ALASKA NATIVE, PATIENT DECLINED TO ANSWER, NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER,
MULTIPLE RACE/ETHNICITY, UNABLE TO OBTAIN. State this plainly in the reply.
Table 1 footnote 2 to become: "Self-reported race (33 MIMIC-IV-ED categories) collapsed by
keyword; the mapping is given in Supplemental Table S10."

### Reply

Comment 4

In Table 1, footnote 2 states that race categories were collapsed for clarity, but the original categories and grouping rule are not given. Please add this mapping to the supplement.

Thank you. We have added the full mapping to the supplement as Supplemental Table S10. MIMIC-IV-ED records self-reported race in 33 categories. Each category was assigned to White, Black, Hispanic/Latino or Asian if its label contains that keyword (WHITE, BLACK, HISPANIC or ASIAN); every other category was assigned to Other. By this rule, Other includes the Other, Unknown, Patient declined to answer, Unable to obtain and Multiple race/ethnicity categories, and also the Portuguese, South American, American Indian/Alaska Native and Native Hawaiian or Other Pacific Islander categories, each of which accounts for 0.3% of visits or fewer. Supplemental Table S10 lists every original category with its group and the number and percentage of visits in it.

Table 1 footnote 2 now reads:

"Self-reported race (33 MIMIC-IV-ED categories) collapsed by keyword; the mapping is given in Supplemental Table S10."

## R2-5. Diagnosis-algorithm code-level mapping

Status: Step 2 delivered and verified 20 Oct 2026.

Verified facts (MIMICED/1_mimic_data.ipynb, new cell 67 -> MIMICED/nyu_source_summary.csv):
- Sources: NYU ICD-10 list "Updated 2.4.25" (75,242 rows); NYU ICD-9 list "6.23.15" (14,613);
  Johnston et al. 2017 (HSR 52(4):1264-76, doi 10.1111/1475-6773.12638, PMC5517669)
  Appendix S6 ICD-9 (7,443) and S7 ICD-10 (47,132).
- Johnston rows override NYU rows for the same code: ICD-9 6,663 NYU codes replaced,
  ICD-10 all 47,132 Johnston codes replace NYU rows. Combined lookup: 15,393 ICD-9 and
  75,242 ICD-10 codes, no duplicates.
- Study sample (424,707 diagnosed visits): 4,316 distinct ICD-9 and 8,331 ICD-10 primary
  codes, every one matched (0 unmatched). Visits classified via NYU-original rows 72,995;
  via Johnston rows 351,712.
- The probabilities themselves are third-party and are NOT redistributed. README section
  "Required external files (download manually)" gives file names, URLs, expected columns.
  .gitignore now excludes the files. File-check cell stops with per-file instructions.

Note for James (not a reviewer item): cell 64 maps Johnston `edcnpa` (ED care needed,
preventable/avoidable) to `ed_needed` and `edcnnpa` (not preventable) to `ed_prevent`,
i.e. swapped relative to the NYU rows. Does not affect the `nyu` flag; nothing reads
`ed_needed`/`ed_prevent`. FIXED 20 Oct 2026 (MIMICED commit f28ab49): columns corrected, ed_join_cc.parquet rewritten,
nyu/res/acuity_out totals unchanged (151,604 / 93,364 / 29,552).

Discrepancies found: NYU page now links a newer ICD-10 file (5.5.25); the 2.4.25 file
is still at its direct URL and is the one used. Wiley may name Appendix S6
`hesr12638-sup-0006-AppendixS6.txt`; README says to rename.

Table S11 built (3_descriptive.ipynb cell 34 -> ANALYSIS/table_S11.docx), verified against the csv.
Observation: every Johnston ICD-10 code is already in the NYU 2025 ICD-10 list (47,132 of
75,242), so for ICD-10 the extension changes probabilities, not coverage.

### Reply

Comment 5

In the Methods, under the Diagnosis algorithm description, the per code probability assignments used to classify visits are not included in the supplement, only chapter level groupings in Table S8. Please add the full code level mapping used in this study for reproducibility.

Thank you for raising this. The per-code probabilities are third-party work: the NYU ED algorithm code lists (NYU Wagner) and the extension published by Johnston et al. (Health Serv Res 2017;52(4):1264-76). They are not ours to redistribute, so we have not reproduced them in the supplement. Instead, we have made the mapping fully reproducible from the cited sources.

The Methods now state the exact files and versions used, the rule for combining them, how codes were matched and the classification threshold:

"We used the NYU ED algorithm code lists for ICD-9 (version 23 June 2015) and ICD-10 (version 4 February 2025), extended with the ICD-9 and ICD-10 code lists published by Johnston et al. Where a code appeared in both an NYU list and the Johnston et al. lists, the Johnston et al. probabilities were used. Each visit's primary diagnosis was matched exactly on code and ICD version, and all 12,647 distinct primary diagnosis codes in the dataset were matched (Supplemental Table S11). We labelled a visit as potentially avoidable if the summed probability for the Non-emergent and Emergent-Primary Care categories was over 0.5. The code lists are the work of their authors and are not redistributed with our code; the files, versions and download instructions are given in the README of the online code repository."

New Supplemental Table S11 lists each source file (NYU ICD-9 and ICD-10 lists; Johnston et al. Appendices S6 and S7), the number of codes in each, the number of NYU codes replaced by the Johnston et al. extension, and the number of the study's distinct diagnosis codes and visits classified by each source. No diagnosis code or visit was left unmatched. The README of the public code repository gives the file names, sources and download instructions for each list, and our code reads these files and applies them unchanged, so anyone who downloads the cited files can reproduce the code-level mapping exactly.

The chapter-level table you refer to (previously Table S8) is now Supplemental Table S1, and the references to it in the Methods and in the Table 4 footnote have been corrected.
