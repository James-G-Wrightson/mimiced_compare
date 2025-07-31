# Comparing methods to identify avoidable ED visits using the MIMIC-IV-ED database

This project was an analysis of the MIMIC-IV-ED 2.2. database. The aim was to compare how using different algorithms used to define and identify "potentially avoidable" emergency department visits affected the types of visits, patients and conditions selected. A full descriptions of the background, methods and results can be found in the preprint (ADD PREPRINT LINK). 

## Instructions
To reproduce this analysis, follow these steps in order. 
1. Clone (or download as a zip) this repo, and reopen the readme.md locally
    - The kernel I used to run this analysis was R 4.5.0
        - The necessary packages are installed and loaded using the R package "pacman" at the start of the notebooks

2. First, the MIMICED data for this analysis must be created using the [MIMICED](https://github.com/James-G-Wrightson/MIMICED.git) repo, which included  as a submodule of this repo. 
    - Instructions for creating the data can be found in the [readme](https://github.com/James-G-Wrightson/MIMICED/blob/main/README.md) file for that repo.
    - When you clone this current repo, the submodule will be available in a folder called MIMICED

3. Once the data are created, the [analysis](ANALYSIS/3_descriptive.ipynb) notebook can be run.
    - The packages required for analysis are installed (if necessary) and loaded at the start of the notebook, using the R package "pacman"
    - The kernel used for this analysis was R 4.5.0
    - The notebook outputs figures as .svg and tables in .docx format
