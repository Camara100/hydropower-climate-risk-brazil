# Temporal Disaggregation

This module reproduces the temporal disaggregation of quarterly financial flows for the Santo Antônio (SA) and Belo Monte (BM) hydropower plants.

## Purpose

Quarterly sales revenue and purchased-energy flows are converted to monthly frequency for the subsequent financial-transmission and Revenue-at-Risk analyses.

## Input files

Place the following files in `data/01_monthlyization/`:

- `ARQ_XLSX_SA.xlsx`
- `ARQ_XLSX_BM.xlsx`

Each workbook contains:

- `Receita_TRI`: quarterly financial-flow data;
- `Energia_MES`: monthly electricity generation used as the high-frequency indicator in the sensitivity methods.

The original sheet and variable names are retained to preserve compatibility with the subsequent analysis.

## Methods

The validated specification uses:

- **Baseline:** Denton–Cholette without a high-frequency indicator (`quarterly_flow ~ 1`);
- **Sensitivity 1:** Chow–Lin maximum likelihood with monthly electricity generation (`quarterly_flow ~ monthly_generation`);
- **Sensitivity 2:** Fernández with monthly electricity generation (`quarterly_flow ~ monthly_generation`).

Automatic method fallback is disabled.

The target monthly analysis window is April 2016 through December 2024.

## Script

`Temporal_Disaggregation_SA_BM.R`

A single script processes both SA and BM using the same validated workflow.

## Required R packages

- `readxl`
- `openxlsx`
- `dplyr`
- `tidyr`
- `zoo`
- `tempdisagg`
- `stringr`
- `stringi`
- `purrr`
- `lubridate`
- `rlang`

The script does not install packages automatically.

## How to run

From the repository root, run:

```r
source("code/01_monthlyization/Temporal_Disaggregation_SA_BM.R")
```

The script expects the repository-relative paths shown above and writes reproduced files to:

`outputs/01_monthlyization/`

## Validation checks

The workflow includes:

- quarterly and monthly temporal-continuity checks;
- duplicate-observation checks;
- quarterly reconciliation after temporal disaggregation;
- explicit recording of requested and effective methods;
- purchased-energy sign audit;
- non-positive-value checks before logarithmic transformation;
- sensitivity comparisons against the Denton–Cholette baseline;
- session information for reproducibility.

## Reference results

Validated reference workbooks are stored in `results/01_monthlyization/`:

- `Monthlyization_SA_results.xlsx`
- `Monthlyization_BM_results.xlsx`

Reproduced outputs can be compared with these reference files.

## Notes

The reference results were produced using the same methodological specification described above. Machine-specific absolute file paths are not required for reproduction and should not be included in public reference outputs.
