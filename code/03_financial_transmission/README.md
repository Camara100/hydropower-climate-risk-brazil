# Financial Transmission and Revenue-at-Risk (RaR10)

This module reproduces the financial-transmission analysis for the Santo Antônio (SA) and Belo Monte (BM) hydropower plants.

## Purpose

The module evaluates whether changes in electricity generation are transmitted to sales revenue and converts the estimated generation elasticity into a standardized Revenue-at-Risk measure for a 10% decline in generation.

The primary specification is:

`ln(Sales Revenue)_t = alpha + beta_E ln(Generation)_t + beta_P ln(Lagged Implicit Price Proxy)_t + month fixed effects + error_t`

The coefficient `beta_E` is the generation-to-sales-revenue elasticity used in the primary RaR10 calculation.

## Inputs

This module directly consumes the validated public outputs from Module 01:

- `results/01_monthlyization/Monthlyization_SA_results.xlsx`
- `results/01_monthlyization/Monthlyization_BM_results.xlsx`

No duplicate financial input files are stored in this module.

The required worksheets are:

- `Receita_Vendas_MES_DC`
- `Receita_Vendas_MES_CL`
- `Receita_Vendas_MES_FERN`
- `Energia_MES`

## Temporal-disaggregation methods

Three monthly sales-revenue series are evaluated:

- **DC** — Denton–Cholette baseline;
- **CL** — Chow–Lin sensitivity;
- **FERN** — Fernández sensitivity.

Denton–Cholette is the baseline used for the primary reported financial-transmission and RaR10 results.

## Primary financial-transmission model

The primary model is `Multivariada_HAC`.

Inference uses Newey–West heteroskedasticity-and-autocorrelation-consistent covariance with:

- lag rule: `max(1, floor(4 * (T/100)^(2/9)))`;
- `prewhite = FALSE`;
- `adjust = TRUE`.

Month fixed effects are included.

## Implicit-price proxy

The price control is constructed from prior sales revenue per unit of generation:

1. raw implicit price proxy = Sales Revenue / Generation;
2. three-month moving average;
3. one-month lag;
4. natural logarithm.

This variable is a lagged and smoothed accounting proxy. It must not be interpreted as an exogenous market price.

## ARDL robustness model

A manual-lag ARDL model with HAC inference is estimated as a robustness exercise.

Candidate grid:

- `p = 1:2` for lagged sales revenue;
- `q = 0:2` for generation;
- `r = 0:2` for the implicit-price proxy.

BIC selection is performed on a common complete-case sample across all candidate specifications. The selected specification is then re-estimated on its natural maximum complete sample.

The ARDL model is **robustness only** and is never used as an automatic fallback for the primary RaR10 calculation.

## Revenue-at-Risk convention

For a standardized 10% decline in generation:

`RevenueChange_10pct = 100 * (0.90^beta_E - 1)`

and:

`RaR10_Loss_pct = 100 * (1 - 0.90^beta_E)`

Therefore:

`RaR10_Loss_pct = -RevenueChange_10pct`

A positive `RaR10_Loss_pct` indicates a revenue loss under the standardized generation shock.

If `beta_E` is not statistically significant at the 5% level, the result is classified as **No robust effect** rather than as a financial benefit.

## Required R packages

- `readxl`
- `dplyr`
- `purrr`
- `lmtest`
- `sandwich`
- `zoo`
- `openxlsx`

The script does not install packages automatically.

## How to run

Run from the repository root:

```r
source("code/03_financial_transmission/Elasticity_RaR10.R")
```

The script runs SA and BM sequentially.

## Reproduced outputs

The primary reproduced workbooks are written to:

- `outputs/03_financial_transmission/Elasticity_RaR10_SA_reproduced.xlsx`
- `outputs/03_financial_transmission/Elasticity_RaR10_BM_reproduced.xlsx`

The same folder also contains execution logs and `sessionInfo()` files.

The `outputs/` directory is ignored by Git.

## Public reference results

After reproduction is verified, the public reference workbooks are stored as:

- `results/03_financial_transmission/Elasticity_RaR10_SA_results.xlsx`
- `results/03_financial_transmission/Elasticity_RaR10_BM_results.xlsx`

## Main output sheets

The workbooks include, among others:

- `RUN_CONFIG`
- `INPUT_AUDIT`
- `JOIN_AUDIT`
- `PRICE_PROXY_AUDIT`
- `SAMPLE_AUDIT`
- `Elasticidade_Principal`
- `Coef_Preco_Principal`
- `Detalhe_Multivariada`
- `ARDL_Contemporaneo`
- `ARDL_Long_Run`
- `Detalhe_ARDL`
- `ARDL_BIC_GRID`
- `RaR10_BASELINE_DC`
- `RaR10_TODOS_METODOS`
- `SENSIBILIDADE_RaR10`

## Reproducibility notes

The original variable and worksheet names are retained where needed for exact compatibility with the validated analysis. English explanations are provided in the repository documentation without renaming analytical variables or changing the computational specification.
