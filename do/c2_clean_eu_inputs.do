/****************************************************************************************
File: do/c2_clean_eu_inputs.do
Purpose: Clean + standardize EU inputs to a common panel keyed by (nuts2016, year)
        - ESF payments (DG REGIO historic payments)
        - Eurostat employment rate (lfst_r_lfe2emprt)
        - Eurostat unemployment rate (lfst_r_lfu3rt)
        - Eurostat GDP (nama_10r_2gdp)
        - Eurostat population (demo_r_d2jan)
Outputs: dta/clean_*.dta (one file per source, all with nuts2016 year)
****************************************************************************************/
*===============================================================================
* Setup
*===============================================================================
version 18.0
capture log close _all
* Load project setup if not already loaded
do "do/ado/00_project_setup.ado"
eu_proj_setup, projectroot("`c(pwd)'")
confirm file "$dta/crosswalk_nuts2021_2016.dta"
log using "$logs/c2_clean_eu_inputs.log", replace text

*===============================================================================
* 0. Configuration
*===============================================================================
global XWALK "$dta/crosswalk_nuts2021_2016.dta"
local f_empr "$raw/eurostat/lfst_r_lfe2emprt.xlsx"
local f_unemp "$raw/eurostat/lfst_r_lfu3rt.xlsx"
local f_gdp "$raw/eurostat/nama_10r_2gdp.xlsx"
local f_pop "$raw/eurostat/demo_r_d2jan.xlsx"
* NUTS level used in project (NUTS2 = 4 characters)
local code_len 4

*===============================================================================
* Helper Programs
*===============================================================================
*** Helper: Map NUTS codes to nuts2016 using crosswalk
capture program drop _to_nuts2016
program define _to_nuts2016
    syntax, NUTSVAR(name) YEARVAR(name) VALVARS(varlist) MODE(string)
    
    tempvar nuts_clean
    gen `nuts_clean' = upper(strtrim(`nutsvar'))
    
    * Check crosswalk match rate
    preserve
    keep `nuts_clean'
    duplicates drop
    count
    local n_all = r(N)
    
    rename `nuts_clean' nuts2021
    merge m:1 nuts2021 using "$XWALK", keep(match) nogenerate
    count
    local n_match = r(N)
    restore
    
    * If >= 60% match, treat as NUTS2021 and map to NUTS2016
    if (`n_match' / max(`n_all', 1)) >= 0.60 {
        di as result "Mapping via crosswalk (treating as NUTS2021). Match rate = " ///
            %6.2f (100*`n_match'/max(`n_all',1)) "%"
        
        rename `nuts_clean' nuts2021
        merge m:1 nuts2021 using "$XWALK", keep(match) nogenerate
        
        * Apply weights
        foreach v of varlist `valvars' {
            replace `v' = `v' * w
        }
        
        * Collapse
        if "`mode'" == "avg" {
            collapse (sum) `valvars', by(nuts2016 `yearvar')
        }
        else if "`mode'" == "sum" {
            collapse (sum) `valvars', by(nuts2016 `yearvar')
        }
        else {
            di as error "mode() must be 'avg' or 'sum'"
            error 198
        }
        
        drop if missing(nuts2016) | missing(`yearvar')
        rename `yearvar' year
        order nuts2016 year, first
    }
    else {
        di as result "Skipping crosswalk (treating as already NUTS2016)."
        rename `nuts_clean' nuts2016
        rename `yearvar' year
        keep nuts2016 year `valvars'
        keep if strlen(nuts2016) == `code_len'
    }
    
    assert !missing(nuts2016) & !missing(year)
    sort nuts2016 year, stable
end

*** Helper: Clean Eurostat Excel with merged headers
capture program drop _clean_eurostat_excel
program define _clean_eurostat_excel
    syntax, FILEpath(string) STARTrow(integer) STARTyear(integer) VARname(name)
    
    * Import without firstrow (merged cells cause issues)
    import excel "`filepath'", sheet("Sheet 1") cellrange(A`startrow') clear
    
    * First row has the year labels, second row starts data
    * Column A = GEO codes, Column B = GEO labels
    * Column C onwards: every ODD column (C, E, G, I...) has data
    *                   every EVEN column (D, F, H, J...) is blank (from merged cells)
    
    * Rename first two columns
    rename A nuts_code
    rename B region_name
    
    * Get all remaining columns
    ds nuts_code region_name, not
    local all_cols `r(varlist)'
    
    * Keep only odd-positioned columns (data columns) and rename to years
    local year = `startyear'
    local pos = 1
    foreach col of local all_cols {
        * Keep odd positions (1st, 3rd, 5th... = data columns)
        if mod(`pos', 2) == 1 {
            capture confirm variable `col'
            if !_rc {
                rename `col' y`year'
                destring y`year', replace force ignore(":" "b" "u" "p" "e" "bu")
                local year = `year' + 1
            }
        }
        else {
            * Drop even positions (blank columns from merged cells)
            capture drop `col'
        }
        local pos = `pos' + 1
    }
    
    * Drop first row (it had the year headers, now it's data)
    drop in 1
    
    * Reshape to long
    reshape long y, i(nuts_code) j(year)
    rename y `varname'
    
    * Clean
    replace nuts_code = upper(strtrim(nuts_code))
    
    * Drop metadata rows
    drop if missing(nuts_code) | nuts_code == "GEO (CODES)" | ///
            inlist(nuts_code, "EU27_2020", "EA20", "EU28", "EA19")
    drop if missing(year)
    drop region_name
end

*===============================================================================
* 1. Clean Population (demo_r_d2jan)
*===============================================================================
di as result _newline "===== Cleaning Population Data ====="
_clean_eurostat_excel, filepath("`f_pop'") startrow(10) startyear(2015) varname(pop)

* Keep only NUTS2 level
keep if strlen(nuts_code) == `code_len'

* Filter to reasonable years
keep if year <= 2023

* Convert to NUTS2016
_to_nuts2016, nutsvar(nuts_code) yearvar(year) valvars(pop) mode(sum)

capture isid nuts2016 year
if _rc {
    collapse (sum) pop, by(nuts2016 year)
}

assert pop >= 0 if !missing(pop)
compress
save "$dta/clean_population.dta", replace
di as result "Saved: $dta/clean_population.dta"

*===============================================================================
* 2. Clean GDP (nama_10r_2gdp)
*===============================================================================
di as result _newline "===== Cleaning GDP Data ====="
_clean_eurostat_excel, filepath("`f_gdp'") startrow(8) startyear(2015) varname(gdp)

* Keep only NUTS2 level
keep if strlen(nuts_code) == `code_len'

* Filter to reasonable years
keep if year <= 2023

* Convert to NUTS2016
_to_nuts2016, nutsvar(nuts_code) yearvar(year) valvars(gdp) mode(sum)

capture isid nuts2016 year
if _rc {
    collapse (sum) gdp, by(nuts2016 year)
}

assert gdp >= 0 if !missing(gdp)
compress
save "$dta/clean_gdp.dta", replace
di as result "Saved: $dta/clean_gdp.dta"

*===============================================================================
* 3. Clean Employment Rate (lfst_r_lfe2emprt)
*===============================================================================
di as result _newline "===== Cleaning Employment Rate Data ====="
_clean_eurostat_excel, filepath("`f_empr'") startrow(10) startyear(2015) varname(emprate)

* Keep only NUTS2 level
keep if strlen(nuts_code) == `code_len'

* Filter to reasonable years
keep if year <= 2023

* Standardize to percentage (0-100) for non-missing values
quietly summ emprate if !missing(emprate), meanonly
if r(N) > 0 & r(max) <= 1.5 {
    replace emprate = 100 * emprate
}

* Validate ranges for non-missing values
assert emprate >= 0 & emprate <= 100 if !missing(emprate)

* Convert to NUTS2016
_to_nuts2016, nutsvar(nuts_code) yearvar(year) valvars(emprate) mode(avg)

capture isid nuts2016 year
if _rc {
    collapse (mean) emprate, by(nuts2016 year)
}

compress
save "$dta/clean_employment_rate.dta", replace
di as result "Saved: $dta/clean_employment_rate.dta"

*===============================================================================
* 4. Clean Unemployment Rate (lfst_r_lfu3rt)
*===============================================================================
di as result _newline "===== Cleaning Unemployment Rate Data ====="
_clean_eurostat_excel, filepath("`f_unemp'") startrow(11) startyear(2014) varname(unemprate)

* Keep only NUTS2 level
keep if strlen(nuts_code) == `code_len'

* Filter to reasonable years
keep if year <= 2023

* Standardize to percentage (0-100) for non-missing values
quietly summ unemprate if !missing(unemprate), meanonly
if r(N) > 0 & r(max) <= 1.5 {
    replace unemprate = 100 * unemprate
}

* Validate ranges for non-missing values
assert unemprate >= 0 & unemprate <= 100 if !missing(unemprate)

* Convert to NUTS2016
_to_nuts2016, nutsvar(nuts_code) yearvar(year) valvars(unemprate) mode(avg)

* Collapse if needed
capture isid nuts2016 year
if _rc {
    collapse (mean) unemprate, by(nuts2016 year)
}

* Report missingness
count if missing(unemprate)
di as text "Observations with missing unemployment rate: `r(N)' (`=string(100*r(N)/_N, "%4.1f")'%)"
count if !missing(unemprate)
di as text "Observations with unemployment rate: `r(N)' (`=string(100*r(N)/_N, "%4.1f")'%)"

compress
save "$dta/clean_unemployment_rate.dta", replace
di as result "Saved: $dta/clean_unemployment_rate.dta"

*===============================================================================
* 5. Clean ESF Payments (esf_payments.csv)
*===============================================================================
di as result _newline "===== Cleaning ESF Payments Data ====="
import delimited "C:\Users\kanikashokeen\Downloads\Git_Reproducibility\Git_Reproducibility\data\raw\dg_regio\esf_payments.csv.csv", clear varnames(1) encoding("UTF-8")

* Standardize variable names
gen nuts_code = upper(strtrim(nuts2_id))  
rename year year_temp
gen year = real(string(year_temp))
drop year_temp
gen esf_pay_raw = real(string(eu_payment_annual))

* Filter to ESF only 
gen fund_std = upper(strtrim(fund))
keep if fund_std == "ESF" | strpos(fund_std, "EUROPEAN SOCIAL FUND") > 0
drop fund_std

* Drop missing observations
drop if missing(nuts_code) | missing(year) | missing(esf_pay_raw)

* Keep NUTS2 level (4 characters)
keep if strlen(nuts_code) == 4

* Handle payment values
gen esf_pay = esf_pay_raw
replace esf_pay = 0 if esf_pay_raw == 0  // Zeros are real (no payment)
replace esf_pay = . if esf_pay < 0        // Negatives become missing
drop esf_pay_raw

* Keep only necessary variables
keep nuts_code year esf_pay

* Collapse to unique nuts_code-year 
collapse (sum) esf_pay, by(nuts_code year)

* Convert to NUTS2016 classification
_to_nuts2016, nutsvar(nuts_code) yearvar(year) valvars(esf_pay) mode(sum)

* Verify uniqueness
isid nuts2016 year

* Summary statistics
di as result _newline "=== FINAL ESF DATA SUMMARY ==="
unique nuts2016
di as text "Unique NUTS2 regions: `r(unique)'"
quietly summarize year
di as text "Year range: `r(min)' to `r(max)'"
summ esf_pay, detail
count if esf_pay == 0
di as text "Zero payments: `r(N)' (`=string(100*r(N)/_N, "%4.1f")'%)"
count if esf_pay > 0
di as text "Positive payments: `r(N)' (`=string(100*r(N)/_N, "%4.1f")'%)"

compress
save "$dta/clean_esf_payments.dta", replace
di as result "Saved: $dta/clean_esf_payments.dta"

*===============================================================================
* 6. Create Base Merged Panel
*===============================================================================
di as result _newline "===== Building Base Merged Panel ====="

* Start with population
use "$dta/clean_population.dta", clear
di as text "Starting with population: `=_N' observations"

* Merge GDP
merge 1:1 nuts2016 year using "$dta/clean_gdp.dta"
tab _merge
drop if _merge == 2  // Drop GDP-only observations
gen has_gdp = (_merge == 3)
drop _merge

* Merge employment rate
merge 1:1 nuts2016 year using "$dta/clean_employment_rate.dta"
tab _merge
drop if _merge == 2  // Drop employment-only observations
gen has_emp = (_merge == 3)
drop _merge

* Merge unemployment rate
merge 1:1 nuts2016 year using "$dta/clean_unemployment_rate.dta"
tab _merge
drop if _merge == 2  // Drop unemployment-only observations
gen has_unemp = (_merge == 3)
drop _merge

* Merge ESF payments
merge 1:1 nuts2016 year using "$dta/clean_esf_payments.dta"
tab _merge
gen has_esf = (_merge == 3)
* Keep observations from master or matched (ESF can be missing/zero for some years)
drop if _merge == 2
drop _merge

* CRITICAL: Filter to EU member states only
* Keep only regions from EU countries (exclude Albania, etc.)
gen country = substr(nuts2016, 1, 2)
local eu_countries "AT BE BG CY CZ DE DK EE ES FI FR GR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK"
gen byte is_eu = 0
foreach cc of local eu_countries {
    replace is_eu = 1 if country == "`cc'"
}
keep if is_eu == 1
drop is_eu country

* CRITICAL: Filter to years with actual data (not projections)
* Keep only years where we have outcomes OR ESF data
keep if has_emp == 1 | has_unemp == 1 | has_esf == 1

* Report data availability
di as result _newline "=== DATA AVAILABILITY ==="
count if has_gdp == 1
di as text "Observations with GDP: `r(N)'"
count if has_emp == 1
di as text "Observations with employment: `r(N)'"
count if has_unemp == 1
di as text "Observations with unemployment: `r(N)'"
count if has_esf == 1
di as text "Observations with ESF > 0: `r(N)'"

* Create per-capita measure
gen esf_pc = esf_pay / pop if pop > 0
replace esf_pc = 0 if esf_pay == 0 & pop > 0  // Explicit zeros

* Label variables
label var nuts2016 "NUTS 2016 region code"
label var year "Year"
label var pop "Population"
label var gdp "GDP (million EUR)"
label var emprate "Employment rate (%)"
label var unemprate "Unemployment rate (%)"
label var esf_pay "ESF payments (EUR)"
label var esf_pc "ESF payments per capita (EUR/person)"
label var has_gdp "=1 if GDP available"
label var has_emp "=1 if employment rate available"
label var has_unemp "=1 if unemployment rate available"
label var has_esf "=1 if ESF payment > 0"

* Drop the availability flags (or keep for diagnostics)
drop has_gdp has_emp has_unemp has_esf

compress
sort nuts2016 year, stable
save "$dta/panel_base_inputs.dta", replace
save "$tmp/panel_base_inputs_tmp.dta", replace
di as result "Saved: $dta/panel_base_inputs.dta"

*===============================================================================
* Summary
*===============================================================================
di as result _newline "===== Data Cleaning Summary ====="
di as text "Base panel created with `=_N' observations"
unique nuts2016
di as text "Number of EU NUTS2 regions: `r(unique)'"
summ year
di as text "Year range: `r(min)' to `r(max)'"

* Check completeness
count if !missing(emprate, unemprate, gdp, esf_pay)
di as text "Complete observations (all vars): `r(N)'"

log close