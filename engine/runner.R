#!/usr/bin/env Rscript
# -*- coding: utf-8 -*-
# GlazeR R 执行引擎 —— 仅依赖 base R，不依赖 jsonlite 等附加包
#
# 用法：
#   Rscript runner.R --check [pkg1,pkg2,...]    检查 R 版本与函数依赖包
#   Rscript runner.R <job.R>                    执行 GlazeR 生成的任务脚本
#
# 结果：stdout 最后一行输出单行 JSON：
#   {"ok":true,"message":"...","output":"...","elapsed":0.12,
#    "summary":"...","log":"...","warnings":"..."}
#
# job.R 由 Swift 端生成，定义以下变量（均为字符常量，已做 R 字符串转义）：
#   .gz_mode          "call" | "expr"
#   .gz_function      函数名，如 readr::read_csv / read.csv / my_fun
#   .gz_source        可选，执行前 source() 的用户脚本路径
#   .gz_code          expr 模式的 R 代码
#   .gz_file_arg      文件路径注入的形参名，空字符串表示不注入
#   .gz_files         字符向量：本次处理的输入文件路径
#   .gz_param_keys    默认参数名字符向量
#   .gz_param_exprs   与 keys 对应的 R 表达式字符向量
#   .gz_output_mode   none | print | rds | csv | rdata | dta | custom
#   .gz_output_dir    输出目录
#   .gz_output_suffix 输出文件名后缀
#   .gz_output_code   custom 模式的写出代码
#   .gz_out_base      输出文件名主体（默认取首个输入文件名去扩展名）
#   .gz_workdir       R 工作目录
#
# 执行时自动解析并注入的路径变量（表达式 / 默认参数 / source 的自定义函数均可用）：
#   .file 完整路径  ·  .filename 文件名含后缀  ·  .dir 所在目录
#   .filebasename 不含后缀的纯文件名  ·  .files 全部路径（字符向量）

# ---------------------------------------------------------------- JSON 工具

.jstr <- function(x) {
  if (is.null(x)) return("null")
  x <- paste(as.character(x), collapse = "\n")
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  paste0("\"", x, "\"")
}

.jbool <- function(x) if (isTRUE(x)) "true" else "false"
.jnum <- function(x) format(as.numeric(x), digits = 6, scientific = FALSE, trim = TRUE)

.emit <- function(ok, message, output = "", elapsed = 0,
                  summary = "", log = "", warnings = "") {
  cat(sprintf(
    '{"ok":%s,"message":%s,"output":%s,"elapsed":%s,"summary":%s,"log":%s,"warnings":%s}\n',
    .jbool(ok), .jstr(message), .jstr(output), .jnum(elapsed),
    .jstr(summary), .jstr(log), .jstr(warnings)))
  flush(stdout())
}

.clip <- function(x, n = 12000L) {
  x <- paste(x, collapse = "\n")
  if (nchar(x) > n) paste0(substr(x, 1L, n), "\n…（日志已截断）") else x
}

# 阶段事件：Swift 端逐行解析并实时更新任务卡片，避免长时间任务看起来「卡死」
.stage <- function(msg) {
  cat(sprintf('{"event":"stage","message":%s}\n', .jstr(msg)))
  flush(stdout())
}

.args <- commandArgs(trailingOnly = TRUE)

# ------------------------------------------------------------ check 子命令

if (length(.args) >= 1L && identical(.args[1], "--check")) {
  .pkgs <- if (length(.args) >= 2L) strsplit(.args[2], ",", fixed = TRUE)[[1]] else character()
  .pkgs <- unique(.pkgs[nzchar(.pkgs)])
  .status <- vapply(.pkgs, function(p) requireNamespace(p, quietly = TRUE), logical(1))
  .pairs <- vapply(seq_along(.pkgs), function(i) {
    sprintf("%s:%s", .jstr(.pkgs[i]), if (isTRUE(.status[i])) "true" else "false")
  }, character(1))
  .missing <- .pkgs[!.status]
  .miss_json <- paste(vapply(.missing, .jstr, character(1)), collapse = ",")
  cat(sprintf('{"ok":true,"rscript":%s,"version":%s,"libpaths":[%s],"packages":{%s},"missing":[%s]}\n',
              .jstr(file.path(R.home("bin"), "Rscript")),
              .jstr(as.character(getRversion())),
              paste(vapply(.libPaths(), .jstr, character(1)), collapse = ","),
              paste(.pairs, collapse = ","), .miss_json))
  flush(stdout())
  quit(save = "no", status = 0L)
}

if (length(.args) < 1L) {
  .emit(FALSE, "用法：Rscript runner.R <job.R> 或 --check")
  quit(save = "no", status = 1L)
}

# GUI 应用以 Rscript（非交互会话）执行用户脚本。部分包会按 interactive()
# 改变行为，例如 servr::httd() 在 interactive() == FALSE 时会阻塞式常驻，
# 导致任务永久挂起。这里把 servr 的本地服务强制设为守护模式，使其立即返回。
options(servr.daemon = TRUE)

# pagedown::chrome_print() 在非交互会话里常报 "Chrome crashed"：headless
# Chrome 的 sandbox 无法在终端 / 后台进程中初始化。pagedown 只在 Windows
# 自动追加 --no-sandbox，macOS 必须显式指定。这里做一层兼容包装，让未改动
# 的旧脚本也能正常渲染；显式传入的 extra_args 会被保留并去重。
# 关闭方式：options(glazer.chrome.compat = FALSE)（写入 .Rprofile）。
.glazer_chrome_compat <- function() {
  if (!isTRUE(getOption("glazer.chrome.compat", TRUE))) return(invisible(NULL))
  if (!requireNamespace("pagedown", quietly = TRUE)) return(invisible(NULL))
  try({
    .ns <- asNamespace("pagedown")
    .orig <- get("chrome_print", envir = .ns, inherits = FALSE)
    if (!isTRUE(attr(.orig, "glazer_patched", exact = TRUE))) {
      # formals() 取到的是表达式 c("--disable-gpu")，必须先求值成字符向量
      .default_extra <- tryCatch(
        eval(formals(.orig)$extra_args, envir = .ns),
        error = function(e) character())
      if (!is.character(.default_extra)) .default_extra <- character()
      .patched <- function(..., extra_args = .default_extra) {
        extra_args <- unique(c(as.character(extra_args),
                               "--no-sandbox", "--disable-dev-shm-usage"))
        .orig(..., extra_args = extra_args)
      }
      attr(.patched, "glazer_patched") <- TRUE
      assignInNamespace("chrome_print", .patched, ns = "pagedown")
    }
  }, silent = TRUE)
  invisible(NULL)
}
.glazer_chrome_compat()

# ------------------------------------------------------------------ 准备任务

.start <- proc.time()[["elapsed"]]
.job_file <- .args[1]

if (!file.exists(.job_file)) {
  .emit(FALSE, paste("找不到任务文件：", .job_file))
  quit(save = "no", status = 1L)
}

.jobenv <- new.env(parent = globalenv())
.load_err <- tryCatch({
  sys.source(.job_file, envir = .jobenv)
  NULL
}, error = function(e) conditionMessage(e))

if (!is.null(.load_err)) {
  .emit(FALSE, paste("任务脚本解析失败：", .load_err))
  quit(save = "no", status = 1L)
}

.gz <- function(name, default = "") {
  if (!exists(name, envir = .jobenv, inherits = FALSE)) return(default)
  v <- get(name, envir = .jobenv)
  if (length(v) == 0L) return(default)
  as.character(v)[1]
}

.files <- if (exists(".gz_files", envir = .jobenv, inherits = FALSE)) {
  as.character(get(".gz_files", envir = .jobenv))
} else character()
if (!length(.files)) {
  .emit(FALSE, "任务中没有输入文件")
  quit(save = "no", status = 1L)
}

.wd <- .gz(".gz_workdir", "")
if (nzchar(.wd) && dir.exists(.wd)) setwd(.wd)

# 执行环境：暴露路径变量与各默认参数，供表达式、自定义代码 source 的函数引用。
#   .file          文件完整路径（单文件为字符串；整批模式为字符向量）
#   .filename      文件名（含后缀），与 .file 等长
#   .dir           文件所在目录（不含文件名）
#   .filebasename  纯文件名（不含后缀）
#   .files         全部输入文件路径（始终为字符向量）
.env <- new.env(parent = globalenv())
.path_vec <- .files
.file_v <- if (length(.path_vec) == 1L) .path_vec[1] else .path_vec
.env$.file <- .file_v
.env$.files <- .path_vec
.env$file <- .file_v
.env$.filename <- basename(.path_vec)
.env$.dir <- dirname(.path_vec)
.env$.filebasename <- tools::file_path_sans_ext(basename(.path_vec))
# 自定义函数一般定义在全局环境，同步一份，函数体内可直接写 .file / .dir 等
for (.nm in c(".file", ".files", ".filename", ".dir", ".filebasename")) {
  assign(.nm, get(.nm, envir = .env), envir = globalenv())
}

.pre_err <- tryCatch({
  # 用户脚本：可在此定义自定义函数 / 读入配置
  .src <- .gz(".gz_source", "")
  if (nzchar(.src)) {
    if (!file.exists(.src)) stop(paste("找不到 R 脚本：", .src))
    sys.source(.src, envir = globalenv())
  }

  # 默认参数：值按 R 表达式求值（TRUE / NULL / "utf8" / c(1, 2) / .file 等）
  .keys <- if (exists(".gz_param_keys", envir = .jobenv, inherits = FALSE)) {
    as.character(get(".gz_param_keys", envir = .jobenv))
  } else character()
  .exprs <- if (exists(".gz_param_exprs", envir = .jobenv, inherits = FALSE)) {
    as.character(get(".gz_param_exprs", envir = .jobenv))
  } else character()
  .args_list <- list()
  for (i in seq_along(.keys)) {
    .k <- .keys[i]
    if (!nzchar(.k)) next
    .v <- eval(parse(text = .exprs[i]), envir = .env)
    .args_list[[.k]] <- .v
    assign(.k, .v, envir = .env)
  }

  # 把拖入的文件注入到用户指定的形参
  .fa <- .gz(".gz_file_arg", "file")
  .fval <- if (length(.files) == 1L) .files[1] else .files
  if (nzchar(.fa)) {
    .args_list[[.fa]] <- .fval
    assign(.fa, .fval, envir = .env)
  }
  NULL
}, error = function(e) conditionMessage(e))

if (!is.null(.pre_err)) {
  .emit(FALSE, paste("参数准备失败：", .pre_err))
  quit(save = "no", status = 1L)
}

# -------------------------------------------------------------------- 执行

.stage(sprintf("R 正在执行：%s",
               if (identical(.gz(".gz_mode", "call"), "expr")) "自定义 R 代码"
               else .gz(".gz_function", "")))

.logs <- character()
.warns <- character()
.err <- NULL
.result <- NULL

.logs <- capture.output({
  .result <- tryCatch(
    withCallingHandlers({
      if (identical(.gz(".gz_mode", "call"), "expr")) {
        .code <- .gz(".gz_code", "")
        if (!nzchar(.code)) stop("未配置自定义 R 代码")
        eval(parse(text = .code), envir = .env)
      } else {
        .fname <- .gz(".gz_function", "")
        if (!nzchar(.fname)) stop("未配置 R 函数")
        .fn <- if (grepl("::", .fname, fixed = TRUE)) {
          .parts <- strsplit(.fname, "::", fixed = TRUE)[[1]]
          getExportedValue(.parts[1], .parts[2])
        } else {
          get(.fname, envir = .env, mode = "function")
        }
        do.call(.fn, .args_list)
      }
    }, warning = function(w) {
      .warns <<- c(.warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }),
    error = function(e) { .err <<- conditionMessage(e); NULL }
  )
}, type = "output")

if (!is.null(.err)) {
  .emit(FALSE, .err, log = .clip(.logs), warnings = .clip(.warns),
        elapsed = proc.time()[["elapsed"]] - .start)
  quit(save = "no", status = 1L)
}

# ------------------------------------------------------------------ 结果写出

.stage("正在写出结果…")

.unique_path <- function(p) {
  if (!file.exists(p)) return(p)
  .d <- dirname(p); .b <- basename(p)
  .ext <- tools::file_ext(.b)
  .stem <- if (nzchar(.ext)) substr(.b, 1L, nchar(.b) - nchar(.ext) - 1L) else .b
  .suffix <- if (nzchar(.ext)) paste0(".", .ext) else ""
  for (i in seq_len(999L)) {
    .q <- file.path(.d, sprintf("%s(%d)%s", .stem, i, .suffix))
    if (!file.exists(.q)) return(.q)
  }
  p
}

.out <- ""
.omode <- .gz(".gz_output_mode", "none")
.ext <- switch(.omode,
               rds = ".rds", csv = ".csv", rdata = ".RData", dta = ".dta", "")
.odir <- .gz(".gz_output_dir", "")
if (!nzchar(.odir)) .odir <- dirname(.files[1])
.obase <- .gz(".gz_out_base", "")
if (!nzchar(.obase)) .obase <- tools::file_path_sans_ext(basename(.files[1]))
.osuffix <- .gz(".gz_output_suffix", "_glazed")
.target <- .unique_path(file.path(.odir, paste0(.obase, .osuffix, .ext)))

.write_err <- tryCatch({
  if (!.omode %in% c("none", "print") && !dir.exists(.odir)) {
    dir.create(.odir, recursive = TRUE, showWarnings = FALSE)
  }
  switch(.omode,
    none = invisible(NULL),
    print = { .logs <- c(.logs, capture.output(print(.result))) },
    rds = { saveRDS(.result, .target); .out <<- .target },
    csv = {
      # 写出带 BOM 的 UTF-8 CSV，Excel 直接打开中文不乱码
      .con <- file(.target, open = "wb")
      writeBin(charToRaw("\ufeff"), .con)
      utils::write.csv(.result, file = .con, row.names = FALSE, na = "")
      close(.con)
      .out <<- .target
    },
    rdata = {
      .oe <- new.env(); .oe$.glazer_result <- .result
      save(list = ".glazer_result", file = .target, envir = .oe, compress = TRUE)
      .out <<- .target
    },
    dta = {
      if (!requireNamespace("haven", quietly = TRUE)) stop("写出 .dta 需要安装 haven 包")
      haven::write_dta(as.data.frame(.result), .target)
      .out <<- .target
    },
    custom = {
      .oenv <- new.env(parent = .env)   # 继承 .file / .filename / .dir / .filebasename
      .oenv$.result <- .result
      .oenv$.out <- .target
      .ocode <- .gz(".gz_output_code", "")
      if (!nzchar(.ocode)) stop("未配置自定义写出代码")
      .clog <- capture.output(eval(parse(text = .ocode), envir = .oenv))
      .logs <<- c(.logs, .clog)
      .out <<- if (file.exists(.target)) .target else ""
    },
    stop(paste("未知的输出方式：", .omode))
  )
  NULL
}, error = function(e) conditionMessage(e))

if (!is.null(.write_err)) {
  .emit(FALSE, paste("结果写出失败：", .write_err), log = .clip(.logs),
        warnings = .clip(.warns), elapsed = proc.time()[["elapsed"]] - .start)
  quit(save = "no", status = 1L)
}

# -------------------------------------------------------------------- 汇总

.summary <- tryCatch({
  if (is.data.frame(.result)) {
    sprintf("%d 行 × %d 列", nrow(.result), ncol(.result))
  } else if (is.null(.result)) {
    "返回 NULL"
  } else if (is.atomic(.result)) {
    sprintf("%s[%d]", class(.result)[1], length(.result))
  } else {
    paste(class(.result), collapse = " / ")
  }
}, error = function(e) "")

.msg <- if (nzchar(.out)) "处理完成，已写出结果" else "处理完成"
if (nzchar(.summary)) .msg <- paste0(.msg, "（", .summary, "）")

.emit(TRUE, .msg, output = .out, elapsed = proc.time()[["elapsed"]] - .start,
      summary = .summary, log = .clip(.logs), warnings = .clip(.warns))
