/****************************************************************************************
File: do/0_main.do
****************************************************************************************/
version 18.0
clear all
capture log close _all

***1) Project setup 
*
*   - change this path to your local project folder 
global PROJECTROOT "C:\Users\kanikashokeen\Downloads\Git_Reproducibility\Git_Reproducibility" 
do "$PROJECTROOT/do/ado/00_project_setup.ado"
eu_proj_setup, projectroot("$PROJECTROOT")

********************************************************************************
***2) Create output directories
cap mkdir "$project/out"
cap mkdir "$project/out/figs"
cap mkdir "$project/out/tables"

********************************************************************************
***3) Run pipeline steps

do "$do/c1_crosswalk_nuts2016_2021.do"
do "$do/c2_clean_eu_inputs.do"
do "$do/c3_construct_treatment_eventtime.do"
do "$do/r0_pre_analysis_checks.do"
do "$do/r1_regressions_main.do"

********************************************************************************
***4) Final checkpoints
capture confirm file "$dta/panel_analysis.dta"
if _rc {
    di as error "Missing $dta/panel_analysis.dta (treatment step may have failed)."
    error 601
}

capture confirm file "$project/out/tables/table_did_main.rtf"
if _rc di as error "Table output not found: out/tables/table_did_main.rtf"

capture confirm file "$project/out/figs/eventstudy_employment_rate.png"
if _rc di as error "Figure output not found: out/figs/eventstudy_employment_rate.png"

di as result "Pipeline complete."
di as text   "Key outputs:"
di as text   " - $dta/panel_analysis.dta"
di as text   " - $project/out/tables/table_did_main.rtf"
di as text   " - $project/out/tables/table_eventstudy_main.rtf"
di as text   " - $project/out/figs/eventstudy_employment_rate.png"
di as text   " - $project/out/figs/eventstudy_unemployment_rate.png"
