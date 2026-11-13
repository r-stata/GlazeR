// GlazeR — .glazer 配置文件语法高亮
//
// 按「内容类别」着色：注释、段落标记、键名、分隔符、枚举值、颜色值、
// 三引号代码块（内部再区分字符串 / 关键字 / 数字 / 注释）。
// 只改 NSTextStorage 的显示属性，不改变文本内容，保存的始终是纯文本。
import AppKit

enum GlazerSyntax {

    struct Theme {
        let id: Int
        let background: NSColor
        let plain: NSColor
        let comment: NSColor
        let section: NSColor
        let key: NSColor
        let separator: NSColor
        let value: NSColor
        let enumValue: NSColor
        let number: NSColor
        let string: NSColor
        let keyword: NSColor
        let code: NSColor
        let codeBackground: NSColor
        let legendBar: NSColor
    }

    static let light = Theme(
        id: 0,
        background: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        plain: NSColor(srgbRed: 0.12, green: 0.14, blue: 0.19, alpha: 1),
        comment: NSColor(srgbRed: 0.54, green: 0.58, blue: 0.65, alpha: 1),
        section: NSColor(srgbRed: 0.43, green: 0.16, blue: 0.85, alpha: 1),
        key: NSColor(srgbRed: 0.11, green: 0.31, blue: 0.85, alpha: 1),
        separator: NSColor(srgbRed: 0.58, green: 0.63, blue: 0.71, alpha: 1),
        value: NSColor(srgbRed: 0.06, green: 0.46, blue: 0.43, alpha: 1),
        enumValue: NSColor(srgbRed: 0.71, green: 0.33, blue: 0.04, alpha: 1),
        number: NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 1),
        string: NSColor(srgbRed: 0.06, green: 0.47, blue: 0.44, alpha: 1),
        keyword: NSColor(srgbRed: 0.75, green: 0.10, blue: 0.36, alpha: 1),
        code: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1),
        codeBackground: NSColor(srgbRed: 0.965, green: 0.957, blue: 1.0, alpha: 1),
        legendBar: NSColor(srgbRed: 0.973, green: 0.976, blue: 0.984, alpha: 1))

    static let dark = Theme(
        id: 1,
        background: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1),
        plain: NSColor(srgbRed: 0.88, green: 0.90, blue: 0.94, alpha: 1),
        comment: NSColor(srgbRed: 0.52, green: 0.56, blue: 0.63, alpha: 1),
        section: NSColor(srgbRed: 0.76, green: 0.55, blue: 1.0, alpha: 1),
        key: NSColor(srgbRed: 0.45, green: 0.72, blue: 1.0, alpha: 1),
        separator: NSColor(srgbRed: 0.50, green: 0.55, blue: 0.63, alpha: 1),
        value: NSColor(srgbRed: 0.42, green: 0.85, blue: 0.78, alpha: 1),
        enumValue: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.36, alpha: 1),
        number: NSColor(srgbRed: 0.78, green: 0.64, blue: 1.0, alpha: 1),
        string: NSColor(srgbRed: 0.45, green: 0.87, blue: 0.81, alpha: 1),
        keyword: NSColor(srgbRed: 1.0, green: 0.49, blue: 0.68, alpha: 1),
        code: NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1),
        codeBackground: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.24, alpha: 1),
        legendBar: NSColor(srgbRed: 0.15, green: 0.16, blue: 0.21, alpha: 1))

    static let mono = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static let monoBold = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)
    static let monoSemibold = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
    static let monoItalic = NSFontManager.shared.convert(
        NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular), toHaveTrait: .italicFontMask)

    struct Legend: Identifiable {
        let id = UUID()
        let title: String
        let color: NSColor
    }

    static func legend(_ theme: Theme) -> [Legend] {
        [
            Legend(title: "注释", color: theme.comment),
            Legend(title: "段落", color: theme.section),
            Legend(title: "键名", color: theme.key),
            Legend(title: "枚举", color: theme.enumValue),
            Legend(title: "颜色/数字", color: theme.number),
            Legend(title: "代码", color: theme.value),
            Legend(title: "关键字", color: theme.keyword),
            Legend(title: "字符串", color: theme.string),
        ]
    }

    // MARK: 主入口

    static func apply(_ storage: NSTextStorage, theme: Theme, enabled: Bool) {
        let full = NSRange(location: 0, length: storage.length)
        let base: [NSAttributedString.Key: Any] = [
            .font: mono,
            .foregroundColor: theme.plain,
            .backgroundColor: NSColor.clear,
        ]
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        if enabled { colorize(storage, theme: theme) }
        storage.endEditing()
    }

    private static func paint(_ storage: NSTextStorage, _ range: NSRange,
                              color: NSColor, font: NSFont? = nil,
                              background: NSColor? = nil) {
        guard range.location >= 0, NSMaxRange(range) <= storage.length, range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: color, range: range)
        if let font { storage.addAttribute(.font, value: font, range: range) }
        if let background { storage.addAttribute(.backgroundColor, value: background, range: range) }
    }

    private static func colorize(_ storage: NSTextStorage, theme: Theme) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        var loc = 0
        var inCode = false

        while loc < text.length {
            let lineR = text.lineRange(for: NSRange(location: loc, length: 0))
            if lineR.length == 0 { break }
            let raw = text.substring(with: lineR)
            let bodyLen = raw.hasSuffix("\n") ? raw.count - 1 : raw.count
            let line = (raw as NSString).substring(to: max(0, bodyLen))
            let body = NSRange(location: lineR.location, length: max(0, bodyLen))
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if inCode {
                // 块内任何内容都按代码着色，包括看起来像 # 注释 / 段落标记的行
                if isDelimiter(trimmed) {
                    inCode = false
                    paint(storage, body, color: theme.section, font: monoBold,
                          background: theme.codeBackground)
                } else {
                    colorizeCodeLine(storage, body: body, line: line, theme: theme)
                }
            } else if trimmed.hasPrefix("#") {
                paint(storage, body, color: theme.comment, font: monoItalic)
            } else if isSection(trimmed) {
                paint(storage, body, color: theme.section, font: monoBold,
                      background: theme.codeBackground)
            } else if isDelimiter(trimmed) {
                // 手工编辑时也有人把三引号单独成行
                inCode = true
                paint(storage, body, color: theme.section, font: monoBold,
                      background: theme.codeBackground)
            } else if let (keyR, sepR, valR) = splitKeyValue(line, body: body) {
                paint(storage, keyR, color: theme.key, font: monoSemibold)
                paint(storage, sepR, color: theme.separator)
                let valueText = (text as NSString).substring(with: valR)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let delim = String(repeating: "\"", count: 3)
                let altDelim = String(repeating: "'", count: 3)
                if valueText == delim || valueText == altDelim {
                    // 「自定义代码 = """」：从这里开始进入代码块
                    inCode = true
                    paint(storage, valR, color: theme.section, font: monoBold)
                } else if valueText.hasPrefix(delim) && valueText.hasSuffix(delim)
                            && valueText.count > 6 {
                    // 单行三引号代码："""code"""
                    paint(storage, valR, color: theme.code,
                          background: theme.codeBackground)
                } else {
                    colorizeValue(storage, range: valR, line: line, theme: theme)
                }
            }

            loc = NSMaxRange(lineR)
        }
    }

    private static func isDelimiter(_ s: String) -> Bool {
        s == "\"\"\"" || s == "'''"
    }

    private static func isSection(_ s: String) -> Bool {
        let v = s.lowercased()
            .replacingOccurrences(of: "【", with: "[").replacingOccurrences(of: "】", with: "]")
        return ["[转盘]", "[扇区]", "[[wheel]]", "[[slice]]", "[wheel]", "[slice]",
                "[[profile]]", "[action]"].contains(v)
    }

    /// 返回 (键, 分隔符, 值) 三个 NSRange（均相对整个文本）
    private static func splitKeyValue(_ line: String, body: NSRange)
        -> (NSRange, NSRange, NSRange)? {
        let ns = line as NSString
        var sep = NSRange(location: NSNotFound, length: 0)
        for mark in ["=", "：", ":"] {
            let r = ns.range(of: mark)
            if r.location != NSNotFound, sep.location == NSNotFound || r.location < sep.location {
                sep = r
            }
        }
        guard sep.location != NSNotFound else { return nil }
        let key = NSRange(location: body.location, length: sep.location)
        let separator = NSRange(location: body.location + sep.location, length: sep.length)
        let valueStart = sep.location + sep.length
        let value = NSRange(location: body.location + valueStart,
                            length: max(0, body.length - valueStart))
        return (key, separator, value)
    }

    private static let enumWords: Set<String> = [
        "是", "否", "函数", "调用函数", "代码", "自定义代码", "逐文件", "整批", "一次",
        "无", "不写出", "打印", "自定义", ".rds", ".csv", ".rdata", ".dta",
        "r", "python", "py", "stata", "true", "false", "none", "null", "na",
    ]

    private static func colorizeValue(_ storage: NSTextStorage, range: NSRange,
                                      line: String, theme: Theme) {
        guard range.length > 0 else { return }
        // 基础样式已在 apply() 中统一设为 plain，这里只叠加需要高亮的部分
        let valueText = (storage.string as NSString).substring(with: range)
        let trimmed = valueText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return }

        // 颜色值 #RRGGBB：直接把该段显示为它本身的颜色（做亮度保护）
        colorMatches("#[0-9A-Fa-f]{6}\\b", in: valueText, storage: storage,
                     base: range, color: nil, dynamicColor: true, theme: theme)

        // 枚举值 / 数字
        if enumWords.contains(trimmed.lowercased()) {
            paint(storage, range, color: theme.enumValue, font: monoSemibold)
            return
        }
        if trimmed.count <= 2, Int(trimmed) != nil {
            paint(storage, range, color: theme.number, font: monoBold)
            return
        }
        if trimmed.contains("::") || trimmed.contains("(") || trimmed.contains("/")
            || trimmed.hasPrefix("\"") || trimmed.contains("\\n") {
            paint(storage, range, color: theme.value)
        }
    }

    private static func colorMatches(_ pattern: String, in text: String,
                                     storage: NSTextStorage, base: NSRange,
                                     color: NSColor?, dynamicColor: Bool,
                                     theme: Theme, font: NSFont? = nil) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let r = NSRange(location: base.location + m.range.location, length: m.range.length)
            var c = color ?? theme.number
            if dynamicColor {
                let hex = ns.substring(with: m.range)
                c = readableColor(hex, theme: theme)
            }
            paint(storage, r, color: c, font: font ?? monoBold)
        }
    }

    private static func readableColor(_ hex: String, theme: Theme) -> NSColor {
        var v = hex.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("#") { v = String(v.dropFirst()) }
        guard v.count == 6, let n = UInt32(v, radix: 16) else { return theme.number }
        var r = CGFloat((n >> 16) & 0xFF) / 255
        var g = CGFloat((n >> 8) & 0xFF) / 255
        var b = CGFloat(n & 0xFF) / 255
        // 太亮或太暗时在浅色/深色背景下都拉回可读区间
        let bright = 0.299 * r + 0.587 * g + 0.114 * b
        let target: CGFloat = theme.id == 0 ? 0.42 : 0.72
        let k = bright < 0.001 ? 1 : target / bright
        if abs(k - 1) > 0.12 {
            r = min(1, r * k); g = min(1, g * k); b = min(1, b * k)
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static let codeKeywords =
        "(?<!\\w)(function|if|else|for|foreach|while|return|library|require|source|" +
        "TRUE|FALSE|NULL|NA|" +
        "def|import|from|in|not|and|or|True|False|None|print|result|convert|" +
        "readRDS|saveRDS|read\\.csv|write\\.csv|pd|pandas|c|list|as\\.data\\.frame|" +
        "use|save|append|merge|gen|egen|replace|summarize|sum|regress|reg|display|di|" +
        "import|export|insheet|outsheet|local|global|quietly|capture|noisily|" +
        "by|bysort|keep|drop|rename|collapse|reshape|tabulate|tab|graph|twoway|" +
        "log|clear|set|cd|describe|desc|list|count|collect|return|ereturn|" +
        "program|end|args|syntax|preserve|restore|tempfile|tempvar|file|" +
        "vce|robust|if|in|using)(?!\\w)"

    private static func colorizeCodeLine(_ storage: NSTextStorage, body: NSRange,
                                         line: String, theme: Theme) {
        paint(storage, body, color: theme.code, background: theme.codeBackground)
        let ns = line as NSString

        // 字符串优先记录覆盖范围，避免其中的字符再被关键字/数字着色
        var covered = Set<Int>()
        if let re = try? NSRegularExpression(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'", options: []) {
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let r = NSRange(location: body.location + m.range.location, length: m.range.length)
                paint(storage, r, color: theme.string)
                for i in m.range.location..<NSMaxRange(m.range) { covered.insert(i) }
            }
        }

        func paintMatches(_ pattern: String, _ color: NSColor, _ font: NSFont? = nil,
                          ignoreCovered: Bool = false) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let positions = m.range.location..<NSMaxRange(m.range)
                // 一般匹配要避开字符串内部，避免把 "result" 里的字符当成关键字；
                // 但 Stata 复合引号 `"…"' 内的宏仍会展开，属于变量引用，需要单独着色。
                if !ignoreCovered && positions.contains(where: { covered.contains($0) }) { continue }
                paint(storage, NSRange(location: body.location + m.range.location,
                                       length: m.range.length), color: color, font: font)
            }
        }

        paintMatches("\\b\\d+(\\.\\d+)?\\b", theme.number)
        paintMatches(codeKeywords, theme.keyword, monoSemibold)
        paintMatches("\\.(file|filename|dir|filebasename|files|result|out)\\b", theme.key, monoSemibold)
        paintMatches("\\b(FILE|FILENAME|DIR|FILEBASENAME|FILES|OUT|glazer)\\b", theme.key, monoSemibold)
        // Stata 局部宏 `name' / 全局宏 $name：复合引号内同样会展开，故忽略字符串覆盖
        paintMatches("`[A-Za-z_][A-Za-z0-9_]*'", theme.key, monoSemibold, ignoreCovered: true)
        paintMatches("\\$[A-Za-z_][A-Za-z0-9_]*", theme.key, monoSemibold, ignoreCovered: true)

        // 注释最后覆盖：R/Python 的 #、Stata/Python 的 //、Stata 行首的 *
        // 字符串内部的 # 不再误判（covered 来自字符串匹配）
        var commentStart: Int? = nil
        for mark in ["#", "//", "/*"] {
            var search = 0
            while true {
                let r = ns.range(of: mark, options: .literal,
                                 range: NSRange(location: search, length: ns.length - search))
                guard r.location != NSNotFound else { break }
                if !covered.contains(r.location) { commentStart = r.location; break }
                search = NSMaxRange(r)
                if search >= ns.length { break }
            }
            if commentStart != nil { break }
        }
        if trimmedLeadingAsterisk(line) { commentStart = 0 }
        if let start = commentStart {
            let comment = NSRange(location: body.location + start,
                                  length: body.length - start)
            paint(storage, comment, color: theme.comment, font: monoItalic,
                  background: theme.codeBackground)
        }
    }

    /// Stata 行首 `*` 是整行注释
    private static func trimmedLeadingAsterisk(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("*")
    }
}
