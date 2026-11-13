// GlazeR — Stata 执行层：探测 Stata 批处理可执行文件、生成 job.do、回收 result.txt
//
// macOS 下 `stata-mp -b do job.do` 不写 stdout，只在工作目录生成 job.log，
// 因此结果由 runner.do 写成 key=value 的 result.txt，再由 REngine.launch 统一
// 读取（含超时、取消、阶段事件与日志收集）。
import Foundation

struct StataEnvReport {
    let stata: String
    let version: String
    let flavor: String
}

enum StataEngine {

    // MARK: 路径探测

    static func detectStata(override: String = "") -> (String, Bool) {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return (trimmed, false)
        }
        var candidates = [
            "/usr/local/bin/stata-mp",
            "/usr/local/bin/stata-se",
            "/usr/local/bin/stata",
            "/opt/homebrew/bin/stata-mp",
            "/opt/homebrew/bin/stata-se",
        ]
        // 常见安装形态：/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp
        let roots = ["/Applications/StataNow", "/Applications/Stata"]
        for root in roots {
            guard let bundles = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for bundle in bundles where bundle.hasSuffix(".app") {
                let mac = root + "/" + bundle + "/Contents/MacOS"
                for exe in ["stata-mp", "stata-se", "stata"] {
                    candidates.append(mac + "/" + exe)
                }
            }
        }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return (c, false)
        }
        return ("/usr/bin/env", true)
    }

    static func runnerPath() -> String? {
        if let p = Bundle.main.resourceURL?.appendingPathComponent("engine/runner.do").path,
           FileManager.default.isExecutableFile(atPath: p) || FileManager.default.fileExists(atPath: p) {
            return p
        }
        let candidates = [
            "/Users/ac/Documents/GitHub/GlazeR/engine/runner.do",
            FileManager.default.currentDirectoryPath + "/engine/runner.do",
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) { return c }
        return nil
    }

    // MARK: Stata 复合引号字面量

    /// 生成 `"..."`' 形式的 Stata 复合引号字符串，用于文件路径等普通文本
    static func doQuoted(_ s: String) -> String {
        let cleaned = s
            .replacingOccurrences(of: "\"'", with: "\" '")   // 避免提前闭合复合引号
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        return "`\"" + cleaned + "\"'"
    }

    /// 同目录同名不覆盖：a.dta → a(1).dta → a(2).dta
    static func uniquePath(_ path: String) -> String {
        guard FileManager.default.fileExists(atPath: path) else { return path }
        let ns = path as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: "\(stem)(\(i))" + (ext.isEmpty ? "" : "." + ext)) {
            i += 1
        }
        return "\(stem)(\(i))" + (ext.isEmpty ? "" : "." + ext)
    }

    // MARK: 生成 job.do

    struct Job {
        let text: String
        let resultPath: String
        let logPath: String
        let outputPath: String
    }

    static func makeJob(slice: SliceConfig, files: [String], config: GlazeConfig,
                        outDir: String?, template: String, dir: URL) -> Job {
        let first = files.first ?? ""
        let name = (first as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let sourceDir = (first as NSString).deletingLastPathComponent
        let targetDir = outDir ?? sourceDir
        let workdir = config.workingDir.trimmingCharacters(in: .whitespaces).isEmpty
            ? sourceDir : config.workingDir
        // 打印 / 不写出 / 自定义模式下用户自己写文件，按代码里的写出命令推断扩展名，
        // 避免 export delimited 却拿到 .dta 后缀。
        let ext: String
        switch slice.output {
        case .csv:  ext = "csv"
        case .dta:  ext = "dta"
        default:
            let body = (slice.code + "\n" + slice.outputCode).lowercased()
            let wantsDta = body.contains("save `") || body.contains("save using")
                || body.contains("\nsave ") || body.hasPrefix("save ")
            ext = wantsDta ? "dta" : "csv"
        }
        // `out' 始终是「建议输出文件的完整路径」（含扩展名）。即便结果处理是
        // 打印 / 不写出，也要给自定义代码一个可直接写入的目标；早期版本在
        // print / none 下把它置为空串，用户写 `out'/xxx.csv 会得到根目录路径，
        // Stata 报 invalid file specification r(603)。
        let suggestedOutput = uniquePath(targetDir + "/" + stem + slice.outputSuffix + "." + ext)
        var outputPath = suggestedOutput
        if slice.output == .none || slice.output == .print { outputPath = "" }

        let resultPath = dir.appendingPathComponent("result.txt").path
        let logPath = dir.appendingPathComponent("job.log").path

        // ------------------------------------------------ 路径宏
        var vars: [String] = []
        vars.append("* 由 GlazeR 自动解析：输入 `file' / `filename' / `dir' / `filebasename'")
        vars.append("* 输出 `out'（完整文件路径，不是目录）/ `outdir'（输出目录）")
        vars.append("* 多文件 `file1' … `file\(files.count)' / `nfiles'，另有同名全局宏 $file 等")
        vars.append("local gz_result \(doQuoted(resultPath))")
        vars.append("local gz_outmode \"\(slice.output.rawValue)\"")
        vars.append("local gz_has_output_code \"\(slice.output == .custom ? 1 : 0)\"")
        vars.append("local gz_output_file \(doQuoted(slice.output == .custom ? outputPath : ""))")
        vars.append("local file \(doQuoted(first))")
        vars.append("local filename \(doQuoted(name))")
        vars.append("local dir \(doQuoted(sourceDir))")
        vars.append("local filebasename \(doQuoted(stem))")
        vars.append("local out \(doQuoted(suggestedOutput))")
        vars.append("local outdir \(doQuoted(targetDir))")
        vars.append("local nfiles \(files.count)")
        for (i, p) in files.enumerated() {
            vars.append("local file\(i + 1) \(doQuoted(p))")
        }
        vars.append("global file `\"`file'\"'")
        vars.append("global filename `\"`filename'\"'")
        vars.append("global dir `\"`dir'\"'")
        vars.append("global filebasename `\"`filebasename'\"'")
        vars.append("global out `\"`out'\"'")
        vars.append("global outdir `\"`outdir'\"'")
        vars.append("global nfiles `nfiles'")
        for (i, _) in files.enumerated() {
            vars.append("global file\(i + 1) `\"`file\(i + 1)'\"'")
        }
        vars.append("cd \(doQuoted(workdir))")

        // ------------------------------------------------ 执行代码
        var exec: [String] = []
        if !slice.sourceFile.trimmingCharacters(in: .whitespaces).isEmpty {
            let src = slice.sourceFile
            if FileManager.default.fileExists(atPath: src),
               let body = try? String(contentsOfFile: src, encoding: .utf8) {
                exec.append("* ---- 用户 Stata 脚本：\(src)")
                exec.append(body)
                exec.append("* ---- 用户 Stata 脚本结束")
            } else {
                exec.append("* 找不到用户脚本：\(src)")
            }
        }
        if slice.mode == .expr {
            exec.append("* ---- 扇区自定义 Stata 代码")
            exec.append(slice.code)
        } else {
            // Stata 没有「具名参数」概念：函数名是命令 / program 名，
            // 文件路径作为第一个位置参数，默认参数按 Stata 命令行片段拼接。
            var cmd = slice.function.trimmingCharacters(in: .whitespaces)
            if !slice.fileArg.trimmingCharacters(in: .whitespaces).isEmpty {
                cmd += " `\"`file'\"'"
            }
            for p in slice.params where p.enabled
                        && !p.key.trimmingCharacters(in: .whitespaces).isEmpty {
                let k = p.key.trimmingCharacters(in: .whitespaces)
                let v = p.value.trimmingCharacters(in: .whitespaces)
                if v.isEmpty { cmd += " " + k }
                else { cmd += " " + k + "(" + v + ")" }
            }
            exec.append("* ---- 扇区 Stata 命令")
            exec.append(cmd)
        }
        if slice.output == .custom && !slice.outputCode.trimmingCharacters(in: .whitespaces).isEmpty {
            exec.append("* ---- 自定义写出代码（可用 `out'）")
            exec.append(slice.outputCode)
        }
        if exec.isEmpty { exec.append("* （未配置可执行内容）") }

        // ------------------------------------------------ 组装模板
        // 逐行精确替换：占位标记只在「独立成行」时生效。
        // 早期用 replacingOccurrences 全局替换，模板头部注释里提到的占位符
        // 也被替换，整段路径宏被拼进注释行，Stata 报 invalid syntax r(198)。
        var textLines: [String] = []
        for line in template.components(separatedBy: "\n") {
            switch line.trimmingCharacters(in: .whitespaces) {
            case "__GZ_VARS__": textLines.append(vars.joined(separator: "\n"))
            case "__GZ_EXEC__": textLines.append(exec.joined(separator: "\n"))
            default:            textLines.append(line)
            }
        }
        let text = textLines.joined(separator: "\n")
        return Job(text: text, resultPath: resultPath, logPath: logPath, outputPath: outputPath)
    }

    // MARK: 环境检测

    static func check(config: GlazeConfig,
                      onDone: @escaping (Result<StataEnvReport, GZError>) -> Void) {
        guard let runner = runnerPath() else {
            onDone(.failure(.msg("找不到 engine/runner.do（请重新构建应用）"))); return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlazeR-StataCheck-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let doFile = tmp.appendingPathComponent("check.do")
        let result = tmp.appendingPathComponent("check.txt")
        let body = [
            "set linesize 255",
            "file open gz_ch using \(doQuoted("check.txt")), write replace text",
            "file write gz_ch \"version=`c(stata_version)'\" _n",
            "file write gz_ch \"flavor=`c(flavor)'\" _n",
            "file close gz_ch",
        ].joined(separator: "\n") + "\n"
        do {
            try body.write(to: doFile, atomically: true, encoding: .utf8)
        } catch {
            onDone(.failure(.msg("无法写入 Stata 检测脚本：\(error.localizedDescription)"))); return
        }
        let (exe, _) = detectStata(override: config.stataPath)
        REngine.launch(["-b", "do", doFile.path], config: config,
                       runner: runner,
                       executable: detectStata(override: config.stataPath),
                       envProgram: "stata-mp", engineLabel: "Stata",
                       timeout: 60, workingDirectory: tmp.path,
                       resultFile: result.path, logFile: tmp.appendingPathComponent("check.log").path) { res in
            defer { try? FileManager.default.removeItem(at: tmp) }
            switch res {
            case .failure(let e): onDone(.failure(e))
            case .success(let r):
                let version = r["version"] as? String ?? ""
                guard !version.isEmpty else {
                    onDone(.failure(.msg("Stata 未返回版本信息，请检查解释器路径"))); return
                }
                onDone(.success(StataEnvReport(
                    stata: exe,
                    version: version,
                    flavor: r["flavor"] as? String ?? "Stata")))
            }
        }
    }

    // MARK: 失败诊断

    /// 从批处理日志提取最后一条错误（如 `invalid file specification r(603);`），
    /// 让通知卡片不必展开日志也能看出失败原因。
    static func errorSnippet(_ log: String) -> String {
        let lines = log.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // 批处理日志末尾会重复一次 r(NNN);，所以不能只取最后一条；
        // 遍历所有返回码行，找到带错误说明的那一条（如 invalid file specification）。
        let rcIndices = lines.indices.filter { lines[$0].hasPrefix("r(") && lines[$0].hasSuffix(");") }
        guard !rcIndices.isEmpty else { return "" }
        var best = ""
        for idx in rcIndices {
            var j = idx - 1
            while j >= 0, idx - j <= 4 {
                let s = lines[j]
                if !s.hasPrefix("."), !s.hasPrefix("r("), !s.hasPrefix("end of do-file"),
                   !s.hasPrefix("("), !s.hasPrefix("* ") {
                    // Stata 的路径类错误往往是一整行超长路径；只保留末尾关键短语，
                    // 避免摘要被路径挤满、看不到「could not be opened」。
                    best = s.count > 120 ? "…" + String(s.suffix(60)) : s
                    break
                }
                j -= 1
            }
        }
        return String(best.prefix(160))
    }

    /// 失败时把 job.do / job.log / result.txt 另存到应用支持目录，
    /// 否则回调结束后临时目录即被删除，用户事后无法查看完整执行过程。
    static func saveDiagnostics(tmp: URL, label: String) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safe = label.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
        let dest = GlazeConfig.dir
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("Stata-\(stamp)-\(safe)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            for name in ["job.do", "job.log", "result.txt"] {
                let src = tmp.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.copyItem(at: src, to: dest.appendingPathComponent(name))
                }
            }
            return dest
        } catch { return nil }
    }

    // MARK: 执行扇区动作

    static func run(slice: SliceConfig, files: [String], config: GlazeConfig,
                    outDir: String?,
                    onStage: ((String) -> Void)? = nil,
                    onProcess: ((Process) -> Void)? = nil,
                    onDone: @escaping (Result<RunResult, GZError>) -> Void) {
        guard !files.isEmpty else { onDone(.failure(.msg("没有输入文件"))); return }
        guard slice.isConfigured else {
            onDone(.failure(.msg("扇区「\(slice.label)」尚未配置 Stata 命令或代码"))); return
        }
        guard let runner = runnerPath(),
              let template = try? String(contentsOfFile: runner, encoding: .utf8) else {
            onDone(.failure(.msg("找不到 engine/runner.do（请重新构建应用）"))); return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlazeR-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            onDone(.failure(.msg("无法创建临时目录：\(error.localizedDescription)"))); return
        }
        let job = makeJob(slice: slice, files: files, config: config,
                          outDir: outDir, template: template, dir: tmp)
        let doFile = tmp.appendingPathComponent("job.do")
        do {
            try job.text.write(to: doFile, atomically: true, encoding: .utf8)
        } catch {
            onDone(.failure(.msg("无法写入任务脚本：\(error.localizedDescription)"))); return
        }

        let started = Date()
        appendGlazeLog("run start · \(slice.label) [Stata] · \(files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))")
        // 常见误用：`out' 是完整输出文件路径，把它当目录拼子文件名会得到无效路径（r(603)）。
        if slice.code.contains("`out'/") || slice.outputCode.contains("`out'/") {
            appendGlazeLog("⚠ 扇区「\(slice.label)」把 `out' 当作目录使用；`out' 是完整输出文件路径，拼接文件名请改用 `outdir'/ 或直接写入 `out'。")
            DispatchQueue.main.async { onStage?("注意：`out' 是文件路径，拼文件名请用 `outdir'") }
        }
        DispatchQueue.main.async { onStage?("Stata 正在执行：\(slice.label)") }
        REngine.launch(["-b", "do", doFile.path], config: config,
                       runner: runner,
                       executable: detectStata(override: config.stataPath),
                       envProgram: "stata-mp", engineLabel: "Stata",
                       workingDirectory: tmp.path,
                       resultFile: job.resultPath, logFile: job.logPath,
                       onStage: onStage, onProcess: onProcess) { res in
            defer { try? FileManager.default.removeItem(at: tmp) }
            let elapsed = Date().timeIntervalSince(started)
            switch res {
            case .failure(let e):
                appendGlazeLog("run failed · \(slice.label) [Stata] · \(e.message)")
                var fullLog = e.log
                if let saved = Self.saveDiagnostics(tmp: tmp, label: slice.label) {
                    appendGlazeLog("Stata 诊断文件：\(saved.path)")
                    fullLog += "\n\n完整诊断文件：\(saved.path)/job.do · \(saved.path)/job.log"
                }
                onDone(.failure(.withLog(e.message, log: fullLog)))
            case .success(let r):
                let ok = r["ok"] as? Bool ?? false
                let rc = r["rc"] as? Double ?? 0
                let output = r["output"] as? String ?? ""
                let note = r["note"] as? String ?? ""
                let log = r["log"] as? String ?? ""
                var message = "处理完成"
                if ok {
                    if !output.isEmpty { message += "，已写出结果" }
                } else {
                    message = "Stata 执行失败（r(\(Int(rc)))）"
                    if !note.isEmpty { message += "：\(note)" }
                }
                if ok {
                    let result = RunResult(ok: ok, message: message, output: output,
                                           elapsed: elapsed, summary: "Stata",
                                           log: log, warnings: note)
                    appendGlazeLog("run end · \(slice.label) [Stata] · ok=true · \(message)")
                    onDone(.success(result))
                } else {
                    // 失败时把具体报错行、完整 job.log 与落盘诊断文件一并返回，
                    // UI 的通知卡片与「运行日志」页可直接展开查看。
                    let snippet = Self.errorSnippet(log)
                    if !snippet.isEmpty { message += "：\(snippet)" }
                    var fullLog = log
                    if let saved = Self.saveDiagnostics(tmp: tmp, label: slice.label) {
                        appendGlazeLog("Stata 诊断文件：\(saved.path)")
                        fullLog += "\n\n完整诊断文件：\(saved.path)/job.do · \(saved.path)/job.log"
                    }
                    appendGlazeLog("Stata job.log（失败）· \(slice.label)\n" + String(log.suffix(12000)))
                    appendGlazeLog("run end · \(slice.label) [Stata] · ok=false · \(message)")
                    onDone(.failure(.withLog(message, log: fullLog)))
                }
            }
        }
    }
}
