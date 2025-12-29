## Reproducibility Best Practices using a Stata DID/Event Study

This repository showcases my coding best practices with a focus on reproducible, human-led approaches to coding. I ask that the reader's focus not be on the soundness of the research question, which was taken from the perspective of practice. Instead, this form of coding reflects a broader shift in econometrics research to ensure scientific inquiry can stand the test of time. As packages popularly used in Stata/R/Python are regularly updated by committed individuals, and data held in public repositories can change with subsequent versions, it becomes harder for a researcher to defend their code as more time passes. Therefore, organizations such as the World Bank's Reproducibility Initiative (RRR: https://reproducibility.worldbank.org/index.php/home) are building important new workflows that can easily be incorporated into a project's scripts that ensure the study is robust, defendable and reproducible across time.   

Researchers looking to submit or publish a reproducibility package for their paper, Stata coders looking to make their code easier for collaboration with colleagues or their future selves, advocates for transparency and openness in science and Stata users who have noticed their results change using the same code but have no idea why, are all examples of crucial use cases of reproducibility best practices. 

Therefore, showcasing what I learnt working as a Short-Term Consultant with the World Bank, following is a Difference-in-Differences (DiD) model with event-study specifications executed in Stata. I estimate changes in the EU labour market with the policy changes that took place in the European Social Fund between their 2014-2020 and 2021-2027 period (limiting the analysis to 2021-2023, which was the last year of data availability). The workflow harmonizes geography to a single **analysis vintage (NUTS 2016)** using Eurostat correspondence tables, cleans and merges EU inputs (Eurostat regional indicators + DG REGIO historic EU payments), constructs treatment/exposure and event-time indicators, and exports regression tables/figures into one output folder. The focus is on a **clean econometric workflow, modular scripts, and reproducible outputs** rather than novelty. 

To recreate these results, please clone this repository into your own computer. It it crucial that you do not change the order of the folders. By running 0_main.do after setting the correct path to your folders in this script, you will be able to recreate my figures and tables identically. A local copy of the data sources exists in /data/raw, as downloaded by me on 12/15/2025, but please find the official sources cited below. 

---

## Research design (high level)

- **Unit:** NUTS2 region × year panel (harmonized to NUTS 2016 codes).
- **Outcomes:** employment rate, unemployment rate (Eurostat).
- **Exposure/treatment:** ESF (or cohesion) payments per capita and event-time indicators around a 2018 treatment threshold.
- **Baseline DiD:** region fixed effects + country-by-year fixed effects; clustered standard errors at the region level.
- **Event study:** leads/lags of treatment relative to each region’s event year, omitting a reference period (e.g., `t = -1`).

---

## Data sources (official)

### Eurostat (regional statistics, NUTS2)
Download (CSV recommended) from the Eurostat Data Browser pages below (or via Eurostat bulk/API options):
- **Employment rates by NUTS2** (`lfst_r_lfe2emprt`): https://ec.europa.eu/eurostat/databrowser/view/lfst_r_lfe2emprt__custom_16843686/default/table
- **Unemployment rate by NUTS2** (`lfst_r_lfu3rt`): https://ec.europa.eu/eurostat/databrowser/view/lfst_r_lfu3rt/default/table
- **GDP by NUTS2** (`nama_10r_2gdp`): https://ec.europa.eu/eurostat/databrowser/view/NAMA_10R_2GDP__custom_1707376/default/table?lang=en
- **Population by NUTS2** (`demo_r_d2jan`): https://ec.europa.eu/eurostat/databrowser/explore/all/popul?display=list&extractionId=demo_r_d2jan&lang=en&sort=category&subtheme=demo.demopreg

### DG REGIO / Cohesion Policy (historic payments)
- **Historic EU payments – regionalised and modelled** (NUTS2 annual expenditure for multiple funds, incl. ESF):
  - Dataset landing page: https://data.europa.eu/data/datasets/eu-cohesion-policy-historic-eu-payments-regionalised-and-modelled?locale=en
  - DG REGIO “Data for research” overview: https://ec.europa.eu/regional_policy/policy/evaluations/data-for-research_en

### Crosswalk / geography harmonization (Eurostat NUTS)
- **Eurostat correspondence tables** (incl. NUTS 2016 ↔ NUTS 2021 changes): https://ec.europa.eu/eurostat/web/nuts/correspondence-tables
- **NUTS 2021 change workbook** (includes 2016→2021 mapping details): https://ec.europa.eu/eurostat/documents/345175/629341/NUTS2021.xlsx
- **GISCO NUTS boundaries** (optional for maps): https://ec.europa.eu/eurostat/web/gisco/geodata/statistical-units/territorial-units-statistics

---

## Folder structure

```text
diff-in-diff/
├── do/
│   ├── ado/
│   │   └── 00_project_setup.ado
│   ├── 0_master.do
│   ├── c1_crosswalk_nuts2016_2021.do
│   ├── c2_clean_eu_inputs.do
│   ├── p1_construct_treatment_eventtime.do
│   └── r1_main_regressions.do
├── data/
│   ├── raw/
│   │   ├── crosswalk/
│   │   ├── eurostat/
│   │   └── dg_regio/
│   ├── dta/
│   └── tmp/
├── out/
│   ├── tables/
│   └── figures/
├── logs/
├── LICENSE
└── README.md
