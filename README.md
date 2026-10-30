# Physical climate risk and revenue exposure in Brazilian Amazon hydropower plants

Reproducible code, analysis-ready data, and validated reference results for assessing physical climate risk and financial transmission in the Santo Antônio (SA) and Belo Monte (BM) hydropower plants in Brazil.

## Study overview

This repository supports the revised research manuscript **“Physical climate risk and revenue exposure in Brazilian Amazon hydropower plants.”** An earlier preprint, listed under *Associated research* below, retains its original title for version traceability.

The study asks a practical question:

> **How are plant-level hydropower generation responses associated with hydroclimatic conditions, and to what extent is generation statistically associated with sales revenue?**

The empirical framework separates two related but distinct channels:

1. **Hydroclimate → generation:** physical-operational sensitivity of electricity generation to hydroclimatic conditions.
2. **Generation → revenue:** an estimated statistical relationship between generated electricity and sales revenue, evaluated separately from the hydroclimatic stress tests.

The analysis combines monthly dynamic time-series models, hydroclimatic stress scenarios, temporal disaggregation of quarterly financial data, generation–revenue regressions, and a Revenue-at-Risk metric for a standardized 10% decline in generation (RaR10).

The two hydropower plants are:

- **Santo Antônio (SA)** — Madeira River, Rondônia, Brazil.
- **Belo Monte (BM)** — Xingu River, Pará, Brazil.

The physical-model sample covers **April 2016 through January 2025**. The financial temporal-disaggregation window covers **April 2016 through December 2024**; after construction of the lagged implicit-price proxy, the primary financial model uses **102 monthly observations per plant**.

## Main empirical message

The study assesses **conditional generation responses** and **revenue exposure** as separate, complementary dimensions. In particular:

- Under the *same individual* 10% reduction in turbine flow, the modeled average generation responses are **−1.69% for SA** and **−3.39% for BM**.
- The *plant-specific combined* hydroclimatic stress portfolios yield average modeled generation changes of **−14.55% for SA** and **−3.60% for BM**, but their shock compositions differ. They therefore **cannot establish a controlled ranking of overall physical vulnerability**.
- In the separate financial model, SA's generation–revenue elasticity is **−0.0418** and **not statistically significant** (p = 0.5955); BM's elasticity is **0.4412** (p = 0.0049), with a modeled **RaR10 revenue loss of approximately 4.54%** for a separately imposed, standardized **10% decline in generation**.

The SA temperature stress is an econometric perturbation of the X-13-adjusted log-transformed temperature regressor constructed from Celsius observations; **it is not an invariant physical warming scenario or a climate projection**. The financial regression uses monthly revenue series *statistically disaggregated from quarterly statements*, not independently observed monthly financial reports. RaR10 is an indicator of modeled **revenue exposure**, not credit risk, an estimate of credit losses, or a direct financial conversion of the plant-specific hydroclimatic scenarios.

These results are conditional model-based associations and sensitivities, not causal identification of commercial mechanisms. The repository enables reproduction **from the committed analysis-ready inputs and validated reference workbooks**, subject to the boundaries documented below; the scientific interpretation should be read alongside the revised manuscript.

## Repository structure

```text
hydropower-climate-risk-brazil/
│
├── README.md
├── CITATION.cff
├── LICENSE
├── DATA_NOTICE.md
├── .gitignore
│
├── code/
│   ├── 01_monthlyization/
│   │   ├── README.md
│   │   └── Temporal_Disaggregation_SA_BM.R
│   ├── 02_ardl/
│   │   ├── README.md
│   │   ├── ARDL_SA.R
│   │   └── ARDL_BM.R
│   └── 03_financial_transmission/
│       ├── README.md
│       └── Elasticity_RaR10.R
│
├── data/
│   ├── 01_monthlyization/
│   │   ├── ARQ_XLSX_SA.xlsx
│   │   └── ARQ_XLSX_BM.xlsx
│   └── 02_ardl/
│       ├── LN_Variaveis_Ajustadas_X13_SA.xlsx
│       └── LN_Variaveis_Ajustadas_X13_BM.xlsx
│
├── results/
│   ├── 01_monthlyization/
│   │   ├── Monthlyization_SA_results.xlsx
│   │   └── Monthlyization_BM_results.xlsx
│   ├── 02_ardl/
│   │   ├── ARDL_SA_results.xlsx
│   │   └── ARDL_BM_results.xlsx
│   └── 03_financial_transmission/
│       ├── Elasticity_RaR10_SA_results.xlsx
│       └── Elasticity_RaR10_BM_results.xlsx
│
└── documentation/
    ├── data_dictionary.md
    ├── methodology_notes.md
    └── reproducibility_notes.md
```

The local `outputs/` directory is created by the scripts and is intentionally ignored by Git.

## Empirical workflow

### 1. Temporal disaggregation of financial flows

Script:

```r
source("code/01_monthlyization/Temporal_Disaggregation_SA_BM.R")
```

The module converts quarterly financial flows to monthly frequency.

- **Baseline:** Denton–Cholette without a high-frequency indicator.
- **Sensitivity:** Chow–Lin maximum likelihood and Fernández using monthly generation as the high-frequency indicator.
- Automatic fallback between methods is disabled.
- Quarterly reconciliation and continuity checks are performed automatically.

See [`code/01_monthlyization/README.md`](code/01_monthlyization/README.md).

### 2. Physical-risk ARDL models

Santo Antônio:

```r
source("code/02_ardl/ARDL_SA.R")
```

Belo Monte:

```r
source("code/02_ardl/ARDL_BM.R")
```

The physical-risk workflow includes stationarity assessment, variable screening, ARDL estimation, HC1 robust inference, diagnostics, Bounds tests, CUSUM stability tests, Granger tests, elasticity calculations, and individual and combined stress scenarios.

Validated specifications:

- **SA:** `ARDL(3,1,1,1,4)`
- **BM:** `ARDL(1,1,1,0,1,0)`

See [`code/02_ardl/README.md`](code/02_ardl/README.md).

### 3. Financial transmission and RaR10

Script:

```r
source("code/03_financial_transmission/Elasticity_RaR10.R")
```

The primary financial-transmission specification estimates sales revenue as a function of generation, a lagged smoothed implicit-price proxy, and month fixed effects using Newey–West HAC inference.

The ARDL financial specification is used only as a robustness exercise and is not an automatic fallback for the primary RaR10 calculation.

See [`code/03_financial_transmission/README.md`](code/03_financial_transmission/README.md).

## Data sources

The analysis-ready data are constructed from publicly accessible information from:

- **Operador Nacional do Sistema Elétrico (ONS):** electricity generation and turbine-flow data.
- **Agência Nacional de Águas e Saneamento Básico (ANA), HidroWeb:** precipitation series.
- **Brazilian Air Force / ICEA, CLIMAER Surface:** air-temperature series.
- **Instituto Nacional de Pesquisas Espaciais (INPE), Programa Queimadas:** active fire-hotspot data.
- **Norte Energia S.A. and Santo Antônio Energia:** publicly available company financial statements.

The repository preserves the analytical variable codes used in the validated models. See [`documentation/data_dictionary.md`](documentation/data_dictionary.md) for definitions.

For data provenance, attribution, and reuse information, see [`DATA_NOTICE.md`](DATA_NOTICE.md).

## Reproducibility scope

The repository reproduces the empirical analyses from the supplied analysis-ready inputs.

For the physical-risk module, the files in `data/02_ardl/` already contain the natural-log and X-13-adjusted series used by the final ARDL models. The repository therefore begins this module from the analysis-ready workbooks rather than from the original provider downloads.

The financial module includes the temporal-disaggregation step from quarterly financial inputs and monthly generation.

Validated reference workbooks are included under `results/` so reproduced outputs can be checked against the reference analysis.

## Documentation

- [`documentation/data_dictionary.md`](documentation/data_dictionary.md) — variables, transformations, sources, and derived fields.
- [`documentation/methodology_notes.md`](documentation/methodology_notes.md) — methodological details and interpretation caveats.
- [`documentation/reproducibility_notes.md`](documentation/reproducibility_notes.md) — execution order, software requirements, expected outputs, and reproducibility checks.
- [`DATA_NOTICE.md`](DATA_NOTICE.md) — data provenance, attribution, and reuse conditions.

## Software

The analysis is implemented in **R**. Required packages are listed in each module README and checked by the scripts before estimation.

The public scripts do not install packages automatically and do not use machine-specific absolute paths.

Exact package versions are not pinned with `renv`; scripts generate or report execution metadata where applicable. See the reproducibility notes for details.

## Associated research

Preprint:

**Câmara, C. S.** *Physical climate risk and financial vulnerability in Amazon hydropower plants: evidence from hydroclimatic stress tests and Revenue-at-Risk.*

SSRN DOI: **10.2139/ssrn.7157984**

The repository should be cited together with the associated manuscript/preprint until a final journal citation is available.

Repository citation metadata are provided in [`CITATION.cff`](CITATION.cff).

## License and data-use notice

Original source code in the `code/` directory is licensed under the MIT License.

Data files, source-derived series, and third-party materials are not covered by the MIT License and remain subject to the rights, attribution requirements, and applicable terms of their original providers.

See [`LICENSE`](LICENSE) for the software license and [`DATA_NOTICE.md`](DATA_NOTICE.md) for data provenance and reuse information.

## Contact

For questions about the analysis or reproducibility materials, please use the contact information provided in the associated manuscript or the repository issue tracker.
