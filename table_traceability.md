# Manuscript-to-code-and-results traceability matrix (R5)

## Purpose and interpretation

This document links each of the **seven tables** in *Physical climate risk and revenue exposure in Brazilian Amazon hydropower plants* (approved English manuscript, 30 October 2026) to the public R scripts, input workbooks, and **exact worksheet names** in frozen reference results. The mapping reflects the repository ZIP provided for audit (30 October 2026); it is not a claim that the scripts were rerun independently for this update.

**Reference-path convention:** `results/...` contains frozen, validated outputs; `outputs/...` contains locally regenerated files after executing the corresponding scripts. Do not overwrite `results/` during replication. The manuscript's table values are rounded; comparisons should use full precision where possible.

## Crosswalk: all seven manuscript tables

| Paper table | Primary script(s) | Frozen reference workbook(s) and worksheets | Primary verification |
|---|---|---|---|
| **Table 1 — ARDL principal results** | `code/02_ardl/ARDL_SA.R`; `ARDL_BM.R` | `results/02_ardl/ARDL_{SA,BM}_results.xlsx`: `Resumo_modelo`, `Coef_Robust_HC1`, `Elasticidades`, `Bounds_Test` | Adjusted R², plant-specific coefficient summaries, and the separately reported Bounds evidence |
| **Table 2 — Individual hydroclimatic stresses** | Same physical ARDL scripts | `results/02_ardl/ARDL_{SA,BM}_results.xlsx`: `StressInd_*` (individual scenario tabs), `Stress_Validacao`, `Stress_Semaforo`, `Stress_Config` | Scenario definition, signed mean response over 2022–2024, stress classification; distinguish numerical shock and modeled generation response |
| **Table 3 — Plant-specific combined stresses** | Same physical ARDL scripts | `results/02_ardl/ARDL_{SA,BM}_results.xlsx`: `Top3_Comb`, `StressComb_Top3`, `StressComb_Valid`, `Stress_Semaforo`, `Stress_Config` | Actual portfolio composition, signed average effect, classification; portfolios differ and must not be used as controlled physical-vulnerability ranking |
| **Table 4 — Generation–revenue elasticity and RaR10** | `code/01_monthlyization/Temporal_Disaggregation_SA_BM.R`; `code/03_financial_transmission/Elasticity_RaR10.R` | `results/03_financial_transmission/Elasticity_RaR10_{SA,BM}_results.xlsx`: `Elasticidade_Principal`, `Coef_Preco_Principal`, `RaR10_BASELINE_DC`, `SAMPLE_AUDIT`, `RUN_CONFIG` | Baseline Denton–Cholette generation/revenue model; coefficient, p-value, sample N, proxy, and independent −10% generation RaR10 |
| **Table 5 — Complete physical ARDL coefficients** | `code/02_ardl/ARDL_SA.R`; `ARDL_BM.R` | `results/02_ardl/ARDL_{SA,BM}_results.xlsx`: `Coef_Robust_HC1`, `Dummies_Regime`, `Resumo_modelo` | Estimated coefficients, HC1 standard errors, p-values, dummies, published significance markings |
| **Table 6 — Physical-model diagnostics** | Same physical ARDL scripts | `results/02_ardl/ARDL_{SA,BM}_results.xlsx`: `Diagnosticos`, `VIF`, `Bounds_Test`, `Bounds_Audit`, `CUSUM_Tests`, `Validation_Assertions` | DW, BG, BP, JB, VIF, Bounds Case **2** in both public scripts, stability and validation conditions |
| **Table 7 — Complete financial model coefficients** | `code/03_financial_transmission/Elasticity_RaR10.R` | `results/03_financial_transmission/Elasticity_RaR10_{SA,BM}_results.xlsx`: `Detalhe_Multivariada`, `Elasticidade_Principal`, `Coef_Preco_Principal`, `SAMPLE_AUDIT`, `RUN_CONFIG` | OLS coefficients, Newey–West HAC standard errors and p-values, month dummies, N and dependent-variable definition |

`{SA,BM}` is **notation in this documentation**, not a literal filename; open the separate `SA` and `BM` files. `StressInd_*` means the individually named scenario worksheets in each ARDL workbook (some workbook sheet names are shortened by Excel's worksheet-name limit).

## Physical-channel input lineage

| Asset | Analysis-ready input | Code | Frozen reference | Regeneration target |
|---|---|---|---|---|
| SA | `data/02_ardl/LN_Variaveis_Ajustadas_X13_SA.xlsx` (`Ajustada`) | `code/02_ardl/ARDL_SA.R` | `results/02_ardl/ARDL_SA_results.xlsx` | `outputs/02_ardl/ARDL_SA_reproduced.xlsx`; additional files in `outputs/02_ardl/SA/` |
| BM | `data/02_ardl/LN_Variaveis_Ajustadas_X13_BM.xlsx` (`Ajustada`) | `code/02_ardl/ARDL_BM.R` | `results/02_ardl/ARDL_BM_results.xlsx` | `outputs/02_ardl/ARDL_BM_reproduced.xlsx`; additional files in `outputs/02_ardl/BM/` |

Both public ARDL scripts specify `CASE_BOUNDS = 2`, primary inference `ROBUST_MODE = "HC1"`, and non-recursive conditional distributed-lag stress tests. SA and BM have **different combined stress portfolios**. The SA temperature perturbation concerns a transformed, X-13-adjusted Celsius-based series and is not a physical climate projection.

## Monthlyization and financial-channel lineage

| Asset | Initial financial/generation input | Code | Frozen temporal-disaggregation results | Frozen financial results |
|---|---|---|---|---|
| SA | `data/01_monthlyization/ARQ_XLSX_SA.xlsx` | `code/01_monthlyization/Temporal_Disaggregation_SA_BM.R` | `results/01_monthlyization/Monthlyization_SA_results.xlsx` | `results/03_financial_transmission/Elasticity_RaR10_SA_results.xlsx` |
| BM | `data/01_monthlyization/ARQ_XLSX_BM.xlsx` | Same monthlyization script | `results/01_monthlyization/Monthlyization_BM_results.xlsx` | `results/03_financial_transmission/Elasticity_RaR10_BM_results.xlsx` |

- Quarterly/monthly reconciliation: `Recon_Receita_Vendas_DC`, `Recon_Energia_Comprada_DC`, `VALIDACAO_DC`, `RECON_SUMMARY`; repeat `_CL` and `_FERN` for the sensitivity variants. No month-by-month corporate revenue reports are claimed: the monthly flows are **estimated** by temporal disaggregation.
- Financial script inputs: **frozen** `results/01_monthlyization/Monthlyization_{SA,BM}_results.xlsx` (`Receita_Vendas_MES_DC`, `Energia_MES` for the principal specification; `_CL`/`_FERN` for sensitivity).
- Financial regeneration targets: `outputs/03_financial_transmission/Elasticity_RaR10_{SA,BM}_reproduced.xlsx`.
- Monthlyization regeneration targets: `outputs/01_monthlyization/Monthlyization_{SA,BM}_reproduced.xlsx`.
- The implicit-price control is a lagged proxy; it is not assumed exogenous.
- RaR10 is estimated under a separate **standardized 10% decline in generation**, not by applying a plant-specific hydroclimatic shock to the financial regression.

## Minimum table-level sign-off protocol

1. **Input identification:** verify plant, worksheet, 2016–2025 physical window or 2016–2024 financial window, and relevant sample sizes.
2. **Runtime trace:** record R version, packages, repository revision, script end status, generated logs and validation assertions.
3. **Source-to-reference comparison:** for each row/column in Tables 1–7, compare the published number to the named frozen workbook worksheet and, where available, the locally regenerated result. Apply the manuscript's published rounding.
4. **Model integrity:** confirm robust inference type, Bounds Case 2, primary-vs-sensitivity model, and conditional (not recursively propagated) stress interpretation.
5. **Report:** record any discrepancy with table, row, plant, reference file, worksheet, expected, observed, allowed rounding and diagnosis. Do not silently modify a validated value.

**Scope limitation:** this mapping documents computational traceability **from committed analysis-ready datasets and frozen reference results**. It does not assert full reconstruction of all X-13 transformations or institutional financial source collection from raw external systems.
