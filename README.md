## Reproducibility Best Practices using a Stata DID/Event Study

This repository is a reproducible, Stata-first coding sample that builds a NUTS2 region-year panel and estimates paper-style Difference-in-Differences (DiD) and event-study specifications on EU labour-market outcomes. The workflow harmonizes geography to a single **analysis vintage (NUTS 2016)** using Eurostat correspondence tables, cleans and merges EU inputs (Eurostat regional indicators + DG REGIO historic EU payments), constructs treatment/exposure and event-time indicators, and exports regression tables/figures for a concise write-up. The focus is on **clean econometric workflow, modular scripts, and reproducible outputs** rather than novelty.

---

## Research design (high level)

- **Unit:** NUTS2 region × year panel (harmonized to NUTS 2016 codes).
- **Outcomes (examples):** employment rate, unemployment rate (Eurostat).
- **Exposure/treatment (examples):** ESF (or cohesion) payments per capita and event-time indicators around an “exposure start” / treatment threshold.
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
