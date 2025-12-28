/****************************************************************************************
File: do/c3_construct_treatment_eventtime.do
Purpose: Construct ESF treatment/exposure measures + event-time indicators for DiD/event-study
Inputs:  dta/panel_base_inputs.dta   (from c2_clean_eu_inputs.do)
         Variables expected: nuts2016 year pop gdp emprate unemprate esf_pay esf_pc
Outputs: dta/panel_analysis.dta      (final analysis panel used by regression scripts)
         dta/tmp/panel_analysis_tmp.dta
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

log using "$logs/c3_construct_treatment_eventtime.log", replace text

*===============================================================================
* 0. Configuration
*===============================================================================
* Baseline window (used to define "treated" intensity groups and baseline ESF level)
* Leave missing to auto-detect first 5 years of data
local base_start = .
local base_end   = .

* Event definition: first year ESF per-capita rises at least (1+delta)*baseline_mean
local delta = 0.25

* Event-study window for leads/lags dummies
local L = 5     // number of leads (periods before treatment)
local K = 5     // number of lags (periods after treatment)

* Reference period to omit in event-study (usually -1)
local ref = -1

*===============================================================================
* 1. Load and Validate Base Panel
*===============================================================================
use "$dta/panel_base_inputs.dta", clear

* Verify required variables exist
foreach v in nuts2016 year pop gdp emprate unemprate esf_pay esf_pc {
    capture confirm variable `v'
    if _rc {
        di as error "Required variable '`v'' not found in panel_base_inputs.dta."
        di as error "Run c2_clean_eu_inputs.do first."
        error 111
    }
}

* Basic integrity checks
assert strlen(nuts2016) == 4
assert year == floor(year)

sort nuts2016 year, stable

* Ensure unique panel
capture isid nuts2016 year
if _rc {
    di as text "Panel not unique; collapsing by (nuts2016 year)."
    collapse (sum) pop gdp esf_pay ///
             (mean) emprate unemprate esf_pc, ///
             by(nuts2016 year)
    sort nuts2016 year, stable
    isid nuts2016 year
}

di as result "Panel loaded: `=_N' observations"

*===============================================================================
* 2. Define Baseline Window
*===============================================================================
quietly summarize year, meanonly
local y_min = r(min)
local y_max = r(max)

* Auto-detect baseline if not specified
if missing(`base_start') | missing(`base_end') {
    local base_start = `y_min'
    local base_end   = min(`y_min' + 4, `y_max')
    di as result "Auto-detected baseline window: `base_start' to `base_end'"
}
else {
    di as result "User-specified baseline window: `base_start' to `base_end'"
}

gen byte in_base = inrange(year, `base_start', `base_end')
label var in_base "=1 if year in baseline window"

*===============================================================================
* 3. Construct Core Exposure Variables
*===============================================================================
* Log-transformed ESF per capita
gen ln_esf_pc = ln(1 + esf_pc)
label var ln_esf_pc "ln(1 + ESF per-capita)"

* GDP per capita
gen gdp_pc = gdp / pop if pop > 0
label var gdp_pc "GDP per capita"

gen ln_gdp_pc = ln(gdp_pc) if gdp_pc > 0
label var ln_gdp_pc "ln(GDP per capita)"

di as result "Created exposure variables: ln_esf_pc, gdp_pc, ln_gdp_pc"

*===============================================================================
* 4. Define Treatment Group (Regions that Experience ESF Jump)
*===============================================================================
* Calculate baseline mean ESF per capita for each region
bysort nuts2016: egen esf_pc_base = mean(cond(in_base == 1, esf_pc, .))
label var esf_pc_base "Mean ESF per-capita in baseline window"

* Drop regions without baseline data
count if missing(esf_pc_base)
if r(N) > 0 {
    di as text "Dropping `r(N)' observations with missing baseline ESF"
    drop if missing(esf_pc_base)
}

*===============================================================================
* 5. Define Event Year (First ESF Jump)
*===============================================================================
* Flag years where ESF exceeds threshold (for ALL regions, not just treated)
gen esf_jump = (esf_pc >= (1 + `delta') * esf_pc_base) ///
    if !missing(esf_pc, esf_pc_base)
label var esf_jump "=1 if ESF pc >= (1+`delta')*baseline mean"

* First year of jump for ANY region
bysort nuts2016 (year): egen event_year = min(cond(esf_jump == 1, year, .))
label var event_year "First year ESF intensity jump"

* Define treated group as regions that EVER experience a jump
bysort nuts2016: egen ever_treated = max(esf_jump)
replace ever_treated = 0 if missing(ever_treated)
gen byte treated = (ever_treated == 1)
label var treated "=1 if region ever experiences ESF jump"
drop ever_treated

* Event time (relative year)
gen rel_year = year - event_year if !missing(event_year)
label var rel_year "Event time (year - event_year)"

* Summary
di as result "Treatment groups defined:"
tab treated, missing
count if !missing(event_year)
di as result "`r(N)' observations have defined event years"
quietly summarize event_year if !missing(event_year), detail
di as text "Event year range: `r(min)' to `r(max)'"

*===============================================================================
* 6. Build Event-Study Lead/Lag Dummies
*===============================================================================
di as result "Creating event-study dummies from -`L' to +`K'"

* Drop any existing dummies from previous runs (safe names; no minus signs)
forvalues j = 1/`L' {
    capture drop D_m`j'
    capture drop Dm`j'
}
forvalues j = 0/`K' {
    capture drop D_p`j'
    capture drop D`j'
    capture drop Dp`j'
}

* Create lead dummies (negative values, before treatment)
forvalues j = `L'(-1)1 {
    gen byte D_m`j' = (rel_year == -`j') if !missing(rel_year)
    label var D_m`j' "Event-time dummy: t = -`j'"
}

* Create lag dummies (zero and positive values, at and after treatment)
forvalues j = 0/`K' {
    gen byte D_p`j' = (rel_year == `j') if !missing(rel_year)
    label var D_p`j' "Event-time dummy: t = +`j'"
}

* Handle reference period (omit from regressions)
if `ref' < 0 {
    local ref_abs = abs(`ref')
    capture confirm variable D_m`ref_abs'
    if !_rc {
        replace D_m`ref_abs' = .
        di as text "Omitting reference period: t = `ref' (D_m`ref_abs')"
    }
}

* ALSO set the alternative naming to missing
capture confirm variable Dm1
if !_rc {
    replace Dm1 = .
    di as text "Omitting reference period: Dm1"
}

* Alternative: create simpler naming if preferred
* Creates: Dm5 Dm4 ... Dm1 D0 Dp1 ... DpK (instead of invalid names like D-1)
forvalues j = 1/`L' {
    capture confirm variable D_m`j'
    if !_rc {
        clonevar Dm`j' = D_m`j'
        label var Dm`j' "Event-time dummy: t = -`j'"
    }
}

capture confirm variable D_p0
if !_rc {
    clonevar D0 = D_p0
    label var D0 "Event-time dummy: t = 0"
}

forvalues j = 1/`K' {
    capture confirm variable D_p`j'
    if !_rc {
        clonevar Dp`j' = D_p`j'
        label var Dp`j' "Event-time dummy: t = +`j'"
    }
}

*===============================================================================
* 7. Additional DiD Indicators
*===============================================================================
* Post-treatment indicator
gen byte post = (year >= event_year) if !missing(event_year)
label var post "=1 if year >= event_year"

* Treatment intensity x post (continuous DiD)
gen ln_esf_pc_post = ln_esf_pc * post if !missing(post)
label var ln_esf_pc_post "ln(1+ESF pc) × Post"

*===============================================================================
* 8. Sample Restrictions and Final Checks
*===============================================================================

* DIAGNOSTIC: Check missingness patterns before defining sample
di as result _newline "=== Missingness Diagnostics ==="
foreach v in esf_pc ln_esf_pc emprate unemprate ln_gdp_pc event_year rel_year {
    count if missing(`v')
    di as text "`v': `r(N)' missing observations (`=string(100*r(N)/_N, "%4.1f")'%)"
}

* Show missingness by year
di as text _newline "ESF missingness by year:"
tab year if missing(esf_pc), missing

* Create multiple sample flags for different analyses
gen byte sample_outcomes = !missing(emprate, unemprate)
label var sample_outcomes "=1 if outcomes non-missing"

gen byte sample_controls = !missing(ln_gdp_pc)
label var sample_controls "=1 if controls non-missing"

gen byte sample_treatment = !missing(ln_esf_pc, event_year)
label var sample_treatment "=1 if treatment vars non-missing"

* Main sample requires outcomes + controls (treatment can vary by year)
* This allows regions with intermittent ESF payments to remain in sample
gen byte sample_main = (sample_outcomes == 1 & sample_controls == 1)
label var sample_main "=1 if outcomes and controls non-missing"

* Report sample sizes
di as result _newline "=== Sample Composition ==="
count if sample_outcomes == 1
di as text "Observations with outcomes: `r(N)'"
count if sample_controls == 1
di as text "Observations with controls: `r(N)'"
count if sample_treatment == 1
di as text "Observations with treatment vars: `r(N)'"
count if sample_main == 1
di as result "Main analysis sample: `r(N)' observations"

* Show overlap of sample criteria
di as text _newline "Sample overlap:"
tab sample_outcomes sample_controls, missing
di as text _newline "Main sample by treatment availability:"
tab sample_main sample_treatment, missing

* Additional sample for treatment effect analyses (stricter)
* Only use this for regressions that require treatment intensity
gen byte sample_did = (sample_main == 1 & sample_treatment == 1)
label var sample_did "=1 if main sample + treatment vars present"
count if sample_did == 1
di as text "DiD/Event-study sample (with treatment): `r(N)' observations"

* Plausibility checks
assert inlist(treated, 0, 1)
assert missing(event_year) | (event_year >= `y_min' & event_year <= `y_max')

count if !missing(rel_year) & abs(rel_year) > 20
if r(N) > 0 {
    di as text "Warning: `r(N)' observations with |rel_year| > 20"
}

* Check for regions completely missing from main sample
preserve
    keep nuts2016 sample_main
    collapse (sum) n_obs = sample_main (count) total_obs = sample_main, by(nuts2016)
    count if n_obs == 0
    if r(N) > 0 {
        di as text _newline "Warning: `r(N)' regions have NO observations in main sample:"
        list nuts2016 if n_obs == 0, clean noobs
    }
restore

*===============================================================================
* 9. Order Variables and Save
*===============================================================================
order nuts2016 year treated event_year rel_year post ///
      esf_pay esf_pc ln_esf_pc esf_pc_base esf_jump ///
      pop gdp gdp_pc ln_gdp_pc emprate unemprate ///
      sample_main in_base, first

compress
sort nuts2016 year, stable

save "$dta/panel_analysis.dta", replace
save "$tmp/panel_analysis_tmp.dta", replace

di as result _newline "Treatment construction complete."
di as text "Output saved to: $dta/panel_analysis.dta"

*===============================================================================
* 10. Summary Statistics
*===============================================================================
di as result _newline "===== Summary Statistics ====="

di as text _newline "Treatment status:"
tab treated

di as text _newline "Event years (treated regions):"
tab event_year if treated == 1, missing

di as text _newline "Relative year distribution:"
tab rel_year if sample_main == 1

di as text _newline "Key variables:"
summ esf_pc esf_pc_base ln_esf_pc emprate unemprate ln_gdp_pc if sample_main == 1

log close
