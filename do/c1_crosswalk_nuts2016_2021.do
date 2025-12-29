/****************************************************************************************
File: do/c1_crosswalk_nuts2016_2021.do
Purpose: Build reproducible crosswalk between NUTS 2016 and NUTS 2021 (Eurostat)
Strategy: Harmonize everything to NUTS 2016 as analysis vintage
Inputs:  $data/raw/crosswalk/nuts2021_nuts2016.xlsx 
Outputs: $dta/crosswalk_nuts2016_2021.dta (forward map: 2016 → 2021)
         $dta/crosswalk_nuts2021_2016.dta (reverse map: 2021 → 2016)
****************************************************************************************/

*===============================================================================
* Setup
*===============================================================================
capture log close _all
log using "$logs/c1_crosswalk_nuts2016_2021.log", replace text

*===============================================================================
* 1. Import Eurostat correspondence table
*===============================================================================
import excel "$raw/crosswalk/nuts2021_nuts2016.xlsx", ///
    sheet("Changes detailed NUTS 2016-2021") firstrow clear
	
describe, simple
di as result "Available columns listed above. Proceeding with import..."

local v_from "Code2016"
local v_to   "Code2021"

foreach var in `v_from' `v_to' {
    capture confirm variable `var'
    if _rc {
        di as error "Required column '`var'' not found in Excel file."
        di as error "Check the column names above and adjust the script."
        error 111
    }
}

*===============================================================================
* 2. Clean and standardize NUTS codes
*===============================================================================
* Standardize codes
gen nuts2016 = upper(strtrim(`v_from'))
gen nuts2021 = upper(strtrim(`v_to'))

* Drop missing observations
drop if missing(nuts2016) | missing(nuts2021)

* Optional: Keep change information for documentation
capture confirm variable Changecodes
if !_rc {
    rename Changecodes change_type
    label var change_type "Type of change between 2016 and 2021"
}

capture confirm variable Changecomments
if !_rc {
    rename Changecomments change_comment
    label var change_comment "Description of change"
}

* Restrict to NUTS2 level (4-character codes)
local nuts_level = 2
local code_len = cond(`nuts_level'==1, 3, cond(`nuts_level'==2, 4, 5))

keep if strlen(nuts2016)==`code_len' & strlen(nuts2021)==`code_len'

di as result "Kept `=_N' region pairs at NUTS level `nuts_level'"

*===============================================================================
* 3. Create and normalize weights
*===============================================================================
gen w = .

* Check if a weight/share column exists
capture confirm variable Share
if !_rc {
    local v_w "Share"
}
else {
    capture confirm variable SHARE
    if !_rc {
        local v_w "SHARE"
    }
}

* Use provided shares if available
if "`v_w'" != "" {
    capture confirm variable `v_w'
    if !_rc {
        gen w_raw = real(`v_w')
        replace w_raw = . if missing(w_raw)
        
        * Convert percentages to proportions if needed
        replace w = w_raw/100 if w_raw > 1 & w_raw <= 100
        replace w = w_raw     if w_raw >= 0 & w_raw <= 1
        drop w_raw
        
        di as result "Using weights from column '`v_w''"
    }
}

* Equal weights if none provided
bysort nuts2016: gen n_to = _N
replace w = 1/n_to if missing(w)
drop n_to

* We have found that this dataset has no shared column 

di as result "Assigned equal weights within source regions"

* Normalize weights to sum to 1 within each source region
bysort nuts2016: egen wsum = total(w)
replace w = w/wsum
drop wsum

*===============================================================================
* 4. Validation
*===============================================================================
* Check for missing values
assert !missing(nuts2016)
assert !missing(nuts2021)
assert !missing(w)

* Verify weights sum to 1 by source region
bysort nuts2016: egen chk = total(w)
count if abs(chk - 1) >= 1e-6
if r(N) > 0 {
    di as error "Warning: `r(N)' source regions have weights not summing to 1"
    list nuts2016 chk if abs(chk - 1) >= 1e-6, sepby(nuts2016)
}
assert abs(chk - 1) < 1e-6
drop chk

di as result "Validation passed: all weights sum to 1 within source regions"

* Summary statistics
unique nuts2016
local n_source = r(unique)
unique nuts2021
local n_target = r(unique)

di as result "Crosswalk summary:"
di as text "  - Source regions (NUTS 2016): `n_source'"
di as text "  - Target regions (NUTS 2021): `n_target'"

*===============================================================================
* 5. Save forward crosswalk (2016 → 2021)
*===============================================================================
keep nuts2016 nuts2021 w change_type change_comment

duplicates drop
sort nuts2016 nuts2021, stable

label var nuts2016 "NUTS 2016 code"
label var nuts2021 "NUTS 2021 code"
label var w "Weight for mapping 2016 → 2021"

compress
save "$dta/crosswalk_nuts2016_2021.dta", replace
di as result "Saved forward crosswalk: $dta/crosswalk_nuts2016_2021.dta"

*===============================================================================
* 6. Create and save reverse crosswalk (2021 → 2016)
*===============================================================================
preserve

* Swap direction
rename (nuts2016 nuts2021) (nuts2021 nuts2016)

* Re-normalize weights for collapsing from 2021 → 2016
bysort nuts2021: egen wsum2 = total(w)
replace w = w/wsum2
drop wsum2

* Validate reverse weights
bysort nuts2021: egen chk2 = total(w)
count if abs(chk2 - 1) >= 1e-6
if r(N) > 0 {
    di as error "Warning: `r(N)' target regions have weights not summing to 1"
}
assert abs(chk2 - 1) < 1e-6
drop chk2

sort nuts2021 nuts2016, stable

label var nuts2021 "NUTS 2021 code"
label var nuts2016 "NUTS 2016 code"  
label var w "Weight for collapsing 2021 → 2016"

compress
save "$dta/crosswalk_nuts2021_2016.dta", replace
di as result "Saved reverse crosswalk: $dta/crosswalk_nuts2021_2016.dta"

restore

*===============================================================================
* 7. Save intermediate file
*===============================================================================
save "$tmp/crosswalk_tmp_nuts.dta", replace

*===============================================================================
* 8. Display sample of crosswalk
*===============================================================================
di as result _newline "Sample of crosswalk (first 10 rows):"
list nuts2016 nuts2021 w change_type in 1/10, clean noobs

log close

di as result _newline "Crosswalk construction complete."
