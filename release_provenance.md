# Versioning, integrity, and archival release policy (R6)

## Purpose and current status

The public repository should identify **one stable, auditable revision** for the accepted English manuscript *Physical climate risk and revenue exposure in Brazilian Amazon hydropower plants*. This document defines the freeze procedure, without changing any models, scripts, source spreadsheets, or validated workbooks.

**Status at preparation (30 October 2026): DOCUMENTATION UPDATE IN PROGRESS — NOT YET FROZEN.** R2 and R3 were reported as published by the author. The repository ZIP received for technical audit predates those updates, and live GitHub contents / current full Git commit SHA were not independently accessible here. **No commit hash, release tag, or DOI is asserted as already created.**

## Required order for a defensible release

1. Publish the R4 computational-environment documentation, the R5 table traceability matrix, and this R6 version policy under `documentation/`.
2. Perform the controlled local rerun of the four scientific R scripts, retaining logs and the software/environment capture in `outputs/`. Do **not** overwrite `data/` or `results/`.
3. Verify the results and table-to-workbook crosswalk. If any corrections prove necessary, approve and commit them *before* the freeze; do not silently change validated estimates.
4. Open the GitHub repository's **Commits** history (or latest commit details) and copy the **complete 40-character commit SHA** for the validated repository state. The short hash displayed beside a single old file does not prove which full revision is now being frozen.
5. Create a repository version tag or GitHub Release (suggested name `e3-submission-v1`, **only after** validation). The tag must refer to that verified commit. Tags should not be moved after public citation; if a correction is needed, publish a new version.
6. Record the exact tag, full commit SHA, validation date, and repository permanent URL in the researcher's controlled submission log. A permanent tree link has the form `https://github.com/Camara100/hydropower-climate-risk-brazil/tree/<FULL_COMMIT_SHA>`. Do not insert placeholder links in the manuscript.
7. In the E3 submission package, refer to the validated revision; if a manuscript data/code-availability statement is changed, verify it against the actual public GitHub version first.

**Why not put the current repository's own full SHA in this tracked document?** Adding or editing the SHA in a tracked file creates another commit and therefore changes the SHA again. Keep the final SHA in the external submission log / release metadata, or cite a stable release tag that points to it.

## Snapshot integrity manifest

The following SHA-256 digests were calculated from the **10 XLSX bytes in the researcher's repository ZIP used for the audit on 30 October 2026**. They are a snapshot provenance check, **not** proof of live GitHub state and not a statement that R was executed here. These digests apply only if those files have remained unchanged in the newer repo revision.

| Relative path | SHA-256 |
|---|---|
| `data/01_monthlyization/ARQ_XLSX_SA.xlsx` | `3558418253ad3ac0865a5d381f0ff9c9190c50639bef1c9644ec053b83f750ee` |
| `data/01_monthlyization/ARQ_XLSX_BM.xlsx` | `569fdad34f0b052a6023936ed15b6e62cb402a3916043189e873a7ca9bff3120` |
| `data/02_ardl/LN_Variaveis_Ajustadas_X13_SA.xlsx` | `a879c4a09961d945d4981c54cfbb7e5d48f36bd2cda56c01eeb73d5c2965a59c` |
| `data/02_ardl/LN_Variaveis_Ajustadas_X13_BM.xlsx` | `bcccc55a9e874d62c8e091eedfd0dded84323b683f309457c435f7ac173e4170` |
| `results/01_monthlyization/Monthlyization_SA_results.xlsx` | `8f5c12bce31218e1790c535206fe94fa71a7829cba826ce0f3b31b3ca9a00a42` |
| `results/01_monthlyization/Monthlyization_BM_results.xlsx` | `0b6b80970c813793e635f6a233b592ff31530f5c98cb65f14c1e39c0642bc02f` |
| `results/02_ardl/ARDL_SA_results.xlsx` | `c8f8a09ee92b28b248af2c644b38cd61c0b15b3a3d4f7f36e28eaa4d2d7d7c84` |
| `results/02_ardl/ARDL_BM_results.xlsx` | `94310ed09019c3d834aaec60fd12f506df852c5043e1918cf5d7034dd3e52c4c` |
| `results/03_financial_transmission/Elasticity_RaR10_SA_results.xlsx` | `65e8d1d85e0411e2e4386ec02d9ef0ca4e932ac24ffa9b70a336833aa5adfd5b` |
| `results/03_financial_transmission/Elasticity_RaR10_BM_results.xlsx` | `8c3527acbfb8746b6ce76fd986ef805a8e9263662c61e5c89775cffa49dcadbb` |

An independent verifier can calculate SHA-256 locally on Windows using PowerShell (replace the path and compare with the table):

```powershell
Get-FileHash -Algorithm SHA256 -Path "data/02_ardl/LN_Variaveis_Ajustadas_X13_SA.xlsx"
```

Or run the following in base R from the repository root to capture **current-file MD5** values (note: MD5 is not interchangeable with the SHA-256 values above):

```r
files <- c(
  "data/01_monthlyization/ARQ_XLSX_SA.xlsx",
  "data/01_monthlyization/ARQ_XLSX_BM.xlsx",
  "data/02_ardl/LN_Variaveis_Ajustadas_X13_SA.xlsx",
  "data/02_ardl/LN_Variaveis_Ajustadas_X13_BM.xlsx"
)
print(tools::md5sum(files))
```

## Version registration template (complete outside tracked repository)

| Field | Value/status |
|---|---|
| Manuscript | Physical climate risk and revenue exposure in Brazilian Amazon hydropower plants |
| Associated earlier SSRN preprint | DOI `10.2139/ssrn.7157984` (earlier title retained) |
| Source repository | `https://github.com/Camara100/hydropower-climate-risk-brazil` |
| Final full commit SHA | **PENDING — capture after R4/R5/R6 publication and validation** |
| Tag or GitHub Release | **PENDING — create after full validation** |
| R and package versions | **PENDING — capture in R4** |
| Four-script rerun | **PENDING** |
| Check of seven manuscript tables | **PENDING full regenerated-output comparison** |
| Approved freeze date | **PENDING** |

This file intentionally **does not claim submission readiness, archival-grade reproducibility, a frozen GitHub release, or independent execution** before these tasks are completed.
