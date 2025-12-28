/****************************************************************************************
File: do/r1_regressions_main.do
Purpose: Paper-style DiD + event-study regressions using dta/panel_analysis.dta
         - Region FE (nuts2016)
         - Country-by-year FE
         - Clustered SE at region level
         - Export tables + event-study figures for write-up
Inputs:  dta/panel_analysis.dta  (from c3_construct_treatment_eventtime.do)
Outputs: out/tables/.rtf, *.csv
         out/figs/eventstudy_*.png
****************************************************************************************/

*===============================================================================
* Setup
*===============================================================================
version 18.0
capture log close _all

* Load project setup if not already loaded
capture confirm global project
if _rc {
    do "do/ado/00_project_setup.ado"
    eu_proj_setup, projectroot("`c(pwd)'")
}
else {
    eu_proj_setup, projectroot("$project")
}

* Output folders
global out   "$project/out"
global figs  "$out/figs"
global tabs  "$out/tables"
cap mkdir "$out"
cap mkdir "$figs"
cap mkdir "$tabs"

log using "$logs/r1_regressions_main.log", replace text

*===============================================================================
* 0. Install Required Packages
*===============================================================================
cap which reghdfe
if _rc ssc install reghdfe, replace

cap which esttab
if _rc ssc install estout, replace

cap which coefplot
if _rc ssc install coefplot, replace

cap which eststo
if _rc ssc install estout, replace

*===============================================================================
* 1. Load and Validate Analysis Panel
*===============================================================================
use "$dta/panel_analysis.dta", clear

* Verify required variables
local required_vars nuts2016 year emprate unemprate treated post ln_esf_pc ///
                    ln_esf_pc_post ln_gdp_pc rel_year sample_main

foreach v of local required_vars {
    cap confirm variable `v'
    if _rc {
        di as error "Required variable '`v'' not found in panel_analysis.dta."
        di as error "Run c3_construct_treatment_eventtime.do first."
        error 111
    }
}

* Create country identifier from NUTS code
gen str2 country = substr(nuts2016, 1, 2)
label var country "Country (ISO2 from NUTS)"

* Country-by-year fixed effects group
egen long cy = group(country year)
label var cy "Country-by-year FE group"

* Restrict to analysis sample
keep if sample_main == 1

* Validate panel structure
assert strlen(nuts2016) == 4
assert year == floor(year)

di as result "Analysis panel loaded: `=_N' observations"
unique nuts2016
di as text "Number of regions: `r(unique)'"
unique year
di as text "Number of years: `r(unique)'"

*===============================================================================
* 2. Event-Study Dummy Construction
*===============================================================================
* Event-study window (should match c3 configuration)
local L   = 5   // leads (periods before treatment)
local K   = 5   // lags (periods after treatment)
local ref = -1  // reference period to omit

* Define event-study sample
* Option A: Treated regions with defined event time only
gen byte es_sample = (treated == 1 & !missing(rel_year))
label var es_sample "Event-study sample (treated w/ defined event)"

* Option B: Include never-treated as control (uncomment if preferred)
* gen byte es_sample = (!missing(rel_year) | treated == 0)
* label var es_sample "Event-study sample (treated + never-treated)"

count if es_sample == 1
di as result "Event-study sample size: `r(N)' observations"

* Build event-time dummies (safe variable names)
* Format: Dm5, Dm4, ..., Dm2, D0, Dp1, ..., Dp5 (omitting Dm1 as reference)
local es_dummies ""

forvalues j = -`L'/`K' {
    * Skip reference period
    if `j' == `ref' continue
    
    * Create variable name
    if `j' < 0 {
        local nm = "Dm" + string(abs(`j'))
    }
    else if `j' == 0 {
        local nm = "D0"
    }
    else {
        local nm = "Dp" + string(`j')
    }
    
    * Drop if exists from previous run
    cap drop `nm'
    
    * Create dummy
    gen byte `nm' = (rel_year == `j') if es_sample == 1
    label var `nm' "Event-time dummy: t = `j'"
    
    * Add to list
    local es_dummies "`es_dummies' `nm'"
}

* Verify all dummies were created
di as text "Event-study dummies created:"
di as text "`es_dummies'"

foreach v of local es_dummies {
    cap confirm variable `v'
    if _rc {
        di as error "Event-study dummy `v' was not created successfully."
        error 111
    }
}

*===============================================================================
* 3. Run Regressions
*===============================================================================
eststo clear

di as result _newline "===== Running Regressions ====="

*** A) Binary DiD (Treated x Post)
di as text _newline "A) Binary DiD specifications..."

gen byte treated_post = treated * post if !missing(treated, post)
label var treated_post "Treated × Post"

* Check variation in key variables
tab treated_post, missing
count if treated_post == 1
di as text "Treated×Post = 1: `r(N)' observations"

* Employment rate
di as text "Running: Employment rate (binary DiD)..."
capture noisily reghdfe emprate treated_post ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
if _rc {
    di as error "ERROR in binary DiD (employment). Return code: `=_rc'"
    error _rc
}
eststo did_emp
di as result "Binary DiD (employment rate): coef = " %6.3f _b[treated_post]

* Unemployment rate
di as text "Running: Unemployment rate (binary DiD)..."
capture noisily reghdfe unemprate treated_post ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
if _rc {
    di as error "ERROR in binary DiD (unemployment). Return code: `=_rc'"
    error _rc
}
eststo did_unemp
di as result "Binary DiD (unemployment rate): coef = " %6.3f _b[treated_post]

*** B) Continuous Intensity DiD
di as text _newline "B) Continuous intensity DiD specifications..."

* Check ln_esf_pc_post has variation
summ ln_esf_pc_post
count if !missing(ln_esf_pc_post) & ln_esf_pc_post > 0
di as text "Non-zero ln_esf_pc_post: `r(N)' observations"

* Employment rate
di as text "Running: Employment rate (continuous DiD)..."
capture noisily reghdfe emprate ln_esf_pc_post ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
if _rc {
    di as error "ERROR in continuous DiD (employment). Return code: `=_rc'"
    error _rc
}
eststo didc_emp
di as result "Continuous DiD (employment rate): coef = " %6.3f _b[ln_esf_pc_post]

* Unemployment rate
di as text "Running: Unemployment rate (continuous DiD)..."
capture noisily reghdfe unemprate ln_esf_pc_post ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
if _rc {
    di as error "ERROR in continuous DiD (unemployment). Return code: `=_rc'"
    error _rc
}
eststo didc_unemp
di as result "Continuous DiD (unemployment rate): coef = " %6.3f _b[ln_esf_pc_post]

*** C) Event-Study
di as text _newline "C) Event-study specifications..."

* Check event-study sample
count if es_sample == 1
if r(N) == 0 {
    di as error "ERROR: es_sample has 0 observations!"
    error 2000
}
di as text "Event-study sample: `r(N)' observations"

* Employment rate (event-study sample)
di as text "Running: Employment rate (event-study)..."
preserve
keep if es_sample == 1
capture noisily reghdfe emprate `es_dummies' ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
if _rc {
    di as error "ERROR in event-study (employment). Return code: `=_rc'"
    restore
    error _rc
}
eststo es_emp
di as result "Event-study (employment rate) completed"
restore

* Unemployment rate (event-study sample)
di as text "Running: Unemployment rate (event-study)..."
preserve
keep if es_sample == 1
capture noisily reghdfe unemprate `es_dummies' ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
if _rc {
    di as error "ERROR in event-study (unemployment). Return code: `=_rc'"
    restore
    error _rc
}
eststo es_unemp
di as result "Event-study (unemployment rate) completed"
restore

*===============================================================================
* 4. Export Tables
*===============================================================================
di as result _newline "===== Exporting Tables ====="

*** DiD Results Table
esttab did_emp did_unemp didc_emp didc_unemp ///
    using "$tabs/table_did_main.rtf", replace ///
    title("Main DiD Results") ///
    mtitles("Emp Rate" "Unemp Rate" "Emp Rate" "Unemp Rate") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    stats(N r2_a, fmt(%9.0fc %9.3f) labels("Observations" "Adj. R²")) ///
    keep(treated_post ln_esf_pc_post ln_gdp_pc) ///
    order(treated_post ln_esf_pc_post ln_gdp_pc) ///
    addnotes("All models include NUTS2 region FE and country-by-year FE." ///
             "Standard errors clustered by region in parentheses." ///
             "*** p<0.01, ** p<0.05, * p<0.1")

esttab did_emp did_unemp didc_emp didc_unemp ///
    using "$tabs/table_did_main.csv", replace ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    keep(treated_post ln_esf_pc_post ln_gdp_pc)

di as result "Saved: $tabs/table_did_main.rtf"
di as result "Saved: $tabs/table_did_main.csv"

*** Event-Study Results Table
esttab es_emp es_unemp ///
    using "$tabs/table_eventstudy_main.rtf", replace ///
    title("Event-Study Results (Treated Regions)") ///
    mtitles("Emp Rate" "Unemp Rate") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    stats(N r2_a, fmt(%9.0fc %9.3f) labels("Observations" "Adj. R²")) ///
    keep(`es_dummies' ln_gdp_pc) ///
    order(`es_dummies' ln_gdp_pc) ///
    addnotes("Event time = 0 is first year ESF intensity exceeds (1+δ)×baseline mean." ///
             "Reference period t = -1 omitted." ///
             "All models include NUTS2 region FE and country-by-year FE." ///
             "Standard errors clustered by region in parentheses." ///
             "*** p<0.01, ** p<0.05, * p<0.1")

di as result "Saved: $tabs/table_eventstudy_main.rtf"

*===============================================================================
* 5. Event-Study Figures
*===============================================================================
di as result _newline "===== Creating Event-Study Figures ====="

*** Employment Rate Event-Study
estimates restore es_emp

* Create coefficient labels (skip reference period)
local coeflabels ""
forvalues j = `L'(-1)1 {
    if `j' == abs(`ref') continue
    local coeflabels `"`coeflabels' Dm`j' = "-`j'""'
}
local coeflabels `"`coeflabels' D0 = "0""'
forvalues j = 1/`K' {
    local coeflabels `"`coeflabels' Dp`j' = "+`j'""'
}

coefplot, ///
    keep(`es_dummies') ///
    vertical ///
    yline(0, lcolor(red) lpattern(dash)) ///
    title("Event-Study: Employment Rate", size(medium)) ///
    subtitle("Treated Regions Only", size(small)) ///
    xtitle("Years Relative to ESF Jump", size(small)) ///
    ytitle("Coefficient (percentage points)", size(small)) ///
    xlabel(, angle(0) labsize(small)) ///
    ylabel(, labsize(small)) ///
    coeflabels(`coeflabels') ///
    graphregion(color(white)) ///
    ciopts(recast(rcap) lcolor(navy))

graph export "$figs/eventstudy_employment_rate.png", replace width(2400)
di as result "Saved: $figs/eventstudy_employment_rate.png"

*** Unemployment Rate Event-Study
estimates restore es_unemp

coefplot, ///
    keep(`es_dummies') ///
    vertical ///
    yline(0, lcolor(red) lpattern(dash)) ///
    title("Event-Study: Unemployment Rate", size(medium)) ///
    subtitle("Treated Regions Only", size(small)) ///
    xtitle("Years Relative to ESF Jump", size(small)) ///
    ytitle("Coefficient (percentage points)", size(small)) ///
    xlabel(, angle(0) labsize(small)) ///
    ylabel(, labsize(small)) ///
    coeflabels(`coeflabels') ///
    graphregion(color(white)) ///
    ciopts(recast(rcap) lcolor(navy))

graph export "$figs/eventstudy_unemployment_rate.png", replace width(2400)
di as result "Saved: $figs/eventstudy_unemployment_rate.png"

*===============================================================================
* 6. Summary
*===============================================================================
di as result _newline "===== Regression Analysis Complete ====="
di as text "Tables saved to: $tabs/"
di as text "  - table_did_main.rtf"
di as text "  - table_did_main.csv"
di as text "  - table_eventstudy_main.rtf"
di as text ""
di as text "Figures saved to: $figs/"
di as text "  - eventstudy_employment_rate.png"
di as text "  - eventstudy_unemployment_rate.png"

log close