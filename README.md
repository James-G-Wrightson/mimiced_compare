# Comparing methods to identify avoidable ED visits using the MIMIC-IV-ED database

This project was an analysis of the MIMIC-IV-ED 2.2. database. The aim was to compare how using different algorithms used to define and identify "potentially avoidable" emergency department visits affected the types of visits, patients and conditions selected. A full descriptions of the background, methods and results can be found in the preprint (ADD PREPRINT LINK). 

## Instructions
1. Clone (or download as a zip) this repo, and reopen the readme.md locally  (all links hereafter refer to locally cloned/downloaded folders and files).
2. The data for this analysis must be created using the [MIMICED](/MIMICED/) repo, which is a submodule of this repo. 
- Instructions for creating the data can be found in the [readme](MIMICED/README.md) file for that repo.
3. Once the data are created, the [analysis](ANALYSIS/3_descriptive.ipynb) notebook can be run.
- The packages required for analysis are installed (if necessary) and loaded at the start of the notebook, using the R package "pacman"
- The kernel used for this analysis was R 4.5.0
- The notebook outputs figures as s.vg and tables in .docx format
