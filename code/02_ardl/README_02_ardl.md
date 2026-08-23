# ARDL Physical-Risk Models

This module reproduces the physical climate-risk ARDL analyses for the Santo Antônio (SA) and Belo Monte (BM) hydropower plants.

## Input data

Place the following files in `data/02_ardl/`:

- `LN_Variaveis_Ajustadas_X13_SA.xlsx`
- `LN_Variaveis_Ajustadas_X13_BM.xlsx`

The scripts read the worksheet `Ajustada`.

The original variable names are retained for exact compatibility with the validated analysis. Variable definitions and data sources are documented separately in `documentation/data_dictionary.md`.

## Scripts

- `ARDL_SA.R`
- `ARDL_BM.R`

The two plants are estimated separately because they have plant-specific variables, regime dummies, selected lag structures, and stress configurations.

## Core methodology

The reproducibility scripts implement the validated pipeline used in the study:

- log-transformed, X-13 seasonally adjusted monthly series;
- maximum ARDL lag order of 4;
- AIC-based lag selection;
- ADF and KPSS stationarity assessment;
- Zivot–Andrews structural-break unit-root test when the level tests conflict;
- an explicit guardrail against selected I(2) variables;
- univariate screening followed by multivariate ARDL selection;
- VIF guardrail;
- HC1 robust covariance for the primary inference;
- Bounds F-test, Case 2, aligned with the regime dummies;
- short-run impact, cumulative short-run, and long-run elasticity calculations;
- Durbin–Watson, Breusch–Godfrey, Breusch–Pagan, Jarque–Bera, and VIF diagnostics;
- recursive and OLS CUSUM stability tests;
- Granger-causality tests with four lags;
- individual and combined stress scenarios.

## Validated plant-specific specifications

### Santo Antônio (SA)

Regime dummies:

- `D_2017 = 1` from February 2017 onward;
- `D_2023 = 1` from June 2023 onward.

Validated selected regressors:

- `LN_Vazao_SA_X13`
- `LN_Temperatura_SA_X13`
- `LN_560002_SA_X13`
- `LN_359001_SA_X13`

Validated lag structure:

`ARDL(3,1,1,1,4)`

### Belo Monte (BM)

Regime dummies:

- `D_2023 = 1` from October 2023 onward;
- `D_2024 = 1` from August 2024 onward.

Validated selected regressors:

- `LN_Vazao_BM_X13`
- `LN_153000_BM_X13`
- `LN_254010_BM_X13`
- `LN_254011_BM_X13`
- `LN_252001_BM_X13`

Validated lag structure:

`ARDL(1,1,1,0,1,0)`

## Stress-scenario interpretation

The stress exercise is a **conditional distributed-lag, nonrecursive scenario**.

The contemporaneous and distributed-lag effects of shocks are evaluated while observed lagged electricity generation remains fixed. Therefore, the exercise must not be interpreted as a fully recursive multi-period ARDL forecast trajectory.

## Required R packages

- `readxl`
- `dplyr`
- `tibble`
- `tidyr`
- `stringr`
- `purrr`
- `lubridate`
- `zoo`
- `dynlm`
- `lmtest`
- `sandwich`
- `car`
- `tseries`
- `urca`
- `strucchange`
- `ggplot2`
- `openxlsx`
- `ARDL`
- `officer`
- `flextable`

The scripts do not install packages automatically.

## How to run

Run the scripts from the repository root.

Santo Antônio:

```r
source("code/02_ardl/ARDL_SA.R")
```

Belo Monte:

```r
source("code/02_ardl/ARDL_BM.R")
```

The primary reproduced result workbooks are written to:

- `outputs/02_ardl/ARDL_SA_reproduced.xlsx`
- `outputs/02_ardl/ARDL_BM_reproduced.xlsx`

Additional logs, figures, RDS objects, diagnostic tables, Word reports, and session information are written to plant-specific subdirectories under `outputs/02_ardl/`.

The `outputs/` directory is intentionally ignored by Git.

## Reference results

After reproduction is verified, the validated reference workbooks are stored in:

- `results/02_ardl/ARDL_SA_results.xlsx`
- `results/02_ardl/ARDL_BM_results.xlsx`

## Reproducibility guardrails

The scripts stop if key validated features change, including:

- the selected regressor set;
- the validated ARDL lag order;
- the selected combined-stress variables;
- Bounds-model alignment;
- analytical stress validation;
- the I(2) guardrail;
- the VIF threshold.

These assertions are intentional and help ensure that the public scripts reproduce the validated study rather than silently estimating a different specification.

## Notes

Some internal variable and output labels retain their original Portuguese names because they are part of the validated data and output structure. The repository documentation provides English descriptions without renaming analytical variables or changing the computational pipeline.
