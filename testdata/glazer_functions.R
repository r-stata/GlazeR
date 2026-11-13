# -*- coding: utf-8 -*-
# GlazeR 自定义函数示例（在扇区的「自定义 R 脚本」里选择本文件即可 source）
# 说明：文件路径由 GlazeR 注入到扇区配置的形参名（默认 file），其余参数来自「默认参数」。

# 示例一：读取任意表格并输出结构化摘要（返回字符串向量）
gz_table_summary <- function(file, n = 5, ...) {
  ext <- tolower(tools::file_ext(file))
  df <- switch(ext,
    csv = utils::read.csv(file, check.names = FALSE, ...),
    tsv = utils::read.delim(file, check.names = FALSE, ...),
    rds = readRDS(file),
    stop("不支持的扩展名：", ext)
  )
  c(
    sprintf("文件：%s", basename(file)),
    sprintf("维度：%d 行 × %d 列", nrow(df), ncol(df)),
    sprintf("列名：%s", paste(names(df), collapse = ", ")),
    capture.output(print(utils::head(df, n)))
  )
}

# 示例二：把 CSV 转成 Stata .dta（需要 haven）
gz_csv_to_dta <- function(file, label = "数据处理：微信公众号 RStata", ...) {
  if (!requireNamespace("haven", quietly = TRUE)) stop("请先安装 haven 包")
  df <- utils::read.csv(file, check.names = FALSE, ...)
  out <- file.path(dirname(file),
                   paste0(tools::file_path_sans_ext(basename(file)), "_glazed.dta"))
  haven::write_dta(df, out, label = label)
  out
}

# 示例三：批量合并同目录 CSV（配合「整批一次执行」，此时 file 为字符向量）
gz_bind_csv <- function(file, ...) {
  d <- do.call(rbind, lapply(file, function(p) {
    x <- utils::read.csv(p, check.names = FALSE, ...)
    x$.source <- basename(p)
    x
  }))
  d
}
