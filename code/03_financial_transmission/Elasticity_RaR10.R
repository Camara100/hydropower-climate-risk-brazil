# =============================================================================
# Elasticity_RaR10.R
# Public reproducibility script
#
# Financial transmission and Revenue-at-Risk (RaR10)
# Plants: Santo Antonio (SA) and Belo Monte (BM)
#
# PRIMARY SPECIFICATION
#   ln(Sales Revenue)_t =
#       alpha + beta_E ln(Generation)_t
#       + beta_P ln(Lagged Implicit Price Proxy)_t
#       + month fixed effects + error_t
#
# Primary inference:
#   Newey-West HAC
#   - lag rule: max(1, floor(4 * (T/100)^(2/9)))
#   - prewhite = FALSE
#   - adjust = TRUE
#
# ROBUSTNESS
#   Manual-lag ARDL with HAC.
#   Candidate grid: p = 1:2, q = 0:2, r = 0:2.
#   BIC selection uses a common sample across candidate models.
#
# TEMPORAL-DISAGGREGATION INPUTS
#   Baseline: Receita_Vendas_MES_DC
#   Sensitivity: Receita_Vendas_MES_CL and Receita_Vendas_MES_FERN
#   Generation: Energia_MES
#
# REVENUE-AT-RISK CONVENTIONS
#   RevenueChange_10pct = 100 * (0.90^beta_E - 1)
#   RaR10_Loss_pct      = 100 * (1 - 0.90^beta_E)
#
# IMPORTANT
#   - Multivariada_HAC is the primary financial-transmission model.
#   - ARDL_HAC is robustness only and is never used as an automatic RaR10
#     fallback.
#   - A non-significant beta_E is classified as "No robust effect".
#   - The implicit-price control is a lagged, smoothed proxy based on prior
#     sales revenue per unit of generation; it is not treated as an exogenous
#     market price.
#   - Package installation is not performed automatically.
#
# Run this script from the repository root.
# Inputs are read from results/01_monthlyization/.
# Reproduced outputs are written to outputs/03_financial_transmission/.
# =============================================================================

run_financial_validation <- function(
    input_file,
    plant,
    output_dir,
    run_tag = "200826",
    start_date = as.Date("2016-04-01"),
    end_date   = as.Date("2024-12-01"),
    revenue_sheets = c(
      DC   = "Receita_Vendas_MES_DC",
      CL   = "Receita_Vendas_MES_CL",
      FERN = "Receita_Vendas_MES_FERN"
    ),
    energy_sheet = "Energia_MES",
    alpha = 0.05,
    p_grid = 1:2,
    q_grid = 0:2,
    r_grid = 0:2
) {

  # ---------------------------------------------------------------------------
  # Packages
  # ---------------------------------------------------------------------------
  required_packages <- c(
    "readxl", "dplyr", "purrr", "lmtest", "sandwich", "zoo", "openxlsx"
  )

  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(missing_packages) > 0L) {
    stop(
      "Missing required packages: ",
      paste(missing_packages, collapse = ", "),
      ". Install them before running this validation.",
      call. = FALSE
    )
  }

  plant <- toupper(trimws(plant))
  stopifnot(plant %in% c("SA", "BM"))

  if (!file.exists(input_file)) {
    stop("Input workbook not found: ", input_file, call. = FALSE)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  output_file <- file.path(
    output_dir,
    paste0("Elasticity_RaR10_", plant, "_reproduced.xlsx")
  )
  log_file <- file.path(
    output_dir,
    paste0("Elasticity_RaR10_", plant, "_reproduced.log")
  )
  session_file <- file.path(
    output_dir,
    paste0("sessionInfo_Elasticity_RaR10_", plant, "_reproduced.txt")
  )

  if (file.exists(output_file)) {
    stop(
      "Reproduced output already exists and will not be overwritten: ",
      output_file,
      call. = FALSE
    )
  }

  log_con <- file(log_file, open = "wt", encoding = "UTF-8")
  sink(log_con, split = TRUE)
  on.exit({
    if (sink.number() > 0L) try(sink(type = "output"), silent = TRUE)
    try(if (isOpen(log_con)) close(log_con), silent = TRUE)
  }, add = TRUE)

  cat("============================================================\n")
  cat("FINAL financial-transmission validation\n")
  cat("Plant:", plant, "\n")
  cat("Run tag:", run_tag, "\n")
  cat("Input:", gsub("\\\\", "/", input_file), "\n")
  cat("MD5:", unname(tools::md5sum(input_file)), "\n")
  cat("Window:", as.character(start_date), "to", as.character(end_date), "\n")
  cat("Primary model: Multivariada_HAC\n")
  cat("ARDL role: robustness only; no fallback for RaR10\n")
  cat("============================================================\n\n")

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  stop_if <- function(condition, message) {
    if (isTRUE(condition)) stop(message, call. = FALSE)
  }

  clean_names_ <- function(x) {
    x <- gsub("\\s+", "_", trimws(x))
    x <- iconv(x, to = "ASCII//TRANSLIT")
    tolower(x)
  }

  mk_log <- function(x) {
    ifelse(is.finite(x) & x > 0, log(x), NA_real_)
  }

  nw_lag <- function(Tn) {
    max(1L, floor(4 * (Tn / 100)^(2 / 9)))
  }

  expected_months <- seq.Date(start_date, end_date, by = "month")

  normalize_date_column <- function(df, object_name) {
    nr <- names(df)
    nrc <- clean_names_(nr)

    data_col <- if ("data" %in% nrc) nr[which(nrc == "data")[1]] else NULL

    if (!is.null(data_col)) {
      df$Data <- as.Date(df[[data_col]])
    } else if (all(c("ano", "mes") %in% nrc)) {
      ano_col <- nr[which(nrc == "ano")[1]]
      mes_col <- nr[which(nrc == "mes")[1]]
      df$Data <- as.Date(
        sprintf(
          "%04d-%02d-01",
          as.integer(df[[ano_col]]),
          as.integer(df[[mes_col]])
        )
      )
    } else {
      stop(
        object_name,
        ": a Data column or the pair Ano/Mes is required.",
        call. = FALSE
      )
    }

    df
  }

  pick_revenue_value <- function(df) {
    preferred <- c("valor_mensal", "receita_vendas", "valor", "rv")
    nx <- clean_names_(names(df))

    for (p in preferred) {
      j <- which(nx == p)
      if (length(j)) return(names(df)[j[1]])
    }

    nums <- names(df)[vapply(df, is.numeric, logical(1))]
    if (length(nums)) return(nums[length(nums)])

    stop("Sales Revenue: no numeric value column found.", call. = FALSE)
  }

  pick_energy_value <- function(df) {
    candidates <- c(
      "energia_base_mwh", "energia", "valor_mensal",
      "mwh", "valor", "ebase", "eb"
    )
    nx <- clean_names_(names(df))

    for (p in candidates) {
      j <- which(nx == p)
      if (length(j)) return(names(df)[j[1]])
    }

    stop(
      "Energy: no expected energy column found (e.g. Energia_Base_MWh).",
      call. = FALSE
    )
  }

  normalize_revenue <- function(raw, sheet_name) {
    raw <- normalize_date_column(raw, paste0("Revenue sheet ", sheet_name))
    nr <- names(raw)
    nrc <- clean_names_(nr)

    usina_col <- if ("usina" %in% nrc) {
      nr[which(nrc == "usina")[1]]
    } else {
      stop("Revenue sheet ", sheet_name, ": column 'Usina' not found.", call. = FALSE)
    }

    value_col <- pick_revenue_value(raw)

    out <- raw |>
      dplyr::transmute(
        Usina = toupper(trimws(as.character(.data[[usina_col]]))),
        Data = as.Date(Data),
        Valor_RV = as.numeric(.data[[value_col]])
      ) |>
      dplyr::filter(
        Usina == plant,
        Data >= start_date,
        Data <= end_date
      ) |>
      dplyr::arrange(Data)

    stop_if(nrow(out) == 0L, paste0("No revenue data for ", plant, " in ", sheet_name, "."))
    stop_if(anyDuplicated(out[c("Usina", "Data")]) > 0L,
            paste0("Duplicated Usina/Data keys in ", sheet_name, "."))
    stop_if(any(!is.finite(out$Valor_RV)),
            paste0("Non-finite Sales Revenue values in ", sheet_name, "."))
    stop_if(any(out$Valor_RV <= 0),
            paste0("Non-positive Sales Revenue values in ", sheet_name, "."))

    stop_if(
      !identical(out$Data, expected_months),
      paste0(
        "Revenue monthly sequence is incomplete or misaligned in ",
        sheet_name, "."
      )
    )

    out
  }

  normalize_energy <- function(raw) {
    raw <- normalize_date_column(raw, "Energy sheet")
    ne <- names(raw)
    nec <- clean_names_(ne)

    usina_col <- if ("usina" %in% nec) {
      ne[which(nec == "usina")[1]]
    } else {
      stop("Energy sheet: column 'Usina' not found.", call. = FALSE)
    }

    energy_col <- pick_energy_value(raw)

    out <- raw |>
      dplyr::transmute(
        Usina = toupper(trimws(as.character(.data[[usina_col]]))),
        Data = as.Date(Data),
        Energia_Base = as.numeric(.data[[energy_col]])
      ) |>
      dplyr::filter(
        Usina == plant,
        Data >= start_date,
        Data <= end_date
      ) |>
      dplyr::arrange(Data)

    stop_if(nrow(out) == 0L, paste0("No energy data for ", plant, "."))
    stop_if(anyDuplicated(out[c("Usina", "Data")]) > 0L,
            "Duplicated Usina/Data keys in Energia_MES.")
    stop_if(any(!is.finite(out$Energia_Base)),
            "Non-finite generation values in Energia_MES.")
    stop_if(any(out$Energia_Base <= 0),
            "Non-positive generation values found; log model cannot proceed.")

    stop_if(
      !identical(out$Data, expected_months),
      "Energy monthly sequence is incomplete or misaligned."
    )

    out
  }

  # ---------------------------------------------------------------------------
  # Read inputs and verify required sheets
  # ---------------------------------------------------------------------------
  sheets <- readxl::excel_sheets(input_file)

  required_sheets <- unique(c(unname(revenue_sheets), energy_sheet))
  missing_sheets <- setdiff(required_sheets, sheets)

  stop_if(
    length(missing_sheets) > 0L,
    paste0("Missing required sheet(s): ", paste(missing_sheets, collapse = ", "))
  )

  en <- normalize_energy(readxl::read_excel(input_file, sheet = energy_sheet))

  revenue_by_method <- lapply(names(revenue_sheets), function(tag) {
    normalize_revenue(
      readxl::read_excel(input_file, sheet = unname(revenue_sheets[[tag]])),
      sheet_name = unname(revenue_sheets[[tag]])
    )
  })
  names(revenue_by_method) <- names(revenue_sheets)

  # ---------------------------------------------------------------------------
  # Workbook helper
  # ---------------------------------------------------------------------------
  wb <- openxlsx::createWorkbook()
  used_sheets <- character()

  add_sheet <- function(sheet, data) {
    s <- substr(gsub("[\\[\\]\\*\\?/\\\\:]", "_", sheet), 1L, 31L)

    if (s %in% used_sheets) {
      base_s <- substr(s, 1L, 27L)
      i <- 1L
      while (paste0(base_s, "_", i) %in% used_sheets) i <- i + 1L
      s <- paste0(base_s, "_", i)
    }

    used_sheets <<- c(used_sheets, s)
    openxlsx::addWorksheet(wb, s)
    openxlsx::writeData(wb, s, as.data.frame(data))
    invisible(s)
  }

  # ---------------------------------------------------------------------------
  # Run configuration / input audit
  # ---------------------------------------------------------------------------
  input_audit <- data.frame(
    Plant = plant,
    Input_File = gsub("\\\\", "/", input_file),
    MD5 = unname(tools::md5sum(input_file)),
    N_Energy = nrow(en),
    Energy_Start = as.character(min(en$Data)),
    Energy_End = as.character(max(en$Data)),
    N_Energy_NonPositive = sum(en$Energia_Base <= 0),
    stringsAsFactors = FALSE
  )

  run_config <- data.frame(
    Item = c(
      "Run_Tag",
      "Target_Start",
      "Target_End",
      "Primary_Model",
      "Primary_Formula",
      "Price_Proxy",
      "HAC_Lag_Rule",
      "HAC_Prewhite",
      "HAC_Adjust",
      "ARDL_Role",
      "ARDL_p_grid",
      "ARDL_q_grid",
      "ARDL_r_grid",
      "ARDL_BIC_Sample",
      "RaR10_Primary_Source",
      "RevenueChange_Formula",
      "RaR10_Loss_Formula",
      "Significance_Alpha",
      "sandwich_Version",
      "lmtest_Version"
    ),
    Value = c(
      run_tag,
      as.character(start_date),
      as.character(end_date),
      "Multivariada_HAC",
      "ln_RV ~ ln_E + ln_P + month fixed effects",
      "ln of lagged 3-month moving average of prior Sales Revenue / Generation",
      "max(1, floor(4 * (T/100)^(2/9)))",
      "FALSE",
      "TRUE",
      "Robustness only; never automatic fallback for RaR10",
      paste(p_grid, collapse = ","),
      paste(q_grid, collapse = ","),
      paste(r_grid, collapse = ","),
      "Common complete-case sample across full candidate lag grid",
      "Multivariada_HAC only",
      "100 * (0.90^Beta - 1)",
      "100 * (1 - 0.90^Beta)",
      as.character(alpha),
      as.character(utils::packageVersion("sandwich")),
      as.character(utils::packageVersion("lmtest"))
    ),
    stringsAsFactors = FALSE
  )

  add_sheet("RUN_CONFIG", run_config)
  add_sheet("INPUT_AUDIT", input_audit)

  # ---------------------------------------------------------------------------
  # Exact 1:1 join + model-data construction
  # ---------------------------------------------------------------------------
  build_model_data <- function(rv, tag) {

    rv_only <- dplyr::anti_join(rv, en, by = c("Usina", "Data"))
    en_only <- dplyr::anti_join(en, rv, by = c("Usina", "Data"))

    join_audit <- data.frame(
      Plant = plant,
      Method = tag,
      N_Revenue = nrow(rv),
      N_Energy = nrow(en),
      N_Revenue_Without_Energy = nrow(rv_only),
      N_Energy_Without_Revenue = nrow(en_only),
      Exact_OneToOne_Match =
        nrow(rv) == nrow(en) &&
        nrow(rv_only) == 0L &&
        nrow(en_only) == 0L,
      stringsAsFactors = FALSE
    )

    stop_if(
      !join_audit$Exact_OneToOne_Match[1],
      paste0("Revenue/Energy key mismatch for method ", tag, ".")
    )

    dd <- dplyr::left_join(rv, en, by = c("Usina", "Data")) |>
      dplyr::arrange(Data)

    # No artificial floor: positivity was already validated explicitly.
    dd <- dd |>
      dplyr::mutate(
        Preco_impl_bruto = Valor_RV / Energia_Base
      ) |>
      dplyr::group_by(Usina) |>
      dplyr::arrange(Data, .by_group = TRUE) |>
      dplyr::mutate(
        P_ma3 = zoo::rollmean(
          Preco_impl_bruto,
          k = 3,
          align = "right",
          fill = NA_real_
        ),
        P_ma3_L1 = dplyr::lag(P_ma3, 1L),
        ln_RV = mk_log(Valor_RV),
        ln_E = mk_log(Energia_Base),
        ln_P = mk_log(P_ma3_L1)
      ) |>
      dplyr::ungroup() |>
      dplyr::mutate(
        Mes = as.integer(format(Data, "%m")),
        D_m1 = ifelse(Mes == 1L, 1L, 0L),
        D_m2 = ifelse(Mes == 2L, 1L, 0L),
        D_m3 = ifelse(Mes == 3L, 1L, 0L),
        D_m4 = ifelse(Mes == 4L, 1L, 0L),
        D_m5 = ifelse(Mes == 5L, 1L, 0L),
        D_m6 = ifelse(Mes == 6L, 1L, 0L),
        D_m7 = ifelse(Mes == 7L, 1L, 0L),
        D_m8 = ifelse(Mes == 8L, 1L, 0L),
        D_m9 = ifelse(Mes == 9L, 1L, 0L),
        D_m10 = ifelse(Mes == 10L, 1L, 0L),
        D_m11 = ifelse(Mes == 11L, 1L, 0L)
      )

    price_audit <- data.frame(
      Plant = plant,
      Method = tag,
      N_Total = nrow(dd),
      N_Raw_Price_Valid = sum(is.finite(dd$Preco_impl_bruto) & dd$Preco_impl_bruto > 0),
      N_MA3_Valid = sum(is.finite(dd$P_ma3) & dd$P_ma3 > 0),
      N_Lagged_MA3_Valid = sum(is.finite(dd$P_ma3_L1) & dd$P_ma3_L1 > 0),
      N_lnP_Valid = sum(is.finite(dd$ln_P)),
      First_lnP_Date = if (any(is.finite(dd$ln_P))) {
        as.character(min(dd$Data[is.finite(dd$ln_P)]))
      } else NA_character_,
      stringsAsFactors = FALSE
    )

    list(data = dd, join_audit = join_audit, price_audit = price_audit)
  }

  # ---------------------------------------------------------------------------
  # Primary multivariate OLS + Newey-West HAC
  # ---------------------------------------------------------------------------
  fit_multivar_HAC <- function(dd, tag) {

    fml <- ln_RV ~ ln_E + ln_P +
      D_m1 + D_m2 + D_m3 + D_m4 + D_m5 + D_m6 +
      D_m7 + D_m8 + D_m9 + D_m10 + D_m11

    vars <- all.vars(fml)

    model_df <- dd |>
      dplyr::select(Data, dplyr::all_of(vars))

    model_df <- model_df[
      stats::complete.cases(model_df[, vars, drop = FALSE]),
      ,
      drop = FALSE
    ]

    stop_if(nrow(model_df) < 24L, paste0("Primary model sample too short for ", tag, "."))

    fit <- stats::lm(fml, data = model_df)
    L <- nw_lag(nrow(model_df))

    vc_hac <- sandwich::NeweyWest(
      fit,
      lag = L,
      prewhite = FALSE,
      adjust = TRUE
    )

    ct <- lmtest::coeftest(fit, vcov. = vc_hac)

    detail <- data.frame(
      Plant = plant,
      Method = tag,
      Model = "Multivariada_HAC",
      Term = rownames(ct),
      Estimate = ct[, 1],
      SE_HAC = ct[, 2],
      Statistic = ct[, 3],
      Test = "t",
      df_residual = stats::df.residual(fit),
      p_value = ct[, 4],
      R2 = summary(fit)$r.squared,
      Adjusted_R2 = summary(fit)$adj.r.squared,
      N = nrow(model_df),
      L_NW = L,
      Sample_Start = as.character(min(model_df$Data)),
      Sample_End = as.character(max(model_df$Data)),
      stringsAsFactors = FALSE,
      row.names = NULL
    )

    list(
      fit = fit,
      vcov_hac = vc_hac,
      detail = detail,
      model_df = model_df
    )
  }

  # ---------------------------------------------------------------------------
  # ARDL helpers
  # ---------------------------------------------------------------------------
  mk_lag <- function(x, k) {
    if (k == 0L) return(x)
    c(rep(NA_real_, k), head(x, -k))
  }

  prepare_ardl_lags <- function(dd) {
    z <- dd |>
      dplyr::arrange(Data) |>
      dplyr::select(
        Data, ln_RV, ln_E, ln_P,
        D_m1, D_m2, D_m3, D_m4, D_m5, D_m6,
        D_m7, D_m8, D_m9, D_m10, D_m11
      ) |>
      as.data.frame()

    for (L in seq_len(max(p_grid))) {
      z[[paste0("L_ln_RV_", L)]] <- mk_lag(z$ln_RV, L)
    }

    for (L in 0:max(q_grid)) {
      z[[paste0("L_ln_E_", L)]] <- mk_lag(z$ln_E, L)
    }

    for (L in 0:max(r_grid)) {
      z[[paste0("L_ln_P_", L)]] <- mk_lag(z$ln_P, L)
    }

    z
  }

  ardl_rhs <- function(p, q, r) {
    c(
      paste0("D_m", 1:11),
      paste0("L_ln_RV_", 1:p),
      paste0("L_ln_E_", 0:q),
      paste0("L_ln_P_", 0:r)
    )
  }

  fit_ardl_HAC <- function(dd, tag, verbose = TRUE) {

    z <- prepare_ardl_lags(dd)

    all_candidate_cols <- c(
      "ln_RV",
      paste0("D_m", 1:11),
      paste0("L_ln_RV_", seq_len(max(p_grid))),
      paste0("L_ln_E_", 0:max(q_grid)),
      paste0("L_ln_P_", 0:max(r_grid))
    )

    common_ok <- stats::complete.cases(z[, all_candidate_cols, drop = FALSE])
    common_df <- z[common_ok, , drop = FALSE]

    stop_if(
      nrow(common_df) < 24L,
      paste0("ARDL common selection sample is too short for ", tag, ".")
    )

    grid_rows <- list()
    best_bic <- Inf
    best_spec <- NULL

    idx <- 0L

    for (p in p_grid) for (q in q_grid) for (r in r_grid) {
      idx <- idx + 1L

      rhs <- ardl_rhs(p, q, r)
      fml_txt <- paste("ln_RV ~", paste(rhs, collapse = " + "))
      fml <- stats::as.formula(fml_txt)

      fit_sel <- try(stats::lm(fml, data = common_df), silent = TRUE)

      if (inherits(fit_sel, "try-error")) {
        grid_rows[[idx]] <- data.frame(
          Plant = plant, Method = tag,
          p = p, q = q, r = r,
          N_Common = nrow(common_df),
          K = NA_integer_,
          BIC = NA_real_,
          Valid = FALSE,
          Formula = fml_txt,
          stringsAsFactors = FALSE
        )
        next
      }

      k <- length(stats::coef(fit_sel))
      bic <- stats::BIC(fit_sel)

      valid <- is.finite(bic) && nrow(common_df) > (k + 3L)

      grid_rows[[idx]] <- data.frame(
        Plant = plant, Method = tag,
        p = p, q = q, r = r,
        N_Common = nrow(common_df),
        K = k,
        BIC = bic,
        Valid = valid,
        Formula = fml_txt,
        stringsAsFactors = FALSE
      )

      if (valid && bic < best_bic) {
        best_bic <- bic
        best_spec <- list(p = p, q = q, r = r, formula = fml, formula_txt = fml_txt)
      }
    }

    grid <- dplyr::bind_rows(grid_rows) |>
      dplyr::arrange(BIC)

    stop_if(is.null(best_spec), paste0("No valid ARDL specification for ", tag, "."))

    # Re-estimate selected specification on its natural maximum complete sample.
    rhs_best <- ardl_rhs(best_spec$p, best_spec$q, best_spec$r)
    selected_vars <- c("ln_RV", rhs_best)

    final_ok <- stats::complete.cases(z[, selected_vars, drop = FALSE])
    final_df <- z[final_ok, c("Data", selected_vars), drop = FALSE]

    final_fit <- stats::lm(best_spec$formula, data = final_df)

    Tn_eff <- stats::nobs(final_fit)
    L <- nw_lag(Tn_eff)

    vc_hac <- sandwich::NeweyWest(
      final_fit,
      lag = L,
      prewhite = FALSE,
      adjust = TRUE
    )

    ct <- lmtest::coeftest(final_fit, vcov. = vc_hac)

    detail <- data.frame(
      Plant = plant,
      Method = tag,
      Model = "ARDL_HAC",
      Term = rownames(ct),
      Estimate = ct[, 1],
      SE_HAC = ct[, 2],
      Statistic = ct[, 3],
      Test = "t",
      df_residual = stats::df.residual(final_fit),
      p_value = ct[, 4],
      R2 = summary(final_fit)$r.squared,
      Adjusted_R2 = summary(final_fit)$adj.r.squared,
      N = Tn_eff,
      L_NW = L,
      p = best_spec$p,
      q = best_spec$q,
      r = best_spec$r,
      BIC_Selection = best_bic,
      N_BIC_Common = nrow(common_df),
      Sample_Start = as.character(min(final_df$Data)),
      Sample_End = as.character(max(final_df$Data)),
      Formula = best_spec$formula_txt,
      stringsAsFactors = FALSE,
      row.names = NULL
    )

    if (isTRUE(verbose)) {
      message(
        sprintf(
          "[ARDL %s %s] selected p=%d q=%d r=%d | N common=%d | N final=%d",
          plant, tag,
          best_spec$p, best_spec$q, best_spec$r,
          nrow(common_df), Tn_eff
        )
      )
    }

    # Contemporaneous energy coefficient.
    sr_term <- "L_ln_E_0"
    stop_if(
      !sr_term %in% names(stats::coef(final_fit)),
      paste0("Selected ARDL does not contain ", sr_term, " for ", tag, ".")
    )

    j_sr <- which(rownames(ct) == sr_term)

    short_run <- data.frame(
      Plant = plant,
      Method = tag,
      Model = "ARDL_HAC",
      Effect = "Contemporaneous_Energy_Coefficient",
      Term = sr_term,
      Estimate = ct[j_sr, 1],
      SE_HAC = ct[j_sr, 2],
      Statistic = ct[j_sr, 3],
      Test = "t",
      df_residual = stats::df.residual(final_fit),
      p_value = ct[j_sr, 4],
      N = Tn_eff,
      p = best_spec$p,
      q = best_spec$q,
      r = best_spec$r,
      stringsAsFactors = FALSE
    )

    # Long-run energy elasticity with delta-method HAC standard error.
    coef_vec <- stats::coef(final_fit)
    phi_terms <- paste0("L_ln_RV_", 1:best_spec$p)
    e_terms <- paste0("L_ln_E_", 0:best_spec$q)

    phi_sum <- sum(coef_vec[phi_terms])
    beta_e_sum <- sum(coef_vec[e_terms])
    denom <- 1 - phi_sum

    lr_est <- beta_e_sum / denom

    grad <- rep(0, length(coef_vec))
    names(grad) <- names(coef_vec)

    grad[e_terms] <- 1 / denom
    grad[phi_terms] <- beta_e_sum / (denom^2)

    lr_var <- as.numeric(t(grad) %*% vc_hac %*% grad)
    lr_se <- if (is.finite(lr_var) && lr_var >= 0) sqrt(lr_var) else NA_real_
    lr_stat <- lr_est / lr_se
    lr_p <- if (is.finite(lr_stat)) {
      2 * stats::pt(
        abs(lr_stat),
        df = stats::df.residual(final_fit),
        lower.tail = FALSE
      )
    } else NA_real_

    long_run <- data.frame(
      Plant = plant,
      Method = tag,
      Model = "ARDL_HAC",
      Effect = "Long_Run_Energy_Elasticity",
      Estimate = lr_est,
      SE_HAC_Delta = lr_se,
      Statistic = lr_stat,
      Test = "t (delta method)",
      df_residual = stats::df.residual(final_fit),
      p_value = lr_p,
      Phi_Sum = phi_sum,
      Energy_Coefficient_Sum = beta_e_sum,
      Denominator = denom,
      N = Tn_eff,
      p = best_spec$p,
      q = best_spec$q,
      r = best_spec$r,
      stringsAsFactors = FALSE
    )

    list(
      fit = final_fit,
      vcov_hac = vc_hac,
      detail = detail,
      short_run = short_run,
      long_run = long_run,
      grid = grid,
      common_n = nrow(common_df),
      final_n = Tn_eff
    )
  }

  # ---------------------------------------------------------------------------
  # Estimate all temporal-disaggregation methods
  # ---------------------------------------------------------------------------
  model_data <- list()
  join_audits <- list()
  price_audits <- list()
  multivar_results <- list()
  ardl_results <- list()

  for (tag in names(revenue_by_method)) {

    cat("\n------------------------------------------------------------\n")
    cat("Temporal-disaggregation method:", tag, "\n")
    cat("------------------------------------------------------------\n")

    built <- build_model_data(revenue_by_method[[tag]], tag)

    model_data[[tag]] <- built$data
    join_audits[[tag]] <- built$join_audit
    price_audits[[tag]] <- built$price_audit

    multivar_results[[tag]] <- fit_multivar_HAC(built$data, tag)
    ardl_results[[tag]] <- fit_ardl_HAC(built$data, tag, verbose = TRUE)

    add_sheet(
      paste0("MODEL_DATA_", tag),
      built$data |>
        dplyr::select(
          Usina, Data, Valor_RV, Energia_Base,
          Preco_impl_bruto, P_ma3, P_ma3_L1,
          ln_RV, ln_E, ln_P, Mes
        )
    )
  }

  join_audit_all <- dplyr::bind_rows(join_audits)
  price_audit_all <- dplyr::bind_rows(price_audits)

  detail_multivar <- dplyr::bind_rows(
    lapply(multivar_results, function(x) x$detail)
  )

  detail_ardl <- dplyr::bind_rows(
    lapply(ardl_results, function(x) x$detail)
  )

  ardl_short_run <- dplyr::bind_rows(
    lapply(ardl_results, function(x) x$short_run)
  )

  ardl_long_run <- dplyr::bind_rows(
    lapply(ardl_results, function(x) x$long_run)
  )

  ardl_bic_grid <- dplyr::bind_rows(
    lapply(ardl_results, function(x) x$grid)
  )

  # ---------------------------------------------------------------------------
  # Primary financial elasticity by temporal-disaggregation method
  # ---------------------------------------------------------------------------
  primary_elasticity <- detail_multivar |>
    dplyr::filter(Term == "ln_E") |>
    dplyr::transmute(
      Plant,
      Method,
      Model,
      Term,
      Beta = Estimate,
      SE = SE_HAC,
      Statistic,
      Test,
      df_residual,
      p_value,
      R2,
      Adjusted_R2,
      N,
      L_NW,
      Sample_Start,
      Sample_End
    ) |>
    dplyr::arrange(factor(Method, levels = c("DC", "CL", "FERN")))

  stop_if(
    nrow(primary_elasticity) != length(revenue_sheets),
    "Primary ln_E coefficient was not recovered for all temporal-disaggregation methods."
  )

  # Price coefficient.
  price_elasticity <- detail_multivar |>
    dplyr::filter(Term == "ln_P") |>
    dplyr::transmute(
      Plant,
      Method,
      Model,
      Term,
      Beta = Estimate,
      SE = SE_HAC,
      Statistic,
      Test,
      df_residual,
      p_value,
      R2,
      N,
      L_NW
    ) |>
    dplyr::arrange(factor(Method, levels = c("DC", "CL", "FERN")))

  # ---------------------------------------------------------------------------
  # RaR10: primary model only, with both sign conventions
  # ---------------------------------------------------------------------------
  rar_primary <- primary_elasticity |>
    dplyr::mutate(
      Significant_5pct = is.finite(p_value) & p_value < alpha,
      RevenueChange_10pct = 100 * (0.90^Beta - 1),
      RaR10_Loss_pct = 100 * (1 - 0.90^Beta),
      Effect_Interpretation = dplyr::case_when(
        !Significant_5pct ~ "No robust effect",
        RaR10_Loss_pct > 0 ~ "Statistically significant revenue loss",
        RaR10_Loss_pct < 0 ~ "Statistically significant revenue increase",
        TRUE ~ "No revenue change"
      ),
      Risk_Class = dplyr::case_when(
        !Significant_5pct ~ "Not classified (effect not statistically significant)",
        RaR10_Loss_pct <= 0 ~ "No loss under the standardized scenario",
        RaR10_Loss_pct < 2 ~ "Low loss (<2%)",
        RaR10_Loss_pct < 5 ~ "Moderate loss (2-5%)",
        TRUE ~ "High loss (>=5%)"
      )
    ) |>
    dplyr::select(
      Plant, Method, Model,
      Beta, SE, Statistic, p_value,
      Significant_5pct,
      RevenueChange_10pct,
      RaR10_Loss_pct,
      Effect_Interpretation,
      Risk_Class,
      R2, N, L_NW
    ) |>
    dplyr::arrange(factor(Method, levels = c("DC", "CL", "FERN")))

  # Explicit baseline table: DC + primary model only.
  rar10_baseline <- rar_primary |>
    dplyr::filter(Method == "DC", Model == "Multivariada_HAC")

  stop_if(
    nrow(rar10_baseline) != 1L,
    "FINAL validation failed: a unique DC / Multivariada_HAC baseline was not found for RaR10."
  )

  # ---------------------------------------------------------------------------
  # Sensitivity summary against DC primary estimate
  # ---------------------------------------------------------------------------
  dc_beta <- rar_primary$Beta[rar_primary$Method == "DC"]
  dc_loss <- rar_primary$RaR10_Loss_pct[rar_primary$Method == "DC"]

  sensitivity_primary <- rar_primary |>
    dplyr::mutate(
      Beta_Difference_vs_DC = Beta - dc_beta,
      RaR10_Loss_Difference_pp_vs_DC = RaR10_Loss_pct - dc_loss
    ) |>
    dplyr::select(
      Plant, Method, Beta, SE, p_value,
      Significant_5pct,
      RevenueChange_10pct,
      RaR10_Loss_pct,
      Beta_Difference_vs_DC,
      RaR10_Loss_Difference_pp_vs_DC,
      Effect_Interpretation
    )

  # ---------------------------------------------------------------------------
  # Sample audit
  # ---------------------------------------------------------------------------
  sample_audit <- dplyr::bind_rows(
    lapply(names(model_data), function(tag) {
      dd <- model_data[[tag]]
      pfit <- multivar_results[[tag]]
      afit <- ardl_results[[tag]]

      data.frame(
        Plant = plant,
        Method = tag,
        N_Input = nrow(dd),
        N_Primary = nrow(pfit$model_df),
        Primary_Start = as.character(min(pfit$model_df$Data)),
        Primary_End = as.character(max(pfit$model_df$Data)),
        N_ARDL_BIC_Common = afit$common_n,
        N_ARDL_Final = afit$final_n,
        stringsAsFactors = FALSE
      )
    })
  )

  # ---------------------------------------------------------------------------
  # Output sheets
  # ---------------------------------------------------------------------------
  add_sheet("JOIN_AUDIT", join_audit_all)
  add_sheet("PRICE_PROXY_AUDIT", price_audit_all)
  add_sheet("SAMPLE_AUDIT", sample_audit)

  add_sheet("Elasticidade_Principal", primary_elasticity)
  add_sheet("Coef_Preco_Principal", price_elasticity)
  add_sheet("Detalhe_Multivariada", detail_multivar)

  add_sheet("ARDL_Contemporaneo", ardl_short_run)
  add_sheet("ARDL_Long_Run", ardl_long_run)
  add_sheet("Detalhe_ARDL", detail_ardl)
  add_sheet("ARDL_BIC_GRID", ardl_bic_grid)

  add_sheet("RaR10_BASELINE_DC", rar10_baseline)
  add_sheet("RaR10_TODOS_METODOS", rar_primary)
  add_sheet("SENSIBILIDADE_RaR10", sensitivity_primary)

  # ---------------------------------------------------------------------------
  # Final validation assertions
  # ---------------------------------------------------------------------------
  stop_if(any(!join_audit_all$Exact_OneToOne_Match),
          "FINAL validation failed: at least one revenue/energy join is not 1:1.")

  stop_if(any(sample_audit$N_Input != length(expected_months)),
          "FINAL validation failed: unexpected input sample length.")

  stop_if(any(primary_elasticity$N < 24L),
          "FINAL validation failed: primary estimation sample too short.")

  stop_if(any(!is.finite(primary_elasticity$Beta)),
          "FINAL validation failed: non-finite primary elasticity.")

  # ---------------------------------------------------------------------------
  # Save
  # ---------------------------------------------------------------------------
  openxlsx::saveWorkbook(wb, output_file, overwrite = FALSE)
  capture.output(utils::sessionInfo(), file = session_file)

  cat("\n============================================================\n")
  cat("FINAL financial validation completed successfully.\n")
  cat("Output:", normalizePath(output_file, winslash = "/", mustWork = TRUE), "\n")
  cat("Log:", normalizePath(log_file, winslash = "/", mustWork = TRUE), "\n")
  cat("============================================================\n\n")

  cat("Primary elasticity / RaR10 summary:\n")
  print(rar_primary)

  invisible(list(
    plant = plant,
    input_file = input_file,
    output_file = output_file,
    log_file = log_file,
    session_file = session_file,
    primary_elasticity = primary_elasticity,
    rar10_baseline = rar10_baseline,
    rar10_all_methods = rar_primary,
    sensitivity = sensitivity_primary,
    ardl_short_run = ardl_short_run,
    ardl_long_run = ardl_long_run,
    ardl_bic_grid = ardl_bic_grid,
    join_audit = join_audit_all,
    price_audit = price_audit_all,
    sample_audit = sample_audit
  ))
}

# =============================================================================
# PUBLIC EXECUTION CONFIGURATION
# =============================================================================
#
# This module consumes the validated public reference workbooks produced by
# Module 01 (temporal disaggregation).
#
# Expected files:
#   results/01_monthlyization/Monthlyization_SA_results.xlsx
#   results/01_monthlyization/Monthlyization_BM_results.xlsx
#
# Run from the repository root.
# =============================================================================

INPUT_FILES <- c(
  SA = file.path(
    "results", "01_monthlyization",
    "Monthlyization_SA_results.xlsx"
  ),
  BM = file.path(
    "results", "01_monthlyization",
    "Monthlyization_BM_results.xlsx"
  )
)

OUTPUT_DIR <- file.path("outputs", "03_financial_transmission")
RUN_TAG <- "REPRODUCED"

cat("\nConfigured public financial-transmission inputs:\n")
print(INPUT_FILES)

missing_inputs <- INPUT_FILES[!file.exists(INPUT_FILES)]

if (length(missing_inputs) > 0L) {
  stop(
    "Input file(s) not found: ",
    paste(missing_inputs, collapse = " | "),
    "\nRun this script from the repository root and confirm that the ",
    "validated Module 01 result workbooks are stored in ",
    "results/01_monthlyization/.",
    call. = FALSE
  )
}

financial_validation_results <- list()

for (plant_name in names(INPUT_FILES)) {
  financial_validation_results[[plant_name]] <- run_financial_validation(
    input_file = INPUT_FILES[[plant_name]],
    plant = plant_name,
    output_dir = OUTPUT_DIR,
    run_tag = RUN_TAG
  )
}

cat("\n============================================================\n")
cat("SA and BM financial-transmission reproduction finished.\n")
cat("Reproduced outputs are in: ", gsub("\\\\", "/", OUTPUT_DIR), "\n", sep = "")
cat("============================================================\n")
