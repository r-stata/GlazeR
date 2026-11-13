// 生成 examples/wheels.glazer（保证示例与真实导出格式完全一致）
// 编译：swiftc -swift-version 5 -parse-as-library \
//          native/Sources/Models.swift native/Sources/WheelTextCodec.swift \
//          native/Tests/gen_example.swift -o build/tmp/gen_example
//     build/tmp/gen_example > examples/wheels.glazer
import Foundation

@main
struct GenExample {
    static func main() {
        // ① R 函数处理转盘（数字键槽位 1）
        var a = WheelProfile.demo().normalized
        a.id = "EXAMPLE-WHEEL-001"
        a.name = "R 数据处理（示例）"
        a.hotkeyFlags = ["option"]
        a.slot = 1

        // ② Python 函数处理转盘（数字键槽位 2）
        let py1 = SliceConfig(
            label: "文件信息", detail: "Python 代码里直接使用 FILE / DIR / FILEBASENAME",
            engine: .python, mode: .expr,
            code: "import os\nresult = {\n    \"路径\": FILE,\n    \"大小\": os.path.getsize(FILE),\n    \"目录\": DIR,\n    \"名称\": FILEBASENAME,\n}",
            fileArg: "", params: [], batch: .each, output: .print,
            outputSuffix: "_glazed", color: "8B5CF6")
        let py2 = SliceConfig(
            label: "CSV 概览", detail: "调用 pandas 函数，默认参数按 Python 表达式求值",
            engine: .python, mode: .call, function: "pandas.read_csv",
            fileArg: "filepath_or_buffer",
            params: [ParamItem(key: "encoding", value: "\"utf-8\"", enabled: true),
                     ParamItem(key: "nrows", value: "100", enabled: false)],
            batch: .each, output: .print, outputSuffix: "_glazed", color: "2563EB")
        let py3 = SliceConfig(
            label: "批量统计", detail: "整批处理，FILES 是全部路径列表",
            engine: .python, mode: .expr,
            code: "result = {\"文件数\": len(FILES), \"路径\": FILES}",
            fileArg: "", params: [], batch: .all, output: .print,
            outputSuffix: "_glazed", color: "0D9488")
        var b = WheelProfile(id: "EXAMPLE-WHEEL-002", name: "Python 函数（示例）",
                             sliceCount: 3, slices: [py1, py2, py3],
                             hotkeyFlags: ["option"], slot: 2)
        b.normalize()

        // ③ DataWheel 格式转换转盘（数字键槽位 3）
        // 与 WheelPresets.dataWheel 的 10 个格式扇区保持一致
        let formats: [(String, String, String)] = [
            ("CSV", "csv", "F59E0B"), ("TSV", "tsv", "F97316"),
            ("TXT", "txt", "D97706"), ("XLSX", "xlsx", "16A34A"),
            ("DTA", "dta", "0891B2"), ("RDS", "rds", "3B82F6"),
            ("PARQUET", "parquet", "8B5CF6"), ("FEATHER", "feather", "EC4899"),
            ("JSON", "json", "65A30D"), ("JSONL", "jsonl", "0D9488"),
        ]
        let dwSlices = formats.map { label, fmt, hex in
            SliceConfig(label: label, detail: "转换为 .\(fmt)",
                        engine: .python, mode: .expr,
                        code: "convert(FILE, \"\(fmt)\")",
                        fileArg: "", params: [], batch: .each,
                        output: .none, outputSuffix: "_glazed", color: hex)
        }
        var c = WheelProfile(id: "EXAMPLE-WHEEL-003", name: "格式转换（DataWheel 示例）",
                             sliceCount: formats.count, slices: dwSlices,
                             hotkeyFlags: ["option"], slot: 3)
        c.normalize()

        // ④ 自定义工作流（数字键槽位 4）：source + 路径变量 + 参数行 + 停用参数
        let s1 = SliceConfig(
            label: "HTML→封面图", detail: "先 source 自己的 R 脚本，再调用其中的函数",
            mode: .call, function: "create_class_titlepic",
            sourceFile: "/Users/ac/Documents/global_dir/create_class_titlepic.R",
            fileArg: "htmlfile", params: [], batch: .each,
            output: .none, outputSuffix: "_glazed", color: "4F46E5")
        let s2 = SliceConfig(
            label: "数据概览", detail: "多行 R 代码用三引号块，直接用 .file / .dir",
            mode: .expr, function: "",
            code: "x <- readRDS(.file)\nmessage(\"目录：\", .dir)\nsummary(x)",
            fileArg: "", params: [], batch: .each,
            output: .print, outputSuffix: "_glazed", color: "0891B2")
        let s3 = SliceConfig(
            label: "CSV→RDS", detail: "默认参数行可重复，停用参数不会传入",
            mode: .call, function: "readr::read_csv",
            params: [ParamItem(key: "show_col_types", value: "FALSE", enabled: true),
                     ParamItem(key: "locale", value: "readr::locale(encoding = \"UTF-8\")", enabled: false)],
            batch: .all, output: .rds, outputSuffix: "_data", color: "16A34A")
        var d = WheelProfile(id: "EXAMPLE-WHEEL-004", name: "常用工作流（示例）",
                             sliceCount: 3, slices: [s1, s2, s3],
                             hotkeyFlags: ["option", "shift"], slot: 4)
        d.normalize()

        // ⑤ Stata 命令转盘（数字键槽位 5）
        let st1 = SliceConfig(
            label: "描述统计", detail: "Stata 代码里直接使用 `file' / `dir'",
            engine: .stata, mode: .expr, function: "",
            code: "use `\"`file'\"', clear\nsummarize",
            fileArg: "", params: [], batch: .each,
            output: .print, outputSuffix: "_glazed", color: "4F46E5")
        let st2 = SliceConfig(
            label: "转 DTA", detail: "读入后由引擎自动写出 .dta",
            engine: .stata, mode: .expr, function: "",
            code: "use `\"`file'\"', clear",
            fileArg: "", params: [], batch: .each,
            output: .dta, outputSuffix: "_glazed", color: "0891B2")
        let st3 = SliceConfig(
            label: "自定义命令", detail: "Stata 命令 + 默认参数按命令行片段拼接",
            engine: .stata, mode: .call, function: "describe",
            fileArg: "", params: [ParamItem(key: "shortly", value: "", enabled: true)],
            batch: .each, output: .print, outputSuffix: "_glazed", color: "16A34A")
        var e = WheelProfile(id: "EXAMPLE-WHEEL-005", name: "Stata 命令（示例）",
                             sliceCount: 3, slices: [st1, st2, st3],
                             hotkeyFlags: ["option"], slot: 5)
        e.normalize()

        print(WheelTextCodec.exportText([a, b, c, d, e]), terminator: "")
    }
}
