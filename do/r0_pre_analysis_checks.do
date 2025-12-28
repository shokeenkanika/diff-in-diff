/****************************************************************************************
File: do/r0_pre_analysis_checks.do
Purpose: Pre-analysis diagnostics and robustness checks before main regressions
         - Parallel trends testing (formal + visual)
         - Balance checks on baseline characteristics
         - Sample composition analysis
         - Heterogeneity exploration by baseline characteristics
Inputs:  dta/panel_analysis.dta (from c3_construct_treatment_eventtime.do)
Outputs: out/tables/balance_table.rtfn
         out/tables/pretrends_test.rtf
         out/figs/parallel_trends_*.png
         out/figs/balance_*.png
         logs/r0_pre_analysis_checks.log
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

log using "$logs/r0_pre_analysis_checks.log", replace text

*===============================================================================
* 0. Install Required Packages
*===============================================================================
cap which reghdfe
if _rc ssc install reghdfe, replace

cap which eststo
if _rc ssc install estout, replace

cap which esttab
if _rc ssc install estout, replace

cap which balancetable
if _rc ssc install balancetable, replace

cap which coefplot
if _rc ssc install coefplot, replace

*===============================================================================
* 1. Load and Prepare Data
*===============================================================================
use "$dta/panel_analysis.dta", clear

* Verify required variables
local required_vars nuts2016 year emprate unemprate treated post ln_esf_pc ///
                    ln_gdp_pc rel_year sample_main esf_pc_base in_base

foreach v of local required_vars {
    cap confirm variable `v'
    if _rc {
        di as error "Required variable '`v'' not found."
        error 111
    }
}

* Create country identifier
gen str2 country = substr(nuts2016, 1, 2)
label var country "Country (ISO2)"

* Country-by-year fixed effects
egen long cy = group(country year)
label var cy "Country-by-year FE"

* Restrict to main sample
keep if sample_main == 1

di as result "Pre-analysis checks starting with `=_N' observations"
unique nuts2016
di as text "Number of regions: `r(unique)'"

*===============================================================================
* 2. Balance Table: Baseline Characteristics by Treatment Status
*===============================================================================
di as result _newline "===== BALANCE CHECKS ====="

* Calculate baseline means for key variables
foreach var in emprate unemprate gdp_pc esf_pc pop {
    bysort nuts2016: egen `var'_baseline = mean(cond(in_base == 1, `var', .))
    label var `var'_baseline "Baseline mean: `var'"
}

* Keep one observation per region for balance table
preserve
keep nuts2016 treated *_baseline country
duplicates drop nuts2016, force

* Balance table
eststo clear

* Manual balance table with t-tests
local baseline_vars emprate_baseline unemprate_baseline gdp_pc_baseline ///
                    esf_pc_baseline pop_baseline

foreach var of local baseline_vars {
    * Summary statistics by treatment group
    qui summ `var' if treated == 0
    local mean_control = r(mean)
    local sd_control = r(sd)
    local n_control = r(N)
    
    qui summ `var' if treated == 1
    local mean_treated = r(mean)
    local sd_treated = r(sd)
    local n_treated = r(N)
    
    * T-test for difference
    qui ttest `var', by(treated)
    local diff = `mean_treated' - `mean_control'
    local pval = r(p)
    local tstat = r(t)
    
    di as text "`var':"
    di as text "  Control:  " %8.3f `mean_control' " (SD: " %8.3f `sd_control' ", N=" `n_control' ")"
    di as text "  Treated:  " %8.3f `mean_treated' " (SD: " %8.3f `sd_treated' ", N=" `n_treated' ")"
    di as text "  Diff:     " %8.3f `diff' " (t=" %6.3f `tstat' ", p=" %6.4f `pval' ")"
    di as text ""
}

* Create formatted balance table
estpost ttest emprate_baseline unemprate_baseline gdp_pc_baseline ///
              esf_pc_baseline pop_baseline, by(treated)

esttab using "$tabs/balance_table.rtf", replace ///
    title("Balance Table: Baseline Characteristics by Treatment Status") ///
    cells("mu_1(fmt(%9.2f) label(Control Mean)) mu_2(fmt(%9.2f) label(Treated Mean)) b(fmt(%9.2f) star label(Difference)) p(fmt(%9.3f) label(P-value))") ///
    label ///
    noobs nonumber ///
    addnotes("Baseline period averages by treatment group." ///
             "Treatment defined as above-median baseline ESF per capita." ///
             "*** p<0.01, ** p<0.05, * p<0.1")

di as result "Saved: $tabs/balance_table.rtf"

* Visual balance check - distribution plots
foreach var in emprate_baseline unemprate_baseline gdp_pc_baseline {
    twoway (kdensity `var' if treated == 0, lcolor(navy) lwidth(medium)) ///
           (kdensity `var' if treated == 1, lcolor(cranberry) lpattern(dash) lwidth(medium)), ///
        title("Distribution of `var'", size(medium)) ///
        subtitle("By Treatment Status", size(small)) ///
        legend(label(1 "Control") label(2 "Treated") position(6) rows(1)) ///
        xtitle("`var'", size(small)) ///
        ytitle("Density", size(small)) ///
        graphregion(color(white))
    
    local clean_name = subinstr("`var'", "_baseline", "", .)
    graph export "$figs/balance_dist_`clean_name'.png", replace width(2400)
}

di as result "Saved balance distribution plots to $figs/"

restore

*===============================================================================
* 3. Parallel Trends: Visual Inspection
*===============================================================================
di as result _newline "===== PARALLEL TRENDS: VISUAL INSPECTION ====="

* Calculate mean outcomes by treatment group and year
preserve

collapse (mean) emprate unemprate gdp_pc, by(treated year)

* Employment rate trends
twoway (connected emprate year if treated == 0, lcolor(navy) mcolor(navy) msymbol(circle)) ///
       (connected emprate year if treated == 1, lcolor(cranberry) mcolor(cranberry) msymbol(square) lpattern(dash)), ///
    title("Pre-Treatment Trends: Employment Rate", size(medium)) ///
    subtitle("By Treatment Group", size(small)) ///
    legend(label(1 "Control (Low ESF)") label(2 "Treated (High ESF)") position(6) rows(1)) ///
    xtitle("Year", size(small)) ///
    ytitle("Employment Rate (%)", size(small)) ///
    graphregion(color(white)) ///
    ylabel(, angle(0) format(%9.1f))

graph export "$figs/parallel_trends_employment_visual.png", replace width(2400)
di as result "Saved: $figs/parallel_trends_employment_visual.png"

* Unemployment rate trends
twoway (connected unemprate year if treated == 0, lcolor(navy) mcolor(navy) msymbol(circle)) ///
       (connected unemprate year if treated == 1, lcolor(cranberry) mcolor(cranberry) msymbol(square) lpattern(dash)), ///
    title("Pre-Treatment Trends: Unemployment Rate", size(medium)) ///
    subtitle("By Treatment Group", size(small)) ///
    legend(label(1 "Control (Low ESF)") label(2 "Treated (High ESF)") position(6) rows(1)) ///
    xtitle("Year", size(small)) ///
    ytitle("Unemployment Rate (%)", size(small)) ///
    graphregion(color(white)) ///
    ylabel(, angle(0) format(%9.1f))

graph export "$figs/parallel_trends_unemployment_visual.png", replace width(2400)
di as result "Saved: $figs/parallel_trends_unemployment_visual.png"

restore

*===============================================================================
* 4. Parallel Trends: Formal Pre-Treatment Test
*===============================================================================
di as result _newline "===== PARALLEL TRENDS: FORMAL TESTS ====="

* Event-study window configuration
local L = 5  // leads (pre-treatment periods)
local K = 5  // lags (post-treatment periods)
local ref = -1  // reference period

* Define pre-treatment sample (only pre-treatment observations)
gen byte pretreat_sample = (treated == 1 & !missing(rel_year) & rel_year < 0)
label var pretreat_sample "Pre-treatment sample for trends test"

* Build pre-treatment dummies only (leads)
local pretreat_dummies ""
forvalues j = `L'(-1)1 {
    if `j' == abs(`ref') continue  // skip reference period
    
    local nm = "Dm" + string(`j')
    cap drop `nm'
    gen byte `nm' = (rel_year == -`j') if (treated == 1 & !missing(rel_year))
    label var `nm' "Event-time dummy: t = -`j'"
    
    local pretreat_dummies "`pretreat_dummies' `nm'"
}

di as text "Pre-treatment dummies: `pretreat_dummies'"

* Test 1: Joint F-test that all pre-treatment coefficients = 0
eststo clear

* Employment rate
preserve
keep if treated == 1 & !missing(rel_year)
reghdfe emprate `pretreat_dummies' ln_gdp_pc if rel_year < 0, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo pretrend_emp

* Joint F-test for all pre-treatment coefficients
qui test `pretreat_dummies'
scalar fstat_emp = r(F)
scalar pval_emp = r(p)

di as result _newline "Pre-trends test (Employment Rate):"
di as text "  F-statistic: " %8.3f fstat_emp
di as text "  P-value:     " %8.4f pval_emp
if pval_emp < 0.05 {
    di as error "  WARNING: Reject parallel trends assumption at 5% level"
}
else {
    di as result "  PASS: Cannot reject parallel trends"
}
restore

* Unemployment rate
preserve
keep if treated == 1 & !missing(rel_year)
reghdfe unemprate `pretreat_dummies' ln_gdp_pc if rel_year < 0, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo pretrend_unemp

* Joint F-test
qui test `pretreat_dummies'
scalar fstat_unemp = r(F)
scalar pval_unemp = r(p)

di as result _newline "Pre-trends test (Unemployment Rate):"
di as text "  F-statistic: " %8.3f fstat_unemp
di as text "  P-value:     " %8.4f pval_unemp
if pval_unemp < 0.05 {
    di as error "  WARNING: Reject parallel trends assumption at 5% level"
}
else {
    di as result "  PASS: Cannot reject parallel trends"
}
restore

* Export pre-trends test results
esttab pretrend_emp pretrend_unemp using "$tabs/pretrends_test.rtf", replace ///
    title("Parallel Trends Test: Pre-Treatment Event-Study Coefficients") ///
    mtitles("Employment" "Unemployment") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    stats(N r2_a F_test p_value, ///
          fmt(%9.0fc %9.3f %9.3f %9.4f) ///
          labels("Observations" "Adj. R²" "Joint F-stat" "P-value")) ///
    scalars("F_test F-statistic from joint test of pre-treatment coefficients" ///
            "p_value P-value of joint test") ///
    keep(`pretreat_dummies' ln_gdp_pc) ///
    addnotes("Sample restricted to treated regions in pre-treatment period only." ///
             "All models include region FE and country-by-year FE." ///
             "Standard errors clustered by region." ///
             "Joint F-test: H0 = all pre-treatment coefficients equal zero." ///
             "*** p<0.01, ** p<0.05, * p<0.1")

di as result "Saved: $tabs/pretrends_test.rtf"

* Visual plot of pre-treatment coefficients
estimates restore pretrend_emp

coefplot, ///
    keep(`pretreat_dummies') ///
    vertical ///
    yline(0, lcolor(red) lpattern(dash)) ///
    title("Pre-Treatment Coefficients: Employment Rate", size(medium)) ///
    subtitle("Joint F-test: p = " + string(pval_emp, "%9.4f"), size(small)) ///
    xtitle("Years Before Treatment", size(small)) ///
    ytitle("Coefficient", size(small)) ///
    coeflabels(Dm5="-5" Dm4="-4" Dm3="-3" Dm2="-2") ///
    graphregion(color(white)) ///
    ciopts(recast(rcap) lcolor(navy))

graph export "$figs/pretrends_coef_employment.png", replace width(2400)
di as result "Saved: $figs/pretrends_coef_employment.png"

*===============================================================================
* 5. Placebo Test: Artificial Treatment Timing
*===============================================================================
di as result _newline "===== PLACEBO TEST: ARTIFICIAL TREATMENT ====="

* Strategy: Among treated units, artificially move event year earlier
* If we find effects before actual treatment, parallel trends violated

preserve

* Keep only treated regions with defined events
keep if treated == 1 & !missing(event_year)

* Create artificial event year (move 3 years earlier)
gen event_year_placebo = event_year - 3
gen rel_year_placebo = year - event_year_placebo

* Keep only periods before actual treatment
keep if year < event_year

* Create placebo post indicator
gen byte post_placebo = (year >= event_year_placebo)

* Run placebo regressions
reghdfe emprate post_placebo ln_gdp_pc if rel_year_placebo >= -5, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo placebo_emp

local coef_placebo_emp = _b[post_placebo]
local se_placebo_emp = _se[post_placebo]
local p_placebo_emp = 2 * ttail(e(df_r), abs(_b[post_placebo]/_se[post_placebo]))

reghdfe unemprate post_placebo ln_gdp_pc if rel_year_placebo >= -5, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo placebo_unemp

local coef_placebo_unemp = _b[post_placebo]
local se_placebo_unemp = _se[post_placebo]
local p_placebo_unemp = 2 * ttail(e(df_r), abs(_b[post_placebo]/_se[post_placebo]))

di as result _newline "Placebo Test Results:"
di as text "Employment Rate:"
di as text "  Placebo coefficient: " %8.4f `coef_placebo_emp' " (SE: " %8.4f `se_placebo_emp' ")"
di as text "  P-value:            " %8.4f `p_placebo_emp'
if `p_placebo_emp' < 0.05 {
    di as error "  WARNING: Significant placebo effect detected"
}
else {
    di as result "  PASS: No significant placebo effect"
}

di as text _newline "Unemployment Rate:"
di as text "  Placebo coefficient: " %8.4f `coef_placebo_unemp' " (SE: " %8.4f `se_placebo_unemp' ")"
di as text "  P-value:            " %8.4f `p_placebo_unemp'
if `p_placebo_unemp' < 0.05 {
    di as error "  WARNING: Significant placebo effect detected"
}
else {
    di as result "  PASS: No significant placebo effect"
}

* Export placebo results
esttab placebo_emp placebo_unemp using "$tabs/placebo_test.rtf", replace ///
    title("Placebo Test: Artificial Treatment 3 Years Before Actual Event") ///
    mtitles("Employment" "Unemployment") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    stats(N r2_a, fmt(%9.0fc %9.3f) labels("Observations" "Adj. R²")) ///
    keep(post_placebo ln_gdp_pc) ///
    addnotes("Sample: Treated regions, years before actual treatment only." ///
             "Placebo event set 3 years before actual event." ///
             "If parallel trends hold, placebo post should be insignificant." ///
             "All models include region FE and country-by-year FE." ///
             "Standard errors clustered by region." ///
             "*** p<0.01, ** p<0.05, * p<0.1")

di as result "Saved: $tabs/placebo_test.rtf"

restore

*===============================================================================
* 6. Heterogeneity Analysis: By Baseline Characteristics
*===============================================================================
di as result _newline "===== HETEROGENEITY ANALYSIS ====="

* Create baseline characteristic indicators
* (a) High vs Low baseline GDP per capita
preserve
keep nuts2016 gdp_pc_baseline
duplicates drop
summ gdp_pc_baseline, detail
local gdp_med = r(p50)
gen byte high_gdp = (gdp_pc_baseline >= `gdp_med')
tempfile gdp_split
save `gdp_split'
restore

merge m:1 nuts2016 using `gdp_split', nogen keep(master match)
label var high_gdp "=1 if baseline GDP pc >= median"

* (b) High vs Low baseline unemployment
preserve
keep nuts2016 unemprate_baseline
duplicates drop
summ unemprate_baseline, detail
local unemp_med = r(p50)
gen byte high_unemp = (unemprate_baseline >= `unemp_med')
tempfile unemp_split
save `unemp_split'
restore

merge m:1 nuts2016 using `unemp_split', nogen keep(master match)
label var high_unemp "=1 if baseline unemployment >= median"

* Create treatment interactions
gen byte treated_post = treated * post if !missing(treated, post)
gen byte treated_post_highgdp = treated_post * high_gdp
gen byte treated_post_lowgdp = treated_post * (1 - high_gdp)
gen byte treated_post_highunemp = treated_post * high_unemp
gen byte treated_post_lowunemp = treated_post * (1 - high_unemp)

label var treated_post_highgdp "Treated × Post × High GDP"
label var treated_post_lowgdp "Treated × Post × Low GDP"
label var treated_post_highunemp "Treated × Post × High Unemployment"
label var treated_post_lowunemp "Treated × Post × Low Unemployment"

* Heterogeneity regressions
eststo clear

* By baseline GDP
reghdfe emprate treated_post_highgdp treated_post_lowgdp ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo hetero_gdp_emp

reghdfe unemprate treated_post_highgdp treated_post_lowgdp ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo hetero_gdp_unemp

* Test equality of coefficients
qui test treated_post_highgdp = treated_post_lowgdp
local p_diff_gdp = r(p)

di as result _newline "Heterogeneity by Baseline GDP:"
di as text "  High GDP effect (Employment): " %8.4f _b[treated_post_highgdp]
di as text "  Low GDP effect (Employment):  " %8.4f _b[treated_post_lowgdp]
di as text "  Difference p-value:          " %8.4f `p_diff_gdp'

* By baseline unemployment
reghdfe emprate treated_post_highunemp treated_post_lowunemp ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo hetero_unemp_emp

reghdfe unemprate treated_post_highunemp treated_post_lowunemp ln_gdp_pc, ///
    absorb(nuts2016 cy) vce(cluster nuts2016)
eststo hetero_unemp_unemp

* Test equality
qui test treated_post_highunemp = treated_post_lowunemp
local p_diff_unemp = r(p)

di as result _newline "Heterogeneity by Baseline Unemployment:"
di as text "  High Unemployment effect: " %8.4f _b[treated_post_highunemp]
di as text "  Low Unemployment effect:  " %8.4f _b[treated_post_lowunemp]
di as text "  Difference p-value:       " %8.4f `p_diff_unemp'

* Export heterogeneity results
esttab hetero_gdp_emp hetero_gdp_unemp hetero_unemp_emp hetero_unemp_unemp ///
    using "$tabs/heterogeneity_analysis.rtf", replace ///
    title("Heterogeneous Treatment Effects by Baseline Characteristics") ///
    mtitles("Emp: GDP" "Unemp: GDP" "Emp: Unemp" "Unemp: Unemp") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    stats(N r2_a, fmt(%9.0fc %9.3f) labels("Observations" "Adj. R²")) ///
    keep(treated_post_highgdp treated_post_lowgdp ///
         treated_post_highunemp treated_post_lowunemp ln_gdp_pc) ///
    addnotes("Columns (1-2): Heterogeneity by baseline GDP (above vs below median)." ///
             "Columns (3-4): Heterogeneity by baseline unemployment (above vs below median)." ///
             "All models include region FE and country-by-year FE." ///
             "Standard errors clustered by region." ///
             "*** p<0.01, ** p<0.05, * p<0.1")

di as result "Saved: $tabs/heterogeneity_analysis.rtf"

*===============================================================================
* 7. Sample Composition and Descriptive Statistics
*===============================================================================
di as result _newline "===== SAMPLE COMPOSITION ====="

* Regional composition by treatment status
preserve
keep nuts2016 treated country
duplicates drop

di as text _newline "Treatment group composition by country:"
tab country treated, row

* Count regions by treatment status
tab treated, missing
count if treated == 0
local n_control = r(N)
count if treated == 1
local n_treated = r(N)

di as result _newline "Treatment Group Counts:"
di as text "  Control regions (no ESF jump):  " `n_control'
di as text "  Treated regions (ESF jump):     " `n_treated'
di as text "  Total regions:                  " `=`n_control' + `n_treated''

restore

* Time coverage
preserve
keep nuts2016 year
bysort nuts2016: gen n_years = _N
summ n_years, detail

di as result _newline "Time Coverage:"
di as text "  Median years per region: " r(p50)
di as text "  Min years per region:    " r(min)
di as text "  Max years per region:    " r(max)
di as text "  Mean years per region:   " %4.1f r(mean)

* Show distribution of panel length
di as text _newline "Distribution of panel length:"
tab n_years

restore

*===============================================================================
* 8. Summary of Diagnostic Results
*===============================================================================
di as result _newline "========================================="
di as result "PRE-ANALYSIS CHECKS SUMMARY"
di as result "========================================="

di as text _newline "1. BALANCE:"
di as text "   - See balance_table.rtf for detailed results"
di as text "   - Visual distributions saved to $figs/balance_dist_*.png"

di as text _newline "2. PARALLEL TRENDS (Visual):"
di as text "   - Employment: $figs/parallel_trends_employment_visual.png"
di as text "   - Unemployment: $figs/parallel_trends_unemployment_visual.png"

di as text _newline "3. PARALLEL TRENDS (Formal Tests):"
di as text "   - Employment F-test p-value:   " %8.4f pval_emp
di as text "   - Unemployment F-test p-value: " %8.4f pval_unemp
if pval_emp > 0.05 & pval_unemp > 0.05 {
    di as result "   ✓ PASS: Cannot reject parallel trends for either outcome"
}
else {
    di as error "   ✗ WARNING: Parallel trends assumption may be violated"
}

di as text _newline "4. PLACEBO TEST:"
di as text "   - Employment placebo p-value:   " %8.4f `p_placebo_emp'
di as text "   - Unemployment placebo p-value: " %8.4f `p_placebo_unemp'
if `p_placebo_emp' > 0.05 & `p_placebo_unemp' > 0.05 {
    di as result "   ✓ PASS: No significant effects before actual treatment"
}
else {
    di as error "   ✗ WARNING: Significant placebo effects detected"
}

di as text _newline "5. HETEROGENEITY:"
di as text "   - By baseline GDP p-value:          " %8.4f `p_diff_gdp'
di as text "   - By baseline unemployment p-value: " %8.4f `p_diff_unemp'
di as text "   - See heterogeneity_analysis.rtf for detailed results"

di as text _newline "All diagnostic outputs saved to:"
di as text "  - Tables: $tabs/"
di as text "  - Figures: $figs/"

di as result _newline "Pre-analysis checks complete."
di as text "Review diagnostic results before proceeding to main analysis (r1_regressions_main.do)"

log close