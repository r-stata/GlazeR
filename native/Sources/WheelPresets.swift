// GlazeR — 一键新建的预设转盘（R / Python / Stata / DataWheel 格式转换）
import Foundation

enum WheelPreset: String, CaseIterable, Identifiable {
    case blank
    case rDemo
    case pythonDemo
    case stataDemo
    case dataWheel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank:       return "空白转盘"
        case .rDemo:       return "R 函数处理（示例）"
        case .pythonDemo:  return "Python 函数处理（示例）"
        case .stataDemo:   return "Stata 命令处理（示例）"
        case .dataWheel:   return "DataWheel 格式转换（10 种格式）"
        }
    }

    var detail: String {
        switch self {
        case .blank:       return "6 个空白扇区，自行填写"
        case .rDemo:       return "CSV / DTA / XLSX 转 RDS、数据概览、转 DTA"
        case .pythonDemo:  return "pandas 概览、类型转换、自定义 Python 代码"
        case .stataDemo:   return "describe / summarize / 转换 DTA / 自定义 do 代码"
        case .dataWheel:   return "与 DataWheel 相同的 10 个格式扇区，拖入即转换"
        }
    }

    func profile() -> WheelProfile {
        var p: WheelProfile
        switch self {
        case .blank:
            p = WheelProfile(name: "空白转盘", sliceCount: 6, slices: [], hotkeyFlags: [])
            p.normalize()

        case .rDemo:
            p = WheelProfile.demo()

        case .pythonDemo:
            p = WheelProfile(name: "Python 函数处理", sliceCount: 6, slices: [
                SliceConfig(label: "转 XLSX", detail: "内置格式转换", engine: .python, mode: .expr,
                            code: "convert(FILE, \"xlsx\")", output: .none, color: "16A34A"),
                SliceConfig(label: "数据概览", detail: "pandas describe()", engine: .python, mode: .expr,
                            code: "import pandas as pd\nresult = pd.read_csv(FILE).describe().to_string()",
                            output: .print, color: "3B82F6"),
                SliceConfig(label: "转 DTA", detail: "内置格式转换", engine: .python, mode: .expr,
                            code: "convert(FILE, \"dta\")", output: .none, color: "0891B2"),
                SliceConfig(label: "转 PARQUET", detail: "内置格式转换", engine: .python, mode: .expr,
                            code: "convert(FILE, \"parquet\")", output: .none, color: "8B5CF6"),
                SliceConfig(label: "转 JSON", detail: "内置格式转换", engine: .python, mode: .expr,
                            code: "convert(FILE, \"json\")", output: .none, color: "65A30D"),
                SliceConfig(label: "自定义 Python", detail: "可编辑的示例代码", engine: .python, mode: .expr,
                            code: "import os\nprint(FILE, FILENAME, DIR, FILEBASENAME)\nresult = FILE",
                            output: .print, color: "F97316"),
            ], hotkeyFlags: [])
            p.normalize()

        case .stataDemo:
            p = WheelProfile(name: "Stata 命令处理", sliceCount: 6, slices: [
                SliceConfig(label: "数据描述", detail: "use + describe", engine: .stata, mode: .expr,
                            code: "use `\"`file'\"', clear\ndescribe",
                            output: .print, color: "4F46E5"),
                SliceConfig(label: "描述统计", detail: "summarize 输出到日志", engine: .stata, mode: .expr,
                            code: "use `\"`file'\"', clear\nsummarize",
                            output: .print, color: "2563EB"),
                SliceConfig(label: "转 DTA", detail: "读入后写出 .dta", engine: .stata, mode: .expr,
                            code: "use `\"`file'\"', clear",
                            output: .dta, outputSuffix: "_glazed", color: "0891B2"),
                SliceConfig(label: "转 CSV", detail: "读入后写出 .csv", engine: .stata, mode: .expr,
                            code: "use `\"`file'\"', clear",
                            output: .csv, outputSuffix: "_glazed", color: "16A34A"),
                SliceConfig(label: "前 10 行", detail: "list in 1/10", engine: .stata, mode: .expr,
                            code: "use `\"`file'\"', clear\nlist in 1/10",
                            output: .print, color: "0D9488"),
                SliceConfig(label: "自定义 Stata", detail: "可编辑的 do 代码示例", engine: .stata, mode: .expr,
                            code: "* 输入用 `file' / `dir'；`out' 是完整输出文件，`outdir' 是输出目录\ndisplay \"文件：`file'\"\ndisplay \"目录：`dir'\"\ndisplay \"输出文件：`out'\"",
                            output: .print, color: "F97316"),
            ], hotkeyFlags: [])
            p.normalize()

        case .dataWheel:
            // 格式与配色沿用 DataWheel 的 Formats.swift
            let formats: [(String, String, String)] = [
                ("CSV",     "csv",     "F59E0B"),
                ("TSV",     "tsv",     "F97316"),
                ("TXT",     "txt",     "D97706"),
                ("XLSX",    "xlsx",    "16A34A"),
                ("DTA",     "dta",     "0891B2"),
                ("RDS",     "rds",     "3B82F6"),
                ("PARQUET", "parquet", "8B5CF6"),
                ("FEATHER", "feather", "EC4899"),
                ("JSON",    "json",    "65A30D"),
                ("JSONL",   "jsonl",   "0D9488"),
            ]
            p = WheelProfile(name: "格式转换（DataWheel）", sliceCount: formats.count,
                             slices: formats.map { label, fmt, hex in
                                 SliceConfig(label: label, detail: "转换为 .\(fmt)",
                                             engine: .python, mode: .expr,
                                             code: "convert(FILE, \"\(fmt)\")",
                                             output: .none, color: hex)
                             }, hotkeyFlags: [])
            p.normalize()
        }
        return p
    }
}
