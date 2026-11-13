# 自定义函数体内直接使用全局路径变量（不通过形参）
gz_probe_paths <- function() {
  sprintf("dir=%s | base=%s | exists=%s",
          .dir, .filebasename, file.exists(.file))
}
