// 独立校验：配置文本导出 → 解析 → 逐字段比对（不参与 App 构建）
// 运行：swiftc -swift-version 5 -parse-as-library \
//          native/Sources/Models.swift native/Sources/WheelTextCodec.swift \
//          native/Tests/textcodec_roundtrip.swift -o /tmp/glazer_roundtrip && /tmp/glazer_roundtrip
import Foundation

@main
struct RoundTrip {
    static func main() {
        var passed = 0, failed = 0
        func check(_ name: String, _ cond: Bool) {
            if cond { passed += 1; print("PASS · \(name)") }
            else { failed += 1; print("FAIL · \(name)") }
        }

        // ---------------------------------------------- 1. 完整 round-trip
        let code = "x <- readRDS(.file)\ncat(\"行1\\n行2\")\nx"
        let outCode = "saveRDS(.result, .out)\nmessage(\"ok\\n\")"
        let s0 = SliceConfig(
            label: "复杂动作", detail: "含 \\n 字面量与真实换行",
            mode: .expr, function: "", sourceFile: "/tmp/a b/脚本.R",
            code: code, fileArg: "",
            params: [ParamItem(key: "verbose", value: "TRUE", enabled: true),
                     ParamItem(key: "na", value: "\"\"", enabled: false),
                     ParamItem(key: "cols", value: "c(1, 2, 3)", enabled: true)],
            batch: .all, output: .custom, outputSuffix: "_out",
            outputCode: outCode, color: "FF00AA", enabled: false)
        let s1 = SliceConfig(label: "DTA→RDS", function: "haven::read_dta",
                             params: [], output: .rds, outputSuffix: "_data",
                             color: "2563EB")
        // Python 扇区：验证引擎字段、三引号 Python 代码块与 Python 风格参数表达式
        let pyCode = "import os\nresult = {\"size\": os.path.getsize(FILE),\n          \"dir\": DIR}"
        let s2 = SliceConfig(label: "转 XLSX", detail: "Python 引擎 + 内置格式转换",
                             engine: .python, mode: .expr, function: "",
                             code: pyCode, fileArg: "",
                             params: [ParamItem(key: "encoding", value: "\"utf-8\"", enabled: true)],
                             batch: .each, output: .none, outputSuffix: "_glazed",
                             color: "0D9488")
        let stCode = "use `\"`file'\"', clear\nsummarize"
        let s3 = SliceConfig(label: "描述统计", detail: "Stata 引擎 + 三引号 do 代码块",
                             engine: .stata, mode: .expr, function: "",
                             code: stCode, fileArg: "",
                             params: [], batch: .each, output: .print,
                             outputSuffix: "_glazed", color: "4F46E5")
        var profile = WheelProfile(id: "FIXED-ID-001", name: "测试转盘",
                                   sliceCount: 4, slices: [s0, s1, s2, s3],
                                   hotkeyFlags: ["option", "shift"], slot: 7)
        profile.normalize()

        let text = WheelTextCodec.exportText([profile])
        check("导出文本含格式头 v3", text.contains("GlazeR 转盘配置文件（.glazer）· 格式 v3"))
        check("导出文本含编号", text.contains("编号 = FIXED-ID-001"))
        check("导出文本含槽位", text.contains("槽位 = 7"))
        check("导出文本含引擎字段", text.contains("引擎 = R") && text.contains("引擎 = Python")
              && text.contains("引擎 = Stata"))
        check("多行代码写成三引号块", text.contains("自定义代码 = \"\"\""))

        let r = WheelTextCodec.parse(text)
        check("解析无错误", r.errors.isEmpty)
        check("解析出 1 套转盘", r.profiles.count == 1)
        check("解析无警告", r.warnings.isEmpty)
        if let p = r.profiles.first {
            check("id", p.id == "FIXED-ID-001")
            check("名称", p.name == "测试转盘")
            check("快捷键", p.hotkeyFlags == ["option", "shift"])
            check("数字键槽位", p.slot == 7)
            check("扇区数", p.slices.count == 4)
            if p.slices.count >= 4 {
                let c = p.slices[2], d = p.slices[3]
                check("Python 引擎", c.engine == .python)
                check("Python 多行代码", c.code == pyCode)
                check("Python 参数表达式", c.params.first?.value == "\"utf-8\"")
                check("Stata 引擎", d.engine == .stata)
                check("Stata 三引号 do 代码", d.code == stCode)
            }
            if p.slices.count >= 2 {
                let a = p.slices[0], b = p.slices[1]
                check("R 引擎为默认", a.engine == .r && b.engine == .r)
                check("标签", a.label == "复杂动作")
                check("说明", a.detail == "含 \\n 字面量与真实换行")
                check("颜色", a.color == "FF00AA" && b.color == "2563EB")
                check("启用状态", a.enabled == false && b.enabled == true)
                check("执行方式", a.mode == .expr && b.mode == .call)
                check("函数名", b.function == "haven::read_dta")
                check("源文件", a.sourceFile == "/tmp/a b/脚本.R")
                check("路径参数", a.fileArg == "" && b.fileArg == "file")
                check("多行 R 代码（含 \\n 字面量）", a.code == code)
                check("批量", a.batch == .all && b.batch == .each)
                check("输出方式", a.output == .custom && b.output == .rds)
                check("输出后缀", a.outputSuffix == "_out" && b.outputSuffix == "_data")
                check("写出代码（含 \\n 字面量）", a.outputCode == outCode)
                check("参数个数", a.params.count == 3)
                check("参数顺序与值", a.params.map(\.key) == ["verbose", "na", "cols"]
                      && a.params[2].value == "c(1, 2, 3)")
                check("停用参数", a.params[1].enabled == false && a.params[0].enabled == true)
            }
        }

        // ---------------------------------------------- 2. 手工编辑文本容错
        let manual = [
            "\u{FEFF}# 手工编辑的配置（BOM + 注释）",
            "【转盘】",
            "名称: 手工转盘",                       // 全角冒号
            "快捷键 = ⌥ + ⇧ + ⌘",                 // 符号写法
            "槽位 = 3",                            // 数字键槽位
            "扇区数 = 3",
            "",
            "【扇区】",
            "标签 = CSV 读取",
            "颜色 = #12abCD",
            "启用 = 否",
            "执行方式 = 函数",
            "函数 = readr::read_csv",
            "自定义代码 = \"\"\"",
            "x <- 1",
            "# 这一行在三引号块内，是代码不是注释",
            "cat(\"hi\\n\")",
            "\"\"\"",
            "批量 = 整批",
            "输出 = 打印",
            "参数.show_col_types = FALSE",
            "停用参数.na = \"\"",
            "",
            "【扇区】",
            "显示名称 = 第二个扇区",
            "引擎 = PY",                            // 引擎别名
            "输出 = .dta",
            "param.limit = 100L",
        ].joined(separator: "\n")

        let m = WheelTextCodec.parse(manual)
        check("手工文本无错误", m.errors.isEmpty)
        check("手工文本解析出 1 套", m.profiles.count == 1)
        if let p = m.profiles.first {
            check("手工·名称", p.name == "手工转盘")
            check("手工·符号快捷键", p.hotkeyFlags == ["option", "shift", "command"])
            check("手工·数字键槽位", p.slot == 3)
            check("手工·声明 3 个但只有 2 个扇区→按实际", p.slices.count == 2)
            check("手工·有数量不一致警告", m.warnings.contains { $0.contains("声明 3 个扇区") })
            if p.slices.count >= 1 {
                let a = p.slices[0]
                check("手工·颜色规范化", a.color == "12ABCD")
                check("手工·布尔", a.enabled == false)
                check("手工·三引号块原样保留", a.code.contains("# 这一行在三引号块内"))
                check("手工·块内 \\n 不反转义", a.code.contains("cat(\"hi\\n\")"))
                check("手工·批量/输出", a.batch == .all && a.output == .print)
                check("手工·参数与停用", a.params.count == 2
                      && a.params[0].enabled && !a.params[1].enabled)
            }
            if p.slices.count >= 2 {
                check("手工·中文键别名", p.slices[1].label == "第二个扇区")
                check("手工·引擎别名 PY", p.slices[1].engine == .python)
                check("手工·英文 param 前缀", p.slices[1].params.first?.key == "limit")
            }
        }

        // ---------------------------------------------- 3. 多转盘 + 英文段落标记
        let multi = [
            "[[wheel]]", "name = Wheel A", "hotkey = option", "slot = 0",
            "[[slice]]", "label = A1", "function = read.csv",
            "[[wheel]]", "name = Wheel B", "hotkey = control+command", "slot = 9",
            "[[slice]]", "label = B1", "engine = python3", "mode = expr", "code = 1 + 1",
        ].joined(separator: "\n")
        let mr = WheelTextCodec.parse(multi)
        check("英文段落标记解析出 2 套", mr.profiles.count == 2)
        check("英文段落·名称", mr.profiles.map(\.name) == ["Wheel A", "Wheel B"])
        check("英文段落·快捷键", mr.profiles.last?.hotkeyFlags == ["control", "command"])
        check("英文段落·槽位", mr.profiles.compactMap(\.slot) == [0, 9])
        check("英文段落·引擎别名 python3", mr.profiles.last?.slices.first?.engine == .python)

        // ---------------------------------------------- 3b. Stata 引擎与 do 代码块
        let st = [
            "【转盘】", "名称 = Stata 转盘", "槽位 = 6",
            "【扇区】", "标签 = 描述统计", "引擎 = STATA",
            "自定义代码 = \"\"\"", "use `\"`file'\"', clear", "summarize", "\"\"\"",
            "输出 = 打印",
        ].joined(separator: "\n")
        let sr = WheelTextCodec.parse(st)
        check("Stata 引擎别名 STATA", sr.profiles.first?.slices.first?.engine == .stata)
        check("Stata 三引号 do 代码块", sr.profiles.first?.slices.first?.code.contains("summarize") == true)
        check("Stata 槽位", sr.profiles.first?.slot == 6)

        // ---------------------------------------------- 4. 异常输入
        check("空文本给出错误", !WheelTextCodec.parse("").errors.isEmpty)
        check("纯注释给出错误", !WheelTextCodec.parse("# 只有注释\n\n").errors.isEmpty)
        let broken = WheelTextCodec.parse("【转盘】\n名称 = X\n颜色 = notacolor\n输出 = 火星模式\n随机一行")
        check("非法字段不崩溃", broken.profiles.count == 1)
        check("非法字段产生警告", !broken.warnings.isEmpty)

        // ---------------------------------------------- 5. 仓库示例文件可回读
        if CommandLine.arguments.count > 1,
           let sample = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) {
            let ex = WheelTextCodec.parse(sample)
            check("示例文件解析无错误", ex.errors.isEmpty)
            check("示例文件包含 5 套转盘", ex.profiles.count == 5)
            check("示例文件共 25 个扇区", ex.sliceTotal == 25)
            check("示例文件解析无警告", ex.warnings.isEmpty)
            check("示例·槽位依次是 1/2/3/4/5", ex.profiles.compactMap(\.slot) == [1, 2, 3, 4, 5])
            let all = ex.profiles.flatMap(\.slices)
            check("示例·13 个 Python 扇区", all.filter { $0.engine == .python }.count == 13)
            check("示例·9 个 R 扇区", all.filter { $0.engine == .r }.count == 9)
            check("示例·3 个 Stata 扇区", all.filter { $0.engine == .stata }.count == 3)
            check("示例·Python 三引号块保留换行", ex.profiles[1].slices[0].code.contains("\n"))
            check("示例·Python 内置 convert()", ex.profiles[2].slices[0].code.contains("convert(FILE"))
            check("示例·Stata 三引号块保留换行", ex.profiles[4].slices[0].code.contains("\n"))
            check("示例·Stata 路径宏", ex.profiles[4].slices[0].code.contains("`file'"))
            check("示例·R 多行代码保留换行", ex.profiles[3].slices[1].code.contains("\n") == true)
            check("示例·停用参数", ex.profiles[3].slices[2].params.last?.enabled == false)
            check("示例·三引擎路径变量提示", sample.contains(".filebasename")
                  && sample.contains("FILEBASENAME") && sample.contains("`filebasename'"))
        }

        print("\n==== \(passed) passed, \(failed) failed ====")
        exit(failed == 0 ? 0 : 1)
    }
}
