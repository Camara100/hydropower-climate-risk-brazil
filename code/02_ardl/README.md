# Physical-risk ARDL models — Santo Antônio and Belo Monte

This module documents the **frozen public physical-risk ARDL workflow** for the Santo Antônio (SA, Madeira River) and Belo Monte (BM, Xingu River) hydropower plants. It is provided for reproduction of the associated manuscript **“Physical climate risk and revenue exposure in Brazilian Amazon hydropower plants”**. The documentation describes the currently committed scripts and reference files; it **does not change the models, scripts, inputs, parameters, or validated outputs**.

## Scope and reproduction boundary

The module estimates plant-specific dynamic relationships between monthly electricity generation and selected hydroclimatic / operational variables. It reproduces ARDL selection, robust coefficient estimates, diagnostics, stability, auxiliary Granger tests, and conditional individual and combined stress exercises **from already prepared analytical inputs**.

- Physical sample: **April 2016–January 2025** (106 monthly records before model-specific lag losses).
- Inputs are **natural-log transformed and X-13-adjusted series already prepared for the validated ARDL pipelines**. The files do **not** recreate every step from raw institutional downloads, missing-data handling, or original X-13 preprocessing.
- The stress exercises cover **2022–2024**. They are **conditional, nonrecursive distributed-lag sensitivities**, not climate projections or recursively simulated future generation.
- This module **does not estimate sales revenue**. The separate financial transmission / RaR10 module is documented in [`../03_financial_transmission/README.md`](../03_financial_transmission/README.md).

See [`../../documentation/methodology_notes.md`](../../documentation/methodology_notes.md), [`../../documentation/reproducibility_notes.md`](../../documentation/reproducibility_notes.md), and [`../../DATA_NOTICE.md`](../../DATA_NOTICE.md) for methodological context, execution instructions, and data provenance / reuse constraints.

## Input workbooks

Run from the **repository root**, not from `code/02_ardl/`. Both scripts read worksheet **`Ajustada`** from their respective workbooks:

| Plant | Input path | Response variable |
|---|---|---|
| SA | `data/02_ardl/LN_Variaveis_Ajustadas_X13_SA.xlsx` | `LN_Energia_SA_X13` |
| BM | `data/02_ardl/LN_Variaveis_Ajustadas_X13_BM.xlsx` | `LN_Energia_BM_X13` |

Dates are read from the `Data` column. Analytical names, column names, and worksheet names are retained exactly, including Portuguese identifiers, to preserve compatibility with the frozen scripts.

## Validated specifications and regime controls

| Setting | Santo Antônio (SA) | Belo Monte (BM) |
|---|---|---|
| Script | `ARDL_SA.R` | `ARDL_BM.R` |
| Validated lag order | `ARDL(3,1,1,1,4)` | `ARDL(1,1,1,0,1,0)` |
| Selected X regressors | `LN_Vazao_SA_X13`, `LN_Temperatura_SA_X13`, `LN_560002_SA_X13`, `LN_359001_SA_X13` | `LN_Vazao_BM_X13`, `LN_153000_BM_X13`, `LN_254010_BM_X13`, `LN_254011_BM_X13`, `LN_252001_BM_X13` |
| Regime dummies | `D_2017` from **2017-02-01**; `D_2023` from **2023-06-01** | `D_2023` from **2023-10-01**; `D_2024` from **2024-08-01** |
| Bounds test | **Case 2**, with fixed regime regressors aligned | **Case 2**, with fixed regime regressors aligned |
| Primary coefficient covariance | **HC1** | **HC1** |

The published scripts use `ARDL::auto_ardl` with AIC selection and a maximum lag order of **4**; validated regressor sets and lag specifications are checked by internal assertions. Primary results use `ROBUST_MODE = "HC1"`. Although the scripts expose an optional HAC setting, **changing the robust mode or other options is outside the frozen baseline reproduction**.

Screening and guardrails include `P_CUTOFF = 0.05`, `TOPK_TARGET = 5`, `MAX_X_POOL = 12`, `VIF_LIMIT = 10`, and `MAX_ITERS_VIF = 15`; the scripts may stop if a validated requirement is violated. The ARDL specification should not be interpreted as an unrestricted causal model.

## Estimation and diagnostic checks

The scripts provide:

- Stationarity classification through ADF (drift, AIC-selected lags up to 4) and KPSS (`mu`, short lags), using Zivot–Andrews with an intercept break **only as a level-series tie-breaker when appropriate**. A selected I(2) series fails the guardrail.
- Dynamic ARDL estimation with HC1 robust coefficient inference, plus conventional fit statistics and a multicollinearity check (VIF, interpreted alongside the model rather than solely by a mechanical cutoff).
- Durbin–Watson, Breusch–Godfrey (4 lags), Breusch–Pagan, and Jarque–Bera diagnostics.
- Bounds F-test (**Case 2**) and specification-alignment checks, recursive and OLS CUSUM stability tests, and auxiliary Granger tests (order 4).
- Impact, cumulative short-run and long-run elasticity calculations, and explicit checks of selected lag sets / stress calculations.

The Bounds result is **complementary evidence on level relationships**, with substantive conclusions resting primarily on the estimated dynamics and diagnostics; it must not be overstated as a universal cointegration finding.

## Hydroclimatic stress protocol

Each stress modifies **selected explanatory variables** for 2022–2024, propagating the changes through estimated contemporaneous and distributed-lag coefficients while **keeping observed lagged generation fixed**. The scripts specify `STRESS_MODE = "conditional_distributed_lag_nonrecursive"` and a default shock of **−10%** for any unmapped selected regressor.

The plant-specific **combined Top-3** configurations validated by internal assertions are:

| Plant | Selected Top-3 explanatory variables | Applied changes |
|---|---|---|
| SA | `LN_Vazao_SA_X13`, `LN_Temperatura_SA_X13`, `LN_359001_SA_X13` | Flow **−10%**; temperature regressor **+10%**; precipitation proxy **−10%** |
| BM | `LN_Vazao_BM_X13`, `LN_153000_BM_X13`, `LN_254010_BM_X13` | Flow **−10%**; both precipitation proxies **−10%** |

**Interpretive constraints:**

- These combined portfolios **are not identical**, so their generation effects cannot be used to rank the plants by *overall* physical vulnerability.
- The individual **−10% turbine-flow** shock is comparable across plants in its nominal specification, but it is still a conditional, model-based sensitivity.
- The SA `LN_Temperatura_SA_X13` perturbation operates on an X-13-adjusted logarithmic variable constructed from Celsius temperature observations. It **must not be presented as an invariant +10% physical warming scenario**, an additive °C shock, or a climate projection.
- The reported stress percentages are methodological scenario choices, **not regulatory or BCBS-prescribed thresholds**. Adverse-shock coefficients can have positive conditional responses; their signs alone do not establish physical causality.
- No hydroclimatic stress output is automatically converted into financial RaR10. RaR10 is computed **separately** from a standardized 10% generation decline in Module 03.

## Required R packages

The same package checks are specified in both scripts:

```r
c(
  "readxl", "dplyr", "tibble", "tidyr", "stringr", "purrr", "lubridate",
  "zoo", "dynlm", "lmtest", "sandwich", "car", "tseries", "urca",
  "strucchange", "ggplot2", "openxlsx", "ARDL", "officer", "flextable"
)
```

The scripts **do not install packages automatically**. Exact versions are not locked by `renv`; save local `sessionInfo()` metadata to record the environment of each run.

## How to reproduce

**1.** Download the repository and extract it. In R or RStudio, set the working directory to the **repository root** (the directory containing `README.md` and `code/`). Confirm the files exist:

```r
file.exists("data/02_ardl/LN_Variaveis_Ajustadas_X13_SA.xlsx")
file.exists("data/02_ardl/LN_Variaveis_Ajustadas_X13_BM.xlsx")
```

**2.** Install any missing required packages *before* execution, if your local R environment does not already have them. For the unmodified frozen baseline, do not change the model-selection settings or hard-coded validation assertions.

**3.** Run each plant separately from the root:

```r
source("code/02_ardl/ARDL_SA.R")
source("code/02_ardl/ARDL_BM.R")
```

**4.** Inspect the saved log and the `Validation_Assertions`, `Selection_Audit`, `Top3_Audit`, `Bounds_Audit`, and `Model_Alignment` worksheets. Successful script completion alone is not a substitute for checking the results against validated references.

**Note on repeated runs.** The summary XLSX is saved with `overwrite = FALSE`. Before rerunning, use a fresh copy of the repository or remove / archive **only the corresponding locally generated** `outputs/02_ardl/ARDL_<PLANT>_reproduced.xlsx`. **Do not delete or overwrite anything under `results/`**; these are the frozen public reference workbooks.

## Output locations

The primary reproduced summary workbooks are:

- `outputs/02_ardl/ARDL_SA_reproduced.xlsx`
- `outputs/02_ardl/ARDL_BM_reproduced.xlsx`

The scripts also generate plant-specific supporting materials in `outputs/02_ardl/SA/` and `outputs/02_ardl/BM/`, including:

- `logs/runner.log` and `logs/sessionInfo_<PLANT>_reproduced.txt`;
- `rds/ARDL_<PLANT>_reproduced.RDS`;
- `tables/ARDL_<PLANT>_reproduced.docx` and supporting tables;
- `figs/` containing diagnostic and stress plots, when generated.

The `outputs/` directory is ignored by Git. Generated material is **not** a replacement for the frozen public reference results.

## Public reference results and comparison

Compare the locally reproduced workbooks with:

- [`../../results/02_ardl/ARDL_SA_results.xlsx`](../../results/02_ardl/ARDL_SA_results.xlsx)
- [`../../results/02_ardl/ARDL_BM_results.xlsx`](../../results/02_ardl/ARDL_BM_results.xlsx)

Key sheets include `Resumo_modelo`, `Robust_Config`, `Input_Audit`, `Stationarity_DETAIL`, `Stationarity_VERDICT`, `Screening_Global`, `Selection_Audit`, `Top3_Audit`, `Coef_Robust_HC1`, `Diagnosticos`, `VIF`, `Bounds_Test`, `Bounds_Audit`, `CUSUM_Tests`, `CUSUM_Process`, `StressComb_Top3`, `Stress_Validacao`, `StressComb_Valid`, `Stress_Semaforo`, and `Validation_Assertions`. Individual stress result sheet names may be abbreviated to comply with Excel's 31-character worksheet limit.

At minimum verify that:

1. Input files and their MD5 fingerprints are recorded, and the run reads the intended input worksheet.
2. The selected X variables, lag orders, Top-3 components, and Bounds settings match the documented baseline.
3. All applicable `Validation_Assertions` pass.
4. Model coefficients, diagnostics, and individual / combined stress results match the public reference **at the analytical-value level**, allowing for published rounding.
5. The local session log and package versions are retained for traceability.

A change in the **binary MD5 of a resaved XLSX** does not by itself imply a change in cell values. Conversely, an XLSX opening successfully is not proof that its analyses were regenerated correctly. Comparisons should use substantive worksheets and numerical values.

## Related documentation

- [Main repository README](../../README.md)
- [Methodology notes](../../documentation/methodology_notes.md)
- [Reproducibility notes](../../documentation/reproducibility_notes.md)
- [Data dictionary](../../documentation/data_dictionary.md)
- [Data notice and reuse conditions](../../DATA_NOTICE.md)
- [Temporal-disaggregation module](../01_monthlyization/README.md)
- [Financial-transmission module](../03_financial_transmission/README.md)

No script, input workbook, frozen output, or published numerical estimate was modified in preparing this documentation.
