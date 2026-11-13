// GlazeR — Python 执行层：探测解释器、生成 job.py、复用 REngine.launch 调度 runner.py
import Foundation

struct PyEnvReport {
    let python: String
    let version: String
    let packages: [String: Bool]
    let missing: [String]
}

enum PythonEngine {

    // MARK: 路径探测

    /// 优先复用已装好 pandas 全家桶的环境（DataWheel 用户的 .venv 可直接用）
    static func detectPython(override: String = "") -> (String, Bool) {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return (trimmed, false)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            home + "/Documents/GitHub/GlazeR/.venv/bin/python",
            home + "/Documents/GitHub/DataWheel/.venv/bin/python",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            // GUI 派生的进程可能没有「文稿」目录的 TCC 授权，此时 venv 里的
            // python 能执行但读不到 pyvenv.cfg，会直接抛
            // `Fatal Python error: init_import_site ... PermissionError`。
            // 遇到不可读的 venv 就跳过，回退到系统 Python（依赖可能不全，
            // 但环境检测能正常返回并列出缺失包，用户可自行指定解释器）。
            guard isReadablePython(c) else { continue }
            return (c, false)
        }
        return ("/usr/bin/env", true)
    }

    /// venv 解释器必须能连同 `pyvenv.cfg` 一起读；TCC 拒绝时跳过该候选
    private static func isReadablePython(_ exe: String) -> Bool {
        guard exe.contains("/.venv/") else { return true }
        let binDir = (exe as NSString).deletingLastPathComponent
        let venvRoot = (binDir as NSString).deletingLastPathComponent
        let cfg = venvRoot + "/pyvenv.cfg"
        guard FileManager.default.fileExists(atPath: cfg) else { return true }
        return (try? Data(contentsOf: URL(fileURLWithPath: cfg))) != nil
    }

    static func runnerPath() -> String? {
        if let p = Bundle.main.resourceURL?.appendingPathComponent("engine/runner.py").path,
           FileManager.default.fileExists(atPath: p) { return p }
        let candidates = [
            "/Users/ac/Documents/GitHub/GlazeR/engine/runner.py",
            FileManager.default.currentDirectoryPath + "/engine/runner.py",
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) { return c }
        return nil
    }

    // MARK: Python 字面量

    static func pyString(_ s: String) -> String {
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

    static func pyList(_ xs: [String]) -> String {
        "[" + xs.map { pyString($0) }.joined(separator: ", ") + "]"
    }

    // MARK: 生成 job.py

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

        return ([
            "# GlazeR generated job — 由应用自动生成，请勿手动修改",
            "GZ_MODE = \(pyString(slice.mode.rawValue))",
            "GZ_FUNCTION = \(pyString(slice.function))",
            "GZ_SOURCE = \(pyString(slice.sourceFile))",
            "GZ_CODE = \(pyString(slice.code))",
            "GZ_FILE_ARG = \(pyString(slice.fileArg))",
            "GZ_FILES = \(pyList(files))",
            "GZ_PARAM_KEYS = \(pyList(keys))",
            "GZ_PARAM_EXPRS = \(pyList(exprs))",
            "GZ_OUTPUT_MODE = \(pyString(slice.output.rawValue))",
            "GZ_OUTPUT_DIR = \(pyString(dir))",
            "GZ_OUTPUT_SUFFIX = \(pyString(slice.outputSuffix))",
            "GZ_OUTPUT_CODE = \(pyString(slice.outputCode))",
            "GZ_OUT_BASE = \(pyString(stem))",
            "GZ_WORKDIR = \(pyString(workdir))",
        ] as [String]).joined(separator: "\n") + "\n"
    }

    // MARK: 环境检测

    static func check(config: GlazeConfig,
                      onDone: @escaping (Result<PyEnvReport, GZError>) -> Void) {
        guard let runner = runnerPath() else {
            onDone(.failure(.msg("找不到 engine/runner.py（请重新构建应用）"))); return
        }
        REngine.launch(["@RUNNER@", "--check"], config: config,
                       runner: runner,
                       executable: detectPython(override: config.pythonPath),
                       envProgram: "python3", engineLabel: "Python", timeout: 60) { res in
            switch res {
            case .failure(let e): onDone(.failure(e))
            case .success(let r):
                let (exe, _) = detectPython(override: config.pythonPath)
                onDone(.success(PyEnvReport(
                    python: r["python"] as? String ?? exe,
                    version: r["version"] as? String ?? "",
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
        guard slice.isConfigured else {
            onDone(.failure(.msg("扇区「\(slice.label)」尚未配置 Python 函数或代码"))); return
        }
        guard let runner = runnerPath() else {
            onDone(.failure(.msg("找不到 engine/runner.py（请重新构建应用）"))); return
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlazeR-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            onDone(.failure(.msg("无法创建临时目录：\(error.localizedDescription)"))); return
        }
        let job = tmp.appendingPathComponent("job.py")
        do {
            try makeJob(slice: slice, files: files, config: config, outDir: outDir)
                .write(to: job, atomically: true, encoding: .utf8)
        } catch {
            onDone(.failure(.msg("无法写入任务脚本：\(error.localizedDescription)"))); return
        }

        appendGlazeLog("run start · \(slice.label) [Python] · \(files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))")
        REngine.launch(["@RUNNER@", job.path], config: config,
                       runner: runner,
                       executable: detectPython(override: config.pythonPath),
                       envProgram: "python3", engineLabel: "Python",
                       onStage: onStage, onProcess: onProcess) { res in
            defer { try? FileManager.default.removeItem(at: tmp) }
            switch res {
            case .failure(let e):
                appendGlazeLog("run failed · \(slice.label) [Python] · \(e.message)")
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
                appendGlazeLog("run end · \(slice.label) [Python] · ok=\(result.ok) · \(result.message)")
                if result.ok { onDone(.success(result)) }
                else { onDone(.failure(.msg(result.message.isEmpty ? "Python 执行失败" : result.message))) }
            }
        }
    }
}
