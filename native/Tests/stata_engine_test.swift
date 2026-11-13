// 独立验证：Stata 引擎环境检测 + 真实任务执行（不参与 App 构建）
// 编译：swiftc -swift-version 5 -disable-sandbox -parse-as-library \
//   native/Sources/Models.swift native/Sources/REngine.swift \
//   native/Sources/PythonEngine.swift native/Sources/StataEngine.swift \
//   native/Tests/stata_engine_test.swift -o build/tmp/stata_engine_test
//
// 注意：REngine.launch 的完成回调固定派发到 DispatchQueue.main（GUI 用），
// 命令行测试里绝不能用 sem.wait() 阻塞主线程，否则主队列排空不了 → 死锁。
// 这里改用 dispatchMain() 驱动主队列；输出写 stderr，避免管道缓冲在超时被杀时丢失。
import Foundation

@main
struct StataEngineTest {

    static func note(_ s: String) {
        FileHandle.standardError.write(Data(("\(s)\n").utf8))
    }

    static func main() {
        let cfg = GlazeConfig()
        cfg.stataPath = ""
        let (exe, viaEnv) = StataEngine.detectStata()
        note("Stata exe = \(exe) · viaEnv=\(viaEnv)")

        StataEngine.check(config: cfg) { res in
            switch res {
            case .success(let r): note("CHECK OK · Stata \(r.version) \(r.flavor) · \(r.stata)")
            case .failure(let e): note("CHECK FAILED · \(e.message)")
            }
            runSlice(cfg: cfg)
        }
        dispatchMain()
    }

    static func runSlice(cfg: GlazeConfig) {
        let csv = "/Users/ac/Documents/GitHub/GlazeR/testdata/sample.csv"
        let outDir = "/Users/ac/Documents/GitHub/GlazeR/build/tmp/stata_out"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let code = [
            "display \"文件：`file'\"",
            "display \"目录：`dir'\"",
            "import delimited using `\"`file'\"', clear",
            "summarize",
        ].joined(separator: "\n")
        let slice = SliceConfig(label: "Stata 回归", detail: "导入 CSV 并写出 DTA",
                                engine: .stata, mode: .expr, function: "",
                                code: code, fileArg: "", params: [],
                                batch: .each, output: .dta,
                                outputSuffix: "_glazed", outputCode: "", color: "4F46E5")

        StataEngine.run(slice: slice, files: [csv], config: cfg, outDir: outDir,
                        onStage: { note("STAGE · \($0)") }) { res in
            switch res {
            case .success(let r):
                note("RUN OK · message=\(r.message)")
                note("RUN OK · output=\(r.output)")
                note("RUN OK · exists=\(FileManager.default.fileExists(atPath: r.output))")
                note("RUN OK · logTail=\(String(r.log.suffix(500)))")
            case .failure(let e):
                note("RUN FAILED · \(e.message)")
            }
            exit(0)
        }
    }
}
