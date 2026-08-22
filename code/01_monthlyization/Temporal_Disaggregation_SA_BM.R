# =============================================================================
# Temporal Disaggregation — Santo Antonio (SA) and Belo Monte (BM)
# Public reproducibility script
#
# BASELINE
#   Denton-Cholette WITHOUT a high-frequency indicator
#   Formula: quarterly_flow ~ 1
#
# SENSITIVITY ANALYSES
#   Chow-Lin maximum likelihood WITH monthly electricity generation indicator
#   Formula: quarterly_flow ~ monthly_generation
#
#   Fernandez WITH monthly electricity generation indicator
#   Formula: quarterly_flow ~ monthly_generation
#
# This script:
#   1. Reads the original quarterly financial flows and monthly generation data.
#   2. Preserves the source workbooks unchanged.
#   3. Applies the validated temporal-disaggregation specifications.
#   4. Disables automatic method fallback.
#   5. Checks temporal continuity and quarterly reconciliation.
#   6. Audits purchased-energy sign standardization and non-positive values.
#   7. Writes reproduced outputs to outputs/01_monthlyization/.
#
# Run this script from the repository root.
# Package installation is NOT performed automatically.
# =============================================================================

run_temporal_disaggregation <- function(
    input_file,
    plant,
    output_dir = file.path("outputs", "01_monthlyization"),
    run_tag = "REPRODUCED",
    sheet_quarterly = "Receita_TRI",
    sheet_monthly = "Energia_MES",
    start_year = 2016L,
    start_month = 4L,
    end_year = 2024L,
    end_month = 12L,
    reconciliation_tolerance = 1e-6
) {

  # --------------------------------------------------------------------------
  # Required packages - no automatic installation
  # --------------------------------------------------------------------------
  required_packages <- c(
    "readxl", "openxlsx", "dplyr", "tidyr", "zoo", "tempdisagg",
    "stringr", "stringi", "purrr", "lubridate", "rlang"
  )

  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(missing_packages) > 0L) {
    stop(
      "Missing required packages: ", paste(missing_packages, collapse = ", "),
      ". Install them before running this reproducibility script.",
      call. = FALSE
    )
  }

  plant <- toupper(trimws(as.character(plant)))
  if (!plant %in% c("SA", "BM")) {
    stop("plant must be 'SA' or 'BM'.", call. = FALSE)
  }

  if (!file.exists(input_file)) {
    stop("Input file not found: ", input_file, call. = FALSE)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # --------------------------------------------------------------------------
  # Fixed validation configuration
  # --------------------------------------------------------------------------
  methods <- c("denton-cholette", "chow-lin-maxlog", "fernandez")
  method_tag <- c(
    "denton-cholette" = "DC",
    "chow-lin-maxlog" = "CL",
    "fernandez" = "FERN"
  )

  start_date <- as.Date(sprintf("%04d-%02d-01", start_year, start_month))
  end_date   <- as.Date(sprintf("%04d-%02d-01", end_year, end_month))

  # Convert monthly ts time indexes to first-of-month Date values without
  # relying on zoo's S3 as.Date.yearmon dispatch. This is intentionally
  # explicit for portability across R/zoo loading configurations.
  ts_monthly_dates <- function(x) {
    tt <- as.numeric(stats::time(x))
    yy <- floor(tt + 1e-8)
    mm <- as.integer(round((tt - yy) * 12)) + 1L

    # Defensive normalization against floating-point edge cases.
    over <- mm > 12L
    if (any(over)) {
      yy[over] <- yy[over] + 1L
      mm[over] <- mm[over] - 12L
    }
    under <- mm < 1L
    if (any(under)) {
      yy[under] <- yy[under] - 1L
      mm[under] <- mm[under] + 12L
    }

    as.Date(sprintf("%04d-%02d-01", as.integer(yy), mm))
  }

  output_file <- file.path(
    output_dir,
    paste0("Monthlyization_", plant, "_reproduced.xlsx")
  )

  log_file <- file.path(
    output_dir,
    paste0("Monthlyization_", plant, "_reproduced.log")
  )

  session_file <- file.path(
    output_dir,
    paste0("sessionInfo_", plant, "_reproduced.txt")
  )

  if (file.exists(output_file)) {
    stop(
      "Reproduced output already exists and will not be overwritten: ",
      output_file,
      "\nMove/rename the existing validation file before running again.",
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
  cat("Controlled Reproducibility Validation - Temporal Disaggregation\n")
  cat("Plant:", plant, "\n")
  cat("Run tag:", run_tag, "\n")
  cat("Input:", gsub("\\\\", "/", input_file), "\n")
  cat("Target window:", as.character(start_date), "to", as.character(end_date), "\n")
  cat("Baseline: denton-cholette WITHOUT indicator (y ~ 1)\n")
  cat("Sensitivity 1: chow-lin-maxlog WITH monthly generation indicator\n")
  cat("Sensitivity 2: fernandez WITH monthly generation indicator\n")
  cat("Automatic fallback: DISABLED\n")
  cat("============================================================\n\n")

  # --------------------------------------------------------------------------
  # General helpers
  # --------------------------------------------------------------------------
  stop_if <- function(cond, msg) {
    if (isTRUE(cond)) stop(msg, call. = FALSE)
  }

  q_to_month <- function(q) {
    switch(as.character(q), "1" = 1L, "2" = 4L, "3" = 7L, "4" = 10L)
  }

  prev_q <- function(y, q) {
    if (q == 1L) c(y - 1L, 4L) else c(y, q - 1L)
  }

  next_q <- function(y, q) {
    if (q == 4L) c(y + 1L, 1L) else c(y, q + 1L)
  }

  sanitize_name <- function(x) {
    x <- gsub("[\\[\\]\\*\\?/\\\\:]", "_", x)
    x <- gsub("\\s+", "_", x)
    x <- gsub("_+", "_", x)
    x <- gsub("^_+|_+$", "", x)
    if (!nzchar(x)) x <- "Sheet"
    substr(x, 1L, 31L)
  }

  clean_names_ <- function(nms) {
    nms <- stringi::stri_trans_general(nms, "Latin-ASCII")
    nms <- trimws(tolower(nms))
    nms <- gsub("[^a-z0-9]+", "_", nms)
    nms <- gsub("^_|_$", "", nms)
    nms
  }

  safe_window <- function(x, start, end) {
    obj <- try(stats::window(x, start = start, end = end, extend = FALSE), silent = TRUE)
    if (inherits(obj, "try-error") || length(obj) < 1L) NULL else obj
  }

  make_ts_quarterly <- function(vals, y0, q0) {
    stats::ts(as.numeric(vals), start = c(y0, q0), frequency = 4)
  }

  ts_from_vec <- function(vec, y0, m0) {
    stats::ts(as.numeric(vec), start = c(y0, m0), frequency = 12)
  }

  # --------------------------------------------------------------------------
  # Input-column mapping
  # --------------------------------------------------------------------------
  map_cols_tri <- function(df_raw) {
    nm_raw <- names(df_raw)
    nm_cln <- clean_names_(nm_raw)

    i_year  <- which(nm_cln %in% c("ano", "year"))[1]
    i_qtr   <- which(nm_cln %in% c("trim", "trimestre", "quarter"))[1]
    i_plant <- which(nm_cln %in% c("usina", "planta", "usina_nome", "usinaid", "id_usina"))[1]

    serie_idx <- grep("^serie($|_|[0-9]|\\.)", nm_cln)
    valor_idx <- grep("^valor($|_|[0-9]|\\.)", nm_cln)

    literal_series <- setdiff(
      grep("^(receita|energia)", nm_cln),
      c(serie_idx, valor_idx)
    )

    list(
      nm_raw = nm_raw,
      nm_cln = nm_cln,
      i_year = i_year,
      i_qtr = i_qtr,
      i_plant = i_plant,
      serie_idx = serie_idx,
      valor_idx = valor_idx,
      literal_series = literal_series
    )
  }

  wide_to_long_tri <- function(df_raw) {
    M <- map_cols_tri(df_raw)

    stop_if(
      any(is.na(c(M$i_year, M$i_qtr, M$i_plant))),
      paste0(
        "Sheet '", sheet_quarterly,
        "' must contain columns equivalent to Ano/Year, Trim/Quarter, and Usina/Plant."
      )
    )

    df <- as.data.frame(df_raw)
    names(df) <- M$nm_cln

    df_base <- df |>
      dplyr::rename(
        Ano   = !!M$nm_cln[M$i_year],
        Trim  = !!M$nm_cln[M$i_qtr],
        Usina = !!M$nm_cln[M$i_plant]
      )

    if (length(M$serie_idx) > 0L && length(M$valor_idx) > 0L) {
      s_cols <- names(df)[sort(M$serie_idx)]
      v_cols <- names(df)[sort(M$valor_idx)]

      stop_if(
        length(s_cols) != length(v_cols),
        sprintf(
          "Unbalanced Serie*/Valor* columns (%d vs %d). Execution stops instead of pairing ambiguously.",
          length(s_cols), length(v_cols)
        )
      )

      parts <- vector("list", length(s_cols))
      for (i in seq_along(s_cols)) {
        s_col <- s_cols[i]
        v_col <- v_cols[i]

        parts[[i]] <- df_base |>
          dplyr::select(dplyr::all_of(c("Ano", "Trim", "Usina", s_col, v_col))) |>
          dplyr::rename(
            Serie = !!rlang::sym(s_col),
            Valor = !!rlang::sym(v_col)
          )
      }
      tri_long <- dplyr::bind_rows(parts)

    } else if (length(M$literal_series) >= 1L) {
      parts <- lapply(M$literal_series, function(idx) {
        s_name <- names(df)[idx]
        serie_name <- dplyr::case_when(
          grepl("^receita", s_name) ~ "Receita_Vendas",
          grepl("^energia", s_name) ~ "Energia_Comprada",
          TRUE ~ s_name
        )

        df_base |>
          dplyr::select(dplyr::all_of(c("Ano", "Trim", "Usina", s_name))) |>
          dplyr::rename(Valor = !!rlang::sym(s_name)) |>
          dplyr::mutate(Serie = serie_name)
      })
      tri_long <- dplyr::bind_rows(parts)

    } else {
      stop(
        paste0(
          "Sheet '", sheet_quarterly,
          "' has neither Serie*/Valor* pairs nor recognizable literal series columns."
        ),
        call. = FALSE
      )
    }

    tri_long |>
      dplyr::mutate(
        Ano = as.integer(Ano),
        Trim = as.integer(Trim),
        Usina = toupper(trimws(as.character(Usina))),
        Serie = dplyr::case_when(
          stringr::str_detect(
            Serie,
            stringr::regex("^\\s*receita\\s*_?vendas\\s*$", ignore_case = TRUE)
          ) ~ "Receita_Vendas",
          stringr::str_detect(
            Serie,
            stringr::regex("energia\\s*comprada", ignore_case = TRUE)
          ) ~ "Energia_Comprada",
          TRUE ~ as.character(Serie)
        ),
        Valor = suppressWarnings(as.numeric(Valor))
      ) |>
      dplyr::filter(is.finite(Valor)) |>
      dplyr::arrange(Usina, Serie, Ano, Trim)
  }

  map_cols_mes <- function(df_raw) {
    nm_cln <- clean_names_(names(df_raw))

    i_year  <- which(nm_cln %in% c("ano", "year"))[1]
    i_month <- which(nm_cln %in% c("mes", "mes_", "meses", "month", "m", "mes_num"))[1]
    i_plant <- which(nm_cln %in% c("usina", "planta", "usina_nome", "usinaid", "id_usina"))[1]
    i_energy <- grep("^energia.*(base)?.*mwh$|^energia(_base)?$", nm_cln)[1]

    list(
      nm_cln = nm_cln,
      i_year = i_year,
      i_month = i_month,
      i_plant = i_plant,
      i_energy = i_energy
    )
  }

  normalize_mes <- function(df_raw) {
    M <- map_cols_mes(df_raw)

    stop_if(
      any(is.na(c(M$i_year, M$i_month, M$i_plant, M$i_energy))),
      paste0(
        "Sheet '", sheet_monthly,
        "' must contain columns equivalent to Ano/Year, Mes/Month, Usina/Plant, and Energia_Base_MWh."
      )
    )

    df <- as.data.frame(df_raw)
    names(df) <- M$nm_cln

    df |>
      dplyr::transmute(
        Ano = as.integer(!!rlang::sym(M$nm_cln[M$i_year])),
        Mes = as.integer(!!rlang::sym(M$nm_cln[M$i_month])),
        Usina = toupper(trimws(as.character(!!rlang::sym(M$nm_cln[M$i_plant])))),
        Energia_Base_MWh = suppressWarnings(as.numeric(!!rlang::sym(M$nm_cln[M$i_energy])))
      ) |>
      dplyr::arrange(Usina, Ano, Mes)
  }

  # --------------------------------------------------------------------------
  # Temporal-integrity guardrails
  # --------------------------------------------------------------------------
  check_quarterly_continuity <- function(tri_long) {
    key_dup <- tri_long |>
      dplyr::count(Usina, Serie, Ano, Trim, name = "n") |>
      dplyr::filter(n > 1L)

    stop_if(
      nrow(key_dup) > 0L,
      paste0(
        "Duplicate quarterly observations detected. First duplicates: ",
        paste(utils::capture.output(print(utils::head(key_dup, 10))), collapse = " | ")
      )
    )

    checks <- tri_long |>
      dplyr::group_by(Usina, Serie) |>
      dplyr::arrange(Ano, Trim, .by_group = TRUE) |>
      dplyr::summarise(
        N = dplyr::n(),
        Start = paste0(dplyr::first(Ano), "Q", dplyr::first(Trim)),
        End = paste0(dplyr::last(Ano), "Q", dplyr::last(Trim)),
        Continuous = {
          idx <- Ano * 4L + (Trim - 1L)
          length(idx) <= 1L || all(diff(idx) == 1L)
        },
        .groups = "drop"
      )

    stop_if(
      any(!checks$Continuous),
      paste0(
        "Quarterly gaps detected for: ",
        paste(paste(checks$Usina[!checks$Continuous], checks$Serie[!checks$Continuous], sep = "/"), collapse = ", ")
      )
    )

    checks
  }

  check_monthly_continuity <- function(mes) {
    dup <- mes |>
      dplyr::count(Usina, Ano, Mes, name = "n") |>
      dplyr::filter(n > 1L)

    stop_if(
      nrow(dup) > 0L,
      paste0(
        "Duplicate monthly observations detected. First duplicates: ",
        paste(utils::capture.output(print(utils::head(dup, 10))), collapse = " | ")
      )
    )

    checks <- mes |>
      dplyr::group_by(Usina) |>
      dplyr::arrange(Ano, Mes, .by_group = TRUE) |>
      dplyr::summarise(
        N = dplyr::n(),
        Start = sprintf("%04d-%02d", dplyr::first(Ano), dplyr::first(Mes)),
        End = sprintf("%04d-%02d", dplyr::last(Ano), dplyr::last(Mes)),
        Continuous = {
          idx <- Ano * 12L + (Mes - 1L)
          length(idx) <= 1L || all(diff(idx) == 1L)
        },
        AllFiniteEnergy = all(is.finite(Energia_Base_MWh)),
        .groups = "drop"
      )

    stop_if(
      any(!checks$Continuous),
      paste0("Monthly gaps detected for: ", paste(checks$Usina[!checks$Continuous], collapse = ", "))
    )

    stop_if(
      any(!checks$AllFiniteEnergy),
      paste0("Non-finite monthly energy values detected for: ", paste(checks$Usina[!checks$AllFiniteEnergy], collapse = ", "))
    )

    checks
  }

  # --------------------------------------------------------------------------
  # Purchased-energy sign standardization + audit
  # --------------------------------------------------------------------------
  standardize_ec_sign <- function(tri_long) {
    ec <- tri_long |>
      dplyr::filter(Serie == "Energia_Comprada") |>
      dplyr::group_by(Usina) |>
      dplyr::summarise(
        Original_Median = suppressWarnings(stats::median(Valor, na.rm = TRUE)),
        N_Negative = sum(Valor < 0, na.rm = TRUE),
        N_Zero = sum(Valor == 0, na.rm = TRUE),
        N_Positive = sum(Valor > 0, na.rm = TRUE),
        Sign_Reversed = is.finite(Original_Median) & Original_Median < 0,
        .groups = "drop"
      )

    if (nrow(ec) == 0L) {
      return(list(data = tri_long, audit = data.frame(Msg = "Energia_Comprada not found")))
    }

    rev_map <- stats::setNames(ec$Sign_Reversed, ec$Usina)

    out <- tri_long |>
      dplyr::mutate(
        .reverse = ifelse(Serie == "Energia_Comprada", rev_map[Usina], FALSE),
        Valor = dplyr::if_else(
          Serie == "Energia_Comprada" & .reverse %in% TRUE,
          -Valor,
          Valor
        )
      ) |>
      dplyr::select(-.reverse)

    list(data = out, audit = ec)
  }

  # --------------------------------------------------------------------------
  # Build monthly indicator ts
  # --------------------------------------------------------------------------
  make_ts_monthly_from_data <- function(df_mes_one) {
    df_mes_one <- df_mes_one[order(df_mes_one$Ano, df_mes_one$Mes), , drop = FALSE]
    stats::ts(
      as.numeric(df_mes_one$Energia_Base_MWh),
      start = c(df_mes_one$Ano[1], df_mes_one$Mes[1]),
      frequency = 12
    )
  }

  # --------------------------------------------------------------------------
  # Audited temporal-disaggregation fit
  #
  # REPRODUCIBILITY POLICY
  #   - Denton-Cholette baseline: NO indicator, y ~ 1.
  #   - Chow-Lin / Fernandez: WITH monthly generation indicator.
  #   - Automatic fallback is DISABLED. If the requested method fails,
  #     execution stops rather than silently substituting another method.
  # --------------------------------------------------------------------------
  fit_td_audited <- function(ts_q, ts_indicator, requested_method) {

    if (identical(requested_method, "denton-cholette")) {
      requested_formula <- "y ~ 1"
      indicator_used <- FALSE

      fit <- tryCatch(
        tempdisagg::td(
          ts_q ~ 1,
          method = "denton-cholette",
          conversion = "sum",
          to = "monthly"
        ),
        error = function(e) {
          stop(
            "Denton-Cholette baseline failed: ",
            conditionMessage(e),
            call. = FALSE
          )
        }
      )

    } else if (requested_method %in% c("chow-lin-maxlog", "fernandez")) {
      stop_if(
        is.null(ts_indicator) || length(ts_indicator) < 3L,
        paste0(
          "Monthly generation indicator is required for ",
          requested_method, "."
        )
      )

      requested_formula <- "y ~ indicator"
      indicator_used <- TRUE

      fit <- tryCatch(
        tempdisagg::td(
          ts_q ~ ts_indicator,
          method = requested_method,
          conversion = "sum",
          to = "monthly"
        ),
        error = function(e) {
          stop(
            "Sensitivity method ", requested_method, " failed: ",
            conditionMessage(e),
            ". Automatic fallback is disabled in reproducibility run.",
            call. = FALSE
          )
        }
      )

    } else {
      stop("Unsupported temporal-disaggregation method: ", requested_method, call. = FALSE)
    }

    list(
      fit = fit,
      requested_method = requested_method,
      effective_method = requested_method,
      indicator_used = indicator_used,
      fallback_allowed = FALSE,
      fallback_used = FALSE,
      fallback_reason = "",
      requested_formula = requested_formula
    )
  }

  # --------------------------------------------------------------------------
  # Temporal disaggregation of one quarterly flow
  # --------------------------------------------------------------------------
  disaggregate_flow <- function(
      df_tri_one,
      df_ind_mes_one,
      series_name,
      requested_method
  ) {
    stop_if(nrow(df_tri_one) == 0L, paste("No quarterly data for", series_name))
    stop_if(nrow(df_ind_mes_one) == 0L, paste("No monthly indicator for", series_name))

    df_tri_one <- df_tri_one[order(df_tri_one$Ano, df_tri_one$Trim), , drop = FALSE]
    df_ind_mes_one <- df_ind_mes_one[order(df_ind_mes_one$Ano, df_ind_mes_one$Mes), , drop = FALSE]

    y0 <- df_tri_one$Ano[1]
    q0 <- df_tri_one$Trim[1]
    ts_q <- make_ts_quarterly(df_tri_one$Valor, y0, q0)

    ts_ind <- make_ts_monthly_from_data(df_ind_mes_one)
    yI <- stats::start(ts_ind)[1]
    mI <- stats::start(ts_ind)[2]
    yF <- stats::end(ts_ind)[1]
    mF <- stats::end(ts_ind)[2]

    qI <- ((mI - 1L) %/% 3L) + 1L
    qF <- ((mF - 1L) %/% 3L) + 1L

    q_all_start <- stats::start(ts_q)
    q_all_end <- stats::end(ts_q)

    ts_q_head <- safe_window(ts_q, start = q_all_start, end = prev_q(yI, qI))
    ts_q_mid  <- safe_window(ts_q, start = c(yI, qI), end = c(yF, qF))
    ts_q_tail <- safe_window(ts_q, start = next_q(yF, qF), end = q_all_end)

    parts <- list()
    audit_rows <- list()

    # HEAD - allowed only for the DC baseline.
    if (!is.null(ts_q_head)) {
      if (!identical(requested_method, "denton-cholette")) {
        stop(
          "Monthly indicator does not cover the head segment required by ",
          requested_method,
          ". Automatic fallback is disabled in reproducibility run.",
          call. = FALSE
        )
      }

      fit_h <- tempdisagg::td(
        ts_q_head ~ 1,
        method = "denton-cholette",
        conversion = "sum",
        to = "monthly"
      )
      pred_h <- as.numeric(stats::predict(fit_h))
      yH <- stats::start(ts_q_head)[1]
      qH <- stats::start(ts_q_head)[2]
      parts$head <- ts_from_vec(pred_h, yH, q_to_month(qH))

      audit_rows[[length(audit_rows) + 1L]] <- data.frame(
        Segment = "head",
        Requested_Method = requested_method,
        Effective_Method = "denton-cholette",
        Formula = "y ~ 1",
        Indicator_Used = FALSE,
        Fallback_Allowed = FALSE,
        Fallback_Used = FALSE,
        Fallback_Reason = "",
        stringsAsFactors = FALSE
      )
    }

    # MID - use complete quarters covered by the monthly indicator.
    if (!is.null(ts_q_mid)) {
      yM <- stats::start(ts_q_mid)[1]
      qM <- stats::start(ts_q_mid)[2]
      mid_month_start <- c(yM, q_to_month(qM))

      ts_ind_from <- try(stats::window(ts_ind, start = mid_month_start), silent = TRUE)
      stop_if(inherits(ts_ind_from, "try-error"), "Unable to align monthly indicator with quarterly series.")

      nQ_needed <- length(ts_q_mid)
      nM_have <- length(ts_ind_from)
      nQ_avail <- floor(nM_have / 3L)
      stop_if(nQ_avail < 1L, "Monthly indicator does not contain one complete quarter.")

      nQ_use <- min(nQ_needed, nQ_avail)

      y_end_mid <- yM + ((qM - 1L) + (nQ_use - 1L)) %/% 4L
      q_end_mid <- ((qM - 1L) + (nQ_use - 1L)) %% 4L + 1L

      ts_q_mid_use <- stats::window(
        ts_q_mid,
        start = c(yM, qM),
        end = c(y_end_mid, q_end_mid)
      )

      ts_ind_mid <- ts_from_vec(
        ts_ind_from[seq_len(nQ_use * 3L)],
        yM,
        q_to_month(qM)
      )

      aud <- fit_td_audited(
        ts_q = ts_q_mid_use,
        ts_indicator = ts_ind_mid,
        requested_method = requested_method
      )

      pred_m <- as.numeric(stats::predict(aud$fit))
      parts$mid <- ts_from_vec(pred_m, yM, q_to_month(qM))

      audit_rows[[length(audit_rows) + 1L]] <- data.frame(
        Segment = "mid",
        Requested_Method = aud$requested_method,
        Effective_Method = aud$effective_method,
        Formula = aud$requested_formula,
        Indicator_Used = aud$indicator_used,
        Fallback_Allowed = aud$fallback_allowed,
        Fallback_Used = aud$fallback_used,
        Fallback_Reason = aud$fallback_reason,
        stringsAsFactors = FALSE
      )
    }

    # TAIL - allowed only for the DC baseline.
    if (!is.null(ts_q_tail)) {
      if (!identical(requested_method, "denton-cholette")) {
        stop(
          "Monthly indicator does not cover the tail segment required by ",
          requested_method,
          ". Automatic fallback is disabled in reproducibility run.",
          call. = FALSE
        )
      }

      fit_t <- tempdisagg::td(
        ts_q_tail ~ 1,
        method = "denton-cholette",
        conversion = "sum",
        to = "monthly"
      )
      pred_t <- as.numeric(stats::predict(fit_t))
      yT <- stats::start(ts_q_tail)[1]
      qT <- stats::start(ts_q_tail)[2]
      parts$tail <- ts_from_vec(pred_t, yT, q_to_month(qT))

      audit_rows[[length(audit_rows) + 1L]] <- data.frame(
        Segment = "tail",
        Requested_Method = requested_method,
        Effective_Method = "denton-cholette",
        Formula = "y ~ 1",
        Indicator_Used = FALSE,
        Fallback_Allowed = FALSE,
        Fallback_Used = FALSE,
        Fallback_Reason = "",
        stringsAsFactors = FALSE
      )
    }

    pieces <- Filter(Negate(is.null), parts)
    stop_if(length(pieces) == 0L, paste("No valid disaggregation segments for", series_name))

    first_q <- if (!is.null(ts_q_head)) {
      stats::start(ts_q_head)
    } else if (!is.null(ts_q_mid)) {
      stats::start(ts_q_mid)
    } else {
      stats::start(ts_q_tail)
    }

    vals <- unlist(lapply(pieces, as.numeric), use.names = FALSE)
    ts_all <- stats::ts(
      vals,
      start = c(first_q[1], q_to_month(first_q[2])),
      frequency = 12
    )

    ts_span <- stats::window(
      ts_all,
      start = c(start_year, start_month),
      end = c(end_year, end_month)
    )

    output <- data.frame(
      Data = ts_monthly_dates(ts_span),
      Valor_Mensal = as.numeric(ts_span),
      stringsAsFactors = FALSE
    )

    list(output = output, audit = dplyr::bind_rows(audit_rows))
  }

  # --------------------------------------------------------------------------
  # Read and normalize inputs
  # --------------------------------------------------------------------------
  sheets <- readxl::excel_sheets(input_file)
  stop_if(!sheet_quarterly %in% sheets, paste("Missing sheet:", sheet_quarterly))
  stop_if(!sheet_monthly %in% sheets, paste("Missing sheet:", sheet_monthly))

  tri_raw <- readxl::read_excel(input_file, sheet = sheet_quarterly)
  mes_raw <- readxl::read_excel(input_file, sheet = sheet_monthly)

  tri_long_original <- wide_to_long_tri(tri_raw)
  mes <- normalize_mes(mes_raw)

  # Restrict to the requested plant if the workbook contains more than one.
  tri_long_original <- tri_long_original |>
    dplyr::filter(Usina == plant)
  mes <- mes |>
    dplyr::filter(Usina == plant)

  stop_if(nrow(tri_long_original) == 0L, paste("No quarterly observations found for plant", plant))
  stop_if(nrow(mes) == 0L, paste("No monthly observations found for plant", plant))

  quarterly_continuity <- check_quarterly_continuity(tri_long_original)
  monthly_continuity <- check_monthly_continuity(mes)

  sign_res <- standardize_ec_sign(tri_long_original)
  tri_long <- sign_res$data
  sign_audit <- sign_res$audit

  target_series <- intersect(
    c("Receita_Vendas", "Energia_Comprada"),
    unique(tri_long$Serie)
  )

  stop_if(!"Receita_Vendas" %in% target_series, "Receita_Vendas not found in quarterly input.")

  # --------------------------------------------------------------------------
  # Output workbook + run configuration
  # --------------------------------------------------------------------------
  wb <- openxlsx::createWorkbook()
  used_sheets <- character(0)

  add_sheet <- function(sheet, data) {
    s <- sanitize_name(sheet)
    if (s %in% used_sheets) {
      base <- substr(s, 1L, 27L)
      i <- 1L
      while (paste0(base, "_", i) %in% used_sheets) i <- i + 1L
      s <- paste0(base, "_", i)
    }
    used_sheets <<- c(used_sheets, s)
    openxlsx::addWorksheet(wb, s)
    openxlsx::writeData(wb, s, as.data.frame(data))
    invisible(s)
  }

  run_config <- data.frame(
    Item = c(
      "Plant", "Run_Tag", "Input_File", "Input_MD5", "Quarterly_Sheet",
      "Monthly_Sheet", "Target_Start", "Target_End", "Methods",
      "Baseline_Method", "Baseline_Formula", "Sensitivity_Methods",
      "Sensitivity_Indicator", "Automatic_Fallback",
      "Reconciliation_Tolerance", "tempdisagg_Version"
    ),
    Value = c(
      plant,
      run_tag,
      gsub("\\\\", "/", input_file),
      unname(tools::md5sum(input_file)),
      sheet_quarterly,
      sheet_monthly,
      as.character(start_date),
      as.character(end_date),
      paste(methods, collapse = "; "),
      "denton-cholette",
      "quarterly_flow ~ 1",
      "chow-lin-maxlog; fernandez",
      "monthly electricity generation (Energia_Base_MWh)",
      "DISABLED",
      format(reconciliation_tolerance, scientific = TRUE),
      as.character(utils::packageVersion("tempdisagg"))
    ),
    stringsAsFactors = FALSE
  )

  add_sheet("RUN_CONFIG", run_config)
  method_specification <- data.frame(
    Tag = c("DC", "CL", "FERN"),
    Role = c("Baseline", "Sensitivity", "Sensitivity"),
    Method = c("denton-cholette", "chow-lin-maxlog", "fernandez"),
    Formula = c(
      "quarterly_flow ~ 1",
      "quarterly_flow ~ monthly_generation",
      "quarterly_flow ~ monthly_generation"
    ),
    High_Frequency_Indicator = c(FALSE, TRUE, TRUE),
    Automatic_Fallback = c(FALSE, FALSE, FALSE),
    stringsAsFactors = FALSE
  )

  add_sheet("METHOD_SPECIFICATION", method_specification)
  add_sheet("INPUT_Q_CONTINUITY", quarterly_continuity)
  add_sheet("INPUT_M_CONTINUITY", monthly_continuity)
  add_sheet("SIGN_AUDIT", sign_audit)

  # Copy normalized monthly energy automatically to the result workbook.
  energia_mes_output <- mes |>
    dplyr::mutate(Data = as.Date(sprintf("%04d-%02d-01", Ano, Mes))) |>
    dplyr::filter(Data >= start_date, Data <= end_date) |>
    dplyr::select(Usina, Data, Energia_Base_MWh) |>
    dplyr::arrange(Usina, Data)

  add_sheet("Energia_MES", energia_mes_output)

  # --------------------------------------------------------------------------
  # Main loop by method and series
  # --------------------------------------------------------------------------
  out_monthly_by_method <- list()
  recon_tabs_by_method <- list()
  quality_by_method <- list()
  log_by_method <- list()
  method_audit_rows <- list()

  for (method in methods) {
    tag <- unname(method_tag[[method]])

    cat("\n==============================\n")
    cat("Requested method:", method, "| tag:", tag, "\n")
    cat("==============================\n")

    out_monthly <- list()
    recon_tabs <- list()

    for (series in target_series) {
      cat("Series:", series, "| plant:", plant, "| method:", method, "\n")

      tri_u <- tri_long |>
        dplyr::filter(Usina == plant, Serie == series) |>
        dplyr::arrange(Ano, Trim)

      mes_u <- mes |>
        dplyr::filter(Usina == plant) |>
        dplyr::arrange(Ano, Mes)

      dis <- disaggregate_flow(
        df_tri_one = tri_u,
        df_ind_mes_one = mes_u,
        series_name = paste(series, plant),
        requested_method = method
      )

      df_u <- dis$output
      df_u$Usina <- plant

      out_monthly[[series]] <- df_u |>
        dplyr::relocate(Usina, Data, Valor_Mensal) |>
        dplyr::arrange(Usina, Data)

      aud <- dis$audit |>
        dplyr::mutate(
          Plant = plant,
          Series = series,
          Tag = tag,
          .before = 1
        )
      method_audit_rows[[length(method_audit_rows) + 1L]] <- aud

      add_sheet(
        paste0(series, "_MES_", tag),
        out_monthly[[series]]
      )

      # Quarterly reconciliation.
      df_u_q <- out_monthly[[series]] |>
        dplyr::mutate(
          Ano = lubridate::year(Data),
          Mes = lubridate::month(Data),
          Trim = ((Mes - 1L) %/% 3L) + 1L
        ) |>
        dplyr::group_by(Usina, Ano, Trim) |>
        dplyr::summarise(
          Soma_Mensal = sum(Valor_Mensal, na.rm = TRUE),
          N_Meses = dplyr::n(),
          .groups = "drop"
        )

      tri_u_q <- tri_u |>
        dplyr::select(Usina, Ano, Trim, Valor) |>
        dplyr::rename(Valor_TRI = Valor)

      rec_u <- df_u_q |>
        dplyr::left_join(tri_u_q, by = c("Usina", "Ano", "Trim")) |>
        dplyr::mutate(
          Metodo = tag,
          Serie = series,
          Dif = Soma_Mensal - Valor_TRI,
          AbsDif = abs(Dif),
          Completo = N_Meses == 3L,
          Ok = dplyr::if_else(
            Completo,
            is.finite(Dif) & AbsDif <= reconciliation_tolerance,
            NA
          )
        ) |>
        dplyr::relocate(
          Metodo, Serie, Usina, Ano, Trim, Completo,
          N_Meses, Valor_TRI, Soma_Mensal, Dif, AbsDif, Ok
        ) |>
        dplyr::arrange(Usina, Ano, Trim)

      recon_tabs[[series]] <- rec_u
      add_sheet(paste0("Recon_", series, "_", tag), rec_u)
    }

    # ------------------------------------------------------------------------
    # Net revenue - strict date matching, no silent NA -> 0 replacement
    # ------------------------------------------------------------------------
    rv <- out_monthly[["Receita_Vendas"]]
    ec <- out_monthly[["Energia_Comprada"]]
    rl <- NULL

    if (!is.null(rv)) {
      if (is.null(ec)) {
        stop(
          "Energia_Comprada is absent. The script does not assume purchased energy = 0.",
          call. = FALSE
        )
      }

      matched <- rv |>
        dplyr::rename(RV = Valor_Mensal) |>
        dplyr::full_join(
          ec |> dplyr::rename(EC_custo = Valor_Mensal),
          by = c("Usina", "Data")
        )

      mismatch <- matched |>
        dplyr::filter(!is.finite(RV) | !is.finite(EC_custo))

      stop_if(
        nrow(mismatch) > 0L,
        paste0(
          "Sales revenue and purchased-energy monthly series do not match one-to-one. ",
          "First problematic rows: ",
          paste(utils::capture.output(print(utils::head(mismatch, 10))), collapse = " | ")
        )
      )

      rl <- matched |>
        dplyr::mutate(Receita_Liquida = RV - EC_custo) |>
        dplyr::select(Usina, Data, Receita_Liquida) |>
        dplyr::arrange(Usina, Data)

      add_sheet(paste0("Receita_Liquida_MES_", tag), rl)

      out_monthly[["Receita_Liquida"]] <- rl |>
        dplyr::rename(Valor_Mensal = Receita_Liquida)
    }

    # ------------------------------------------------------------------------
    # Validation and quality summary
    # ------------------------------------------------------------------------
    val_df <- dplyr::bind_rows(recon_tabs)
    add_sheet(paste0("VALIDACAO_", tag), val_df)

    quality <- val_df |>
      dplyr::filter(Completo) |>
      dplyr::group_by(Metodo, Serie, Usina) |>
      dplyr::summarise(
        MaxAbsDiff = max(abs(Dif), na.rm = TRUE),
        N_Erros = sum(!Ok, na.rm = TRUE),
        .groups = "drop"
      )

    quality_by_method[[tag]] <- quality

    # ------------------------------------------------------------------------
    # Log transforms + non-positive audit
    # ------------------------------------------------------------------------
    log_summary <- list()

    make_log_df <- function(df, value_col, series_name) {
      df |>
        dplyr::mutate(
          Valor = .data[[value_col]],
          Ln_Valor = ifelse(is.finite(Valor) & Valor > 0, log(Valor), NA_real_),
          NonPositivo = ifelse(!is.finite(Valor) | Valor <= 0, 1L, 0L)
        ) |>
        dplyr::select(Usina, Data, Ln_Valor, NonPositivo) |>
        dplyr::mutate(Serie = series_name)
    }

    rv_log <- make_log_df(rv, "Valor_Mensal", "Receita_Vendas")
    add_sheet(
      paste0("Receita_Vendas_MES_LOG_", tag),
      rv_log |> dplyr::select(Usina, Data, Ln_Valor)
    )
    log_summary[["Receita_Vendas"]] <- rv_log |>
      dplyr::group_by(Serie, Usina) |>
      dplyr::summarise(N_NonPos = sum(NonPositivo, na.rm = TRUE), .groups = "drop")

    ec_log <- make_log_df(ec, "Valor_Mensal", "Energia_Comprada")
    add_sheet(
      paste0("Energia_Comprada_MES_LOG_", tag),
      ec_log |> dplyr::select(Usina, Data, Ln_Valor)
    )
    log_summary[["Energia_Comprada"]] <- ec_log |>
      dplyr::group_by(Serie, Usina) |>
      dplyr::summarise(N_NonPos = sum(NonPositivo, na.rm = TRUE), .groups = "drop")

    rl_log <- make_log_df(
      rl |> dplyr::rename(Valor_Mensal = Receita_Liquida),
      "Valor_Mensal",
      "Receita_Liquida"
    )
    add_sheet(
      paste0("Receita_Liquida_MES_LOG_", tag),
      rl_log |> dplyr::select(Usina, Data, Ln_Valor)
    )
    log_summary[["Receita_Liquida"]] <- rl_log |>
      dplyr::group_by(Serie, Usina) |>
      dplyr::summarise(N_NonPos = sum(NonPositivo, na.rm = TRUE), .groups = "drop")

    ln_issues <- dplyr::bind_rows(log_summary) |>
      tidyr::pivot_wider(
        names_from = Serie,
        values_from = N_NonPos,
        values_fill = 0
      )

    log_final <- quality |>
      dplyr::full_join(ln_issues, by = "Usina")

    add_sheet(paste0("LOG_", tag), log_final)

    log_by_method[[tag]] <- log_final
    out_monthly_by_method[[tag]] <- out_monthly
    recon_tabs_by_method[[tag]] <- recon_tabs
  }

  # --------------------------------------------------------------------------
  # Method audit - requested versus effective method
  # --------------------------------------------------------------------------
  method_audit <- dplyr::bind_rows(method_audit_rows) |>
    dplyr::arrange(Tag, Series, Segment)

  add_sheet("METHOD_AUDIT", method_audit)

  fallback_summary <- method_audit |>
    dplyr::group_by(
      Plant, Series, Tag, Requested_Method, Effective_Method, Formula,
      Indicator_Used, Fallback_Allowed, Fallback_Used
    ) |>
    dplyr::summarise(N_Segments = dplyr::n(), .groups = "drop")

  add_sheet("FALLBACK_SUMMARY", fallback_summary)

  # --------------------------------------------------------------------------
  # Sensitivity summary versus baseline DC
  # Includes Net Revenue in the corrected validation version.
  # --------------------------------------------------------------------------
  make_sensitivity_summary <- function(out_by_method, series_names, base_tag = "DC") {
    stop_if(is.null(out_by_method[[base_tag]]), "DC baseline not found.")

    base <- out_by_method[[base_tag]]
    rows <- list()

    for (series in series_names) {
      if (is.null(base[[series]])) next
      bdf <- base[[series]] |>
        dplyr::rename(Base = Valor_Mensal)

      for (tag in setdiff(names(out_by_method), base_tag)) {
        adf <- out_by_method[[tag]][[series]]
        if (is.null(adf)) next
        adf <- adf |>
          dplyr::rename(Alt = Valor_Mensal)

        m <- bdf |>
          dplyr::inner_join(adf, by = c("Usina", "Data")) |>
          dplyr::group_by(Usina) |>
          dplyr::summarise(
            Serie = series,
            Metodo = tag,
            N = dplyr::n(),
            Corr = suppressWarnings(stats::cor(Base, Alt, use = "complete.obs")),
            MeanAbsDiff = mean(abs(Alt - Base), na.rm = TRUE),
            MeanAbsRelativeDiff = mean(
              abs((Alt - Base) / ifelse(abs(Base) > 0, abs(Base), NA_real_)),
              na.rm = TRUE
            ),
            MeanAbsPct = 100 * MeanAbsRelativeDiff,
            SdRatio = stats::sd(Alt, na.rm = TRUE) / stats::sd(Base, na.rm = TRUE),
            .groups = "drop"
          )

        rows[[paste(series, tag, sep = "_")]] <- m
      }
    }

    dplyr::bind_rows(rows) |>
      dplyr::arrange(Serie, Usina, Metodo)
  }

  sensitivity_series <- c("Receita_Vendas", "Energia_Comprada", "Receita_Liquida")
  sens_summary <- make_sensitivity_summary(
    out_monthly_by_method,
    sensitivity_series,
    base_tag = "DC"
  )

  add_sheet("SENS_SUMMARY", sens_summary)

  # --------------------------------------------------------------------------
  # Non-positive-value audit by method and series
  # --------------------------------------------------------------------------
  nonpositive_rows <- list()

  for (tag in names(out_monthly_by_method)) {
    for (series in c("Receita_Vendas", "Energia_Comprada", "Receita_Liquida")) {
      obj <- out_monthly_by_method[[tag]][[series]]
      if (is.null(obj)) next

      vals <- as.numeric(obj$Valor_Mensal)

      nonpositive_rows[[length(nonpositive_rows) + 1L]] <- data.frame(
        Plant = plant,
        Tag = tag,
        Series = series,
        N = length(vals),
        N_Negative = sum(vals < 0, na.rm = TRUE),
        N_Zero = sum(vals == 0, na.rm = TRUE),
        N_NonPositive = sum(vals <= 0, na.rm = TRUE),
        Minimum = min(vals, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    }
  }

  nonpositive_summary <- dplyr::bind_rows(nonpositive_rows) |>
    dplyr::arrange(Tag, Series)

  add_sheet("NONPOSITIVE_SUMMARY", nonpositive_summary)

  # Baseline Sales Revenue must remain strictly positive because the next
  # financial-transmission model uses log(Sales Revenue).
  dc_rv_check <- nonpositive_summary |>
    dplyr::filter(Tag == "DC", Series == "Receita_Vendas")

  stop_if(
    nrow(dc_rv_check) != 1L || dc_rv_check$N_NonPositive[1] > 0L,
    paste0(
      "reproducibility run failed: DC baseline Sales Revenue contains ",
      ifelse(nrow(dc_rv_check) == 1L, dc_rv_check$N_NonPositive[1], NA_integer_),
      " non-positive observations."
    )
  )


  # --------------------------------------------------------------------------
  # Final validation checks
  # --------------------------------------------------------------------------
  reconciliation_summary <- dplyr::bind_rows(
    lapply(names(quality_by_method), function(tag) {
      quality_by_method[[tag]] |>
        dplyr::mutate(Tag = tag, .before = 1)
    })
  )

  add_sheet("RECON_SUMMARY", reconciliation_summary)

  if (any(reconciliation_summary$N_Erros > 0L, na.rm = TRUE)) {
    stop(
      "Quarterly reconciliation failed for at least one method/series. Workbook was not saved.",
      call. = FALSE
    )
  }

  # --------------------------------------------------------------------------
  # Save workbook - new file only
  # --------------------------------------------------------------------------
  temp_dir <- tempdir()
  if (!dir.exists(temp_dir)) dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

  save_ok <- TRUE
  tryCatch(
    openxlsx::saveWorkbook(wb, output_file, overwrite = FALSE),
    error = function(e) {
      save_ok <<- FALSE
      cat("saveWorkbook failed with default tempdir:", conditionMessage(e), "\n")
    }
  )

  if (!save_ok) {
    tmp_local <- file.path(
      output_dir,
      paste0("openxlsx_tmp_", plant, "_", run_tag, "_", format(Sys.time(), "%H%M%S"))
    )
    dir.create(tmp_local, recursive = TRUE, showWarnings = FALSE)

    old_opt <- getOption("openxlsx.tempdir", default = NULL)
    options(openxlsx.tempdir = tmp_local)
    on.exit({
      if (is.null(old_opt)) {
        options(openxlsx.tempdir = NULL)
      } else {
        options(openxlsx.tempdir = old_opt)
      }
    }, add = TRUE)

    openxlsx::saveWorkbook(wb, output_file, overwrite = FALSE)
  }

  # Record R/package environment separately.
  writeLines(utils::capture.output(sessionInfo()), con = session_file, useBytes = TRUE)

  cat("\nReproducibility run completed successfully.\n")
  cat("Output workbook:", normalizePath(output_file, winslash = "/", mustWork = TRUE), "\n")
  cat("Log file:", normalizePath(log_file, winslash = "/", mustWork = FALSE), "\n")
  cat("Session info:", normalizePath(session_file, winslash = "/", mustWork = TRUE), "\n")

  invisible(list(
    plant = plant,
    input_file = input_file,
    output_file = output_file,
    log_file = log_file,
    session_file = session_file,
    method_audit = method_audit,
    fallback_summary = fallback_summary,
    method_specification = method_specification,
    sensitivity_summary = sens_summary,
    nonpositive_summary = nonpositive_summary,
    reconciliation_summary = reconciliation_summary,
    sign_audit = sign_audit,
    quarterly_continuity = quarterly_continuity,
    monthly_continuity = monthly_continuity
  ))
}

# ============================================================================
# EXECUTION CONFIGURATION
# ============================================================================
# Expected repository layout:
#
# data/01_monthlyization/
#   ARQ_XLSX_SA.xlsx
#   ARQ_XLSX_BM.xlsx
#
# Reproduced outputs are written to:
# outputs/01_monthlyization/
#
# The validated reference workbooks distributed with the repository are stored
# separately under results/01_monthlyization/.
# ============================================================================

INPUT_DIR <- file.path("data", "01_monthlyization")
OUTPUT_DIR <- file.path("outputs", "01_monthlyization")
RUN_TAG <- "REPRODUCED"

INPUT_FILES <- c(
  SA = file.path(INPUT_DIR, "ARQ_XLSX_SA.xlsx"),
  BM = file.path(INPUT_DIR, "ARQ_XLSX_BM.xlsx")
)

cat("\nInput files configured for this reproducibility run:\n")
print(INPUT_FILES)

missing_inputs <- INPUT_FILES[!file.exists(INPUT_FILES)]
if (length(missing_inputs) > 0L) {
  stop(
    "Input file(s) not found: ",
    paste(missing_inputs, collapse = " | "),
    "\nRun the script from the repository root and verify data/01_monthlyization/.",
    call. = FALSE
  )
}

results_reproduced <- list()

for (plant_name in names(INPUT_FILES)) {
  results_reproduced[[plant_name]] <- run_temporal_disaggregation(
    input_file = INPUT_FILES[[plant_name]],
    plant = plant_name,
    output_dir = OUTPUT_DIR,
    run_tag = RUN_TAG
  )
}

cat("\n============================================================\n")
cat("SA and BM temporal-disaggregation reproduction finished.\n")
cat("Reproduced outputs are in:", OUTPUT_DIR, "\n")
cat("============================================================\n")
