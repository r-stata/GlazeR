// GlazeR — 转盘配置文件（.glazer）导出 / 导入
//
// 设计目标：导出的是「人能直接读懂并手工编辑」的纯文本，而不是配置文件快照。
// .glazer 是 GlazeR 注册的专属文档类型（UTI: com.rstata.glazer.wheel），
// 遵循 public.utf8-plain-text，双击即在 GlazeR 的可编辑文档窗口打开（带语法高亮）。
// 段落式结构：【转盘】开始一套转盘，其后的【扇区】归属该转盘；
// 字段写成「键 = 值」，参数行可重复，多行 R / Python / Stata 代码用三引号块书写。
// 解析全程容错：注释、空行、全角冒号、中英文键名/值、BOM、缺失字段都能处理，
// 并把不确定之处汇总成 warnings 交给 UI 预览，绝不因为一处笔误丢掉整份配置。
import Foundation
import UniformTypeIdentifiers

// MARK: - 解析结果

struct WheelTextParseResult {
    var profiles: [WheelProfile] = []
    var warnings: [String] = []
    var errors: [String] = []
    var lineCount: Int = 0

    var sliceTotal: Int { profiles.reduce(0) { $0 + $1.slices.count } }
}

// MARK: - 导入策略

enum WheelImportMode: String, CaseIterable, Identifiable {
    case replaceMatching
    case appendAll
    case replaceAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replaceMatching: return "替换同名转盘"
        case .appendAll:       return "全部作为新增"
        case .replaceAll:      return "清空后导入"
        }
    }

    var detail: String {
        switch self {
        case .replaceMatching:
            return "按「编号」优先、名称次之匹配现有转盘并覆盖；文件中没有对应项的转盘追加为新转盘。"
        case .appendAll:
            return "文件里的每套转盘都生成新编号追加到末尾，现有转盘保持不变。"
        case .replaceAll:
            return "删除现有全部转盘，只保留文件中的内容（当前转盘会切到第一套）。"
        }
    }
}

// MARK: - 编解码器

enum WheelTextCodec {
    static let formatVersion = 3
    static let fileExtension = "glazer"
    static let typeIdentifier = "com.rstata.glazer.wheel"

    /// 文档类型：打包后的 app 里由 Info.plist 导出；从源码直接运行时退化为按扩展名推断
    static var documentType: UTType {
        UTType(typeIdentifier) ?? UTType(filenameExtension: fileExtension) ?? .plainText
    }

    static func isGlazerFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }

    /// 导出文件头部：既当说明文档，也当格式模板
    static let header: String = [
        "# ============================================================",
        "# GlazeR 转盘配置文件（.glazer）· 格式 v\(formatVersion)",
        "# ------------------------------------------------------------",
        "# 编辑说明",
        "#   · 本文件是 UTF-8 纯文本；双击 .glazer 会用 GlazeR 的可编辑文档窗口",
        "#     打开（可保存 / 另存为 / 应用到转盘），也可用任意文本编辑器修改。",
        "#   · 以 # 开头的行是注释，空行会被忽略，可自由增删。",
        "#   · 【转盘】开始一套转盘；随后的【扇区】归属该转盘，直到下一个【转盘】。",
        "#     也接受英文段落标记 [[wheel]] / [[slice]]。",
        "#   · 字段写成「键 = 值」或「键: 值」，键名两侧空格忽略；值里的换行可写 \\n。",
        "#   · 多行 R / Python / Stata 代码推荐写成三引号块，块内内容原样保留：",
        "#         自定义代码 = \"\"\"",
        "#         readRDS(.file)",
        "#         \"\"\"",
        "#   · 参数行可重复：参数.名称 = 表达式（R 用 TRUE / c(1,2)，Python 用 True / [1,2]，",
        "#     Stata 用命令行片段如 replace / n(5)）；停用参数.名称 = 表达式 表示不启用。",
        "#   · 颜色写 #RRGGBB；快捷键用 option / shift / control / command 以 + 连接。",
        "#   · 槽位 = 0…9：按住全局组合键 + 该数字直接呼出这套转盘，最多 10 套。",
        "#   · 引擎：R | Python | Stata（默认 R）。执行方式：函数 | 代码    批量：逐文件 | 整批",
        "#   · R 扇区自动解析：.file 完整路径 / .filename 文件名.后缀 / .dir 所在目录 /",
        "#     .filebasename 纯名称（不含后缀）/ .files 全部路径；写 .result、.out。",
        "#   · Python 扇区自动解析：FILE / FILENAME / DIR / FILEBASENAME / FILES / OUT，",
        "#     另有 glazer.file 等对象形式与内置 convert(FILE, \"xlsx\") 格式转换。",
        "#   · Stata 输入宏 `file' / `filename' / `dir' / `filebasename'；",
        "#     `out' 是完整输出文件路径（不是目录），`outdir' 是输出目录；",
        "#     另有 `file1'…`fileN'、`nfiles' 与同名全局宏 $file / $outdir 等。",
        "#   · 输出：无 | 打印 | .rds | .csv | .RData | .dta | 自定义",
        "#   · 编号是替换时的匹配依据，一般不要修改；删掉该行则按名称匹配。",
        "# ------------------------------------------------------------",
        "# 导入时可选择：替换同名转盘 / 全部作为新增 / 清空后导入。",
        "# ============================================================",
    ].joined(separator: "\n")

    // MARK: 导出

    static func exportText(_ profiles: [WheelProfile]) -> String {
        var lines = [header, ""]
        for raw in profiles {
            let p = raw.normalized
            lines.append("【转盘】")
            lines.append("编号 = \(p.id)")
            lines.append("名称 = \(escape(p.name))")
            lines.append("快捷键 = \(p.hotkeyFlags.joined(separator: " + "))")
            lines.append("槽位 = \(p.slot.map(String.init) ?? "无")")
            lines.append("扇区数 = \(p.sliceCount)")
            lines.append("")
            for s in p.slices {
                lines.append("【扇区】")
                lines.append("标签 = \(escape(s.label))")
                lines.append("说明 = \(escape(s.detail))")
                lines.append("颜色 = #\(normalizedColor(s.color))")
                lines.append("启用 = \(s.enabled ? "是" : "否")")
                lines.append("引擎 = \(engineText(s.engine))")
                lines.append("执行方式 = \(s.mode == .call ? "函数" : "代码")")
                lines.append("函数 = \(escape(s.function))")
                lines.append("源文件 = \(escape(s.sourceFile))")
                lines.append("路径参数 = \(escape(s.fileArg))")
                lines.append(contentsOf: field("自定义代码", s.code))
                lines.append("批量 = \(s.batch == .each ? "逐文件" : "整批")")
                lines.append("输出 = \(outputText(s.output))")
                lines.append("输出后缀 = \(escape(s.outputSuffix))")
                lines.append(contentsOf: field("写出代码", s.outputCode))
                for pa in s.params where !pa.key.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append("\(pa.enabled ? "参数" : "停用参数").\(pa.key) = \(escape(pa.value))")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 单行值 / 三引号多行块
    private static func field(_ key: String, _ value: String) -> [String] {
        guard value.contains("\n") else { return ["\(key) = \(escape(value))"] }
        var out = ["\(key) = \"\"\""]
        out.append(contentsOf: value.components(separatedBy: "\n"))
        out.append("\"\"\"")
        return out
    }

    static func engineText(_ e: SliceEngine) -> String {
        switch e {
        case .r:      return "R"
        case .python: return "Python"
        case .stata:  return "Stata"
        }
    }

    private static func outputText(_ m: OutputMode) -> String {
        switch m {
        case .none: return "无"
        case .print: return "打印"
        case .rds: return ".rds"
        case .csv: return ".csv"
        case .rdata: return ".RData"
        case .dta: return ".dta"
        case .custom: return "自定义"
        }
    }

    // MARK: 值转义（保证 R / Python / Stata 代码里的 "\n" 字面量不会被误还原成真实换行）

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" {
                let n = s.index(after: i)
                if n < s.endIndex {
                    let d = s[n]
                    if d == "n" { out.append("\n"); i = s.index(after: n); continue }
                    if d == "t" { out.append("\t"); i = s.index(after: n); continue }
                    if d == "\\" { out.append("\\"); i = s.index(after: n); continue }
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    // MARK: 解析

    private enum FieldKey: String {
        case id, name, hotkey, slot, sliceCount
        case label, detail, color, enabled, engine, mode, function, source
        case fileArg, code, batch, output, suffix, outputCode
    }

    static func parse(_ text: String) -> WheelTextParseResult {
        var result = WheelTextParseResult()
        let cleaned = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = cleaned.components(separatedBy: "\n")
        result.lineCount = lines.count

        var profiles: [WheelProfile] = []
        var profile: WheelProfile?
        var slice: SliceConfig?
        var blockKey: FieldKey?          // 正在收集三引号块的字段
        var blockLines: [String] = []
        var blockStartLine = 0
        var sawWheel = false

        func flushSlice() {
            guard let s = slice else { return }
            if var p = profile { p.slices.append(s); profile = p }
            slice = nil
        }

        func flushProfile() {
            flushSlice()
            guard var p = profile else { return }
            let declared = p.sliceCount       // 0 表示文本里没写「扇区数」
            let actual = p.slices.count
            if declared > 0 && actual > 0 && declared != actual {
                result.warnings.append("转盘「\(p.name)」声明 \(declared) 个扇区，文本中有 \(actual) 个，已按实际数量处理")
            }
            let target = actual > 0 ? actual : (declared > 0 ? declared : 6)
            p.sliceCount = min(max(target, 2), 12)
            if p.slices.count > 12 {
                result.warnings.append("转盘「\(p.name)」超过 12 个扇区，多余的已忽略")
            }
            p.normalize()
            if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = "导入转盘" }
            profiles.append(p)
            profile = nil
        }

        func startProfile() {
            flushProfile()
            profile = WheelProfile(id: UUID().uuidString, name: "导入转盘",
                                   sliceCount: 0, slices: [], hotkeyFlags: [])
            sawWheel = true
        }

        func startSlice(line: Int) {
            if profile == nil {
                result.warnings.append("第 \(line) 行的【扇区】出现在【转盘】之前，已自动创建一套转盘")
                startProfile()
            }
            flushSlice()
            let index = profile?.slices.count ?? 0
            slice = SliceConfig.blank(index: index)
        }

        func applyBlock() {
            guard let key = blockKey else { return }
            let value = blockLines.joined(separator: "\n")
            setValue(key, value, isBlock: true)
            blockKey = nil
            blockLines = []
        }

        func setValue(_ key: FieldKey, _ valueRaw: String, isBlock: Bool = false) {
            let value = isBlock ? valueRaw : unescape(valueRaw)
            // 容错：在扇区段落里写「名称」时，视为该扇区的标签而不是转盘名称
            if key == .name && slice != nil {
                var s = slice!; s.label = value; slice = s; return
            }
            if key == .id || key == .name || key == .hotkey || key == .sliceCount || key == .slot {
                guard var p = profile else {
                    result.warnings.append("字段「\(key.rawValue)」出现在转盘之外，已忽略")
                    return
                }
                switch key {
                case .id:
                    if !value.trimmed.isEmpty { p.id = value.trimmed }
                case .name: p.name = value
                case .hotkey: p.hotkeyFlags = parseHotkeys(value)
                case .slot:
                    let t = value.trimmed.lowercased()
                    if ["", "无", "未分配", "none", "auto", "-"].contains(t) {
                        p.slot = nil
                    } else if let n = Int(t), (0...9).contains(n) {
                        p.slot = n
                    } else {
                        result.warnings.append("「槽位」应为 0–9 或「无」：\(value)")
                    }
                case .sliceCount:
                    if let n = Int(value.trimmed) { p.sliceCount = n }
                    else { result.warnings.append("「扇区数」不是整数：\(value)") }
                default: break
                }
                profile = p
                return
            }

            guard var s = slice else {
                result.warnings.append("字段「\(key.rawValue)」出现在扇区之外，已忽略")
                return
            }
            switch key {
            case .label: s.label = value
            case .detail: s.detail = value
            case .color:
                if let c = parseColor(value) { s.color = c }
                else { result.warnings.append("颜色「\(value)」不是 #RRGGBB，已保留默认色") }
            case .enabled:
                if let b = parseBool(value) { s.enabled = b }
            case .engine:
                if let e = parseEngine(value) { s.engine = e }
                else { result.warnings.append("引擎「\(value)」无法识别，已按 R 处理") }
            case .mode:
                if let m = parseMode(value) { s.mode = m }
                else { result.warnings.append("执行方式「\(value)」无法识别，已按「函数」处理") }
            case .function: s.function = value
            case .source: s.sourceFile = value
            case .fileArg: s.fileArg = value
            case .code: s.code = value
            case .batch:
                if let b = parseBatch(value) { s.batch = b }
            case .output:
                if let m = parseOutput(value) { s.output = m }
                else { result.warnings.append("输出方式「\(value)」无法识别，已按「无」处理") }
            case .suffix: s.outputSuffix = value
            case .outputCode: s.outputCode = value
            default: break
            }
            slice = s
        }

        for (idx, rawLine) in lines.enumerated() {
            let lineNo = idx + 1

            // 三引号块内：原样保留（含 # 注释行与缩进）
            if blockKey != nil {
                if rawLine.trimmed == "\"\"\"" || rawLine.trimmed == "'''" {
                    applyBlock()
                } else {
                    blockLines.append(rawLine)
                }
                continue
            }

            let line = rawLine.trimmed
            if line.isEmpty || line.hasPrefix("#") { continue }

            if isWheelMark(line) { startProfile(); continue }
            if isSliceMark(line) { startSlice(line: lineNo); continue }

            guard let (keyText, valueText) = splitField(line) else {
                result.warnings.append("第 \(lineNo) 行无法解析，已跳过：\(String(line.prefix(40)))")
                continue
            }

            if valueText.trimmed == "\"\"\"" || valueText.trimmed == "'''" {
                if let key = canonicalField(keyText) {
                    blockKey = key
                    blockLines = []
                    blockStartLine = lineNo
                } else {
                    result.warnings.append("第 \(lineNo) 行的多行块字段名无法识别，已跳过")
                }
                continue
            }

            if let (name, enabled) = parseParamKey(keyText) {
                guard var s = slice else {
                    result.warnings.append("第 \(lineNo) 行的参数出现在扇区之外，已忽略")
                    continue
                }
                s.params.append(ParamItem(key: name, value: unescape(valueText.trimmed),
                                          enabled: enabled))
                slice = s
                continue
            }

            guard let key = canonicalField(keyText) else {
                result.warnings.append("第 \(lineNo) 行的字段「\(keyText)」无法识别，已忽略")
                continue
            }
            setValue(key, valueText.trimmed)
        }

        if blockKey != nil {
            result.warnings.append("第 \(blockStartLine) 行开始的多行块没有闭合，已按文件末尾处理")
            applyBlock()
        }
        flushProfile()

        if !sawWheel && profiles.isEmpty {
            result.errors.append("文件中没有找到【转盘】段落。请确认选择的是 GlazeR 导出的 .glazer 配置文件。")
        }
        result.profiles = profiles
        return result
    }

    // MARK: 行解析辅助

    private static func isWheelMark(_ s: String) -> Bool {
        let v = s.lowercased()
            .replacingOccurrences(of: "【", with: "[").replacingOccurrences(of: "】", with: "]")
        return ["[转盘]", "[wheel]", "[profile]", "[[wheel]]", "[[profile]]"].contains(v)
    }

    private static func isSliceMark(_ s: String) -> Bool {
        let v = s.lowercased()
            .replacingOccurrences(of: "【", with: "[").replacingOccurrences(of: "】", with: "]")
        return ["[扇区]", "[slice]", "[[slice]]", "[action]"].contains(v)
    }

    /// 优先按第一个「=」切分，其次按「:」/「：」切分
    private static func splitField(_ line: String) -> (String, String)? {
        if let r = line.range(of: "=") {
            return (String(line[..<r.lowerBound]).trimmed,
                    String(line[r.upperBound...]).trimmed)
        }
        for sep in ["：", ":"] {
            if let r = line.range(of: sep) {
                return (String(line[..<r.lowerBound]).trimmed,
                        String(line[r.upperBound...]).trimmed)
            }
        }
        return nil
    }

    private static func canonicalField(_ raw: String) -> FieldKey? {
        switch raw.trimmed.lowercased() {
        case "编号", "id", "uuid":                                  return .id
        case "名称", "转盘名称", "name", "title":                   return .name
        case "快捷键", "组合键", "hotkey", "hotkeys", "modifiers": return .hotkey
        case "槽位", "数字键", "数字槽位", "slot", "digit", "number": return .slot
        case "扇区数", "扇区数量", "slices", "slice_count", "count": return .sliceCount
        case "标签", "显示名称", "label":                          return .label
        case "说明", "悬停说明", "detail", "desc", "description":  return .detail
        case "颜色", "color", "colour":                            return .color
        case "启用", "enabled", "active":                          return .enabled
        case "引擎", "语言", "engine", "lang", "language":          return .engine
        case "执行方式", "模式", "mode", "type":                    return .mode
        case "函数", "r函数", "python函数", "function", "fun", "fn": return .function
        case "源文件", "脚本", "source", "source_file", "script":  return .source
        case "路径参数", "文件参数", "file_arg", "filearg", "path_arg": return .fileArg
        case "自定义代码", "代码", "code", "expr", "expression":    return .code
        case "批量", "多文件处理", "batch":                        return .batch
        case "输出", "结果处理", "output", "output_mode":           return .output
        case "输出后缀", "后缀", "suffix", "output_suffix":         return .suffix
        case "写出代码", "自定义写出", "output_code", "write_code": return .outputCode
        default: return nil
        }
    }

    /// 参数行：参数.名称 / param.name / 停用参数.名称 / disabled_param.name
    private static func parseParamKey(_ raw: String) -> (String, Bool)? {
        let k = raw.trimmed
        let lower = k.lowercased()
        // 第二个元素表示「该参数是否停用」，返回时转换成 enabled
        let forms: [(String, Bool)] = [
            ("停用参数.", true), ("disabled_param.", true), ("disabled param.", true),
            ("参数.", false), ("param.", false), ("param:", false),
        ]
        for (prefix, isDisabled) in forms {
            if lower.hasPrefix(prefix.lowercased()) {
                let name = String(k.dropFirst(prefix.count)).trimmed
                guard !name.isEmpty else { return nil }
                return (name, !isDisabled)
            }
        }
        return nil
    }

    // MARK: 值解析

    static func parseBool(_ s: String) -> Bool? {
        switch s.trimmed.lowercased() {
        case "是", "true", "yes", "y", "1", "开", "启用", "on":  return true
        case "否", "false", "no", "n", "0", "关", "停用", "off": return false
        default: return nil
        }
    }

    static func parseEngine(_ s: String) -> SliceEngine? {
        switch s.trimmed.lowercased() {
        case "r", "r语言", "r 函数", "rlang", "rscript":                    return .r
        case "python", "py", "py3", "python3", "python函数", "python 函数": return .python
        case "stata", "stata-mp", "stata-se", "stata函数", "stata 函数",
             "do", "dofile", "stata代码", "stata 代码":                    return .stata
        default: return nil
        }
    }

    static func parseMode(_ s: String) -> SliceMode? {
        switch s.trimmed.lowercased() {
        case "函数", "调用函数", "call", "fun", "function": return .call
        case "代码", "自定义代码", "表达式", "expr", "expression": return .expr
        default: return nil
        }
    }

    static func parseBatch(_ s: String) -> BatchMode? {
        switch s.trimmed.lowercased() {
        case "逐文件", "逐个", "each", "single": return .each
        case "整批", "一次", "全部", "all", "batch": return .all
        default: return nil
        }
    }

    static func parseOutput(_ s: String) -> OutputMode? {
        switch s.trimmed.lowercased() {
        case "无", "不写出", "仅执行", "不写出（仅执行）", "none", "": return OutputMode.none
        case "打印", "打印结果到日志", "print": return .print
        case ".rds", "rds", "保存为 .rds", "保存为rds": return .rds
        case ".csv", "csv", "保存为 .csv", "保存为csv": return .csv
        case ".rdata", "rdata", "保存为 .rdata", "保存为rdata": return .rdata
        case ".dta", "dta", "保存为 .dta", "保存为dta": return .dta
        case "自定义", "自定义写出代码", "custom": return .custom
        default: return nil
        }
    }

    static func parseHotkeys(_ s: String) -> [String] {
        let t = s.trimmed.lowercased()
        if t.isEmpty || ["跟随全局设置", "默认", "auto", "none"].contains(t) { return [] }
        let parts = t.components(separatedBy: CharacterSet(charactersIn: "+,、/ \t"))
        var out: [String] = []
        for p in parts {
            switch p.trimmed {
            case "option", "alt", "⌥", "option键", "alt键":  appendUnique(&out, "option")
            case "shift", "⇧", "shift键":                    appendUnique(&out, "shift")
            case "control", "ctrl", "⌃", "control键":        appendUnique(&out, "control")
            case "command", "cmd", "⌘", "command键":         appendUnique(&out, "command")
            case "capslock", "caps", "⇪":                    appendUnique(&out, "capslock")
            default: break
            }
        }
        return out
    }

    private static func appendUnique(_ arr: inout [String], _ v: String) {
        if !arr.contains(v) { arr.append(v) }
    }

    static func parseColor(_ s: String) -> String? {
        var v = s.trimmed.uppercased()
        if v.hasPrefix("#") { v = String(v.dropFirst()) }
        if v.hasPrefix("0X") { v = String(v.dropFirst(2)) }
        let hex = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard v.count == 6, v.unicodeScalars.allSatisfy({ hex.contains($0) }) else { return nil }
        return v
    }

    static func normalizedColor(_ s: String) -> String {
        parseColor(s) ?? "4F46E5"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
