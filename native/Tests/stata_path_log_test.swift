// 独立验证：Stata 路径宏语义（`out' 是文件 / `outdir' 是目录）+ 失败日志完整回传
// 编译：swiftc -swift-version 5 -disable-sandbox -parse-as-library \
//   native/Sources/Models.swift native/Sources/REngine.swift \
//   native/Sources/PythonEngine.swift native/Sources/StataEngine.swift \
//   native/Tests/stata_path_log_test.swift -o build/tmp/stata_path_log_test
//
// 与 stata_engine_test 一样：REngine.launch 回调派发到主队列，命令行测试必须
// 用 dispatchMain() 驱动，不能用 sem.wait() 阻塞主线程。
import Foundation

@main
struct StataPathLogTest {

    static func note(_ s: String) {
        FileHandle.standardError.write(Data(("\(s)\n").utf8))
    }

    static var failed = 0

    static func check(_ name: String, _ ok: Bool) {
        note("\(ok ? "✓" : "✗") \(name)")
        if !ok { failed += 1 }
    }

    static let dta = "/Volumes/ADT/中转文件夹/1949～2025 年工商企业注册信息数据（版本4）/国民经济行业分类和代码(GB_T4754_2017).dta"
    static let outDir = "/Users/ac/Documents/GitHub/GlazeR/build/tmp/stata_verify"

    static func main() {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: dta) else {
            note("SKIP · 测试用 .dta 不存在"); exit(2)
        }
        let cfg = GlazeConfig()
        cfg.stataPath = ""
        scenarioA(cfg)
        dispatchMain()
    }

    static func makeSlice(_ label: String, _ code: String) -> SliceConfig {
        SliceConfig(label: label, detail: "", engine: .stata, mode: .expr,
                    function: "", code: code, fileArg: "", params: [],
                    batch: .each, output: .print, outputSuffix: "_glazed",
                    outputCode: "", color: "4F46E5")
    }

    // A. 用户原写法：把 `out' 当目录拼接 → r(603)，但必须回传完整日志与错误摘要
    static func scenarioA(_ cfg: GlazeConfig) {
        let code = #"""
use `"`file'"', clear
export delimited using `"`out'/`filebasename'.csv"', replace
"""#
        StataEngine.run(slice: makeSlice("原写法", code), files: [dta],
                        config: cfg, outDir: outDir) { res in
            switch res {
            case .failure(let e):
                check("A 失败信息含 Stata 具体报错", e.message.contains("r(603)")
                      || e.message.contains("invalid file specification"))
                check("A 回传完整 job.log", e.log.contains("export delimited") && e.log.count > 1000)
                check("A 日志含 do 文件执行过程", e.log.contains(". do "))
                check("A 日志含落盘诊断目录", e.log.contains("完整诊断文件"))
                note("  A message = \(e.message)")
                note("  A log 长度 = \(e.log.count)")
            case .success:
                check("A 应当失败", false)
            }
            scenarioB(cfg)
        }
    }

    // B. 正确写法一：用 `outdir' 拼自己的文件名
    static func scenarioB(_ cfg: GlazeConfig) {
        let code = #"""
use `"`file'"', clear
export delimited using `"`outdir'/`filebasename'.csv"', replace
"""#
        StataEngine.run(slice: makeSlice("outdir 写法", code), files: [dta],
                        config: cfg, outDir: outDir) { res in
            switch res {
            case .success(let r):
                let target = outDir + "/国民经济行业分类和代码(GB_T4754_2017).csv"
                check("B 用 `outdir' 成功写出 CSV", FileManager.default.fileExists(atPath: target))
                check("B job.log 含 outdir 宏", r.log.contains("local outdir"))
                check("B 成功也回传完整日志", r.log.count > 1000)
                note("  B output = \(r.output)")
            case .failure(let e):
                check("B 应当成功", false)
                note("  B err = \(e.message)")
            }
            scenarioC(cfg)
        }
    }

    // C. 正确写法二：直接写 `out'（完整路径），引擎应识别为输出并带 .csv 后缀
    static func scenarioC(_ cfg: GlazeConfig) {
        let code = #"""
use `"`file'"', clear
export delimited using `"`out'"', replace
"""#
        StataEngine.run(slice: makeSlice("out 写法", code), files: [dta],
                        config: cfg, outDir: outDir) { res in
            switch res {
            case .success(let r):
                check("C 直接写 `out' 成功且识别为输出", !r.output.isEmpty)
                check("C 输出文件真实存在", FileManager.default.fileExists(atPath: r.output))
                check("C 建议输出扩展名为 .csv", r.output.hasSuffix(".csv"))
                note("  C output = \(r.output)")
            case .failure(let e):
                check("C 应当成功", false)
                note("  C err = \(e.message)")
            }
            note("==== \(failed) failed ====")
            exit(failed == 0 ? 0 : 1)
        }
    }
}
