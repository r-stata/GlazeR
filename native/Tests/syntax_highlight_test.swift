// 独立校验：.glazer 语法高亮对 """ 三引号代码块的识别（不参与 App 构建）
// 编译：swiftc -swift-version 5 -disable-sandbox -parse-as-library \
//   native/Sources/GlazerSyntaxHighlighter.swift native/Tests/syntax_highlight_test.swift \
//   -o build/tmp/syntax_highlight_test
import AppKit

@main
struct SyntaxHighlightTest {
    static var passed = 0, failed = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { passed += 1; print("PASS · \(name)") }
        else { failed += 1; print("FAIL · \(name)") }
    }

    static func main() {
        // 构造一份典型导出片段：起始行 `自定义代码 = """`、块内混入
        // 看起来像注释 / 段落 / 键值对的内容、结束行、块后恢复普通字段。
        let lines = [
            "# 头部注释",                       // 0 配置层注释（无背景）
            "【转盘】",                          // 1 段落
            "名称 = 测试",                       // 2 键值
            "【扇区】",                          // 3 段落
            "标签 = 三引号块",                    // 4 键值
            "引擎 = Stata",                      // 5 键值
            "自定义代码 = \"\"\"",                // 6 三引号起始
            "use `\"`file'\"', clear",          // 7 块内 Stata 代码
            "# 这一行在块内，是代码不是配置注释",   // 8 块内 # 注释
            "【扇区】",                          // 9 块内伪段落
            "批量 = 整批",                       // 10 块内伪键值
            "result = {\"x\": 1}  # 行尾注释",    // 11 块内 Python 代码
            "\"\"\"",                           // 12 三引号结束
            "批量 = 整批",                       // 13 块后键值
            "输出 = 打印",                       // 14 块后枚举值
            "参数.limit = 100L",                 // 15 块后参数行
        ]
        let text = lines.joined(separator: "\n")
        let ns = text as NSString
        let theme = GlazerSyntax.light
        let storage = NSTextStorage(string: text)
        GlazerSyntax.apply(storage, theme: theme, enabled: true)

        // 第 lineIndex 行第 offset 个字符的显示属性
        func attrs(_ lineIndex: Int, _ offset: Int = 0) -> [NSAttributedString.Key: Any] {
            var loc = 0
            for _ in 0..<lineIndex {
                loc = NSMaxRange(ns.lineRange(for: NSRange(location: loc, length: 0)))
            }
            return storage.attributes(at: min(loc + offset, ns.length - 1), effectiveRange: nil)
        }
        func color(_ i: Int, _ off: Int = 0) -> NSColor? { attrs(i, off)[.foregroundColor] as? NSColor }
        func bg(_ i: Int, _ off: Int = 0) -> NSColor? { attrs(i, off)[.backgroundColor] as? NSColor }
        func same(_ c: NSColor?, _ t: NSColor) -> Bool { c?.isEqual(t) ?? false }

        // 起始行：`自定义代码 = """` 的值部分应是段落色粗体，且从这里进入代码块
        check("起始行仍按键值对解析（键名为蓝色）", same(color(6), theme.key))
        check("起始行三引号被标记为段落色",
              same(storage.attribute(.foregroundColor, at: ns.range(of: "\"\"\"").location,
                                    effectiveRange: nil) as? NSColor, theme.section))

        // 块内：全部走代码着色路径（带代码块背景），绝不能被当成配置层解析。
        // 注意行首若是关键字会被涂成 keyword 色，故用背景 + 非关键字位置判断。
        check("块内 Stata 行有代码块背景", same(bg(7), theme.codeBackground))
        check("块内 Stata 关键字被着色", same(color(7), theme.keyword))
        check("块内 Stata 局部宏（复合引号内）仍被着色为变量色", same(color(7, 6), theme.key))
        check("块内普通代码字符是代码色", same(color(10), theme.code))
        check("块内 # 行有代码块背景（区别于配置层注释）", same(bg(8), theme.codeBackground))
        check("块内【扇区】不被判为段落标记", !same(color(9), theme.section) && same(bg(9), theme.codeBackground))
        check("块内伪键值对行首不被判为键名", same(color(10), theme.code))
        check("块内 Python 行有代码块背景", same(bg(11), theme.codeBackground))
        check("配置层注释没有代码块背景", !same(bg(0), theme.codeBackground))

        // 结束行：独占一行的 """ 退出代码块
        check("结束行恢复段落色", same(color(12), theme.section))
        check("块后代码不再有代码块背景", !same(bg(13), theme.codeBackground))

        // 块后：恢复正常字段解析（枚举色要看 = 之后的值，不是行首键名）
        check("块后键名恢复蓝色", same(color(13), theme.key))
        check("块后枚举值恢复枚举色", same(color(14, 4), theme.enumValue))
        check("块后参数行键名恢复蓝色", same(color(15), theme.key))

        // 关闭高亮时不应残留任何着色
        let off = NSTextStorage(string: text)
        GlazerSyntax.apply(off, theme: theme, enabled: false)
        check("关闭高亮后统一为普通文本色",
              same(off.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, theme.plain))

        // 深色主题同样生效（取块内非关键字字符）
        let darkStorage = NSTextStorage(string: text)
        GlazerSyntax.apply(darkStorage, theme: GlazerSyntax.dark, enabled: true)
        var line10 = 0
        for _ in 0..<10 { line10 = NSMaxRange(ns.lineRange(for: NSRange(location: line10, length: 0))) }
        let darkCode = darkStorage.attribute(.foregroundColor, at: line10,
                                             effectiveRange: nil) as? NSColor
        check("深色主题块内文字为浅色", same(darkCode, GlazerSyntax.dark.code))
        check("深色主题块内背景为深色",
              same(darkStorage.attribute(.backgroundColor, at: line10,
                                         effectiveRange: nil) as? NSColor,
                   GlazerSyntax.dark.codeBackground))

        // 单独成行的三引号（手工编辑写法）也能进入 / 退出代码块
        let manual = ["自定义代码 =", "\"\"\"", "x <- 1", "# 块内", "\"\"\"", "输出 = 打印"]
            .joined(separator: "\n")
        let ms = NSTextStorage(string: manual)
        GlazerSyntax.apply(ms, theme: theme, enabled: true)
        let mns = manual as NSString
        let midLoc = mns.range(of: "# 块内").location
        let midBg = ms.attribute(.backgroundColor, at: midLoc, effectiveRange: nil) as? NSColor
        check("独立三引号：块内行有代码块背景", same(midBg, theme.codeBackground))
        let tailLoc = mns.range(of: "输出 = 打印").location
        let tailColor = ms.attribute(.foregroundColor, at: tailLoc, effectiveRange: nil) as? NSColor
        check("独立三引号：结束后恢复键名解析", same(tailColor, theme.key))

        // 单行三引号："""code""" 不误开代码块
        let single = "自定义代码 = \"\"\"x <- 1\"\"\"\n输出 = 打印"
        let ss = NSTextStorage(string: single)
        GlazerSyntax.apply(ss, theme: theme, enabled: true)
        let sns = single as NSString
        let tail2 = sns.range(of: "输出 = 打印").location
        check("单行三引号不会让后续行陷入代码块",
              same(ss.attribute(.foregroundColor, at: tail2, effectiveRange: nil) as? NSColor,
                   theme.key))

        print("\n==== \(passed) passed, \(failed) failed ====")
        exit(failed == 0 ? 0 : 1)
    }
}
