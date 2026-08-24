# Data Notice

## Scope

This repository contains original R code, analysis-ready datasets, derived series, and validated reference results used for academic reproducibility.

The MIT License in the root `LICENSE` file applies **only to original source code authored for this repository**. It does not relicense third-party data, source-derived series, institutional materials, or other content for which rights remain with the original providers.

## Data provenance

The empirical analysis uses information obtained from the following public or publicly accessible institutional sources:

- **Operador Nacional do Sistema Elétrico (ONS):** electricity generation and turbine-flow data.
- **Agência Nacional de Águas e Saneamento Básico (ANA), HidroWeb:** precipitation data.
- **Brazilian Air Force / Instituto de Controle do Espaço Aéreo (ICEA), CLIMAER Surface:** air-temperature observations.
- **Instituto Nacional de Pesquisas Espaciais (INPE), Programa Queimadas:** active fire-hotspot data.
- **Santo Antônio Energia and Norte Energia S.A.:** publicly available financial statements used to construct the financial-flow inputs.

The repository does not claim ownership of the original institutional data.

## Processed and analysis-ready data

The files under `data/02_ardl/` contain analysis-ready series used by the validated ARDL models. These series may include transformations such as natural logarithms, seasonal adjustment, aggregation, and other preprocessing steps described in the repository documentation and associated manuscript.

The files under `data/01_monthlyization/` contain the financial inputs used by the temporal-disaggregation module.

Inclusion of a processed or derived series in this repository does not alter the rights, attribution requirements, or terms applicable to the underlying source data.

## ICEA / CLIMAER Surface authorization

Air-temperature observations used in the study were obtained from the publicly accessible **CLIMAER Surface** interface in the **Meteorological Products** section maintained by ICEA/DECEA.

Before public release of this repository, the author contacted ICEA to clarify whether the processed temperature series used in the econometric analysis could be made publicly available for academic reproducibility purposes.

ICEA reviewed the described use and provided written confirmation that, **for this case, publication is permitted**.

This authorization concerns the academic reproducibility use described to ICEA, including publication of processed series used in the study. It should not be interpreted as a general or transferable license for unrestricted redistribution of the full ICEA/DECEA climatological database or other ICEA products.

Users seeking to obtain, redistribute, or reuse original ICEA/DECEA data beyond the scope represented here should consult the applicable ICEA/DECEA terms and source services directly.

## Attribution and reuse

Users of this repository should:

1. cite the associated study and repository;
2. acknowledge the original institutional data providers;
3. consult the terms and conditions of the relevant provider before redistributing or reusing source-derived data outside this reproducibility context; and
4. avoid representing the repository's MIT License as applying to third-party datasets or institutional materials.

## Repository code

Original R code under `code/` is licensed under the MIT License. See [`LICENSE`](LICENSE).

## Citation

Citation metadata for the repository and associated paper are provided in [`CITATION.cff`](CITATION.cff).

## Contact

Questions regarding the reproducibility materials should be directed to the author through the contact information associated with the manuscript or repository.
