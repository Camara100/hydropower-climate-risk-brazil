# =============================================================================
# ARDL_BM.R
# Public reproducibility script
#
# Plant: Belo Monte (BM)
#
# This script reproduces the validated physical-risk ARDL pipeline used in the
# study. The validated specification is protected by internal assertions.
#
# Main features:
#   - monthly log-transformed, X-13-adjusted input series;
#   - ADF/KPSS stationarity assessment, with Zivot-Andrews used when required;
#   - maximum lag order = 4 and AIC-based ARDL lag selection;
#   - regime dummies: D_2023 and D_2024;
#   - HC1 robust covariance as the primary inference specification;
#   - VIF guardrail;
#   - Bounds test, Case 2, aligned with the fixed regime regressors;
#   - CUSUM stability tests;
#   - Granger tests;
#   - short-run, cumulative, and long-run elasticities;
#   - individual and combined conditional distributed-lag stress scenarios.
#
# IMPORTANT STRESS INTERPRETATION
#   Observed lagged generation remains fixed. The stress exercise is a
#   conditional distributed-lag scenario, NOT a fully recursive ARDL forecast.
#
# Validated model expected by the script: ARDL(1,1,1,0,1,0)
#
# Run this script from the repository root.
# Input data are read from data/02_ardl/.
# Reproduced outputs are written to outputs/02_ardl/.
# Package installation is NOT performed automatically.
# =============================================================================

Raiz <- function() {
  
  # ---------- PACKAGES ----------
  REQUIRED_PACKAGES <- c(
    "readxl", "dplyr", "tibble", "tidyr", "stringr", "purrr", "lubridate",
    "zoo", "dynlm", "lmtest", "sandwich", "car", "tseries", "urca",
    "strucchange", "ggplot2", "openxlsx", "ARDL", "officer", "flextable"
  )
  MISSING_PACKAGES <- REQUIRED_PACKAGES[
    !vapply(REQUIRED_PACKAGES, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(MISSING_PACKAGES)) {
    stop(
      "Missing required packages: ",
      paste(MISSING_PACKAGES, collapse = ", "),
      ". Install them before running ARDL_BM.R.",
      call. = FALSE
    )
  }
  invisible(lapply(REQUIRED_PACKAGES, library, character.only = TRUE))

  set.seed(123)
  options(stringsAsFactors = FALSE)
  
  # ---------- CONFIG GERAL ----------
  PLANTA       <- "BM"
  INPUT_XLSX   <- file.path("data", "02_ardl", "LN_Variaveis_Ajustadas_X13_BM.xlsx")
  SHEET        <- "Ajustada"
  
  MAX_ORDER    <- 4L
  CASE_BOUNDS  <- 2L
  
  # ---- ROBUSTEZ (NOVO) ----
  # Escolha:
  #   "HC1" = heterocedasticidade (White HC1)
  #   "HAC" = Newey–West (autocorrelação + heterocedasticidade)
  ROBUST_MODE <- "HC1"   # <- troque para "HAC" quando quiser Newey–West
  
  # Parâmetros HAC (Newey–West) — úteis p/ séries mensais
  # NW_LAG pode ser:
  #   "auto" (regra do sandwich::NeweyWest)
  #   inteiro (ex.: 4, 6, 12)
  NW_LAG      <- "auto"
  NW_PREWHITE <- TRUE
  NW_ADJUST   <- TRUE
  
  # ---- Stationarity (MÓDULO ÚNICO) ----
  ALPHA <- 0.05
  
  # ADF: ur.df type ("none"|"drift"|"trend")
  ADF_TYPE_LEVEL <- "drift"
  ADF_TYPE_D1    <- "drift"
  ADF_TYPE_D2    <- "drift"
  ADF_MAX_LAG    <- MAX_ORDER  # explicit maximum lag searched by AIC
  
  # KPSS: ur.kpss type ("mu"|"tau") e lags ("short"|"long")
  KPSS_TYPE_LEVEL <- "mu"
  KPSS_TYPE_D1    <- "mu"
  KPSS_TYPE_D2    <- "mu"
  KPSS_LAGS_RULE  <- "short"
  
  # ZA: desempate só no nível quando houver conflito (ADF vs KPSS)
  ZA_MODEL     <- "intercept" # "intercept" ou "trend"
  ZA_LAG_RULE  <- "ADF_AIC"   # usa o lag do ADF nível (selecionado por AIC) para ZA
  
  # ---- Screening guard-rail (não forçar 5 cegamente) ----
  P_CUTOFF     <- 0.05
  TOPK_TARGET  <- 5L
  MAX_X_POOL   <- 12L
  VIF_LIMIT    <- 10
  MAX_ITERS_VIF<- 15L
  
  # ---- Estresse ----
  STRESS_YEARS <- c("2022","2023","2024")
  TOP3_COMB    <- 3L #(alterar se necessário)
  
  # ---- MAPA DE CHOQUES (default aplicado quando variável não mapeada) ----
  STRESS_MAP <- list(
    "LN_Temperatura_BM_X13" = +10,
    "LN_Vazao_BM_X13"       = -10,
    "LN_Queimadas_BM_X13"   = +10,
    "LN_153000_BM_X13"      = -10,
    "LN_254010_BM_X13"      = -10,
    "LN_254011_BM_X13"      = -10,
    "LN_252001_BM_X13"      = -10
  )
  DEFAULT_PCT <- -10
  STRESS_MODE <- "conditional_distributed_lag_nonrecursive"

  # ---- Variáveis essenciais ----
  VARS <- list(
    date = "Data",
    y    = "LN_Energia_BM_X13"
  )
  date_col <- VARS$date
  
  # ============================================================
  # >>> PATCH: DUMMIES DE REGIME (2023-10 e 2024-08) <<<
  # ============================================================
  BREAK_2023 <- as.Date("2023-10-01")
  BREAK_2024 <- as.Date("2024-08-01")

  DUMMY_COLS <- c("D_2023", "D_2024")
  DUMMY_TERMS <- paste(DUMMY_COLS, collapse = " + ")

  OUTPUT_ROOT <- file.path("outputs", "02_ardl")
  
  # ---------- PASTAS / LOG ----------
  RUN_ID <- paste0(
    "REPRODUCED_",
    format(Sys.time(), "%Y-%m-%d_%H%M%S"),
    "_", PLANTA, "_ROBUST_", ROBUST_MODE
  )
  BASE_DIR <- file.path(OUTPUT_ROOT, PLANTA)
  DIRS     <- file.path(BASE_DIR, c("rds", "tables", "figs", "logs"))
  invisible(lapply(DIRS, dir.create, recursive = TRUE, showWarnings = FALSE))
  
  LOG_FILE <- file.path(BASE_DIR, "logs", "runner.log")
  log_con  <- file(LOG_FILE, open = "wt", encoding = "UTF-8")
  sink(log_con, split = TRUE)
  
  on.exit({
    if (sink.number() > 0) try(sink(type = "output"), silent = TRUE)
    try(if (isOpen(log_con)) close(log_con), silent = TRUE)
  }, add = TRUE)
  
  cat("== ARDL BM reproducibility pipeline ==\n")
  cat("Input:", INPUT_XLSX, " | Sheet:", SHEET, "\n")
  cat("Run:", RUN_ID, "\n")
  cat("ROBUST_MODE:", ROBUST_MODE, " | NW_LAG:", NW_LAG, " | PREWHITE:", NW_PREWHITE, " | ADJUST:", NW_ADJUST, "\n\n")
  
  # ============================================================
  # HELPERS (gerais)
  # ============================================================
  stop_if_missing_cols <- function(df, cols) {
    miss <- setdiff(cols, names(df))
    if (length(miss) > 0) stop("❌ Colunas ausentes: ", paste(miss, collapse = ", "))
  }
  
  coerce_numeric_cols <- function(df, num_cols){
    for (nm in num_cols) if (!is.numeric(df[[nm]])) df[[nm]] <- suppressWarnings(as.numeric(df[[nm]]))
    df
  }
  
  make_zoo <- function(df, cols, date_col) zoo::zoo(df[, cols, drop = FALSE], order.by = df[[date_col]])
  
  # lag helper (L(x,k) = lag para trás) — BLINDADO
  L <- function(x, k = 1) {
    if (length(k) != 1L || is.na(k) || !is.numeric(k)) stop("k inválido em L(x,k).")
    k <- as.integer(k)
    if (k < 0L) stop("k deve ser >= 0 em L(x,k).")
    if (k == 0L) return(x)
    stats::lag(x, -k)
  }
  
  .safe_is_numeric <- function(x) is.numeric(x) && any(is.finite(x))
  
  # ---- Sheet name <=31 + unicidade ----
  .safe_sheet_name <- function(x, used = character(0)) {
    x <- gsub("[\\[\\]\\*\\?/\\\\:]", "_", x)
    x <- gsub("\\s+", "_", x)
    x <- gsub("_+", "_", x)
    x <- gsub("^_+|_+$", "", x)
    if (!nzchar(x)) x <- "Sheet"
    
    maxlen <- 31L
    base <- substr(x, 1, maxlen)
    
    out <- base
    i <- 1L
    while (out %in% used) {
      suffix <- paste0("_", i)
      cutlen <- maxlen - nchar(suffix)
      out <- paste0(substr(base, 1, max(1, cutlen)), suffix)
      i <- i + 1L
    }
    out
  }
  
  .add_sheet_df <- function(wb, sheet, df, used_names_env){
    used <- get("used", envir = used_names_env, inherits = FALSE)
    sname <- .safe_sheet_name(sheet, used = used)
    assign("used", c(used, sname), envir = used_names_env)
    
    openxlsx::addWorksheet(wb, sname)
    if (is.null(df) || (is.data.frame(df) && nrow(df) == 0 && ncol(df) == 0)) {
      openxlsx::writeData(wb, sname, data.frame(Msg="Sem dados"), colNames = TRUE)
    } else {
      openxlsx::writeData(wb, sname, df, colNames = TRUE)
    }
    invisible(sname)
  }
  
  write_table <- function(df, fname) {
    path <- file.path(BASE_DIR, "tables", fname)
    openxlsx::write.xlsx(df, path, overwrite = TRUE)
    path
  }
  
  # ============================================================
  # VCOV ROBUSTO (NOVO): HC1 vs HAC(Newey–West)
  # ============================================================
  get_robust_vcov <- function(lm_obj,
                              robust_mode = c("HC1","HAC"),
                              nw_lag = "auto",
                              prewhite = TRUE,
                              adjust = TRUE) {
    
    robust_mode <- match.arg(robust_mode)
    
    if (!inherits(lm_obj, "lm")) return(vcov(lm_obj))
    
    if (robust_mode == "HC1") {
      V <- tryCatch(sandwich::vcovHC(lm_obj, type = "HC1"), error = function(e) NULL)
      if (is.null(V)) V <- vcov(lm_obj)
      return(V)
    }
    
    # HAC / Newey–West
    lag_use <- NULL
    if (is.character(nw_lag) && tolower(nw_lag) == "auto") {
      lag_use <- NULL
    } else {
      lag_use <- as.integer(nw_lag)
      if (!is.finite(lag_use) || lag_use < 0L) lag_use <- NULL
    }
    
    V <- tryCatch({
      sandwich::NeweyWest(lm_obj, lag = lag_use, prewhite = isTRUE(prewhite), adjust = isTRUE(adjust))
    }, error = function(e) NULL)
    
    if (is.null(V)) V <- vcov(lm_obj)
    V
  }
  
  # ============================================================
  # PARSER FOR dynlm L(...) TERM NAMES — VALIDATED FOR BM
  #
  # Handles:
  #   L(x,k)       -> lag k
  #   L(x,a:a)     -> lag a
  #   L(x,a:b)j    -> lag j (dynlm suffix is the actual lag)
  # ============================================================
  .parse_term_L <- function(term_name) {
    # Simple term: L(x,k)
    m1 <- regexec("^L\\(([^,]+),\\s*(-?\\d+)\\)$", term_name, perl = TRUE)
    r1 <- regmatches(term_name, m1)[[1]]
    if (length(r1) == 3L) {
      return(list(var = trimws(r1[2]), lag = as.integer(r1[3])))
    }

    # Singleton range without suffix: L(x,a:a), e.g. L(y,1:1)
    ms <- regexec(
      "^L\\(([^,]+),\\s*(-?\\d+):(-?\\d+)\\)$",
      term_name,
      perl = TRUE
    )
    rs <- regmatches(term_name, ms)[[1]]
    if (length(rs) == 4L) {
      var <- trimws(rs[2])
      a <- as.integer(rs[3])
      b <- as.integer(rs[4])
      if (identical(a, b)) return(list(var = var, lag = a))
    }

    # Expanded range: L(x,a:b)j. The suffix is the actual dynlm lag.
    m2 <- regexec(
      "^L\\(([^,]+),\\s*(-?\\d+):(-?\\d+)\\)(-?\\d+)$",
      term_name,
      perl = TRUE
    )
    r2 <- regmatches(term_name, m2)[[1]]
    if (length(r2) == 5L) {
      var <- trimws(r2[2])
      a <- as.integer(r2[3])
      b <- as.integer(r2[4])
      suffix_lag <- as.integer(r2[5])

      if (!suffix_lag %in% seq.int(a, b)) return(NULL)
      return(list(var = var, lag = suffix_lag))
    }

    NULL
  }

  # ============================================================
  # helper beta(k=0) DEFINIDO ANTES DO USO
  # ============================================================
  .get_beta_k0 <- function(modelo_dynlm, var){
    b <- coef(modelo_dynlm)
    tnames <- names(b)
    
    # 1) Preferência máxima: termo explícito L(var,0)
    pat0 <- paste0("^L\\(", gsub("([\\W])", "\\\\\\1", var), ",\\s*0\\)$")
    idx0 <- grepl(pat0, tnames, perl = TRUE)
    if (any(idx0)) return(as.numeric(b[idx0][1]))
    
    # 2) Fallback: usa o parser e pega lag==0
    parsed <- lapply(tnames, .parse_term_L)
    ok <- vapply(parsed, function(pt){
      !is.null(pt) && identical(pt$var, var) && identical(pt$lag, 0L)
    }, logical(1))
    
    if (!any(ok)) return(NA_real_)
    as.numeric(b[ok][1])
  }
  
  # ============================================================
  # COEFS ROBUSTOS (HC1 ou HAC) — ATUALIZADO
  # ============================================================
  coefs_robustos_df <- function(lm_obj,
                                robust_mode = c("HC1","HAC"),
                                nw_lag = "auto",
                                prewhite = TRUE,
                                adjust = TRUE) {
    robust_mode <- match.arg(robust_mode)
    
    V <- get_robust_vcov(lm_obj,
                         robust_mode = robust_mode,
                         nw_lag = nw_lag,
                         prewhite = prewhite,
                         adjust = adjust)
    
    ct <- tryCatch(lmtest::coeftest(lm_obj, vcov. = V), error = function(e) NULL)
    m  <- tryCatch(as.matrix(ct), error = function(e) NULL)
    
    if (is.null(m)) {
      sm <- summary(lm_obj)$coefficients
      m <- as.matrix(sm[, 1:min(4, ncol(sm)), drop=FALSE])
    }
    if (ncol(m) < 4) {
      est <- m[,1]
      se  <- if (ncol(m)>=2) m[,2] else sqrt(diag(vcov(lm_obj)))
      t   <- est/se
      dfres <- tryCatch(df.residual(lm_obj), error=function(e) NA_integer_)
      p   <- if (is.finite(dfres)) 2*pt(abs(t), df=dfres, lower.tail=FALSE) else 2*pnorm(abs(t), lower.tail=FALSE)
      m   <- cbind(est, se, t, p)
      colnames(m) <- c("Estimate","Std. Error","t value","Pr(>|t|)")
    } else colnames(m)[1:4] <- c("Estimate","Std. Error","t value","Pr(>|t|)")
    
    data.frame(
      Termo=rownames(m),
      Estimativa=as.numeric(m[,1]),
      SE_Robusta=as.numeric(m[,2]),
      t=as.numeric(m[,3]),
      p=as.numeric(m[,4]),
      row.names=NULL,
      check.names=FALSE
    )
  }
  
  diag_metrics <- function(lm_obj) {
    out <- list()
    out$DW  <- tryCatch(lmtest::dwtest(lm_obj), error = function(e) NULL)
    out$BG4 <- tryCatch(lmtest::bgtest(lm_obj, order = 4), error = function(e) NULL)
    out$BP  <- tryCatch(lmtest::bptest(lm_obj), error = function(e) NULL)
    out$JB  <- tryCatch(tseries::jarque.bera.test(residuals(lm_obj)), error = function(e) NULL)
    out$VIF <- tryCatch({
      v <- car::vif(lm_obj)
      if (is.matrix(v)) data.frame(Variavel=rownames(v), VIF=as.numeric(v[,1]), row.names = NULL)
      else data.frame(Variavel=names(v), VIF=as.numeric(v), row.names = NULL)
    }, error = function(e) NULL)
    out
  }
  
  # ============================================================
  # RHS terms a partir de LAG_SPEC (auto_ardl best_order)
  # ============================================================
  build_rhs_terms_from_spec <- function(y, xs, lag_spec) {
    rhs <- character(0)
    
    if (!is.null(lag_spec$y) && length(lag_spec$y)) {
      rhs <- c(rhs, sprintf("L(%s,%s)", y, paste(range(lag_spec$y), collapse=":")))
    }
    
    for (x in xs) {
      ks <- sort(unique(lag_spec[[x]]))
      if (!length(ks)) next
      runs <- split(ks, cumsum(c(1, diff(ks) != 1)))
      for (r in runs) {
        rhs <- c(rhs, if (length(r) == 1) sprintf("L(%s,%d)", x, r) else sprintf("L(%s,%d:%d)", x, min(r), max(r)))
      }
    }
    rhs
  }
  
  # ============================================================
  # LOAD DATA
  # ============================================================
  raw <- readxl::read_excel(INPUT_XLSX, sheet = SHEET) %>% as.data.frame()
  if ("by" %in% names(raw)) { warning("Removendo coluna 'by' da base de entrada."); raw$by <- NULL }
  
  stop_if_missing_cols(raw, c(VARS$date, VARS$y))
  
  raw[[VARS$date]] <- as.Date(raw[[VARS$date]])
  raw <- raw %>% arrange(.data[[VARS$date]])
  
  df <- raw
  num_cols <- setdiff(names(df), VARS$date)
  df <- coerce_numeric_cols(df, num_cols)
  
  # remove colunas totalmente NA (exceto date)
  drop_all_na <- vapply(setdiff(names(df), VARS$date), function(v) all(!is.finite(df[[v]])), logical(1))
  if (any(drop_all_na)) {
    cat("Removendo colunas totalmente NA:\n"); print(names(drop_all_na)[drop_all_na])
    df <- df[, c(VARS$date, setdiff(names(df), c(names(drop_all_na)[drop_all_na], VARS$date))), drop=FALSE]
  }
  
  # ============================================================
  # >>> PATCH: CRIAÇÃO DAS DUMMIES (STEP) 2023-10 e 2024-08 <<<
  # ============================================================
  df[[date_col]] <- as.Date(df[[date_col]])
  df$D_2023 <- as.integer(df[[date_col]] >= BREAK_2023)
  df$D_2024 <- as.integer(df[[date_col]] >= BREAK_2024)

  cat("\n== Dummies de regime inseridas ==\n")
  cat("D_2023 = 1 se Data >= ", as.character(BREAK_2023), " (inclusive)\n", sep = "")
  cat("D_2024 = 1 se Data >= ", as.character(BREAK_2024), " (inclusive)\n", sep = "")
  cat("Prévia contagens:\n")
  print(data.frame(
    Dummy = c("D_2023","D_2024"),
    Soma1 = c(sum(df$D_2023, na.rm=TRUE), sum(df$D_2024, na.rm=TRUE)),
    Soma0 = c(sum(1L - df$D_2023, na.rm=TRUE), sum(1L - df$D_2024, na.rm=TRUE))
  ), row.names = FALSE)

  # ============================================================
  # STATIONARITY — MÓDULO ÚNICO (DETAIL + VERDICT)
  # ============================================================
  
  .get_cval_urca <- function(cval_obj, rowkey = NULL, target = c("1pct","5pct","10pct")) {
    target <- match.arg(target)
    if (is.null(cval_obj)) return(NA_real_)
    
    if (is.matrix(cval_obj)) {
      cn <- colnames(cval_obj)
      if (!is.null(cn) && target %in% cn) {
        if (!is.null(rowkey) && !is.null(rownames(cval_obj)) && rowkey %in% rownames(cval_obj)) {
          return(as.numeric(cval_obj[rowkey, target]))
        }
        return(as.numeric(cval_obj[1, target]))
      }
      if (!is.null(cn)) {
        patt <- switch(target, "1pct"="1", "5pct"="5", "10pct"="10")
        hit <- grep(paste0("^", patt), tolower(gsub("\\s+","",cn)))
        if (length(hit) >= 1) {
          if (!is.null(rowkey) && !is.null(rownames(cval_obj)) && rowkey %in% rownames(cval_obj)) {
            return(as.numeric(cval_obj[rowkey, hit[1]]))
          }
          return(as.numeric(cval_obj[1, hit[1]]))
        }
      }
      return(NA_real_)
    }
    
    if (is.numeric(cval_obj) && is.vector(cval_obj)) {
      nms <- names(cval_obj)
      if (!is.null(nms) && target %in% nms) return(as.numeric(cval_obj[[target]]))
      if (!is.null(nms)) {
        patt <- switch(target, "1pct"="1", "5pct"="5", "10pct"="10")
        hit <- grep(patt, nms, ignore.case = TRUE, value = TRUE)
        if (length(hit) >= 1) return(as.numeric(cval_obj[[hit[1]]]))
      }
      idx <- switch(target, "1pct"=1, "5pct"=2, "10pct"=3)
      if (length(cval_obj) >= idx) return(as.numeric(cval_obj[idx]))
      return(NA_real_)
    }
    
    NA_real_
  }
  
  .clean_series <- function(x, dates) {
    x <- suppressWarnings(as.numeric(x))
    ok <- is.finite(x) & !is.na(dates)
    list(x = x[ok], dates = dates[ok], n_total = length(x), n_used = sum(ok))
  }
  
  .adf_one <- function(x, type = "drift", max_lag = ADF_MAX_LAG) {
    x <- as.numeric(x)
    x <- x[is.finite(x)]
    if (length(x) < 20) {
      return(list(
        ok=FALSE, stat=NA_real_, cval=NULL, rowkey=NA_character_,
        lag=NA_integer_, max_lag=as.integer(max_lag), msg="amostra<20"
      ))
    }

    adf <- tryCatch(
      urca::ur.df(
        x,
        type = type,
        lags = as.integer(max_lag),
        selectlags = "AIC"
      ),
      error = function(e) e
    )
    if (inherits(adf, "error")) {
      return(list(
        ok=FALSE, stat=NA_real_, cval=NULL, rowkey=NA_character_,
        lag=NA_integer_, max_lag=as.integer(max_lag), msg=adf$message
      ))
    }

    rowkey <- switch(type, none="tau1", drift="tau2", trend="tau3", "tau2")
    stat <- tryCatch(as.numeric(adf@teststat[1]), error=function(e) NA_real_)

    # @testreg is summary.lm. Count lagged first-difference regressors
    # retained in the final AIC-selected ADF regression.
    lag_selected <- tryCatch({
      cm <- stats::coef(adf@testreg)
      rn <- rownames(cm)
      if (is.null(rn)) NA_integer_
      else as.integer(sum(grepl("^z\\.diff\\.lag", rn)))
    }, error=function(e) NA_integer_)

    list(
      ok=TRUE, stat=stat, cval=adf@cval, rowkey=rowkey,
      lag=lag_selected, max_lag=as.integer(max_lag), msg=""
    )
  }

  .kpss_one <- function(x, type = "mu", lags_rule = "short") {
    x <- as.numeric(x); x <- x[is.finite(x)]
    if (length(x) < 20) return(list(ok=FALSE, stat=NA_real_, cval=NULL, lag=NA_integer_, msg="amostra<20"))
    kp <- tryCatch(urca::ur.kpss(x, type = type, lags = lags_rule), error = function(e) e)
    if (inherits(kp, "error")) return(list(ok=FALSE, stat=NA_real_, cval=NULL, lag=NA_integer_, msg=kp$message))
    
    stat <- tryCatch(as.numeric(kp@teststat), error=function(e) NA_real_)
    lagv <- tryCatch({
      if ("lags" %in% slotNames(kp)) as.integer(kp@lags) else NA_integer_
    }, error=function(e) NA_integer_)
    
    list(ok=TRUE, stat=stat, cval=kp@cval, lag=lagv, msg="")
  }
  
  .adf_dec <- function(stat, cv5) {
    if (!is.finite(stat) || !is.finite(cv5)) return("Fail")
    if (stat < cv5) "Stationary" else "NonStationary"
  }
  .kpss_dec <- function(stat, cv5) {
    if (!is.finite(stat) || !is.finite(cv5)) return("Fail")
    if (stat < cv5) "Stationary" else "NonStationary"
  }
  
  .nobreak_status <- function(adf_dec, kpss_dec) {
    both_ok <- (adf_dec %in% c("Stationary","NonStationary")) && (kpss_dec %in% c("Stationary","NonStationary"))
    if (both_ok) {
      if (adf_dec == "Stationary" && kpss_dec == "Stationary") return("Stationary")
      if (adf_dec == "NonStationary" && kpss_dec == "NonStationary") return("NonStationary")
      return("Conflict")
    }
    if (adf_dec %in% c("Stationary","NonStationary") && kpss_dec == "Fail") return(adf_dec)
    if (kpss_dec %in% c("Stationary","NonStationary") && adf_dec == "Fail") return(kpss_dec)
    "Fail"
  }
  
  .za_one <- function(x, dates, model = "intercept", lag = 1L) {
    x <- as.numeric(x); ok <- is.finite(x)
    x <- x[ok]; dates <- dates[ok]
    if (length(x) < 30) return(list(ok=FALSE, stat=NA_real_, cval=NULL, lag=as.integer(lag), break_index=NA_integer_, break_date=as.Date(NA), msg="amostra<30"))
    
    za <- suppressWarnings(tryCatch(urca::ur.za(x, model = model, lag = as.integer(lag)), error = function(e) e))
    if (inherits(za, "error")) return(list(ok=FALSE, stat=NA_real_, cval=NULL, lag=as.integer(lag), break_index=NA_integer_, break_date=as.Date(NA), msg=za$message))
    
    stat <- tryCatch(as.numeric(za@teststat[1]), error=function(e) NA_real_)
    cval <- tryCatch(za@cval, error=function(e) NULL)
    
    bidx <- tryCatch(as.integer(za@bpoint)[1], error=function(e) NA_integer_)
    bdate <- as.Date(NA)
    if (is.finite(bidx) && bidx >= 1 && bidx <= length(dates)) bdate <- as.Date(dates[bidx])
    
    list(ok=TRUE, stat=stat, cval=cval, lag=as.integer(lag), break_index=bidx, break_date=bdate, msg="")
  }
  
  .run_one_order <- function(xvec, adf_type, kpss_type, kpss_lags_rule) {
    adf <- .adf_one(xvec, type = adf_type)
    kp  <- .kpss_one(xvec, type = kpss_type, lags_rule = kpss_lags_rule)
    
    adf_cv1  <- .get_cval_urca(adf$cval, rowkey = adf$rowkey, target = "1pct")
    adf_cv5  <- .get_cval_urca(adf$cval, rowkey = adf$rowkey, target = "5pct")
    adf_cv10 <- .get_cval_urca(adf$cval, rowkey = adf$rowkey, target = "10pct")
    
    kp_cv1   <- .get_cval_urca(kp$cval, target = "1pct")
    kp_cv5   <- .get_cval_urca(kp$cval, target = "5pct")
    kp_cv10  <- .get_cval_urca(kp$cval, target = "10pct")
    
    adf_dec <- .adf_dec(adf$stat, adf_cv5)
    kp_dec  <- .kpss_dec(kp$stat, kp_cv5)
    
    list(
      ADF_type=adf_type, ADF_lag=adf$lag, ADF_stat=adf$stat, ADF_cv1=adf_cv1, ADF_cv5=adf_cv5, ADF_cv10=adf_cv10, ADF_dec=adf_dec, ADF_msg=adf$msg,
      KPSS_type=kpss_type, KPSS_lag=kp$lag, KPSS_stat=kp$stat, KPSS_cv1=kp_cv1, KPSS_cv5=kp_cv5, KPSS_cv10=kp_cv10, KPSS_dec=kp_dec, KPSS_msg=kp$msg,
      NoBreak_status=.nobreak_status(adf_dec, kp_dec)
    )
  }
  
  run_stationarity_module <- function(df, date_col, vars, cfg) {
    stopifnot(date_col %in% names(df))
    dates0 <- as.Date(df[[date_col]])
    
    detail_rows <- list()
    verdict_rows <- list()
    
    for (v in vars) {
      xraw <- df[[v]]
      cl0 <- .clean_series(xraw, dates0)
      
      msg0 <- ""
      has_var <- isTRUE(sd(cl0$x, na.rm = TRUE) > 0)
      if (!has_var) msg0 <- "serie_constante_ou_sem_variancia"
      if (length(cl0$x) < 20) msg0 <- paste0(msg0, ifelse(nchar(msg0)>0,";",""), "amostra_pequena")
      
      x0 <- cl0$x
      dts0 <- cl0$dates
      x1 <- if (length(x0) >= 2) diff(x0) else numeric(0)
      x2 <- if (length(x0) >= 3) diff(diff(x0)) else numeric(0)
      
      r0 <- .run_one_order(x0, cfg$ADF_TYPE_LEVEL, cfg$KPSS_TYPE_LEVEL, cfg$KPSS_LAGS_RULE)
      r1 <- .run_one_order(x1, cfg$ADF_TYPE_D1,  cfg$KPSS_TYPE_D1,  cfg$KPSS_LAGS_RULE)
      r2 <- .run_one_order(x2, cfg$ADF_TYPE_D2,  cfg$KPSS_TYPE_D2,  cfg$KPSS_LAGS_RULE)
      
      za_used <- FALSE
      za <- list(ok=FALSE, stat=NA_real_, cval=NULL, lag=NA_integer_, break_index=NA_integer_, break_date=as.Date(NA), msg="NAO_USADO")
      final_nivel <- r0$NoBreak_status
      
      za_cv1 <- NA_real_; za_cv5 <- NA_real_; za_cv10 <- NA_real_; za_dec <- NA_character_
      
      if (identical(r0$NoBreak_status, "Conflict")) {
        za_used <- TRUE
        lag_za <- 1L
        if (identical(cfg$ZA_LAG_RULE, "ADF_AIC") && is.finite(r0$ADF_lag)) lag_za <- as.integer(r0$ADF_lag)
        za <- .za_one(x0, dts0, model = cfg$ZA_MODEL, lag = lag_za)
        
        za_cv1  <- .get_cval_urca(za$cval, target="1pct")
        za_cv5  <- .get_cval_urca(za$cval, target="5pct")
        za_cv10 <- .get_cval_urca(za$cval, target="10pct")
        
        za_dec <- if (!isTRUE(za$ok)) "Fail"
        else if (is.finite(za$stat) && is.finite(za_cv5) && (za$stat < za_cv5)) "Stationary"
        else "NonStationary"
        
        if (za_dec %in% c("Stationary","NonStationary")) final_nivel <- za_dec else final_nivel <- "Conflict"
      }
      
      final_d1 <- r1$NoBreak_status
      final_d2 <- r2$NoBreak_status
      
      I_class <- "Inconclusiva"
      I_flag_I2 <- FALSE
      I_msg <- ""
      
      if (identical(final_nivel, "Stationary")) {
        I_class <- "I(0)"; I_msg <- "nivel_estacionario"
      } else if (identical(final_d1, "Stationary")) {
        I_class <- "I(1)"; I_msg <- "d1_estacionario"
      } else if (identical(final_d2, "Stationary")) {
        I_class <- "I(2)"; I_flag_I2 <- TRUE; I_msg <- "d2_estacionario"
      } else {
        cond0 <- final_nivel %in% c("NonStationary","Conflict","Fail")
        cond1 <- final_d1    %in% c("NonStationary","Conflict","Fail")
        cond2 <- final_d2    %in% c("Conflict","Fail","NonStationary")
        if (cond0 && cond1 && cond2) {
          I_class <- "I(2)_provavel"
          I_flag_I2 <- TRUE
          I_msg <- "nivel_e_d1_nao_resolvidos;d2_nao_confirma"
        } else {
          I_class <- "Inconclusiva"
          I_msg <- "evidencia_insuficiente_apos_fallback"
        }
      }
      
      guard <- "OK"
      if (I_class %in% c("I(2)")) guard <- "BLOCK_I2"
      if (I_class %in% c("I(2)_provavel")) guard <- "WARN_I2"
      if (I_class %in% c("Inconclusiva")) guard <- "WARN_INCONCLUSIVE"
      
      detail_rows[[length(detail_rows)+1]] <- tibble::tibble(
        Variavel = v,
        n_total = length(xraw),
        n_usado_nivel = length(x0),
        n_usado_d1 = length(x1),
        n_usado_d2 = length(x2),
        has_variance = has_var,
        msg_data = msg0,
        
        ADF_type_nivel = r0$ADF_type, ADF_maxlag_nivel = ADF_MAX_LAG, ADF_lag_nivel = r0$ADF_lag, ADF_stat_nivel = round(r0$ADF_stat, 6),
        ADF_cv1_nivel = round(r0$ADF_cv1, 6), ADF_cv5_nivel = round(r0$ADF_cv5, 6), ADF_cv10_nivel = round(r0$ADF_cv10, 6),
        ADF_dec_nivel = r0$ADF_dec, ADF_msg_nivel = r0$ADF_msg,
        
        KPSS_type_nivel = r0$KPSS_type, KPSS_lag_nivel = r0$KPSS_lag, KPSS_stat_nivel = round(r0$KPSS_stat, 6),
        KPSS_cv1_nivel = round(r0$KPSS_cv1, 6), KPSS_cv5_nivel = round(r0$KPSS_cv5, 6), KPSS_cv10_nivel = round(r0$KPSS_cv10, 6),
        KPSS_dec_nivel = r0$KPSS_dec, KPSS_msg_nivel = r0$KPSS_msg,
        
        NoBreak_status_nivel = r0$NoBreak_status,
        Final_status_nivel = final_nivel,
        
        ADF_type_d1 = r1$ADF_type, ADF_maxlag_d1 = ADF_MAX_LAG, ADF_lag_d1 = r1$ADF_lag, ADF_stat_d1 = round(r1$ADF_stat, 6),
        ADF_cv1_d1 = round(r1$ADF_cv1, 6), ADF_cv5_d1 = round(r1$ADF_cv5, 6), ADF_cv10_d1 = round(r1$ADF_cv10, 6),
        ADF_dec_d1 = r1$ADF_dec, ADF_msg_d1 = r1$ADF_msg,
        
        KPSS_type_d1 = r1$KPSS_type, KPSS_lag_d1 = r1$KPSS_lag, KPSS_stat_d1 = round(r1$KPSS_stat, 6),
        KPSS_cv1_d1 = round(r1$KPSS_cv1, 6), KPSS_cv5_d1 = round(r1$KPSS_cv5, 6), KPSS_cv10_d1 = round(r1$KPSS_cv10, 6),
        KPSS_dec_d1 = r1$KPSS_dec, KPSS_msg_d1 = r1$KPSS_msg,
        
        NoBreak_status_d1 = r1$NoBreak_status,
        Final_status_d1 = final_d1,
        
        ADF_type_d2 = r2$ADF_type, ADF_maxlag_d2 = ADF_MAX_LAG, ADF_lag_d2 = r2$ADF_lag, ADF_stat_d2 = round(r2$ADF_stat, 6),
        ADF_cv1_d2 = round(r2$ADF_cv1, 6), ADF_cv5_d2 = round(r2$ADF_cv5, 6), ADF_cv10_d2 = round(r2$ADF_cv10, 6),
        ADF_dec_d2 = r2$ADF_dec,
        ADF_msg_d2 = r2$ADF_msg,
        
        KPSS_type_d2 = r2$KPSS_type, KPSS_lag_d2 = r2$KPSS_lag, KPSS_stat_d2 = round(r2$KPSS_stat, 6),
        KPSS_cv1_d2 = round(r2$KPSS_cv1, 6), KPSS_cv5_d2 = round(r2$KPSS_cv5, 6), KPSS_cv10_d2 = round(r2$KPSS_cv10, 6),
        KPSS_dec_d2 = r2$KPSS_dec, KPSS_msg_d2 = r2$KPSS_msg,
        
        NoBreak_status_d2 = r2$NoBreak_status,
        Final_status_d2 = final_d2,
        
        ZA_used = za_used,
        ZA_model = if (za_used) cfg$ZA_MODEL else NA_character_,
        ZA_lag_select = if (za_used) cfg$ZA_LAG_RULE else NA_character_,
        ZA_lag = if (za_used) za$lag else NA_integer_,
        ZA_stat = if (za_used) round(za$stat, 6) else NA_real_,
        ZA_cv1 = if (za_used) round(za_cv1, 6) else NA_real_,
        ZA_cv5 = if (za_used) round(za_cv5, 6) else NA_real_,
        ZA_cv10 = if (za_used) round(za_cv10, 6) else NA_real_,
        ZA_break_index = if (za_used) za$break_index else NA_integer_,
        ZA_break_date = if (za_used) as.Date(za$break_date) else as.Date(NA),
        ZA_dec = if (za_used) za_dec else NA_character_,
        ZA_msg = if (za_used) za$msg else NA_character_
      )
      
      verdict_rows[[length(verdict_rows)+1]] <- tibble::tibble(
        Variavel = v,
        Final_status_nivel = final_nivel,
        Final_status_d1 = final_d1,
        Final_status_d2 = final_d2,
        I_class = I_class,
        I_flag_I2 = I_flag_I2,
        I_msg = I_msg,
        Used_ZA = za_used,
        ZA_break_date = if (za_used) as.Date(za$break_date) else as.Date(NA),
        Guardrail_ARDL = guard
      )
    }
    
    detail <- dplyr::bind_rows(detail_rows) %>% as.data.frame()
    verdict <- dplyr::bind_rows(verdict_rows) %>% as.data.frame()
    
    list(detail = detail, verdict = verdict)
  }
  
  cat("== Stationarity (MÓDULO ÚNICO) — ADF/KPSS (nível/Δ/Δ²) + ZA (só conflito no nível) ==\n")
  
  # >>> PATCH: EXCLUI dummies do módulo de estacionariedade
  vars_all <- setdiff(names(df), date_col)
  vars_all <- setdiff(vars_all, DUMMY_COLS)
  
  vars_all <- vars_all[vapply(vars_all, function(v){
    x <- df[[v]]
    .safe_is_numeric(x) && (sd(x, na.rm = TRUE) > 0)
  }, logical(1))]
  
  station_cfg <- list(
    ADF_TYPE_LEVEL = ADF_TYPE_LEVEL,
    ADF_TYPE_D1 = ADF_TYPE_D1,
    ADF_TYPE_D2 = ADF_TYPE_D2,
    KPSS_TYPE_LEVEL = KPSS_TYPE_LEVEL,
    KPSS_TYPE_D1 = KPSS_TYPE_D1,
    KPSS_TYPE_D2 = KPSS_TYPE_D2,
    KPSS_LAGS_RULE = KPSS_LAGS_RULE,
    ZA_MODEL = ZA_MODEL,
    ZA_LAG_RULE = ZA_LAG_RULE
  )
  
  station_mod <- run_stationarity_module(df, date_col = date_col, vars = vars_all, cfg = station_cfg)
  station_detail  <- station_mod$detail
  station_verdict <- station_mod$verdict
  
  cat("\nPrévia (verdict):\n")
  print(utils::head(as.data.frame(station_verdict), 12), row.names = FALSE)
  
  write_table(station_detail,  "Stationarity_DETAIL.xlsx")
  write_table(station_verdict, "Stationarity_VERDICT.xlsx")
  
  # ============================================================
  # (1) SCREENING GLOBAL (univariado): TODAS X candidatas -> best_p
  # ============================================================
  ALL_COLS <- names(df)
  
  # >>> PATCH: EXCLUI dummies do pool de candidatas
  cand_vars <- setdiff(ALL_COLS, c(date_col, VARS$y, DUMMY_COLS))
  cand_vars <- cand_vars[vapply(cand_vars, function(v){
    x <- df[[v]]
    .safe_is_numeric(x) && (sd(x, na.rm = TRUE) > 0)
  }, logical(1))]
  
  if (length(cand_vars) < 1) stop("Não há candidatas X numéricas (excluindo data, y e dummies).")
  
  cat("\n== Screening global (univariado): candidatas X =", length(cand_vars), "==\n")
  
  score_one_x <- function(xname){
    # >>> PATCH: garante dummies presentes no data=zoo do dynlm
    serie1 <- make_zoo(df, cols = unique(c(VARS$y, xname, DUMMY_COLS)), date_col = date_col)
    idx1   <- zoo::index(serie1)
    start_y <- as.integer(format(min(idx1), "%Y"))
    start_m <- as.integer(format(min(idx1), "%m"))
    
    # auto_ardl (seleção de lags) continua apenas em y e x, sem dummies
    Xmat1 <- sapply(c(VARS$y, xname), function(v) as.numeric(serie1[, v]))
    colnames(Xmat1) <- c(VARS$y, xname)
    ts1 <- ts(Xmat1, start = c(start_y, start_m), frequency = 12)
    
    fml1 <- as.formula(paste0(VARS$y, " ~ ", xname))
    
    auto1 <- tryCatch(
      ARDL::auto_ardl(fml1, data = ts1, max_order = MAX_ORDER, selection = "AIC", trend = "c"),
      error = function(e) NULL
    )
    if (is.null(auto1)) {
      return(data.frame(Variavel=xname, best_p=NA_real_, best_term=NA_character_, ok=FALSE))
    }
    
    P1 <- unname(auto1$best_order[VARS$y])
    Q1 <- as.integer(unname(auto1$best_order[xname]))
    
    lag_spec1 <- list()
    lag_spec1$y <- if (P1 > 0L) seq_len(P1) else integer(0)
    lag_spec1[[xname]] <- if (Q1 >= 0L) 0:Q1 else integer(0)
    
    rhs_terms1 <- build_rhs_terms_from_spec(VARS$y, c(xname), lag_spec1)
    if (length(rhs_terms1) == 0) {
      return(data.frame(Variavel=xname, best_p=NA_real_, best_term=NA_character_, ok=FALSE))
    }
    
    # >>> PATCH: inclui dummies como exógenas (sem lags) no dynlm
    fml_dyn1 <- as.formula(paste0(VARS$y, " ~ ", paste(rhs_terms1, collapse=" + "), " + ", DUMMY_TERMS))
    fit1 <- tryCatch(dynlm::dynlm(fml_dyn1, data = serie1), error = function(e) NULL)
    if (is.null(fit1)) {
      return(data.frame(Variavel=xname, best_p=NA_real_, best_term=NA_character_, ok=FALSE))
    }
    
    # >>> NOVO: p-valor robusto conforme ROBUST_MODE
    crb1 <- coefs_robustos_df(
      fit1,
      robust_mode = ROBUST_MODE,
      nw_lag = NW_LAG, prewhite = NW_PREWHITE, adjust = NW_ADJUST
    )
    
    parsed <- lapply(crb1$Termo, .parse_term_L)
    varx   <- vapply(parsed, function(z) if (is.null(z)) NA_character_ else z$var, character(1))
    rows_x <- crb1[is.finite(crb1$p) & (varx == xname), , drop=FALSE]
    
    if (nrow(rows_x) == 0) {
      return(data.frame(Variavel=xname, best_p=NA_real_, best_term=NA_character_, ok=FALSE))
    }
    
    j <- which.min(rows_x$p)
    data.frame(Variavel=xname, best_p=rows_x$p[j], best_term=rows_x$Termo[j], ok=is.finite(rows_x$p[j]))
  }
  
  screen_tbl <- dplyr::bind_rows(lapply(cand_vars, score_one_x)) %>%
    dplyr::filter(ok, is.finite(best_p)) %>%
    dplyr::arrange(best_p)
  
  cat("\n== Top 20 do screening (menor p) ==\n")
  print(utils::head(as.data.frame(screen_tbl), 20), row.names = FALSE)
  write_table(screen_tbl, "screening_global_rank.xlsx")
  
  eligible_tbl <- screen_tbl %>% dplyr::filter(best_p <= P_CUTOFF)
  
  cat("\n== Guard-rail do screening: elegíveis (best_p <= ", P_CUTOFF, ") = ", nrow(eligible_tbl), " ==\n", sep="")
  if (nrow(eligible_tbl) == 0) {
    stop("❌ Nenhuma variável elegível no screening (best_p <= ", P_CUTOFF, "). Ajuste P_CUTOFF ou revise a base.")
  }
  
  if (nrow(eligible_tbl) > MAX_X_POOL) {
    cat("⚠️ Muitas elegíveis. Limitando pool a MAX_X_POOL =", MAX_X_POOL, " (top por best_p).\n")
    eligible_tbl <- eligible_tbl %>% dplyr::slice(1:MAX_X_POOL)
  }
  
  rank_pool <- eligible_tbl$Variavel
  K0 <- min(TOPK_TARGET, length(rank_pool))
  if (K0 < 1) stop("Não há variáveis elegíveis suficientes para iniciar multivariado.")
  
  # ============================================================
  # (2) MULTIVARIADO: auto_ardl(AIC) + dynlm + fallback por VIF
  # ============================================================
  fit_multivar_ardl <- function(xs_vec){
    # >>> PATCH: garante dummies presentes no data=zoo do dynlm
    serieM <- make_zoo(df, cols = unique(c(VARS$y, xs_vec, DUMMY_COLS)), date_col = date_col)
    idxM   <- zoo::index(serieM)
    start_y <- as.integer(format(min(idxM), "%Y"))
    start_m <- as.integer(format(min(idxM), "%m"))
    
    # auto_ardl (seleção de lags) continua apenas em y e xs, sem dummies
    XmatM <- sapply(c(VARS$y, xs_vec), function(v) as.numeric(serieM[, v]))
    colnames(XmatM) <- c(VARS$y, xs_vec)
    tsM <- ts(XmatM, start = c(start_y, start_m), frequency = 12)
    
    fmlM <- as.formula(paste0(VARS$y, " ~ ", paste(xs_vec, collapse=" + ")))
    
    autoM <- tryCatch(
      ARDL::auto_ardl(fmlM, data = tsM, max_order = MAX_ORDER, selection = "AIC", trend = "c"),
      error = function(e) NULL
    )
    if (is.null(autoM)) return(list(ok=FALSE, msg="auto_ardl falhou", xs=xs_vec))
    
    P_AR <- unname(autoM$best_order[VARS$y])
    Q_MAP <- as.list(autoM$best_order[xs_vec])
    
    LAG_SPEC_M <- list(y = if (P_AR > 0L) seq_len(P_AR) else integer(0))
    for (x in xs_vec) {
      qx <- as.integer(Q_MAP[[x]])
      LAG_SPEC_M[[x]] <- if (qx >= 0L) 0:qx else integer(0)
    }
    
    rhs_terms <- build_rhs_terms_from_spec(VARS$y, xs_vec, LAG_SPEC_M)
    if (length(rhs_terms) == 0) return(list(ok=FALSE, msg="rhs_terms vazio", xs=xs_vec))
    
    # >>> PATCH: inclui dummies como exógenas (sem lags) no dynlm final
    fml_dyn <- as.formula(paste0(VARS$y, " ~ ", paste(rhs_terms, collapse=" + "), " + ", DUMMY_TERMS))
    fit <- tryCatch(dynlm::dynlm(fml_dyn, data = serieM), error = function(e) NULL)
    if (is.null(fit)) return(list(ok=FALSE, msg="dynlm falhou", xs=xs_vec))
    
    di <- diag_metrics(fit)
    vif_df <- di$VIF
    max_vif <- if (!is.null(vif_df) && nrow(vif_df)) max(vif_df$VIF, na.rm=TRUE) else NA_real_
    
    list(ok=TRUE, xs=xs_vec, auto=autoM, lag_spec=LAG_SPEC_M, fit=fit, diags=di, vif=vif_df, max_vif=max_vif)
  }
  
  choose_drop_by_pressure <- function(fit_obj, xs_current){
    crb <- coefs_robustos_df(
      fit_obj,
      robust_mode = ROBUST_MODE,
      nw_lag = NW_LAG, prewhite = NW_PREWHITE, adjust = NW_ADJUST
    )
    parsed <- lapply(crb$Termo, .parse_term_L)
    varx   <- vapply(parsed, function(z) if (is.null(z)) NA_character_ else z$var, character(1))
    
    tmp <- data.frame(Termo=crb$Termo, var=varx, p=crb$p, stringsAsFactors=FALSE)
    tmp <- tmp[tmp$var %in% xs_current & is.finite(tmp$p), , drop=FALSE]
    if (!nrow(tmp)) return(xs_current[1])
    
    agg <- tmp %>%
      dplyr::group_by(var) %>%
      dplyr::summarise(pmin = min(p, na.rm=TRUE), n_terms = dplyr::n(), .groups="drop") %>%
      dplyr::mutate(score_drop = pmin * (1 + 0.1*n_terms)) %>%
      dplyr::arrange(desc(score_drop))
    
    agg$var[1]
  }
  
  xs_current <- rank_pool[1:K0]
  used <- xs_current
  best_run <- NULL
  
  cat("\n== Multivariado: iniciando com K0 =", K0, " variáveis elegíveis ==\n", sep="")
  print(xs_current)
  
  for (iter in seq_len(MAX_ITERS_VIF)) {
    run <- fit_multivar_ardl(xs_current)
    
    if (!isTRUE(run$ok)) {
      cat("Iter ", iter, ": falha no ajuste multivariado (", run$msg, "). Tentando trocar 1 variável...\n", sep="")
    } else {
      cat("Iter ", iter, ": max VIF = ", run$max_vif, "\n", sep="")
      best_run <- run
      if (is.finite(run$max_vif) && run$max_vif <= VIF_LIMIT) {
        cat("✅ VIF dentro do limite. Conjunto final selecionado.\n")
        break
      }
    }
    
    drop_var <- if (!is.null(run$fit)) choose_drop_by_pressure(run$fit, xs_current) else xs_current[length(xs_current)]
    cat("-> Removendo: ", drop_var, "\n", sep="")
    
    xs_new <- setdiff(xs_current, drop_var)
    
    next_var <- setdiff(rank_pool, union(used, xs_new))[1]
    if (is.na(next_var) || length(next_var)==0) {
      cat("⚠️ Pool esgotado. Reestimando explicitamente o conjunto reduzido.\n")
      xs_current <- xs_new
      if (length(xs_current) < 1L) stop("Pool esgotado e conjunto reduzido vazio.")
      run_reduced <- fit_multivar_ardl(xs_current)
      if (!isTRUE(run_reduced$ok)) {
        stop("Pool esgotado e conjunto reduzido falhou: ", run_reduced$msg)
      }
      best_run <- run_reduced
      break
    }
    cat("-> Adicionando: ", next_var, "\n", sep="")
    xs_current <- c(xs_new, next_var)
    used <- union(used, next_var)
  }
  
  if (is.null(best_run) || !isTRUE(best_run$ok)) stop("Falha: não foi possível obter ARDL multivariado válido.")
  
  XS_ORDERED <- best_run$xs
  auto_aux   <- best_run$auto
  LAG_SPEC   <- best_run$lag_spec
  fit        <- best_run$fit

  EXPECTED_XS <- c(
    "LN_Vazao_BM_X13",
    "LN_153000_BM_X13",
    "LN_254010_BM_X13",
    "LN_254011_BM_X13",
    "LN_252001_BM_X13"
  )
  EXPECTED_ORDER <- c(1L, 1L, 1L, 0L, 1L, 0L)
  CURRENT_ORDER <- as.integer(auto_aux$best_order[c(VARS$y, XS_ORDERED)])

  selection_audit <- data.frame(
    Item = c("Selected_X", "Expected_X", "Selected_Order", "Expected_Order", "X_Set_Identical", "Order_Identical"),
    Value = c(
      paste(XS_ORDERED, collapse = "; "),
      paste(EXPECTED_XS, collapse = "; "),
      paste(CURRENT_ORDER, collapse = ","),
      paste(EXPECTED_ORDER, collapse = ","),
      identical(XS_ORDERED, EXPECTED_XS),
      identical(unname(CURRENT_ORDER), EXPECTED_ORDER)
    ),
    stringsAsFactors = FALSE
  )

  if (!identical(XS_ORDERED, EXPECTED_XS)) {
    stop("FINAL_VALID_200826: selected X variables differ from the validated BM baseline.")
  }
  if (!identical(unname(CURRENT_ORDER), EXPECTED_ORDER)) {
    stop("FINAL_VALID_200826: lag order differs from validated ARDL(1,1,1,0,1,0).")
  }
  
  cat("\n✅ XS_ORDERED selecionado (Top-K final; K<=5, elegíveis por p<=0.05):\n")
  print(XS_ORDERED)
  cat("\n✅ best_order multivariado:\n")
  print(auto_aux$best_order)
  cat("\n✅ max VIF final: ", best_run$max_vif, "\n", sep="")
  
  # ============================================================
  # GUARD-RAIL ARDL: BLOQUEIA I(2) em y e nas X escolhidas
  # ============================================================
  .guardrail_i2 <- function(verdict_tbl, vars_needed){
    sub <- verdict_tbl[verdict_tbl$Variavel %in% vars_needed, , drop=FALSE]
    
    bad  <- sub$Variavel[sub$I_class == "I(2)"]
    warn <- sub$Variavel[sub$I_class == "I(2)_provavel"]
    inconc <- sub$Variavel[sub$I_class == "Inconclusiva" | is.na(sub$I_class)]
    
    list(
      ok = (length(bad)==0),
      bad = bad,
      warn_i2 = warn,
      inconclusivas = inconc,
      sub = sub
    )
  }
  
  vars_needed <- unique(c(VARS$y, XS_ORDERED))
  gr_i2 <- .guardrail_i2(station_verdict, vars_needed)
  
  cat("\n== Guard-rail I(d) (ARDL) ==\n")
  print(gr_i2$sub[, c("Variavel","I_class","Final_status_nivel","Final_status_d1","Final_status_d2","Used_ZA","ZA_break_date","Guardrail_ARDL")], row.names = FALSE)
  
  if (!gr_i2$ok) {
    stop("❌ Guard-rail ARDL acionado: variável(is) I(2) detectada(s): ",
         paste(gr_i2$bad, collapse=", "),
         " | Ajuste base/transformações ou remova estas variáveis antes do ARDL.")
  }
  
  # ============================================================
  # RESUMO DO MODELO + ROBUST (HC1 ou HAC)
  # ============================================================
  cat("\n== RESUMO DO MODELO (dynlm) ==\n")
  print(summary(fit))
  
  cat("\n== COEFICIENTES (ROBUST_MODE = ", ROBUST_MODE, ") ==\n", sep="")
  V_fit <- get_robust_vcov(
    fit,
    robust_mode = ROBUST_MODE,
    nw_lag = NW_LAG, prewhite = NW_PREWHITE, adjust = NW_ADJUST
  )
  rob <- lmtest::coeftest(fit, vcov. = V_fit)
  printCoefmat(as.matrix(rob), digits = 5, signif.stars = TRUE)
  
  coefs_rb <- coefs_robustos_df(
    fit,
    robust_mode = ROBUST_MODE,
    nw_lag = NW_LAG, prewhite = NW_PREWHITE, adjust = NW_ADJUST
  )
  diags    <- diag_metrics(fit)
  
  # ============================================================
  # ELASTICIDADES (CURTO E LONGO PRAZO) — ARDL (log-log)
  #   >>> NOVO: vcov coerente com ROBUST_MODE
  # ============================================================
  .get_coef_by_var_lag <- function(modelo_dynlm, var, lagk, parser_fun){
    b <- stats::coef(modelo_dynlm)
    tn <- names(b)
    parsed <- lapply(tn, parser_fun)
    hit <- which(vapply(parsed, function(pt){
      !is.null(pt) && identical(pt$var, var) && identical(pt$lag, as.integer(lagk))
    }, logical(1)))
    if (!length(hit)) return(list(val = 0, term = NA_character_, found = FALSE))
    list(val = as.numeric(b[hit[1]]), term = tn[hit[1]], found = TRUE)
  }
  
  .compute_elasticities_ardl <- function(fit, lag_spec, xs,
                                         robust_mode = c("HC1","HAC"),
                                         nw_lag = "auto",
                                         prewhite = TRUE,
                                         adjust = TRUE,
                                         parser_fun){
    
    robust_mode <- match.arg(robust_mode)
    stopifnot(inherits(fit, "lm"))
    if (is.null(lag_spec) || is.null(lag_spec$y)) stop("lag_spec inválido: precisa conter $y.")
    if (length(xs) == 0) stop("xs vazio.")
    
    V <- get_robust_vcov(fit, robust_mode = robust_mode,
                         nw_lag = nw_lag, prewhite = prewhite, adjust = adjust)
    
    yname <- as.character(formula(fit))[2]
    y_lags <- sort(unique(as.integer(lag_spec$y)))
    y_lags <- y_lags[y_lags >= 1L]
    
    phi_vals <- numeric(0)
    phi_terms <- character(0)
    for (j in y_lags) {
      cj <- .get_coef_by_var_lag(fit, yname, j, parser_fun)
      phi_vals  <- c(phi_vals, cj$val)
      phi_terms <- c(phi_terms, cj$term)
    }
    
    phi_sum <- sum(phi_vals, na.rm = TRUE)
    denom   <- 1 - phi_sum
    
    if (!is.finite(denom) || abs(denom) < 1e-8) {
      warning("Denominador (1 - sum(phi)) ~ 0. LR pode explodir. Cheque lags de y / estabilidade.")
    }
    
    out_rows <- list()
    detail_rows <- list()
    
    for (x in xs) {
      x_lags <- lag_spec[[x]]
      x_lags <- sort(unique(as.integer(x_lags)))
      if (!length(x_lags)) x_lags <- 0L
      
      beta_vals <- numeric(0)
      beta_terms <- character(0)
      beta_found <- logical(0)
      
      for (k in x_lags) {
        ck <- .get_coef_by_var_lag(fit, x, k, parser_fun)
        beta_vals  <- c(beta_vals, ck$val)
        beta_terms <- c(beta_terms, ck$term)
        beta_found <- c(beta_found, ck$found)
        
        detail_rows[[length(detail_rows)+1]] <- data.frame(
          Variavel = x, Lag = k, Termo = ck$term, Beta = ck$val, Found = ck$found,
          stringsAsFactors = FALSE
        )
      }
      
      beta0 <- beta_vals[which(x_lags == 0L)]
      if (!length(beta0)) beta0 <- 0
      
      sr_sum <- sum(beta_vals, na.rm = TRUE)
      lr <- sr_sum / denom
      
      se_sr0 <- NA_real_
      if (0L %in% x_lags) {
        t0 <- beta_terms[which(x_lags == 0L)][1]
        if (!is.na(t0) && t0 %in% colnames(V)) {
          se_sr0 <- sqrt(V[t0, t0])
        } else if (!is.na(t0) && t0 %in% rownames(V)) {
          se_sr0 <- sqrt(V[t0, t0])
        }
      }
      
      terms_beta <- beta_terms[beta_found & !is.na(beta_terms)]
      se_sr_sum <- NA_real_
      if (length(terms_beta) >= 1 && all(terms_beta %in% colnames(V))) {
        w <- rep(1, length(terms_beta))
        Vb <- V[terms_beta, terms_beta, drop = FALSE]
        se_sr_sum <- sqrt(as.numeric(t(w) %*% Vb %*% w))
      }
      
      se_lr <- NA_real_
      if (length(terms_beta) >= 1 && all(terms_beta %in% colnames(V))) {
        grad <- rep(0, ncol(V))
        names(grad) <- colnames(V)
        
        grad[terms_beta] <- 1/denom
        
        terms_phi <- phi_terms[!is.na(phi_terms)]
        terms_phi <- terms_phi[terms_phi %in% colnames(V)]
        if (length(terms_phi)) {
          grad[terms_phi] <- sr_sum/(denom^2)
        }
        
        se_lr <- sqrt(as.numeric(t(grad) %*% V %*% grad))
      }
      
      dfres <- tryCatch(stats::df.residual(fit), error=function(e) NA_integer_)

      stat_lr <- if (is.finite(se_lr) && se_lr > 0) lr/se_lr else NA_real_
      p_lr <- if (is.finite(stat_lr) && is.finite(dfres)) {
        2*stats::pt(abs(stat_lr), df=dfres, lower.tail=FALSE)
      } else NA_real_

      stat_sr_sum <- if (is.finite(se_sr_sum) && se_sr_sum > 0) sr_sum/se_sr_sum else NA_real_
      p_sr_sum <- if (is.finite(stat_sr_sum) && is.finite(dfres)) {
        2*stats::pt(abs(stat_sr_sum), df=dfres, lower.tail=FALSE)
      } else NA_real_

      stat_sr0 <- if (is.finite(se_sr0) && se_sr0 > 0) beta0/se_sr0 else NA_real_
      p_sr0 <- if (is.finite(stat_sr0) && is.finite(dfres)) {
        2*stats::pt(abs(stat_sr0), df=dfres, lower.tail=FALSE)
      } else NA_real_

      out_rows[[length(out_rows)+1]] <- data.frame(
        Variavel = x,
        p_y = length(y_lags),
        q_x = max(x_lags, na.rm = TRUE),
        Phi_sum = phi_sum,
        Denom_1_minus_phi = denom,
        
        SR_Impacto_beta0 = beta0,
        SR_Impacto_SE = se_sr0,
        SR_Impacto_p = p_sr0,
        
        SR_Acumulado_sumBeta = sr_sum,
        SR_Acumulado_SE = se_sr_sum,
        SR_Acumulado_p = p_sr_sum,
        
        LR_Elasticidade = lr,
        LR_SE = se_lr,
        LR_p = p_lr,
        
        stringsAsFactors = FALSE
      )
    }
    
    elastic_df <- dplyr::bind_rows(out_rows) %>% as.data.frame()
    detail_df  <- dplyr::bind_rows(detail_rows) %>% as.data.frame()
    
    list(elastic = elastic_df, detail = detail_df)
  }
  
  elas <- .compute_elasticities_ardl(
    fit = fit,
    lag_spec = LAG_SPEC,
    xs = XS_ORDERED,
    robust_mode = ROBUST_MODE,
    nw_lag = NW_LAG, prewhite = NW_PREWHITE, adjust = NW_ADJUST,
    parser_fun = .parse_term_L
  )
  
  elasticidades_tbl <- elas$elastic
  elasticidades_detail <- elas$detail
  
  cat("\n== Elasticidades (curto e longo prazo) — PREVIA ==\n")
  print(elasticidades_tbl, row.names = FALSE)
  
  # ============================================================
  # CHECK PARSER/VALIDAÇÃO (exemplo: Vazão)
  # ============================================================
  cat("\n== CHECK PARSER/VALIDACAO (Vazao) ==\n")
  b <- coef(fit); tn <- names(b)
  keep <- grepl("LN_Vazao_BM_X13", tn, fixed = TRUE)
  print(data.frame(
    Termo = tn[keep],
    Beta  = unname(b[keep]),
    Parsed_var = vapply(lapply(tn[keep], .parse_term_L), function(z) if (is.null(z)) NA_character_ else z$var, character(1)),
    Parsed_lag = vapply(lapply(tn[keep], .parse_term_L), function(z) if (is.null(z)) NA_integer_ else z$lag, integer(1)),
    row.names = NULL
  ), row.names = FALSE)
  
  bk0 <- .get_beta_k0(fit, "LN_Vazao_BM_X13")
  cat("beta_k0 extraído =", bk0, "\n")
  
  # ============================================================
  # RANKING FINAL (multivariado final; robusto via parser)
  # ============================================================
  rank_vars <- {
    parsed <- lapply(coefs_rb$Termo, .parse_term_L)
    varx   <- vapply(parsed, function(z) if (is.null(z)) NA_character_ else z$var, character(1))
    
    tmp <- data.frame(Termo=coefs_rb$Termo, var=varx, p=coefs_rb$p, stringsAsFactors=FALSE)
    tmp <- tmp[tmp$var %in% XS_ORDERED & is.finite(tmp$p), , drop=FALSE]
    
    if (!nrow(tmp)) {
      data.frame(Msg="Ranking vazio (nenhum termo L(x,k) com p válido).")
    } else {
      tmp %>%
        dplyr::group_by(var) %>%
        dplyr::summarise(best_p=min(p, na.rm=TRUE), best_termo=Termo[which.min(p)], .groups="drop") %>%
        dplyr::arrange(best_p) %>%
        dplyr::rename(var_base = var)
    }
  }
  cat("\n== Ranking interno (multivariado final) ==\n")
  print(rank_vars)
  
  # ============================================================
  # CONFIG — seleção de variáveis do Estresse Combinado
  # ============================================================
  TOP3_MODE <- "auto"   # "auto" | "manual" | "hybrid"
  
  TOP3_MANUAL_VARS <- c(
    "LN_Vazao_BM_X13",
    "LN_153000_BM_X13",
    "LN_254010_BM_X13"
  )

  TOP3_PMAX <- Inf      # Inf = não filtra
  
  choose_topk_from_model <- function(coefs_rb, xs_ordered, k = 3L,
                                     mode = c("auto","manual","hybrid"),
                                     manual_vars = character(0),
                                     pmax = Inf) {
    
    mode <- match.arg(mode)
    
    fallback <- xs_ordered[1:min(k, length(xs_ordered))]
    if (length(xs_ordered) == 0) return(character(0))
    
    manual_vars <- unique(manual_vars)
    if (mode == "manual") {
      if (length(manual_vars) == 0) {
        stop("TOP3_MODE='manual' mas TOP3_MANUAL_VARS está vazio.")
      }
      manual_ok <- manual_vars[manual_vars %in% xs_ordered]
      if (length(manual_ok) == 0) {
        stop("Nenhuma variável manual está em XS_ORDERED. Verifique nomes e XS_ORDERED.")
      }
      return(manual_ok[1:min(k, length(manual_ok))])
    }
    
    if (is.null(coefs_rb) || !nrow(coefs_rb)) {
      if (mode == "hybrid" && length(manual_vars) > 0) {
        forced <- manual_vars[manual_vars %in% xs_ordered]
        out <- unique(c(forced, setdiff(fallback, forced)))
        return(out[1:min(k, length(out))])
      }
      return(fallback)
    }
    
    parsed <- lapply(coefs_rb$Termo, .parse_term_L)
    vars   <- vapply(parsed, function(z) if (is.null(z)) NA_character_ else z$var, character(1))
    
    dfp <- data.frame(Termo = coefs_rb$Termo, var = vars, p = coefs_rb$p, stringsAsFactors = FALSE)
    dfp <- dfp[dfp$var %in% xs_ordered & is.finite(dfp$p), , drop = FALSE]
    if (!nrow(dfp)) {
      if (mode == "hybrid" && length(manual_vars) > 0) {
        forced <- manual_vars[manual_vars %in% xs_ordered]
        out <- unique(c(forced, setdiff(fallback, forced)))
        return(out[1:min(k, length(out))])
      }
      return(fallback)
    }
    
    if (is.finite(pmax)) {
      dfp <- dfp[dfp$p <= pmax, , drop = FALSE]
      if (!nrow(dfp)) {
        if (mode == "hybrid" && length(manual_vars) > 0) {
          forced <- manual_vars[manual_vars %in% xs_ordered]
          out <- unique(c(forced, setdiff(fallback, forced)))
          return(out[1:min(k, length(out))])
        }
        return(fallback)
      }
    }
    
    topk_auto <- dfp %>%
      dplyr::group_by(var) %>%
      dplyr::summarise(best_p = min(p, na.rm = TRUE), .groups = "drop") %>%
      dplyr::arrange(best_p) %>%
      dplyr::pull(var)
    
    topk_auto <- topk_auto[!is.na(topk_auto)]
    
    if (mode == "hybrid") {
      forced <- manual_vars[manual_vars %in% xs_ordered]
      out <- unique(c(forced, setdiff(topk_auto, forced)))
      if (length(out) < k) out <- unique(c(out, setdiff(xs_ordered, out)))
      return(out[1:min(k, length(out))])
    }
    
    out <- topk_auto[1:min(k, length(topk_auto))]
    if (length(out) < k) out <- c(out, setdiff(xs_ordered, out))[1:min(k, length(xs_ordered))]
    out
  }
  
  TOP3_VARS <- choose_topk_from_model(
    coefs_rb     = coefs_rb,
    xs_ordered   = XS_ORDERED,
    k            = TOP3_COMB,
    mode         = TOP3_MODE,
    manual_vars  = TOP3_MANUAL_VARS,
    pmax         = TOP3_PMAX
  )
  
  TOP3_VARS <- TOP3_VARS[!is.na(TOP3_VARS)]
  if (length(TOP3_VARS) == 0) TOP3_VARS <- XS_ORDERED[1:min(TOP3_COMB, length(XS_ORDERED))]
  
  cat("\n== Variáveis selecionadas (para estresse combinado) ==\n")
  cat("Modo:", TOP3_MODE, "\n")
  print(TOP3_VARS)

  EXPECTED_TOP3 <- c(
    "LN_Vazao_BM_X13",
    "LN_153000_BM_X13",
    "LN_254010_BM_X13"
  )

  top3_audit <- data.frame(
    Selected_Top3 = paste(TOP3_VARS, collapse = "; "),
    Expected_Top3 = paste(EXPECTED_TOP3, collapse = "; "),
    Top3_Identical = identical(TOP3_VARS, EXPECTED_TOP3),
    stringsAsFactors = FALSE
  )
  if (!isTRUE(top3_audit$Top3_Identical[1])) {
    stop("FINAL_VALID_200826: corrected parser changed the validated BM combined-stress Top-3.")
  }
  
  # ============================================================
  # CUSUM — agora também exporta para Excel
  # ============================================================
  cat("\n== CUSUM (Rec/OLS) ==\n")
  cusum_tests_df <- data.frame(Msg="CUSUM não executado", stringsAsFactors = FALSE)
  cusum_process_df <- data.frame(Msg="CUSUM processo indisponível", stringsAsFactors = FALSE)
  cusum_png_path <- NA_character_
  
  try({
    mf <- stats::model.frame(fit); yname <- names(mf)[1]
    f_cus <- stats::as.formula(paste(yname, "~ ."))
    efp_rec <- strucchange::efp(f_cus, data = mf, type = "Rec-CUSUM")
    efp_ols <- strucchange::efp(f_cus, data = mf, type = "OLS-CUSUM")
    
    tst_rec <- strucchange::sctest(efp_rec)
    tst_ols <- strucchange::sctest(efp_ols)
    
    cat("\nCUSUM Rec:\n"); print(tst_rec)
    cat("\nCUSUM OLS:\n"); print(tst_ols)
    
    cusum_tests_df <- data.frame(
      Tipo = c("Rec-CUSUM","OLS-CUSUM"),
      Estatistica = c(unname(tst_rec$statistic), unname(tst_ols$statistic)),
      p_value = c(unname(tst_rec$p.value), unname(tst_ols$p.value)),
      Method = c(tst_rec$method, tst_ols$method),
      stringsAsFactors = FALSE
    )
    
    # Processo + bandas
    bd_rec <- tryCatch(strucchange::boundary(efp_rec), error = function(e) NULL)
    bd_ols <- tryCatch(strucchange::boundary(efp_ols), error = function(e) NULL)
    
    get_proc_df <- function(efp_obj, bd_obj, tipo){
      pr <- tryCatch(efp_obj$process, error = function(e) NULL)
      if (is.null(pr)) return(NULL)
      
      tt <- tryCatch(as.numeric(stats::time(pr)), error=function(e) seq_along(pr))
      pv <- as.numeric(pr)
      
      upper <- rep(NA_real_, length(pv))
      lower <- rep(NA_real_, length(pv))
      
      if (!is.null(bd_obj)) {
        # boundary pode vir como vetor (upper) ou matriz (lower/upper)
        if (is.matrix(bd_obj) && nrow(bd_obj) == length(pv)) {
          cn <- tolower(colnames(bd_obj))
          if ("upper" %in% cn) upper <- as.numeric(bd_obj[, which(cn=="upper")[1]])
          if ("lower" %in% cn) lower <- as.numeric(bd_obj[, which(cn=="lower")[1]])
        } else if (is.numeric(bd_obj) && length(bd_obj) == length(pv)) {
          upper <- as.numeric(bd_obj)
          lower <- -as.numeric(bd_obj)
        }
      }
      
      data.frame(
        Tipo = tipo,
        Time = tt,
        Process = pv,
        Lower = lower,
        Upper = upper,
        stringsAsFactors = FALSE
      )
    }
    
    df_rec <- get_proc_df(efp_rec, bd_rec, "Rec-CUSUM")
    df_ols <- get_proc_df(efp_ols, bd_ols, "OLS-CUSUM")
    
    cusum_process_df <- dplyr::bind_rows(df_rec, df_ols) %>% as.data.frame()
    
    out_png <- file.path(BASE_DIR, "figs", "CUSUM_duplo.png")
    ok_png <- tryCatch({
      png(out_png, width = 1200, height = 600, res = 130, bg = "white")
      op <- par(mfrow = c(1,2), mar = c(4,4,3,1)); on.exit({par(op); dev.off()}, add = TRUE)
      plot(efp_rec, main = paste0("CUSUM (Rec) — ARDL ", PLANTA))
      plot(efp_ols, main = paste0("CUSUM (OLS) — ARDL ", PLANTA))
      TRUE
    }, error = function(e){
      cat("⚠️ Falha ao salvar CUSUM PNG:", e$message, "\n")
      FALSE
    })
    if (isTRUE(ok_png)) {
      cusum_png_path <- out_png
      cat("Gráfico CUSUM salvo em:", out_png, "\n")
    }
  }, silent = TRUE)
  
  # ============================================================
  # BOUNDS TEST — ALIGNED WITH FIXED DUMMIES
  # ============================================================
  cat("\n== Bounds test aligned with D_2023/D_2024 (case=", CASE_BOUNDS, ") ==\n", sep="")
  bt_df <- data.frame(Mensagem = "bounds não executado", check.names = FALSE)
  bounds_audit_df <- data.frame(Mensagem = "bounds audit não executado", check.names = FALSE)
  model_alignment_audit <- data.frame(Mensagem = "model alignment audit não executado", check.names = FALSE)

  if (!is.null(auto_aux)) {
    serieB <- make_zoo(
      df,
      cols = unique(c(VARS$y, XS_ORDERED, DUMMY_COLS)),
      date_col = date_col
    )
    idxB <- zoo::index(serieB)
    start_yB <- as.integer(format(min(idxB), "%Y"))
    start_mB <- as.integer(format(min(idxB), "%m"))

    XmatB <- sapply(c(VARS$y, XS_ORDERED, DUMMY_COLS), function(v) as.numeric(serieB[, v]))
    colnames(XmatB) <- c(VARS$y, XS_ORDERED, DUMMY_COLS)
    tsB <- stats::ts(XmatB, start = c(start_yB, start_mB), frequency = 12)

    fml_bounds <- stats::as.formula(
      paste0(
        VARS$y, " ~ ", paste(XS_ORDERED, collapse = " + "),
        " | ", DUMMY_TERMS
      )
    )

    selected_order <- as.integer(auto_aux$best_order[c(VARS$y, XS_ORDERED)])

    ardl_bounds <- tryCatch(
      ARDL::ardl(
        formula = fml_bounds,
        data = tsB,
        order = selected_order
      ),
      error = function(e) e
    )

    if (inherits(ardl_bounds, "error")) {
      stop("FINAL_VALID_200826: aligned ARDL for Bounds failed: ", ardl_bounds$message)
    }

    btest <- tryCatch(
      ARDL::bounds_f_test(ardl_bounds, case = CASE_BOUNDS),
      error = function(e) e
    )
    if (inherits(btest, "error")) {
      stop("FINAL_VALID_200826: aligned Bounds test failed: ", btest$message)
    }

    bt_df <- data.frame(
      Estatistica_F = unname(btest$statistic),
      p.value = btest$p.value,
      Caso = CASE_BOUNDS,
      Dummies_Aligned = TRUE,
      Fixed_Regressors = paste(DUMMY_COLS, collapse = "; "),
      check.names = FALSE
    )
    print(bt_df)

    auto_bounds <- tryCatch(
      ARDL::auto_ardl(
        formula = fml_bounds,
        data = tsB,
        max_order = MAX_ORDER,
        selection = "AIC",
        trend = "c"
      ),
      error = function(e) e
    )

    if (inherits(auto_bounds, "error")) {
      stop("FINAL_VALID_200826: aligned auto_ardl audit failed: ", auto_bounds$message)
    }

    aligned_order <- as.integer(auto_bounds$best_order[c(VARS$y, XS_ORDERED)])
    bounds_audit_df <- data.frame(
      Selected_Order = paste(selected_order, collapse = ","),
      Aligned_Auto_Order = paste(aligned_order, collapse = ","),
      Order_Identical = identical(unname(selected_order), unname(aligned_order)),
      Aligned_AIC = tryCatch(AIC(auto_bounds$best_model), error=function(e) NA_real_),
      stringsAsFactors = FALSE
    )
    print(bounds_audit_df)

    if (!isTRUE(bounds_audit_df$Order_Identical[1])) {
      stop("FINAL_VALID_200826: aligned Bounds auto-selection changed the validated lag order.")
    }

    # Canonical coefficient alignment: final dynlm vs aligned ARDL object.
    canonical_term <- function(tt) {
      if (tt %in% c("(Intercept)", DUMMY_COLS)) return(tt)
      pt <- .parse_term_L(tt)
      if (!is.null(pt)) return(paste0(pt$var, "__L", pt$lag))
      if (tt %in% XS_ORDERED) return(paste0(tt, "__L0"))
      tt
    }

    cf_dyn <- stats::coef(fit)
    cf_aligned <- stats::coef(ardl_bounds)

    dyn_can <- data.frame(
      Canonical_Term = vapply(names(cf_dyn), canonical_term, character(1)),
      Dynlm_Term = names(cf_dyn),
      Dynlm_Coef = as.numeric(cf_dyn),
      stringsAsFactors = FALSE
    )
    aligned_can <- data.frame(
      Canonical_Term = vapply(names(cf_aligned), canonical_term, character(1)),
      ARDL_Term = names(cf_aligned),
      ARDL_Coef = as.numeric(cf_aligned),
      stringsAsFactors = FALSE
    )
    model_alignment_audit <- merge(dyn_can, aligned_can, by = "Canonical_Term", all = TRUE, sort = FALSE)
    model_alignment_audit$Difference <- model_alignment_audit$ARDL_Coef - model_alignment_audit$Dynlm_Coef
    model_alignment_audit$Abs_Difference <- abs(model_alignment_audit$Difference)

    max_align_diff <- max(model_alignment_audit$Abs_Difference, na.rm = TRUE)
    matched_n <- sum(is.finite(model_alignment_audit$Dynlm_Coef) & is.finite(model_alignment_audit$ARDL_Coef))

    if (matched_n != length(cf_dyn) || matched_n != length(cf_aligned) || max_align_diff > 1e-10) {
      stop(
        "FINAL_VALID_200826: final dynlm and aligned ARDL coefficients are not equivalent. ",
        "Matched=", matched_n, ", max abs diff=", format(max_align_diff, digits=12)
      )
    }
  }

  # ============================================================
  # GRANGER (ordem 4)
  # ============================================================
  cat("\n== Granger (ordem 4) ==\n")
  .__gr_df__ <- as.data.frame(df)
  .__resp__ <- VARS$y
  .__preds__ <- setdiff(intersect(colnames(.__gr_df__), XS_ORDERED), .__resp__)
  
  if (length(.__preds__) == 0L) {
    cat("Nenhuma variável candidata.\n")
    gr_df <- data.frame()
  } else {
    gr_df <- dplyr::bind_rows(lapply(.__preds__, function(v){
      gt <- tryCatch(lmtest::grangertest(reformulate(v, response = .__resp__), order = 4, data = .__gr_df__),
                     error = function(e) e)
      if (inherits(gt, "anova")) {
        data.frame(
          Impulso = v,
          F = suppressWarnings(unname(gt[2, "F"])),
          p_value = suppressWarnings(as.numeric(gt[2, "Pr(>F)"])),
          df1 = suppressWarnings(as.integer(abs(gt[2, "Df"]))),
          df2 = suppressWarnings(as.integer(gt[1, "Res.Df"]))
        )
      } else {
        data.frame(Impulso=v, F=NA_real_, p_value=NA_real_, df1=NA_integer_, df2=NA_integer_)
      }
    }))
    gr_df$sig <- cut(gr_df$p_value, breaks = c(-Inf,0.001,0.01,0.05,0.1,Inf), labels = c("***","**","*","."," "))
    print(gr_df, row.names = FALSE)
  }
  
  # ============================================================
  # ESTRESSE — helpers (inalterado)
  # ============================================================
  .make_base_zoo <- function(dados_df, date_col){
    stopifnot(date_col %in% names(dados_df))
    base <- dados_df
    if ("by" %in% names(base)) { warning("Removendo coluna 'by' da base."); base$by <- NULL }
    base <- base[order(as.Date(base[[date_col]])), , drop = FALSE]
    for (nm in setdiff(names(base), date_col)) if (!is.numeric(base[[nm]])) base[[nm]] <- suppressWarnings(as.numeric(base[[nm]]))
    zoo::zoo(base[, setdiff(names(base), date_col), drop = FALSE], order.by = as.Date(base[[date_col]]))
  }
  
  ._xbeta <- function(modelo_dynlm, newdata_zoo){
    b <- stats::coef(modelo_dynlm)
    idx <- zoo::index(newdata_zoo)
    n   <- length(idx)

    yhat <- rep(0, n)
    if ("(Intercept)" %in% names(b)) yhat <- yhat + unname(b["(Intercept)"])

    termos <- setdiff(names(b), "(Intercept)")
    for (tn in termos) {
      pt <- .parse_term_L(tn)
      if (!is.null(pt)) {
        var <- pt$var
        lagk <- pt$lag

        if (!var %in% colnames(newdata_zoo)) stop("Variável '", var, "' ausente em newdata_zoo.")
        x0 <- newdata_zoo[, var, drop = TRUE]
        xk <- stats::lag(x0, -lagk)

        # lag.zoo changes the time index. Re-align by date before applying beta.
        vx <- rep(NA_real_, n)
        idx_k <- zoo::index(xk)
        pos <- match(idx_k, idx)
        ok_pos <- !is.na(pos)
        vx[pos[ok_pos]] <- as.numeric(zoo::coredata(xk))[ok_pos]

        contrib <- vx * unname(b[tn])
        contrib[!is.finite(contrib)] <- 0
        yhat <- yhat + contrib
        next
      }

      if (tn %in% colnames(newdata_zoo)) {
        vx <- as.numeric(zoo::coredata(newdata_zoo[, tn, drop = TRUE]))
        if (length(vx) < n) vx <- c(vx, rep(NA_real_, n - length(vx)))
        if (length(vx) > n) vx <- vx[1:n]
        contrib <- vx * unname(b[tn])
        contrib[!is.finite(contrib)] <- 0
        yhat <- yhat + contrib
      }
    }
    yhat
  }

  .short_code <- function(v){
    v <- as.character(v)
    v[is.na(v)] <- ""
    s <- gsub("^LN_", "", v)
    s <- gsub("[^A-Za-z0-9]+", "", s)
    n <- nchar(s)
    s <- ifelse(n > 12, substr(s, pmax(1, n - 11), n), s)
    s[s == ""] <- "VAR"
    s
  }
  
  make_stress_scen_topk <- function(xs_ordered, stress_map, default_pct){
    lapply(seq_along(xs_ordered), function(i){
      vn <- xs_ordered[i]
      pct <- if (!is.null(stress_map[[vn]])) stress_map[[vn]] else default_pct
      lab <- paste0("S", i, "_", .short_code(vn), "_", ifelse(pct>=0,"mais","menos"), abs(pct))
      list(label = lab, var = vn, pct = pct)
    })
  }
  
  STRESS_SCEN <- make_stress_scen_topk(XS_ORDERED, STRESS_MAP, DEFAULT_PCT)
  STRESS_SCEN <- Filter(function(sc) sc$var %in% names(df), STRESS_SCEN)
  
  .plot_estresse <- function(out, titulo, ylab = "Energia (log)", path_png, salvar_png = TRUE){
    if (!isTRUE(salvar_png)) return(invisible(FALSE))
    ok <- tryCatch({
      png(path_png, width = 1800, height = 1000, res = 160, bg = "white", pointsize = 12)
      op <- par(no.readonly = TRUE); on.exit({par(op); dev.off()}, add = TRUE)
      par(mar = c(6, 6, 9, 2) + 0.1, xpd = NA)
      plot(out[[date_col]], out$Energia_Base, type = "l", lwd = 2, xlab = date_col, ylab = ylab)
      lines(out[[date_col]], out$Energia_Estresse, lwd = 2, lty = 2)
      mtext(titulo, side = 3, line = 5, cex = 1.35, font = 2)
      legend("bottom", inset = c(0, -0.08), horiz = TRUE, bty = "n",
             legend = c("Base","Estressada"), lty = c(1,2), lwd = 2)
      TRUE
    }, error = function(e){
      cat("⚠️ Falha ao salvar PNG do estresse:", e$message, "\n")
      FALSE
    })
    invisible(ok)
  }
  
  .expected_diff_vector_individual <- function(modelo_dynlm, var_alvo, fator_log, mask){
    b <- coef(modelo_dynlm)
    tnames <- names(b)
    parsed <- lapply(tnames, .parse_term_L)
    
    hits <- which(vapply(parsed, function(pt){
      !is.null(pt) && identical(pt$var, var_alvo) && is.finite(pt$lag)
    }, logical(1)))
    
    if (!length(hits)) return(rep(NA_real_, length(mask)))
    
    n <- length(mask)
    out <- rep(0, n)
    
    for (i in hits) {
      k <- parsed[[i]]$lag
      beta <- as.numeric(b[i])
      
      idx_mask <- rep(FALSE, n)
      if (k == 0L) {
        idx_mask <- mask
      } else if (k > 0L) {
        idx_mask[(k+1):n] <- mask[1:(n-k)]
      }
      out <- out + beta * fator_log * as.numeric(idx_mask)
    }
    out
  }
  
  .expected_diff_vector_combined <- function(modelo_dynlm, var_pcts_named, masks_by_var){
    b <- coef(modelo_dynlm)
    tnames <- names(b)
    parsed <- lapply(tnames, .parse_term_L)
    
    n <- length(masks_by_var[[1]])
    out <- rep(0, n)
    
    for (vn in names(var_pcts_named)) {
      fator_log <- log(1 + var_pcts_named[[vn]]/100)
      mask <- masks_by_var[[vn]]
      
      hits <- which(vapply(parsed, function(pt){
        !is.null(pt) && identical(pt$var, vn) && is.finite(pt$lag)
      }, logical(1)))
      
      if (!length(hits)) next
      
      for (i in hits) {
        k <- parsed[[i]]$lag
        beta <- as.numeric(b[i])
        
        idx_mask <- rep(FALSE, n)
        if (k == 0L) {
          idx_mask <- mask
        } else if (k > 0L) {
          idx_mask[(k+1):n] <- mask[1:(n-k)]
        }
        out <- out + beta * fator_log * as.numeric(idx_mask)
      }
    }
    out
  }
  
  .print_validation_block <- function(df_view, diff_log_theory, tol_abs_pct = 0.05, n_show = 6L){
    exp_pct <- (exp(diff_log_theory) - 1) * 100
    sim_pct <- df_view$Impacto_Percentual
    
    diff_pct_vec <- sim_pct - exp_pct
    max_abs <- max(abs(diff_pct_vec), na.rm = TRUE)
    ok <- is.finite(max_abs) && (max_abs <= tol_abs_pct)
    
    cat("\n--- Validação analítica (Diff_pct ≈ 0; agora data-aware) ---\n")
    cat("Tolerância_abs =", tol_abs_pct, "% | Status:", ifelse(ok, "OK ✅", "FORA ⚠️"), "\n")
    cat("MaxAbs(Diff_pct) =", round(max_abs, 4), "%\n\n")
    
    view <- df_view[, c(date_col,"Impacto_Percentual")]
    view$Esperado_pct_teorico <- round(exp_pct, 2)
    view$Diff_pct <- round(diff_pct_vec, 2)
    
    print(utils::head(view, n_show), row.names = FALSE)
    
    invisible(list(ok=ok, max_abs=max_abs, preview=view))
  }
  
  rodar_estresse_individual <- function(dados_df, modelo_dynlm, var_alvo, pct, anos_alvo,
                                        salvar_png = TRUE, label = NULL, n_print = 3L, date_col,
                                        tol_abs_pct = 0.05){
    if (is.null(label)) label <- paste0("Ind_", .short_code(var_alvo), "_", ifelse(pct>0,"mais","menos"), abs(pct))
    
    base0 <- .make_base_zoo(dados_df, date_col = date_col)
    if (!var_alvo %in% colnames(base0)) stop("Variável alvo ausente: ", var_alvo)
    
    idx  <- zoo::index(base0)
    mask <- format(idx, "%Y") %in% anos_alvo
    fator <- log(1 + pct/100)
    
    base1 <- base0
    v0 <- base1[, var_alvo, drop = TRUE]
    core <- zoo::coredata(v0)
    core[mask] <- core[mask] + fator
    base1[, var_alvo] <- zoo::zoo(core, order.by = idx)
    
    y_base <- ._xbeta(modelo_dynlm, base0)
    y_strs <- ._xbeta(modelo_dynlm, base1)
    
    n <- length(idx)
    out_all <- data.frame(matrix(nrow = n, ncol = 0), check.names = FALSE)
    out_all[[date_col]] <- as.Date(idx)
    out_all$Energia_Base      <- y_base
    out_all$Energia_Estresse  <- y_strs
    out_all$Diferenca         <- y_strs - y_base
    out_all$Impacto_Percentual <- (exp(out_all$Diferenca) - 1) * 100
    
    out_view <- subset(out_all, format(out_all[[date_col]], "%Y") %in% anos_alvo)
    if (nrow(out_view) == 0) stop("Estresse individual gerou 0 linhas após filtro. Verifique STRESS_YEARS e datas.")
    
    diff_theory_all <- .expected_diff_vector_individual(modelo_dynlm, var_alvo, fator, mask)
    diff_theory_view <- diff_theory_all[format(out_all[[date_col]], "%Y") %in% anos_alvo]
    
    valid_row <- data.frame(
      Cenario = label,
      Variavel = var_alvo,
      Choque_pct = pct,
      Periodo = paste0(min(anos_alvo), "-", max(anos_alvo)),
      Primeiro_mes = min(out_view[[date_col]]),
      MaxAbs_Diff_pct = round(max(abs(out_view$Impacto_Percentual - ((exp(diff_theory_view)-1)*100)), na.rm=TRUE), 4),
      Tolerancia_abs_pct = tol_abs_pct,
      stringsAsFactors = FALSE
    )
    attr(out_view, "stress_validation_rows") <- valid_row
    
    cat("\n===== ESTRESSE INDIVIDUAL (", PLANTA, ") =====\n", sep="")
    cat("Var:", var_alvo, " | Choque:", sprintf("%+d%%", pct),
        " | Anos:", paste(anos_alvo, collapse=", "), " | Label:", label, "\n")
    print(utils::head(out_view, n_print)); cat("... (", nrow(out_view), " linhas)\n", sep="")
    
    .print_validation_block(out_view, diff_theory_view, tol_abs_pct = tol_abs_pct, n_show = 6L)
    
    if (isTRUE(salvar_png)) {
      dir.create(file.path(BASE_DIR, "figs"), showWarnings = FALSE, recursive = TRUE)
      fn <- paste0(PLANTA, "_StressInd_", label, "_", format(Sys.time(), "%Y-%m-%d_%H%M"), ".png")
      path_png <- file.path(BASE_DIR, "figs", fn)
      .plot_estresse(
        out = out_view,
        titulo = paste0(PLANTA, " — Estresse individual: ", label, " (", min(anos_alvo), "–", max(anos_alvo), ")"),
        ylab = "Energia (log)",
        path_png = path_png,
        salvar_png = TRUE
      )
      cat("PNG (se disponível) em:", path_png, "\n")
    }
    
    out_view
  }
  
  make_named_pcts <- function(vars_vec, stress_map, default_pct){
    out <- c()
    for (vn in vars_vec) {
      pct <- if (!is.null(stress_map[[vn]])) stress_map[[vn]] else default_pct
      out <- c(out, setNames(pct, vn))
    }
    out
  }
  
  rodar_estresse_combinado <- function(dados_df, modelo_dynlm, var_pcts_named, anos_alvo,
                                       salvar_png = TRUE, label = "Combinado", n_print = 6L, date_col,
                                       tol_abs_pct = 0.05){
    stopifnot(date_col %in% names(dados_df))
    stopifnot(length(var_pcts_named) >= 2)
    
    base0 <- .make_base_zoo(dados_df, date_col = date_col)
    base1 <- base0
    idx  <- zoo::index(base0)
    mask_global <- format(idx, "%Y") %in% anos_alvo
    
    for (vn in names(var_pcts_named)) {
      if (!vn %in% colnames(base1)) stop("Variável ausente p/ combinado: ", vn)
      f <- log(1 + var_pcts_named[[vn]]/100)
      v <- base1[, vn, drop = TRUE]
      core <- zoo::coredata(v)
      core[mask_global] <- core[mask_global] + f
      base1[, vn] <- zoo::zoo(core, order.by = idx)
    }
    
    y_base <- ._xbeta(modelo_dynlm, base0)
    y_strs <- ._xbeta(modelo_dynlm, base1)
    
    n <- length(idx)
    out_all <- data.frame(matrix(nrow = n, ncol = 0), check.names = FALSE)
    out_all[[date_col]] <- as.Date(idx)
    out_all$Energia_Base      <- y_base
    out_all$Energia_Estresse  <- y_strs
    out_all$Diferenca         <- y_strs - y_base
    out_all$Impacto_Percentual <- (exp(out_all$Diferenca) - 1) * 100
    
    out_view <- subset(out_all, format(out_all[[date_col]], "%Y") %in% anos_alvo)
    if (nrow(out_view) == 0) stop("Estresse combinado gerou 0 linhas após filtro. Verifique STRESS_YEARS e datas.")
    
    masks_by_var <- lapply(names(var_pcts_named), function(vn) mask_global)
    names(masks_by_var) <- names(var_pcts_named)
    
    diff_theory_all <- .expected_diff_vector_combined(modelo_dynlm, var_pcts_named, masks_by_var)
    diff_theory_view <- diff_theory_all[format(out_all[[date_col]], "%Y") %in% anos_alvo]
    
    valid_comb <- data.frame(
      Cenario = label,
      Periodo = paste0(min(anos_alvo), "-", max(anos_alvo)),
      Primeiro_mes = min(out_view[[date_col]]),
      MaxAbs_Diff_pct = round(max(abs(out_view$Impacto_Percentual - ((exp(diff_theory_view)-1)*100)), na.rm=TRUE), 4),
      Tolerancia_abs_pct = tol_abs_pct,
      stringsAsFactors = FALSE
    )
    
    attr(out_view, "comb_validation") <- valid_comb
    
    cat("\n===== ESTRESSE COMBINADO (", PLANTA, ") =====\n", sep="")
    cat("Vars/pct: ", paste(paste0(names(var_pcts_named), "(", sprintf("%+d", var_pcts_named), "%)"), collapse = " + "),
        " | Anos: ", paste(anos_alvo, collapse = ", "),
        " | Label: ", label, "\n", sep = "")
    print(utils::head(out_view, n_print)); cat("... (", nrow(out_view), " linhas)\n", sep="")
    
    .print_validation_block(out_view, diff_theory_view, tol_abs_pct = tol_abs_pct, n_show = 6L)
    
    if (isTRUE(salvar_png)) {
      dir.create(file.path(BASE_DIR, "figs"), showWarnings = FALSE, recursive = TRUE)
      nice <- paste(paste0(.short_code(names(var_pcts_named)),
                           ifelse(var_pcts_named>0,"Mais","Menos"),
                           abs(var_pcts_named), "pct"), collapse = "_")
      fn <- paste0(PLANTA, "_StressComb_", nice, "_", format(Sys.time(), "%Y-%m-%d_%H%M"), ".png")
      path_png <- file.path(BASE_DIR, "figs", fn)
      .plot_estresse(
        out = out_view,
        titulo = paste0(PLANTA, " — Estresse combinado: ", label, " (", min(anos_alvo), "–", max(anos_alvo), ")"),
        ylab = "Energia (log)",
        path_png = path_png,
        salvar_png = TRUE
      )
      cat("PNG (se disponível) em:", path_png, "\n")
    }
    
    out_view
  }
  
  # ============================================================
  # RODAR ESTRESSES INDIVIDUAIS
  # ============================================================
  cat("\n== RODANDO ESTRESSES INDIVIDUAIS ==\n")
  stress_results <- list()
  valid_all <- list()
  
  for (sc in STRESS_SCEN) {
    out_sc <- rodar_estresse_individual(
      dados_df     = df,
      modelo_dynlm = fit,
      var_alvo     = sc$var,
      pct          = sc$pct,
      anos_alvo    = STRESS_YEARS,
      salvar_png   = TRUE,
      label        = sc$label,
      n_print      = 6L,
      date_col     = date_col,
      tol_abs_pct  = 0.05
    )
    stress_results[[sc$label]] <- out_sc
    valid_all[[length(valid_all) + 1]] <- attr(out_sc, "stress_validation_rows")
  }
  
  # ============================================================
  # ESTRESSE COMBINADO — automático Top-3
  # ============================================================
  COMB_SCEN <- make_named_pcts(TOP3_VARS, STRESS_MAP, DEFAULT_PCT)
  
  if (length(TOP3_VARS) >= 2 && all(TOP3_VARS %in% names(df))) {
    sc  <- .short_code(TOP3_VARS)
    pct <- unname(COMB_SCEN)
    
    label_comb <- paste0(
      paste0(sc, "(", ifelse(pct >= 0, "+", ""), pct, "%)"),
      collapse = " + "
    )
    
    res_comb <- rodar_estresse_combinado(
      dados_df = df,
      modelo_dynlm = fit,
      var_pcts_named = COMB_SCEN,
      anos_alvo = STRESS_YEARS,
      salvar_png = TRUE,
      label = label_comb,
      n_print = 6L,
      date_col = date_col,
      tol_abs_pct = 0.05
    )
  } else {
    cat("⚠️ Estresse combinado ignorado: Top-3 inválida ou variáveis ausentes.\n")
    res_comb <- data.frame(Msg="Combinado não executado (Top-3 inválida/variáveis ausentes).")
    attr(res_comb, "comb_validation") <- data.frame(Msg="Sem validação (combinado não executado).")
  }
  
  # ============================================================
  # SEMÁFORO
  # ============================================================
  .classify_stress <- function(mean_signed){
    if (is.na(mean_signed)) return(list(nivel = "Indefinido", emoji = "⚪", direcao = "Indefinido"))
    if (mean_signed <= -5)  return(list(nivel = "Alto",      emoji = "🔴", direcao = "Queda"))
    if (mean_signed <= -2)  return(list(nivel = "Moderado",  emoji = "🟡", direcao = "Queda"))
    if (mean_signed <   0)  return(list(nivel = "Leve",      emoji = "🟢", direcao = "Queda"))
    return(list(nivel = "Leve (ganho)", emoji = "🟢", direcao = "Ganho"))
  }
  
  .stress_summary <- function(df_estresse, nome_cenario){
    imp  <- as.numeric(df_estresse$Impacto_Percentual)
    m    <- mean(imp,  na.rm = TRUE)
    med  <- stats::median(imp, na.rm = TRUE)
    sdv  <- stats::sd(imp,     na.rm = TRUE)
    mxA  <- max(abs(imp),      na.rm = TRUE)
    last <- tail(imp[is.finite(imp)], 1)
    cls  <- .classify_stress(mean_signed = m)
    tibble::tibble(
      Cenario = nome_cenario,
      Impacto_Medio_pct   = round(m,   3),
      Impacto_Mediano_pct = round(med, 3),
      Impacto_DP_pct      = round(sdv, 3),
      Impacto_MaxAbs_pct  = round(mxA, 3),
      Impacto_Ultimo_pct  = round(last,3),
      Direcao = cls$direcao, Classificacao = cls$nivel, Semaforo = cls$emoji
    )
  }
  
  stress_semaforo <- dplyr::bind_rows(
    if (length(stress_results)) dplyr::bind_rows(lapply(names(stress_results), function(nm){
      .stress_summary(stress_results[[nm]], paste0("Ind: ", nm))
    })) else NULL,
    if (!("Msg" %in% names(res_comb))) .stress_summary(res_comb, "Comb: Top-3") else NULL
  )
  if (!nrow(stress_semaforo)) stress_semaforo <- data.frame(Msg="Semáforo vazio (sem estresses executados).")
  cat("\n== Semáforo ==\n")
  print(stress_semaforo)
  
  # ============================================================
  # FINAL VALIDATION ASSERTIONS
  # ============================================================
  validation_assertions <- data.frame(
    Check = c(
      "No_I2_Selected_Model",
      "Max_VIF_Within_Limit",
      "Top3_Identical",
      "Bounds_Order_Identical",
      "Bounds_Significant_5pct",
      "Stress_Individual_Analytical_Validation",
      "Stress_Combined_Analytical_Validation"
    ),
    Passed = c(
      !any(gr_i2$sub$I_class == "I(2)", na.rm = TRUE),
      is.finite(best_run$max_vif) && best_run$max_vif <= VIF_LIMIT,
      isTRUE(top3_audit$Top3_Identical[1]),
      isTRUE(bounds_audit_df$Order_Identical[1]),
      is.finite(bt_df$p.value[1]) && bt_df$p.value[1] < 0.05,
      if (length(valid_all)) all(vapply(valid_all, function(z) is.data.frame(z) && nrow(z) > 0 && z$MaxAbs_Diff_pct[1] <= z$Tolerancia_abs_pct[1], logical(1))) else FALSE,
      if (is.data.frame(attr(res_comb, "comb_validation")) && "MaxAbs_Diff_pct" %in% names(attr(res_comb, "comb_validation"))) {
        attr(res_comb, "comb_validation")$MaxAbs_Diff_pct[1] <= attr(res_comb, "comb_validation")$Tolerancia_abs_pct[1]
      } else FALSE
    ),
    stringsAsFactors = FALSE
  )

  if (!all(validation_assertions$Passed)) {
    print(validation_assertions)
    stop("Reproducibility guardrail: one or more validated assertions failed.")
  }

  # ============================================================
  # EXPORTAÇÕES FINAIS (XLSX)
  # ============================================================
  cat("\n== Exportando resumo final (XLSX) ==\n")
  wb <- openxlsx::createWorkbook()
  .used_env <- new.env(parent = emptyenv())
  assign("used", character(0), envir = .used_env)
  
  openxlsx::addWorksheet(wb, "Resumo_modelo")
  assign("used", c(get("used", envir=.used_env), "Resumo_modelo"), envir = .used_env)
  
  .glance <- data.frame(
    AIC   = tryCatch(AIC(fit), error=function(e) NA_real_),
    BIC   = tryCatch(BIC(fit), error=function(e) NA_real_),
    R2    = tryCatch(summary(fit)$r.squared, error=function(e) NA_real_),
    AdjR2 = tryCatch(summary(fit)$adj.r.squared, error=function(e) NA_real_)
  )
  openxlsx::writeData(wb, "Resumo_modelo", .glance)
  
  # NOVO: config robusta
  robust_cfg <- data.frame(
    Item = c("ROBUST_MODE","NW_LAG","NW_PREWHITE","NW_ADJUST"),
    Valor = c(ROBUST_MODE, as.character(NW_LAG), as.character(NW_PREWHITE), as.character(NW_ADJUST)),
    stringsAsFactors = FALSE
  )
  .add_sheet_df(wb, "Robust_Config", robust_cfg, .used_env)


  validation_cfg <- data.frame(
    Item = c(
      "VALIDATION_TAG", "INPUT_MD5", "ADF_MAX_LAG", "ADF_LAG_SELECTION",
      "PARSER_RULE", "BOUNDS_DUMMIES_ALIGNED", "STRESS_MODE",
      "EXPECTED_MODEL"
    ),
    Valor = c(
      "200826",
      unname(tools::md5sum(INPUT_XLSX)),
      as.character(ADF_MAX_LAG),
      "AIC within explicit maximum; selected lag recovered from ADF test regression",
      "dynlm parser handles singleton ranges and expanded-range suffix equals actual lag",
      "TRUE",
      STRESS_MODE,
      "ARDL(1,1,1,0,1,0)"
    ),
    stringsAsFactors = FALSE
  )
  .add_sheet_df(wb, "Validation_Config", validation_cfg, .used_env)

  input_audit <- data.frame(
    Item = c("Input_File", "Input_MD5", "Rows", "Start", "End"),
    Value = c(
      gsub("\\\\", "/", INPUT_XLSX),
      unname(tools::md5sum(INPUT_XLSX)),
      nrow(df),
      as.character(min(df[[date_col]])),
      as.character(max(df[[date_col]]))
    ),
    stringsAsFactors = FALSE
  )
  .add_sheet_df(wb, "Input_Audit", input_audit, .used_env)

  stress_cfg <- data.frame(
    Variable = names(STRESS_MAP),
    Shock_pct = as.numeric(unlist(STRESS_MAP)),
    Stress_Mode = STRESS_MODE,
    Stress_Years = paste(STRESS_YEARS, collapse = ";"),
    stringsAsFactors = FALSE
  )
  .add_sheet_df(wb, "Stress_Config", stress_cfg, .used_env)
  .add_sheet_df(wb, "Selection_Audit", selection_audit, .used_env)
  .add_sheet_df(wb, "Top3_Audit", top3_audit, .used_env)
  
  dummies_info <- data.frame(
    Dummy = c("D_2023","D_2024"),
    Tipo  = c("Step (nível/regime)","Step (nível/regime)"),
    Inicio = c(as.character(BREAK_2023), as.character(BREAK_2024)),
    Regra = c("1 se Data >= 2023-10-01; 0 caso contrário",
              "1 se Data >= 2024-08-01; 0 caso contrário"),
    check.names = FALSE
  )
  .add_sheet_df(wb, "Dummies_Regime", dummies_info, .used_env)
  
  .add_sheet_df(wb, "Stationarity_DETAIL", station_detail, .used_env)
  .add_sheet_df(wb, "Stationarity_VERDICT", station_verdict, .used_env)
  
  .add_sheet_df(wb, "Screening_Global", screen_tbl, .used_env)
  .add_sheet_df(wb, paste0("Elig_p_le_", P_CUTOFF), eligible_tbl, .used_env)
  .add_sheet_df(wb, "XS_ORDERED_Final", data.frame(Variavel=XS_ORDERED), .used_env)
  .add_sheet_df(wb, "Top3_Comb", data.frame(Variavel=TOP3_VARS, Choque_pct=unname(COMB_SCEN)), .used_env)
  
  # NOVO: nome coerente com robust mode
  .add_sheet_df(wb, paste0("Coef_Robust_", ROBUST_MODE), coefs_rb, .used_env)
  
  .add_sheet_df(wb, "Elasticidades", elasticidades_tbl, .used_env)
  .add_sheet_df(wb, "Elasticidades_Detail", elasticidades_detail, .used_env)
  
  sum_mat <- as.data.frame(summary(fit)$coefficients)
  sum_mat$Termo <- rownames(sum_mat); rownames(sum_mat) <- NULL
  colnames(sum_mat)[1:4] <- c("Estimate","Std.Error","t value","Pr(>|t|)")
  sum_mat <- sum_mat[, c("Termo","Estimate","Std.Error","t value","Pr(>|t|)")]
  .add_sheet_df(wb, "Summary_print", sum_mat, .used_env)
  
  .diag_to_df <- function(dx) tibble::tibble(
    Teste = c("DW","BG(lag=4)","BP","JB"),
    Estat = c(if (!is.null(dx$DW)) unname(dx$DW$statistic) else NA_real_,
              if (!is.null(dx$BG4)) unname(dx$BG4$statistic) else NA_real_,
              if (!is.null(dx$BP))  unname(dx$BP$statistic)  else NA_real_,
              if (!is.null(dx$JB))  unname(dx$JB$statistic)  else NA_real_),
    p_value = c(if (!is.null(dx$DW)) dx$DW$p.value else NA_real_,
                if (!is.null(dx$BG4)) dx$BG4$p.value else NA_real_,
                if (!is.null(dx$BP))  dx$BP$p.value  else NA_real_,
                if (!is.null(dx$JB))  dx$JB$p.value  else NA_real_)
  )
  .add_sheet_df(wb, "Diagnosticos", .diag_to_df(diags), .used_env)
  .add_sheet_df(wb, "VIF", diags$VIF, .used_env)
  
  .add_sheet_df(wb, "Ranking_final", rank_vars, .used_env)
  .add_sheet_df(wb, "Bounds_Test", bt_df, .used_env)
  .add_sheet_df(wb, "Bounds_Audit", bounds_audit_df, .used_env)
  .add_sheet_df(wb, "Model_Alignment", model_alignment_audit, .used_env)
  .add_sheet_df(wb, "Granger_ord4", gr_df, .used_env)
  
  # NOVO: CUSUM no Excel
  .add_sheet_df(wb, "CUSUM_Tests", cusum_tests_df, .used_env)
  .add_sheet_df(wb, "CUSUM_Process", cusum_process_df, .used_env)
  
  if (length(stress_results)) {
    for (nm in names(stress_results)) {
      .add_sheet_df(wb, paste0("StressInd_", nm), stress_results[[nm]], .used_env)
    }
  }
  valid_df <- if (length(valid_all)) dplyr::bind_rows(valid_all) else data.frame(Msg="Sem validações")
  .add_sheet_df(wb, "Stress_Validacao", valid_df, .used_env)
  
  .add_sheet_df(wb, "StressComb_Top3", res_comb, .used_env)
  .add_sheet_df(wb, "StressComb_Valid", attr(res_comb, "comb_validation"), .used_env)
  .add_sheet_df(wb, "Stress_Semaforo", stress_semaforo, .used_env)
  .add_sheet_df(wb, "Validation_Assertions", validation_assertions, .used_env)
  
  if (!is.null(auto_aux)) {
    aux_info <- data.frame(
      Item  = c("best_order","equacao_best_model"),
      Valor = c(paste0(capture.output(print(auto_aux$best_order)), collapse = " "),
                paste0(capture.output(print(formula(auto_aux$best_model))), collapse = " ")),
      check.names = FALSE
    )
    .add_sheet_df(wb, "AutoARDL_Aux", aux_info, .used_env)
  }
  
  SUM_XLSX <- file.path(OUTPUT_ROOT, paste0("ARDL_", PLANTA, "_reproduced.xlsx"))
  openxlsx::saveWorkbook(wb, SUM_XLSX, overwrite = FALSE)
  cat("✅ Resumo final exportado para:", SUM_XLSX, "\n")
  
  # ============================================================
  # SALVAR RDS
  # ============================================================
  results <- list(
    meta = list(
      PLANTA=PLANTA,
      RUN_ID=RUN_ID,
      y=VARS$y,
      xs_final=XS_ORDERED,
      top3_comb=TOP3_VARS,
      lag_spec=LAG_SPEC,
      timestamp=Sys.time(),
      best_order = auto_aux$best_order,
      robust = list(
        ROBUST_MODE = ROBUST_MODE,
        NW_LAG = NW_LAG,
        NW_PREWHITE = NW_PREWHITE,
        NW_ADJUST = NW_ADJUST
      ),
      validation = list(
        tag = "200826",
        input_md5 = unname(tools::md5sum(INPUT_XLSX)),
        adf_max_lag = ADF_MAX_LAG,
        bounds_dummies_aligned = TRUE,
        stress_mode = STRESS_MODE,
        assertions = validation_assertions
      ),
      dummies = list(
        cols = DUMMY_COLS,
        break_2023 = BREAK_2023,
        break_2024 = BREAK_2024
      )
    ),
    station_detail = station_detail,
    station_verdict = station_verdict,
    screening = screen_tbl,
    eligible = eligible_tbl,
    fit  = fit,
    coefs_robustos = coefs_rb,
    ranking_final = rank_vars,
    diags = diags,
    bounds = bt_df,
    bounds_audit = bounds_audit_df,
    model_alignment = model_alignment_audit,
    selection_audit = selection_audit,
    top3_audit = top3_audit,
    granger = gr_df,
    cusum_tests = cusum_tests_df,
    cusum_process = cusum_process_df,
    cusum = list(tests = cusum_tests_df, process = cusum_process_df, png = cusum_png_path),
    
    # Elasticidades
    elasticidades = elasticidades_tbl,
    elasticidades_detail = elasticidades_detail,
    
    stress_ind = stress_results,
    stress_valid = valid_df,
    stress_comb = res_comb,
    stress_comb_valid = attr(res_comb, "comb_validation"),
    stress_semaforo = stress_semaforo,
    paths = list(BASE_DIR = BASE_DIR, LOG_FILE = LOG_FILE, SUM_XLSX = SUM_XLSX)
  )
  
  rds_path <- file.path(BASE_DIR, "rds", paste0("ARDL_", PLANTA, "_reproduced.RDS"))
  dir.create(dirname(rds_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(results, rds_path)
  
  # --- GUARDA CAMINHO DO RDS NO OBJETO results (para rastreabilidade) ---
  results$paths$RDS_PATH <- rds_path
  
  # ============================================================
  # WORD (DOCX) — Relatório curto + caminhos (inclui RDS)
  # ============================================================
  make_word_report <- function(results, docx_path){
    
    .add_ft <- function(doc, df){
      if (!is.data.frame(df) || nrow(df) == 0) {
        return(officer::body_add_par(doc, "Tabela indisponível.", style = "Normal"))
      }
      ft <- suppressWarnings(flextable::flextable(df))
      ft <- suppressWarnings(flextable::autofit(ft))
      suppressWarnings(flextable::body_add_flextable(doc, value = ft))
    }
    
    tb_glance <- data.frame(
      AIC   = tryCatch(AIC(results$fit), error=function(e) NA_real_),
      BIC   = tryCatch(BIC(results$fit), error=function(e) NA_real_),
      R2    = tryCatch(summary(results$fit)$r.squared, error=function(e) NA_real_),
      AdjR2 = tryCatch(summary(results$fit)$adj.r.squared, error=function(e) NA_real_)
    )
    
    tb_meta <- data.frame(
      Item = c("PLANTA","RUN_ID","y","xs_final","top3_comb","best_order","ROBUST_MODE","NW_LAG","NW_PREWHITE","NW_ADJUST","BREAK_2023","BREAK_2024"),
      Valor = c(
        results$meta$PLANTA,
        results$meta$RUN_ID,
        results$meta$y,
        paste(results$meta$xs_final, collapse = ", "),
        paste(results$meta$top3_comb, collapse = ", "),
        paste(capture.output(print(results$meta$best_order)), collapse=" "),
        results$meta$robust$ROBUST_MODE,
        as.character(results$meta$robust$NW_LAG),
        as.character(results$meta$robust$NW_PREWHITE),
        as.character(results$meta$robust$NW_ADJUST),
        as.character(results$meta$dummies$break_2023),
        as.character(results$meta$dummies$break_2024)
      ),
      check.names = FALSE
    )
    
    tb_coef <- results$coefs_robustos
    if (is.data.frame(tb_coef) && nrow(tb_coef) > 25) tb_coef <- tb_coef[order(tb_coef$p), ][1:25, ]
    
    tb_vif <- results$diags$VIF
    if (is.data.frame(tb_vif) && nrow(tb_vif) > 15) tb_vif <- tb_vif[order(-tb_vif$VIF), ][1:15, ]
    
    tb_semaforo <- results$stress_semaforo
    tb_elast <- tryCatch(results$elasticidades, error = function(e) NULL)
    if (is.data.frame(tb_elast)) {
      tb_elast <- as.data.frame(tb_elast)
      for (nm in names(tb_elast)) {
        if (is.list(tb_elast[[nm]])) tb_elast[[nm]] <- vapply(tb_elast[[nm]], toString, character(1))
      }
    }
    
    tb_cus <- tryCatch(results$cusum_tests, error=function(e) NULL)
    
    tb_paths <- data.frame(
      Item = c("BASE_DIR","LOG_FILE","SUM_XLSX","RDS_PATH","DOCX_PATH"),
      Path = c(
        tryCatch(results$paths$BASE_DIR, error=function(e) NA_character_),
        tryCatch(results$paths$LOG_FILE, error=function(e) NA_character_),
        tryCatch(results$paths$SUM_XLSX, error=function(e) NA_character_),
        tryCatch(results$paths$RDS_PATH, error=function(e) NA_character_),
        docx_path
      ),
      check.names = FALSE
    )
    
    doc <- officer::read_docx()
    doc <- officer::body_add_par(doc, paste0("ARDL FINAL — ", results$meta$PLANTA, " (V4 Blindado)"), style = "heading 1")
    doc <- officer::body_add_par(doc, paste0("Gerado em: ", format(results$meta$timestamp, "%Y-%m-%d %H:%M:%S")), style = "Normal")
    
    doc <- officer::body_add_par(doc, "1) Metadados do Run", style = "heading 2")
    doc <- .add_ft(doc, tb_meta)
    
    doc <- officer::body_add_par(doc, "2) Métricas do modelo", style = "heading 2")
    doc <- .add_ft(doc, tb_glance)
    
    doc <- officer::body_add_par(doc, paste0("3) Coeficientes robustos (", results$meta$robust$ROBUST_MODE, ") — Top 25 por menor p"), style = "heading 2")
    doc <- .add_ft(doc, tb_coef)
    
    doc <- officer::body_add_par(doc, "3b) Elasticidades (curto e longo prazo)", style = "heading 2")
    if (is.data.frame(tb_elast) && nrow(tb_elast)) {
      doc <- .add_ft(doc, tb_elast)
    } else {
      doc <- officer::body_add_par(doc, "Elasticidades indisponíveis.", style = "Normal")
    }
    
    doc <- officer::body_add_par(doc, "4) VIF (Top 15 por maior VIF)", style = "heading 2")
    if (is.data.frame(tb_vif) && nrow(tb_vif)) {
      doc <- .add_ft(doc, tb_vif)
    } else {
      doc <- officer::body_add_par(doc, "VIF indisponível.", style = "Normal")
    }
    
    doc <- officer::body_add_par(doc, "4b) CUSUM (sctest)", style = "heading 2")
    if (is.data.frame(tb_cus) && nrow(tb_cus)) {
      doc <- .add_ft(doc, tb_cus)
    } else {
      doc <- officer::body_add_par(doc, "CUSUM indisponível.", style = "Normal")
    }
    
    doc <- officer::body_add_par(doc, "5) Semáforo do estresse", style = "heading 2")
    if (is.data.frame(tb_semaforo) && nrow(tb_semaforo)) {
      doc <- .add_ft(doc, tb_semaforo)
    } else {
      doc <- officer::body_add_par(doc, "Semáforo indisponível.", style = "Normal")
    }
    
    doc <- officer::body_add_par(doc, "6) Caminhos dos artefatos (rastreabilidade)", style = "heading 2")
    doc <- .add_ft(doc, tb_paths)
    
    print(doc, target = docx_path)
    docx_path
  }
  
  DOCX_PATH <- file.path(BASE_DIR, "tables", paste0("ARDL_", PLANTA, "_reproduced.docx"))
  
  .warns <- character(0)
  DOCX_OK <- tryCatch({
    withCallingHandlers(
      {
        suppressWarnings(make_word_report(results, DOCX_PATH))
        TRUE
      },
      warning = function(w){
        .warns <<- c(.warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
  }, error = function(e){
    cat("⚠️ Falha ao gerar Word:", e$message, "\n")
    FALSE
  })
  if (length(.warns)) {
    cat("\n⚠️ WARNINGS capturados durante make_word_report (primeiros 50):\n")
    print(utils::head(unique(.warns), 50))
    cat("Total warnings capturados:", length(.warns), "\n\n")
  }
  
  if (isTRUE(DOCX_OK)) {
    cat("✅ DOCX exportado para:", DOCX_PATH, "\n")
    results$paths$DOCX_PATH <- DOCX_PATH
  } else {
    results$paths$DOCX_PATH <- NA_character_
  }
  
  # Atualiza o RDS para incluir RDS_PATH e DOCX_PATH no objeto salvo.
  saveRDS(results, rds_path)
  
  if (!file.exists(rds_path)) {
    stop("❌ Falha ao salvar RDS (arquivo não encontrado após saveRDS): ", rds_path)
  }
  res_check <- tryCatch(readRDS(rds_path), error = function(e) e)
  if (inherits(res_check, "error")) {
    stop("❌ Validação do RDS falhou (readRDS): ", res_check$message, " | Arquivo: ", rds_path)
  }
  cat("\n✅ RDS salvo e validado (readRDS ok) em:\n", rds_path, "\n", sep = "")
  
  SESSION_INFO_PATH <- file.path(BASE_DIR, "logs", "sessionInfo_BM_reproduced.txt")
  capture.output(utils::sessionInfo(), file = SESSION_INFO_PATH)
  results$paths$SESSION_INFO_PATH <- SESSION_INFO_PATH
  saveRDS(results, rds_path)

  cat("\nConcluído. Artefatos em:", BASE_DIR, "\n")
  invisible(results)
}

# Executar
out <- Raiz()
