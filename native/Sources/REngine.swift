// GlazeR — 通用进程执行层：R / Python / Stata 共用超时、取消、阶段事件与结果解析
import Foundation

struct GZError: Error {
    let message: String
    /// 完整执行日志：失败时交给通知卡片与「运行日志」页展开查看。
    /// 早期版本失败只回传一句摘要，Stata 批处理的 job.log 全部丢失。
    let log: String
    static func msg(_ m: String) -> GZError { GZError(message: m, log: "") }
    static func withLog(_ m: String, log: String) -> GZError { GZError(message: m, log: log) }
}

struct RunResult {
    let ok: Bool
    let message: String
    let output: String
    let elapsed: Double
    let summary: String
    let log: String
    let warnings: String
}

struct REnvReport {
    let rscript: String
    let version: String
    let libPaths: [String]
    let packages: [String: Bool]
    let missing: [String]
}

struct JobItem: Identifiable, Equatable {
    var id = UUID()
    let file: String
    let action: String
    var status: Status = .working
    var detail: String = "准备中…"
    var output: String?
    var log: String?
    var warnings: String?
    var stage: String = "准备中…"
    var startedAt: Date = Date()

    enum Status: Equatable { case working, done, failed, cancelled }
    static func == (l: JobItem, r: JobItem) -> Bool { l.id == r.id }
}

final class REngine {

    // MARK: 路径探测

    /// 返回 (可执行文件, 是否需要通过 /usr/bin/env 调用 Rscript)
    static func detectRscript(override: String = "") -> (String, Bool) {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return (trimmed, false)
        }
        let candidates = [
            "/usr/local/bin/Rscript",
            "/opt/homebrew/bin/Rscript",
            "/Library/Frameworks/R.framework/Resources/bin/Rscript",
            "/usr/bin/Rscript",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return (c, false) }
        return ("/usr/bin/env", true)
    }

    static func runnerPath() -> String? {
        if let p = Bundle.main.resourceURL?.appendingPathComponent("engine/runner.R").path,
           FileManager.default.fileExists(atPath: p) { return p }
        let candidates = [
            "/Users/ac/Documents/GitHub/GlazeR/engine/runner.R",
            FileManager.default.currentDirectoryPath + "/engine/runner.R",
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) { return c }
        return nil
    }

    private static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extras = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extras + ":" + (env["PATH"] ?? "")
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["R_DEFAULT_PACKAGES"] = env["R_DEFAULT_PACKAGES"] ?? "datasets,utils,grDevices,graphics,stats,methods"
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        return env
    }

    // MARK: R 字符串字面量转义

    static func rString(_ s: String) -> String {
        var o = "\""
        for ch in s {
            switch ch {
            case "\\": o += "\\\\"
            case "\"": o += "\\\""
            case "\n": o += "\\n"
            case "\r": o += "\\r"
            case "\t": o += "\\t"
            default: o.append(ch)
            }
        }
        return o + "\""
    }

    static func rVector(_ xs: [String]) -> String {
        "c(" + xs.map { rString($0) }.joined(separator: ", ") + ")"
    }

    // MARK: 生成 job.R

    static func makeJob(slice: SliceConfig, files: [String], config: GlazeConfig,
                        outDir: String?) -> String {
        let ps = slice.params.filter { $0.enabled && !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        let keys = ps.map { $0.key.trimmingCharacters(in: .whitespaces) }
        let exprs = ps.map { $0.value }
        let first = files.first ?? ""
        let name = (first as NSString).lastPathComponent
        let rawStem = (name as NSString).deletingPathExtension
        let stem = rawStem.isEmpty ? "glazer_out" : rawStem
        let sourceDir = (first as NSString).deletingLastPathComponent
        let dir = outDir ?? sourceDir
        let workdir = config.workingDir.trimmingCharacters(in: .whitespaces).isEmpty
            ? sourceDir : config.workingDir

        let lines: [String] = [
            "# GlazeR generated job — 由应用自动生成，请勿手动修改",
            ".gz_mode <- \(rString(slice.mode.rawValue))",
            ".gz_function <- \(rString(slice.function))",
            ".gz_source <- \(rString(slice.sourceFile))",
            ".gz_code <- \(rString(slice.code))",
            ".gz_file_arg <- \(rString(slice.fileArg))",
            ".gz_files <- \(rVector(files))",
            ".gz_param_keys <- \(rVector(keys))",
            ".gz_param_exprs <- \(rVector(exprs))",
            ".gz_output_mode <- \(rString(slice.output.rawValue))",
            ".gz_output_dir <- \(rString(dir))",
            ".gz_output_suffix <- \(rString(slice.outputSuffix))",
            ".gz_output_code <- \(rString(slice.outputCode))",
            ".gz_out_base <- \(rString(stem))",
            ".gz_workdir <- \(rString(workdir))",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: 通用进程调用

    /// 通用进程调用：R / Python / Stata 共用同一套超时、取消、阶段事件与结果解析逻辑
    static func launch(_ arguments: [String], config: GlazeConfig,
                       runner overrideRunner: String? = nil,
                       executable overrideExe: (String, Bool)? = nil,
                       envProgram: String = "Rscript",
                       engineLabel: String = "Rscript",
                       timeout: TimeInterval? = nil,
                       workingDirectory: String? = nil,
                       resultFile: String? = nil,
                       logFile: String? = nil,
                       onStage: ((String) -> Void)? = nil,
                       onProcess: ((Process) -> Void)? = nil,
                       onDone: @escaping (Result<[String: Any], GZError>) -> Void) {
        guard let runner = overrideRunner ?? runnerPath() else {
            onDone(.failure(.msg("找不到执行引擎脚本（请重新构建应用）"))); return
        }
        let (exe, viaEnv) = overrideExe ?? detectRscript(override: config.rscriptPath)
        let args = (viaEnv ? [envProgram] : []) + arguments.map { $0 == "@RUNNER@" ? runner : $0 }
        let limit = timeout ?? max(10, config.runTimeoutSeconds)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        var env = processEnvironment()
        // Rscript 默认会执行 ~/.Rprofile（与 RStudio 交互会话共用）。该文件常包含
        // 字体加载 / 绘图主题 / source 自定义脚本，在 GUI 后台进程里既拖慢启动，
        // 又会因 macOS「文稿」目录 TCC 授权缺失而报错并污染 --check 的 JSON。
        // R_PROFILE_USER=/dev/null 只跳过用户级 profile，保留 .Renviron 与 site profile。
        if engineLabel == "Rscript", config.skipUserRProfile {
            env["R_PROFILE_USER"] = "/dev/null"
        }
        proc.environment = env
        if let workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var stdoutLines: [String] = []
        var stderrText = ""
        var outBuffer = Data()
        var didTimeout = false
        let lock = NSLock()

        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty { return }
            lock.lock()
            outBuffer.append(chunk)
            while let nl = outBuffer.firstIndex(of: 0x0A) {
                let line = Data(outBuffer[outBuffer.startIndex..<nl])
                outBuffer.removeSubrange(outBuffer.startIndex...nl)
                if let s = String(data: line, encoding: .utf8) {
                    stdoutLines.append(s)
                    // 阶段事件实时上报（不等待进程结束），长任务不会看起来「卡死」
                    if let d = s.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       obj["event"] as? String == "stage",
                       let msg = obj["message"] as? String, let onStage {
                        DispatchQueue.main.async { onStage(msg) }
                    }
                }
            }
            lock.unlock()
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            if let s = String(data: d, encoding: .utf8) {
                lock.lock(); stderrText += s; lock.unlock()
            }
        }

        // 超时保护：R 脚本长时间不返回时终止，避免任务卡片永远转圈
        let timer = DispatchWorkItem {
            lock.lock(); didTimeout = true; lock.unlock()
            if proc.isRunning { proc.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: timer)

        do {
            try proc.run()
        } catch {
            timer.cancel()
            onDone(.failure(.msg("无法启动 \(engineLabel)（\(exe)）：\(error.localizedDescription)")))
            return
        }
        DispatchQueue.main.async { onProcess?(proc) }

        proc.terminationHandler = { _ in
            timer.cancel()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            let tail = String(data: outBuffer, encoding: .utf8) ?? ""
            if !tail.isEmpty { stdoutLines.append(tail) }
            let lines = stdoutLines
            let errText = stderrText
            let timedOut = didTimeout
            lock.unlock()

            if timedOut {
                DispatchQueue.main.async {
                    onDone(.failure(.msg("任务超过 \(Int(limit)) 秒未返回，已自动终止。可在「设置 → 任务超时」调整，或检查脚本里是否有交互式等待 / 常驻服务（如 servr::httd()）。")))
                }
                return
            }

            // 结果文件优先（Stata 批处理只写日志文件，stdout 为空）
            var result: [String: Any]? = Self.parseResultFile(resultFile, logFile: logFile)
            if result == nil {
                for line in lines.reversed() {
                    guard let d = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          obj["ok"] != nil else { continue }
                    result = obj; break
                }
            }
            DispatchQueue.main.async {
                guard let r = result else {
                    var detail = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Stata 批处理不写 stdout / stderr，错误全在工作目录的 .log 里；
                    // 结果文件缺失时既给摘要，也把完整日志交给 UI 展开查看。
                    var fullLog = ""
                    if let logFile,
                       let log = try? String(contentsOfFile: logFile, encoding: .utf8) {
                        fullLog = log.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if detail.isEmpty, !fullLog.isEmpty { detail = String(fullLog.suffix(1200)) }
                    let msg = detail.isEmpty
                        ? "\(engineLabel) 未返回结果，可能启动失败或运行超时"
                        : String(detail.suffix(1200))
                    onDone(.failure(.withLog(msg, log: fullLog)))
                    return
                }
                onDone(.success(r))
            }
        }
    }

    /// 读取 `key=value` 形式的结果文件（Stata 用），并把批处理日志塞进 log 字段
    private static func parseResultFile(_ path: String?, logFile: String?) -> [String: Any]? {
        guard let path,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var obj: [String: Any] = [:]
        for raw in text.components(separatedBy: .newlines) {
            guard let eq = raw.firstIndex(of: "=") else { continue }
            let key = String(raw[..<eq]).trimmingCharacters(in: .whitespaces)
            let val = String(raw[raw.index(after: eq)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            // 只把约定的布尔 / 数值字段转成对应类型，其余一律保留字符串。
            // 早期版本把所有纯数字字符串都转成 Double，会把 version=19.5
            // 变成数字，Swift 侧 `as? String` 取不到值。
            switch key {
            case "ok":
                obj[key] = (val == "true")
            case "rc":
                obj[key] = Double(val) ?? 0
            default:
                obj[key] = val
            }
        }
        guard !obj.isEmpty else { return nil }
        if let logFile, let log = try? String(contentsOfFile: logFile, encoding: .utf8) {
            let r = log.range(of: ". do ", options: .literal)
            let body = r.map { String(log[$0.lowerBound...]) } ?? log
            obj["log"] = String(body.suffix(12000))
        }
        return obj
    }

    // MARK: 环境检测

    /// packages 从所有扇区的 pkg::fun 与自定义代码中提取，检测是否已安装
    static func check(packages: [String], config: GlazeConfig,
                      onDone: @escaping (Result<REnvReport, GZError>) -> Void) {
        launch(["@RUNNER@", "--check", packages.joined(separator: ",")], config: config, timeout: 60) { res in
            switch res {
            case .failure(let e): onDone(.failure(e))
            case .success(let r):
                let (exe, _) = detectRscript(override: config.rscriptPath)
                onDone(.success(REnvReport(
                    rscript: r["rscript"] as? String ?? exe,
                    version: r["version"] as? String ?? "",
                    libPaths: r["libpaths"] as? [String] ?? [],
                    packages: r["packages"] as? [String: Bool] ?? [:],
                    missing: r["missing"] as? [String] ?? [])))
            }
        }
    }

    // MARK: 执行扇区动作

    static func run(slice: SliceConfig, files: [String], config: GlazeConfig,
                    outDir: String?,
                    onStage: ((String) -> Void)? = nil,
                    onProcess: ((Process) -> Void)? = nil,
                    onDone: @escaping (Result<RunResult, GZError>) -> Void) {
        guard !files.isEmpty else { onDone(.failure(.msg("没有输入文件"))); return }
        if slice.engine == .python {
            PythonEngine.run(slice: slice, files: files, config: config, outDir: outDir,
                             onStage: onStage, onProcess: onProcess, onDone: onDone)
            return
        }
        if slice.engine == .stata {
            StataEngine.run(slice: slice, files: files, config: config, outDir: outDir,
                            onStage: onStage, onProcess: onProcess, onDone: onDone)
            return
        }
        guard slice.isConfigured else {
            onDone(.failure(.msg("扇区「\(slice.label)」尚未配置 R 函数或代码"))); return
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlazeR-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            onDone(.failure(.msg("无法创建临时目录：\(error.localizedDescription)"))); return
        }
        let job = tmp.appendingPathComponent("job.R")
        do {
            try makeJob(slice: slice, files: files, config: config, outDir: outDir)
                .write(to: job, atomically: true, encoding: .utf8)
        } catch {
            onDone(.failure(.msg("无法写入任务脚本：\(error.localizedDescription)"))); return
        }

        appendGlazeLog("run start · \(slice.label) · \(files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))")
        launch(["@RUNNER@", job.path], config: config,
               onStage: onStage, onProcess: onProcess) { res in
            defer { try? FileManager.default.removeItem(at: tmp) }
            switch res {
            case .failure(let e):
                appendGlazeLog("run failed · \(slice.label) · \(e.message)")
                onDone(.failure(e))
            case .success(let r):
                let result = RunResult(
                    ok: r["ok"] as? Bool ?? false,
                    message: r["message"] as? String ?? "",
                    output: r["output"] as? String ?? "",
                    elapsed: r["elapsed"] as? Double ?? 0,
                    summary: r["summary"] as? String ?? "",
                    log: r["log"] as? String ?? "",
                    warnings: r["warnings"] as? String ?? "")
                appendGlazeLog("run end · \(slice.label) · ok=\(result.ok) · \(result.message)")
                if result.ok { onDone(.success(result)) }
                else { onDone(.failure(.msg(result.message.isEmpty ? "R 执行失败" : result.message))) }
            }
        }
    }

    /// 收集配置里引用的 R 包（pkg::fun、library(pkg)、require(pkg)）
    static func referencedPackages(_ config: GlazeConfig) -> [String] {
        var found = Set<String>()
        let pattern = try? NSRegularExpression(pattern: "([A-Za-z][A-Za-z0-9._]*)\\s*::", options: [])
        for p in config.profiles {
            for s in p.slices where s.engine == .r {
                let texts = [s.function, s.code, s.outputCode, s.sourceFile]
                    + s.params.filter { $0.enabled }.map { $0.value }
                for t in texts {
                    guard let pattern = pattern else { continue }
                    let matches = pattern.matches(in: t, range: NSRange(t.startIndex..., in: t))
                    for m in matches where m.numberOfRanges > 1 {
                        if let r = Range(m.range(at: 1), in: t) { found.insert(String(t[r])) }
                    }
                }
            }
        }
        return found.sorted()
    }
}
