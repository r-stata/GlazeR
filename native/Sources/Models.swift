// GlazeR — 数据模型：转盘组、扇区动作、默认参数、全局配置、运行记录
// 配置持久化：~/Library/Application Support/GlazeR/config.json
import Foundation
import SwiftUI
import ApplicationServices

// MARK: - 主题

let brandColor = Color(hex: 0x4F46E5)
let brandSoft = Color(hex: 0xF1F0FE)
let brandBorder = Color(hex: 0xDCD9F7)
let inkColor = Color(hex: 0x1F2430)
let subInkColor = Color(hex: 0x5A6472)
let hintColor = Color(hex: 0x8A8F9E)
let lineColor = Color(hex: 0xE6E9EE)
let canvasColor = Color(hex: 0xF6F6FA)

/// 12 色扇区调色板
let slicePalette: [String] = [
    "4F46E5", "2563EB", "0891B2", "0D9488", "16A34A", "65A30D",
    "F59E0B", "F97316", "DC2626", "DB2777", "8B5CF6", "64748B",
]

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// 支持 "RRGGBB" / "#RRGGBB" / "0xRRGGBB"，非法值回退品牌色
    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self.init(hex: 0x4F46E5); return
        }
        self.init(hex: UInt32(v))
    }
}

// MARK: - 修饰键

enum ModKey: String, CaseIterable, Codable {
    case command, control, option, shift, capslock

    var label: String {
        switch self {
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .shift: return "⇧ Shift"
        case .capslock: return "⇪ Caps"
        }
    }

    var shortLabel: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .capslock: return "⇪"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .capslock: return .maskAlphaShift
        }
    }

    static func flags(_ keys: [String]) -> CGEventFlags {
        var f: CGEventFlags = []
        for k in keys { if let m = ModKey(rawValue: k) { f.insert(m.flag) } }
        return f
    }

    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate,
                                             .maskShift, .maskAlphaShift]

    static func comboLabel(_ keys: [String]) -> String {
        keys.compactMap { ModKey(rawValue: $0)?.shortLabel }.joined()
    }
}

// MARK: - 容错解码辅助

extension KeyedDecodingContainer {
    /// 字段缺失 / 类型不符时使用默认值，保证旧配置或手工编辑的 JSON 不会导致整个配置失效
    func dv<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return fallback
    }
}

// MARK: - 默认参数

struct ParamItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var key: String = ""            // 形参名
    var value: String = "TRUE"      // R / Python 表达式字符串，由对应引擎求值
    var enabled: Bool = true

    init() {}
    init(id: String = UUID().uuidString, key: String, value: String, enabled: Bool = true) {
        self.id = id; self.key = key; self.value = value; self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.dv(.id, UUID().uuidString)
        key = c.dv(.key, "")
        value = c.dv(.value, "TRUE")
        enabled = c.dv(.enabled, true)
    }
}

// MARK: - 扇区动作

enum SliceMode: String, Codable, CaseIterable {
    case call   // 调用函数
    case expr   // 执行自定义代码

    var title: String { self == .call ? "调用函数" : "自定义代码" }
}

/// 扇区使用的执行引擎：R → runner.R，Python → runner.py，Stata → runner.do
enum SliceEngine: String, Codable, CaseIterable, Identifiable {
    case r
    case python
    case stata

    var id: String { rawValue }
    var title: String {
        switch self {
        case .r:      return "R 函数 / 代码"
        case .python: return "Python 函数 / 代码"
        case .stata:  return "Stata 命令 / 代码"
        }
    }
    var shortTitle: String {
        switch self {
        case .r:      return "R"
        case .python: return "Python"
        case .stata:  return "Stata"
        }
    }
    /// 编辑器里显示的路径变量提示标题
    var variableTitle: String {
        switch self {
        case .r:      return "R 路径变量"
        case .python: return "Python 路径变量"
        case .stata:  return "Stata 路径宏"
        }
    }
}

enum BatchMode: String, Codable, CaseIterable {
    case each   // 每个文件单独执行一次
    case all    // 一次传入全部文件路径（字符向量）

    var title: String { self == .each ? "逐文件执行" : "整批一次执行" }
}

enum OutputMode: String, Codable, CaseIterable {
    case none, print, rds, csv, rdata, dta, custom

    var title: String {
        switch self {
        case .none: return "不写出（仅执行）"
        case .print: return "打印结果到日志"
        case .rds: return "保存为 .rds"
        case .csv: return "保存为 .csv"
        case .rdata: return "保存为 .RData"
        case .dta: return "保存为 .dta"
        case .custom: return "自定义写出代码"
        }
    }

    var ext: String {
        switch self {
        case .rds: return ".rds"
        case .csv: return ".csv"
        case .rdata: return ".RData"
        case .dta: return ".dta"
        default: return ""
        }
    }
}

struct SliceConfig: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var label: String = "新动作"
    var detail: String = ""             // 悬停时中心盘补充说明
    var engine: SliceEngine = .r        // R / Python / Stata
    var mode: SliceMode = .call
    var function: String = ""           // 函数名：readr::read_csv / pandas.read_csv / my_fun
    var sourceFile: String = ""         // 可选：先执行的用户脚本（.R / .py）
    var code: String = ""               // expr 模式的代码
    var fileArg: String = "file"        // 文件路径注入到哪个参数；留空 = 不注入
    var params: [ParamItem] = []
    var batch: BatchMode = .each
    var output: OutputMode = .none
    var outputSuffix: String = "_glazed"
    var outputCode: String = ""         // custom 写出模式：R 用 .result / .out / .file，Python 用 result / OUT / FILE
    var color: String = "4F46E5"
    var enabled: Bool = true

    var swiftColor: Color { Color(hexString: color) }

    /// 是否配置了可执行内容
    var isConfigured: Bool {
        mode == .call ? !function.trimmingCharacters(in: .whitespaces).isEmpty
                      : !code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func blank(index: Int) -> SliceConfig {
        SliceConfig(label: "动作 \(index + 1)", color: slicePalette[index % slicePalette.count])
    }

    init() {}
    init(id: String = UUID().uuidString, label: String, detail: String = "",
         engine: SliceEngine = .r, mode: SliceMode = .call,
         function: String = "", sourceFile: String = "",
         code: String = "", fileArg: String = "file", params: [ParamItem] = [],
         batch: BatchMode = .each, output: OutputMode = .none,
         outputSuffix: String = "_glazed", outputCode: String = "",
         color: String = "4F46E5", enabled: Bool = true) {
        self.id = id; self.label = label; self.detail = detail
        self.engine = engine; self.mode = mode
        self.function = function; self.sourceFile = sourceFile; self.code = code
        self.fileArg = fileArg; self.params = params; self.batch = batch
        self.output = output; self.outputSuffix = outputSuffix; self.outputCode = outputCode
        self.color = color; self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.dv(.id, UUID().uuidString)
        label = c.dv(.label, "新动作")
        detail = c.dv(.detail, "")
        engine = c.dv(.engine, SliceEngine.r)
        mode = c.dv(.mode, SliceMode.call)
        function = c.dv(.function, "")
        sourceFile = c.dv(.sourceFile, "")
        code = c.dv(.code, "")
        fileArg = c.dv(.fileArg, "file")
        params = c.dv(.params, [ParamItem]())
        batch = c.dv(.batch, BatchMode.each)
        output = c.dv(.output, OutputMode.none)
        outputSuffix = c.dv(.outputSuffix, "_glazed")
        outputCode = c.dv(.outputCode, "")
        color = c.dv(.color, "4F46E5")
        enabled = c.dv(.enabled, true)
    }
}

// MARK: - 转盘组（支持创建多套转盘，各自可绑定不同修饰键组合）

struct WheelProfile: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "我的转盘"
    var sliceCount: Int = 6             // 转盘扇区数量 2...12
    var slices: [SliceConfig] = []
    var hotkeyFlags: [String] = []      // 为空时沿用全局默认组合键
    var slot: Int? = nil                // 数字键槽位 0...9；按住全局组合键 + 数字直接呼出该转盘

    /// 保证 slices 长度与 sliceCount 一致
    mutating func normalize() {
        sliceCount = min(max(sliceCount, 2), 12)
        while slices.count < sliceCount { slices.append(.blank(index: slices.count)) }
        if slices.count > sliceCount { slices = Array(slices.prefix(sliceCount)) }
    }

    var normalized: WheelProfile { var p = self; p.normalize(); return p }

    /// 未单独配置组合键时返回空数组，由 HotkeyMonitor 回退到全局默认
    var comboFlags: [String] { hotkeyFlags }

    static func demo() -> WheelProfile {
        var p = WheelProfile(id: UUID().uuidString, name: "R 数据处理", sliceCount: 6, slices: [
            SliceConfig(label: "CSV→RDS", detail: "readr 读取 CSV", function: "readr::read_csv",
                        params: [ParamItem(key: "show_col_types", value: "FALSE")],
                        output: .rds, outputSuffix: "_data", color: slicePalette[0]),
            SliceConfig(label: "DTA→RDS", detail: "haven 读取 Stata", function: "haven::read_dta",
                        output: .rds, outputSuffix: "_data", color: slicePalette[1]),
            SliceConfig(label: "XLSX→RDS", detail: "readxl 读取 Excel", function: "readxl::read_excel",
                        fileArg: "path", output: .rds, outputSuffix: "_data", color: slicePalette[2]),
            SliceConfig(label: "RDS→CSV", detail: "读取 rds 并写出 csv", mode: .expr,
                        code: "readRDS(.file)", output: .csv, outputSuffix: "_glazed", color: slicePalette[3]),
            SliceConfig(label: "数据概览", detail: "summary 输出到日志", mode: .expr,
                        code: "summary(readr::read_csv(.file, show_col_types = FALSE))",
                        output: .print, color: slicePalette[4]),
            SliceConfig(label: "转 DTA", detail: "写出 Stata 数据", mode: .expr,
                        code: "readr::read_csv(.file, show_col_types = FALSE)",
                        output: .dta, outputSuffix: "_glazed", color: slicePalette[5]),
        ], hotkeyFlags: ["option"], slot: 1)
        p.normalize()
        return p
    }

    init() {}
    init(id: String = UUID().uuidString, name: String, sliceCount: Int = 6,
         slices: [SliceConfig] = [], hotkeyFlags: [String] = [], slot: Int? = nil) {
        self.id = id; self.name = name; self.sliceCount = sliceCount
        self.slices = slices; self.hotkeyFlags = hotkeyFlags; self.slot = slot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.dv(.id, UUID().uuidString)
        name = c.dv(.name, "我的转盘")
        sliceCount = c.dv(.sliceCount, 6)
        slices = c.dv(.slices, [SliceConfig]())
        hotkeyFlags = c.dv(.hotkeyFlags, [String]())
        if let v = try? c.decodeIfPresent(Int.self, forKey: .slot) { slot = v }
    }
}

// MARK: - 全局配置

final class GlazeConfig: Codable {
    var hotkeyFlags: [String] = ["option"]
    var enableHoldTrigger: Bool = true  // 选中文件后长按组合键呼出转盘
    var holdDelay: Double = 0.45        // 长按判定时间（秒）
    var rscriptPath: String = ""        // 留空自动探测
    var pythonPath: String = ""         // 留空自动探测（优先复用已装好 pandas 的环境）
    var stataPath: String = ""          // 留空自动探测（stata-mp / stata-se / stata）
    var skipUserRProfile: Bool = true   // 默认跳过 ~/.Rprofile（GUI 后台进程常无「文稿」目录授权）
    var workingDir: String = ""         // 留空 = 源文件所在目录
    var outputMode: String = "source"   // source | ask | custom
    var customOutDir: String = ""
    var launchAtLogin: Bool = false
    var profiles: [WheelProfile] = []
    var activeProfileId: String = ""
    var autoRevealOutput: Bool = false
    var logSuccess: Bool = true
    var runTimeoutSeconds: Double = 300   // 单个任务的超时（秒），超时自动终止并报错

    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlazeR", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var configURL: URL { dir.appendingPathComponent("config.json") }
    static var recentsURL: URL { dir.appendingPathComponent("recents.json") }
    static var logURL: URL { dir.appendingPathComponent("glazer.log") }

    static func load() -> GlazeConfig {
        if let d = try? Data(contentsOf: configURL),
           let c = try? JSONDecoder().decode(GlazeConfig.self, from: d), !c.profiles.isEmpty {
            return c.normalized()
        }
        let demo = WheelProfile.demo()
        let c = GlazeConfig()
        c.profiles = [demo]
        c.activeProfileId = demo.id
        c.save()
        return c
    }

    func normalized() -> GlazeConfig {
        profiles = profiles.map { $0.normalized }
        if profiles.isEmpty { profiles = [WheelProfile.demo().normalized] }

        // 数字键槽位 0...9：去重、丢弃越界值，未分配的按 1,2,…,9,0 自动补空位
        var used = Set<Int>()
        for i in profiles.indices {
            if let s = profiles[i].slot, (0...9).contains(s), !used.contains(s) {
                used.insert(s)
            } else {
                profiles[i].slot = nil
            }
        }
        let preferred = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
        for i in profiles.indices where profiles[i].slot == nil {
            if let free = preferred.first(where: { !used.contains($0) }) {
                profiles[i].slot = free
                used.insert(free)
            }
        }

        if !profiles.contains(where: { $0.id == activeProfileId }) { activeProfileId = profiles[0].id }
        return self
    }

    var activeProfile: WheelProfile {
        profiles.first { $0.id == activeProfileId } ?? profiles[0]
    }

    func updateProfile(_ p: WheelProfile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p.normalized }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let d = try? enc.encode(self) { try? d.write(to: Self.configURL, options: .atomic) }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyFlags = c.dv(.hotkeyFlags, ["option"])
        enableHoldTrigger = c.dv(.enableHoldTrigger, true)
        holdDelay = c.dv(.holdDelay, 0.45)
        rscriptPath = c.dv(.rscriptPath, "")
        pythonPath = c.dv(.pythonPath, "")
        stataPath = c.dv(.stataPath, "")
        skipUserRProfile = c.dv(.skipUserRProfile, true)
        workingDir = c.dv(.workingDir, "")
        outputMode = c.dv(.outputMode, "source")
        customOutDir = c.dv(.customOutDir, "")
        launchAtLogin = c.dv(.launchAtLogin, false)
        profiles = c.dv(.profiles, [WheelProfile]())
        activeProfileId = c.dv(.activeProfileId, "")
        autoRevealOutput = c.dv(.autoRevealOutput, false)
        logSuccess = c.dv(.logSuccess, true)
        runTimeoutSeconds = c.dv(.runTimeoutSeconds, 300.0)
    }
}

// MARK: - 运行记录

struct RunRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Date
    var input: String
    var action: String
    var profile: String
    var output: String
    var ok: Bool
    var message: String
    var elapsed: Double
    var log: String
}

func appendGlazeLog(_ line: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let text = "[\(ts)] \(line)\n"
    guard let d = text.data(using: .utf8) else { return }
    if let fh = try? FileHandle(forWritingTo: GlazeConfig.logURL) {
        fh.seekToEndOfFile(); try? fh.write(contentsOf: d); try? fh.close()
    } else {
        try? d.write(to: GlazeConfig.logURL)
    }
}
