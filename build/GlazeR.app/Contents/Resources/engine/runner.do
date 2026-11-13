* ============================================================
* GlazeR Stata 执行引擎模板（由 Swift 端填充占位符后生成 job.do）
* ------------------------------------------------------------
* Swift 会替换下方两处独立成行的占位标记：
*   VARS 段：自动解析的路径宏与任务参数
*   EXEC 段：用户的 Stata 代码 / 命令 / 自定义写出代码
* 注意：占位标记只能单独成行，切勿写进注释，否则整段宏会被拼进注释行。
* 结果写出段是固定模板，写成 key=value 纯文本，交由 Swift 组装结果字典。
*
* 为什么不用 stdout：macOS 下 Stata 批处理（-b do）把所有输出写进
* 当前工作目录的 <do 文件名>.log，stdout 始终为空。因此结果用一个
* 独立的 result.txt 回传，Swift 再把 .log 内容并进任务卡片的日志区。
* ============================================================
set linesize 255
set more off
capture log close _all

* ---------------------------------------------- 路径变量与任务参数
__GZ_VARS__

* ---------------------------------------------- 执行用户代码
capture noisily {
__GZ_EXEC__
}
local gz_rc = _rc

* ---------------------------------------------- 按输出方式自动写出
local gz_output ""
local gz_note ""
if `gz_rc' == 0 & "`gz_outmode'" == "dta" {
    capture noisily save `"`out'"', replace
    if _rc == 0 {
        local gz_output `"`out'"'
    }
    else {
        local gz_rc = _rc
        local gz_note "save 写出 .dta 失败"
    }
}
if `gz_rc' == 0 & "`gz_outmode'" == "csv" {
    capture noisily export delimited using `"`out'"', replace
    if _rc == 0 {
        local gz_output `"`out'"'
    }
    else {
        local gz_rc = _rc
        local gz_note "export delimited 写出 .csv 失败"
    }
}
if `gz_rc' == 0 & "`gz_outmode'" == "custom" {
    * 自定义写出代码已在执行块里运行，可用 `out' 或 `outdir' 自行指定路径
    if "`gz_output_file'" != "" {
        capture confirm file `"`gz_output_file'"'
        if _rc == 0 {
            local gz_output `"`gz_output_file'"'
        }
        else {
            local gz_note "未在建议路径检测到输出文件（若已写到其他位置可忽略）"
        }
    }
}

* 用户代码自行写出文件时（例如打印模式下 export delimited using `"`out'"'），
* 只要 `out' 指向的文件存在就当作本次输出，卡片可直接「打开 / 在 Finder 中显示」。
if `gz_rc' == 0 & "`gz_output'" == "" {
    capture confirm file `"`out'"'
    if _rc == 0 {
        local gz_output `"`out'"'
    }
}

* ---------------------------------------------- 结果回传
file open gz_rh using `"`gz_result'"', write replace text
if `gz_rc' == 0 {
    file write gz_rh "ok=true" _n
}
else {
    file write gz_rh "ok=false" _n
}
file write gz_rh "rc=`gz_rc'" _n
file write gz_rh "output=`gz_output'" _n
file write gz_rh "note=`gz_note'" _n
file close gz_rh
