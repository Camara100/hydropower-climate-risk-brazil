# Methodology Notes

This document summarizes methodological decisions that are important for interpreting and reproducing the public pipeline. It complements the manuscript and the module-specific READMEs; it does not replace the full methodological discussion in the article.

## 1. Two-channel empirical framework

The study separates physical climate risk into two empirical channels:

1. **Hydroclimate → generation**, representing physical-operational sensitivity.
2. **Generation → revenue**, representing financial transmission.

This distinction is substantive. A plant can be highly sensitive to hydroclimatic shocks in generation while exhibiting weak direct transmission from generation to sales revenue, or vice versa.

## 2. Analysis windows

The physical ARDL inputs cover:

- **April 2016 through January 2025**
- **106 monthly observations** before model-specific lag losses.

The temporal-disaggregation target covers:

- **April 2016 through December 2024**.

The primary financial model uses:

- **102 monthly observations per plant** after construction of the lagged implicit-price proxy.

## 3. Transformations and seasonality

Physical-model variables are analyzed in transformed logarithmic form and seasonally adjusted using **X-13-ARIMA-SEATS**.

Where the underlying series contains zeros or values incompatible with a direct natural logarithm, the analysis-ready input reflects the log-compatible transformation adopted during preprocessing.

The public ARDL scripts begin from the analysis-ready `Ajustada` worksheets. They do not rerun the earlier source-data cleaning, gap imputation, log transformation, or X-13 preprocessing.

The underlying preprocessing used high-completeness series, with isolated gaps handled by seasonal interpolation or Kalman smoothing as appropriate. STL was used in the research workflow as a seasonal-adjustment robustness check, but the public final ARDL scripts reproduce the X-13 specification used in the validated main results.

## 4. Stationarity assessment

Before final ARDL interpretation, integration properties are assessed using:

- augmented Dickey–Fuller (ADF);
- KPSS;
- Zivot–Andrews (ZA), when ADF and KPSS conflict at levels.

The public ARDL pipeline uses:

- ADF with drift;
- maximum ADF lag of 4;
- AIC selection within the ADF regression;
- KPSS with `mu` and the short-lag rule;
- ZA with an intercept break;
- the lag retained by ADF passed to ZA when the ZA tie-break is required.

ZA is used as a **tie-breaking diagnostic**, not mechanically for every variable.

The pipeline contains an explicit guardrail preventing a final ARDL specification from proceeding when a selected variable is classified as I(2).

## 5. ARDL selection and inference

The physical-risk models allow a maximum of four monthly lags.

The workflow combines:

- univariate screening;
- AIC-based lag selection;
- multivariate estimation;
- a VIF guardrail;
- fixed regime controls.

Primary coefficient inference uses **HC1 heteroskedasticity-consistent covariance**.

HC1 is important because the final diagnostics show heteroskedasticity, and residual normality is imperfect—especially for BM. Robust inference therefore receives greater weight than conventional homoskedastic standard errors.

### Validated Santo Antônio specification

Selected regressors:

- `LN_Vazao_SA_X13`
- `LN_Temperatura_SA_X13`
- `LN_560002_SA_X13`
- `LN_359001_SA_X13`

Validated order:

`ARDL(3,1,1,1,4)`

Fixed regime indicators:

- `D_2017`: 1 from February 2017 onward;
- `D_2023`: 1 from June 2023 onward.

### Validated Belo Monte specification

Selected regressors:

- `LN_Vazao_BM_X13`
- `LN_153000_BM_X13`
- `LN_254010_BM_X13`
- `LN_254011_BM_X13`
- `LN_252001_BM_X13`

Validated order:

`ARDL(1,1,1,0,1,0)`

Fixed regime indicators:

- `D_2023`: 1 from October 2023 onward;
- `D_2024`: 1 from August 2024 onward.

## 6. Bounds test interpretation

The public scripts implement the ARDL **Bounds F-test, Case 2**, with the regime dummies included as fixed regressors in the aligned specification.

The Bounds test is treated as **complementary evidence of a persistent level relationship**, not as an unrestricted claim of classical cointegration.

This qualification is important because the stationarity results contain a mixture of I(0) and I(1) series and, for some specifications, stationary variables predominate. The substantive interpretation therefore emphasizes the dynamic ARDL effects, diagnostics, stability, and physical coherence rather than relying on the Bounds result alone.

## 7. ARDL diagnostics and stability

The physical pipeline reports:

- Durbin–Watson;
- Breusch–Godfrey, order 4;
- Breusch–Pagan;
- Jarque–Bera;
- VIF;
- recursive CUSUM;
- OLS-CUSUM.

Granger-causality tests with four lags are also reported as auxiliary temporal-precedence evidence. They are not interpreted as a substitute for structural causality.

## 8. Short-run, cumulative, and long-run elasticities

Because the physical variables are modeled in logarithmic form, ARDL coefficients and derived effects can be interpreted as elasticities within the adopted specification.

The public scripts distinguish:

- contemporaneous / impact effect;
- cumulative short-run sum of distributed-lag coefficients;
- long-run elasticity obtained by dividing the cumulative explanatory-variable coefficients by `1 − sum(autoregressive coefficients)`.

The public validation corrected parsing of expanded `dynlm` lag labels before these derived elasticities were frozen. The scripts include assertions that protect the validated lag structures.

## 9. Hydroclimatic stress scenarios

Stress scenarios apply standardized percentage shocks to selected explanatory variables over **2022–2024**.

Examples include:

- temperature: +10%;
- turbine flow: −10%;
- precipitation proxies: typically −10%.

The simulations are **conditional distributed-lag, nonrecursive stress scenarios**.

This means:

- observed lagged generation remains fixed;
- stressed explanatory variables change according to the scenario;
- their estimated contemporaneous and lagged coefficients transmit the shock;
- the dependent variable is not recursively fed back as a simulated future generation path.

Therefore, these exercises are not multi-period recursive forecasts. They are conditional scenario analyses designed to compare physical-operational sensitivity.

Positive simulated responses to an adverse precipitation shock should not be interpreted as proof that lower rainfall causally improves generation. Such signs can arise from the estimated conditional distributed-lag structure and must be interpreted together with the full dynamics.

## 10. Temporal disaggregation of quarterly financial flows

Quarterly financial flows are transformed to monthly frequency before the generation-to-revenue analysis.

The validated methods are:

### Baseline

**Denton–Cholette without a high-frequency indicator**

Conceptually:

`quarterly_flow ~ 1`

### Sensitivity 1

**Chow–Lin maximum likelihood**, using monthly electricity generation as the high-frequency indicator.

### Sensitivity 2

**Fernández**, also using monthly generation as the high-frequency indicator.

Automatic fallback is disabled. If a requested method fails, the script stops rather than silently replacing it with another method.

Each method must reconcile to the original quarterly totals.

Purchased-energy signs are standardized and audited before construction of net revenue. The script does not silently assume that missing purchased-energy observations equal zero.

## 11. Primary financial-transmission model

The primary model is a log-linear OLS regression:

`ln(Sales Revenue)_t = alpha + beta_E ln(Generation)_t + beta_P ln(Lagged Implicit Price Proxy)_t + month fixed effects + error_t`

The main parameter is `beta_E`, the generation-to-sales-revenue elasticity.

Inference uses **Newey–West HAC** covariance with:

- lag rule: `max(1, floor(4 × (T/100)^(2/9)))`;
- `prewhite = FALSE`;
- `adjust = TRUE`.

Month fixed effects control for residual calendar seasonality.

## 12. Lagged implicit-price proxy

The price control is constructed as follows:

1. `Sales Revenue / Generation`;
2. three-month right-aligned moving average;
3. one-month lag;
4. natural logarithm.

It is therefore a **lagged and smoothed accounting proxy based on prior revenue per unit of generation**.

It must not be interpreted as:

- an independently observed spot-market price;
- an exogenous market-price instrument;
- a causal price shock.

Its role is to control parsimoniously for the price/revenue component of the observed generation–revenue relationship.

## 13. Financial ARDL robustness model

A separate manually lagged ARDL regression with HAC inference is estimated as a robustness exercise.

Candidate grid:

- revenue lags `p = 1:2`;
- generation lags `q = 0:2`;
- implicit-price lags `r = 0:2`.

BIC selection uses a common complete-case sample across candidate models. The selected model is then re-estimated on its natural maximum complete sample.

This ARDL is **robustness only**.

It is not used as an automatic replacement for the primary `Multivariada_HAC` estimate and does not become the source of RaR10 when the primary elasticity is non-significant.

## 14. Revenue-at-Risk (RaR10)

For a standardized 10% decline in generation:

`RevenueChange_10pct = 100 × (0.90^beta_E − 1)`

The corresponding loss-oriented convention is:

`RaR10_Loss_pct = 100 × (1 − 0.90^beta_E)`

so that:

`RaR10_Loss_pct = −RevenueChange_10pct`.

The public workbooks export the numerical transformation for transparency. Substantive interpretation, however, depends on statistical support and sign.

A non-significant `beta_E` is classified as **No robust effect**, not as evidence that a generation decline produces an economic benefit.

Accordingly:

- BM exhibits a statistically supported positive generation–revenue elasticity and a material modeled revenue loss under the standardized decline.
- SA does not exhibit a statistically robust direct generation-to-revenue loss channel in the primary model.

RaR10 is a revenue-sensitivity metric. It is **not** a direct estimate of probability of default, expected credit loss, rating migration, or insolvency.

## 15. Interpretation boundary

The study is a plant-level quantitative assessment for SA and BM. Results should not be mechanically generalized to the full Brazilian hydropower fleet or to every hydropower asset in the Amazon Basin.

The principal interpretation is comparative:

**physical-operational sensitivity and financial vulnerability are related but are not equivalent.**
