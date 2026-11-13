# 测试 expr 模式 + print 输出 + 参数表达式引用 .file
.gz_mode <- "expr"
.gz_function <- ""
.gz_source <- ""
.gz_code <- "d <- read.csv(.file, check.names = FALSE); cat('读入行数:', nrow(d), '\n'); summary(d$value)"
.gz_file_arg <- ""
.gz_files <- c("/Users/ac/Documents/GitHub/GlazeR/testdata/sample.csv")
.gz_param_keys <- c("threshold")
.gz_param_exprs <- c("20")
.gz_output_mode <- "print"
.gz_output_dir <- "/Users/ac/Documents/GitHub/GlazeR/testdata/out"
.gz_output_suffix <- "_demo"
.gz_output_code <- ""
.gz_out_base <- "sample"
.gz_workdir <- "/Users/ac/Documents/GitHub/GlazeR/testdata"
