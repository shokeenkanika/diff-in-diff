/****************************************************************************************
File: do/00_project_setup.ado
Purpose: Central project setup for reproducibility (paths, seeds, folders, adopath)
****************************************************************************************/

capture program drop eu_proj_setup
program define eu_proj_setup
    version 18.0 
    syntax, PROJECTROOT(string)

    * ---- Core reproducibility defaults ----
    clear
    set more off, permanently
    set varabbrev on
    set linesize 255
    set seed 123456
    set sortseed 123456

    * ---- Project paths ----
    global project "C:\Users\kanikashokeen\Downloads\Git_Reproducibility\Git_Reproducibility"
    cd "$project"

    * ---- Standard folder globals ----
    global do     "$project/do"
    global ado    "$project/do/ado"
    global raw    "$project/data/raw"
    global dta    "$project/dta"
    global tmp    "$project/dta/tmp"
    global logs   "$project/logs"

    * ---- Ensure folders exist ----
    cap mkdir "$dta"
    cap mkdir "$tmp"
    cap mkdir "$logs"

    * ---- Ensure custom ado path is active ----
    cap sysdir set PLUS "$ado"
    cap adopath ++ "$ado"

    * ---- (Optional) install common econometrics packages ----
cap which reghdfe
if _rc ssc install reghdfe, replace
cap which ppmlhdfe
if _rc ssc install ppmlhdfe, replace
end
