// GlazeR — 全局状态：配置、任务、运行记录、R 环境检测
import AppKit
import SwiftUI

final class AppState: ObservableObject {
    static let shared = AppState()

    enum Page: String, CaseIterable, Identifiable {
        case home, editor, logs, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "首页"
            case .editor: return "转盘编辑器"
            case .logs: return "运行日志"
            case .settings: return "设置"
            }
        }
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .editor: return "circle.grid.2x2.fill"
            case .logs: return "list.bullet.rectangle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    enum EnvState: Equatable {
        case checking
        case ok
        case missing([String])
        case failed(String)
    }

    @Published var config: GlazeConfig
    @Published var page: Page = .home
    @Published var jobs: [JobItem] = []
    @Published var recents: [RunRecord] = []
    @Published var logLines: [String] = []
    @Published var showSettings = false
    @Published var envState: EnvState = .checking
    @Published var envReport: REnvReport?
    @Published var pyEnvState: EnvState = .checking
    @Published var pyEnvReport: PyEnvReport?
    @Published var stataEnvState: EnvState = .checking
    @Published var stataEnvReport: StataEnvReport?

    /// 文档窗口「应用到转盘…」投递的 .glazer 文件，由转盘编辑器消费后清空
    @Published var externalImportURLs: [URL] = []

    /// 把 .glazer 文件交给主窗口的导入预览：切到编辑器并前置主窗口
    func openWheelDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        page = .editor
        externalImportURLs = urls
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "gz-main" }) {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }

    init() {
        config = GlazeConfig.load()
        loadRecents()
        checkEnv()
        checkPythonEnv()
        // Stata 批处理启动较慢，只有确实配置了 Stata 扇区时才随启动自检
        if config.profiles.contains(where: { $0.slices.contains { $0.engine == .stata } }) {
            checkStataEnv()
        }
    }

    // MARK: 配置

    func reloadConfig() { config = GlazeConfig.load() }

    func saveConfig(recheckEnv: Bool = true) {
        _ = config.normalized()
        config.save()
        if recheckEnv { checkEnv() }
    }

    func setActiveProfile(_ id: String) {
        config.activeProfileId = id
        config.save()
        objectWillChange.send()
    }

    // MARK: R 环境

    func checkEnv() {
        envState = .checking
        let pkgs = REngine.referencedPackages(config)
        REngine.check(packages: pkgs, config: config) { [weak self] res in
            guard let self else { return }
            switch res {
            case .success(let report):
                self.envReport = report
                self.envState = report.missing.isEmpty ? .ok : .missing(report.missing)
                self.log("R \(report.version) · \(report.rscript)")
            case .failure(let err):
                self.envReport = nil
                self.envState = .failed(err.message)
                self.log("R 环境检测失败：\(err.message)")
            }
        }
    }

    // MARK: Python 环境

    func checkPythonEnv() {
        pyEnvState = .checking
        PythonEngine.check(config: config) { [weak self] res in
            guard let self else { return }
            switch res {
            case .success(let report):
                self.pyEnvReport = report
                self.pyEnvState = report.missing.isEmpty ? .ok : .missing(report.missing)
                self.log("Python \(report.version) · \(report.python)")
            case .failure(let err):
                self.pyEnvReport = nil
                self.pyEnvState = .failed(err.message)
                self.log("Python 环境检测失败：\(err.message)")
            }
        }
    }

    // MARK: Stata 环境

    func checkStataEnv() {
        stataEnvState = .checking
        StataEngine.check(config: config) { [weak self] res in
            guard let self else { return }
            switch res {
            case .success(let report):
                self.stataEnvReport = report
                self.stataEnvState = .ok
                self.log("Stata \(report.version) \(report.flavor) · \(report.stata)")
            case .failure(let err):
                self.stataEnvReport = nil
                self.stataEnvState = .failed(err.message)
                self.log("Stata 环境检测失败：\(err.message)")
            }
        }
    }

    // MARK: 日志与记录

    func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logLines.insert("[\(f.string(from: Date()))] \(s)", at: 0)
        if logLines.count > 200 { logLines = Array(logLines.prefix(200)) }
        appendGlazeLog(s)
    }

    func clearLogs() { logLines = [] }

    func loadRecents() {
        if let d = try? Data(contentsOf: GlazeConfig.recentsURL),
           let items = try? JSONDecoder().decode([RunRecord].self, from: d) { recents = items }
    }

    func addRecent(_ item: RunRecord) {
        recents.insert(item, at: 0)
        recents = Array(recents.prefix(50))
        if let d = try? JSONEncoder().encode(recents) {
            try? d.write(to: GlazeConfig.recentsURL, options: .atomic)
        }
    }

    func clearRecents() {
        recents = []
        try? Data().write(to: GlazeConfig.recentsURL)
    }

    func closeAllJobs() {
        withAnimation(.easeOut(duration: 0.2)) { jobs = [] }
    }

    // MARK: 任务控制（长任务可取消）

    private var runningProcesses: [UUID: Process] = [:]
    private var cancelledJobs: Set<UUID> = []

    func cancel(jobID: UUID) {
        cancelledJobs.insert(jobID)
        if let proc = runningProcesses.removeValue(forKey: jobID), proc.isRunning {
            proc.terminate()
        }
        if let idx = jobs.firstIndex(where: { $0.id == jobID }) {
            var it = jobs[idx]
            it.status = .cancelled
            it.detail = "已取消"
            it.stage = "已取消"
            jobs[idx] = it
        }
        WheelPanel.shared.jobFinished(detail: "已取消")
        log("■ 任务已取消")
    }

    // MARK: 执行

    /// 转盘扇区命中后调用：把文件交给对应扇区的 R / Python / Stata 动作
    func run(paths: [String], sliceIndex: Int, profileID: String? = nil) {
        let cfg = GlazeConfig.load()
        let profile = cfg.profiles.first { $0.id == (profileID ?? cfg.activeProfileId) }
            ?? cfg.activeProfile
        guard sliceIndex >= 0, sliceIndex < profile.slices.count else { return }
        let slice = profile.slices[sliceIndex]

        if !slice.enabled {
            let name = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: " + ")
            jobs.insert(JobItem(file: name, action: slice.label, status: .failed,
                                detail: "扇区「\(slice.label)」已禁用"), at: 0)
            if jobs.count > 5 { jobs = Array(jobs.prefix(5)) }
            log("✗ 扇区「\(slice.label)」已禁用")
            WheelPanel.shared.jobFinished(detail: "扇区已禁用")
            return
        }

        let groups: [[String]] = slice.batch == .all ? [paths] : paths.map { [$0] }

        // 输出目录策略
        var outDir: String? = nil
        switch cfg.outputMode {
        case "custom":
            let d = cfg.customOutDir.trimmingCharacters(in: .whitespaces)
            outDir = d.isEmpty ? nil : d
        case "ask":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "选择输出目录"
            if panel.runModal() == .OK, let url = panel.url { outDir = url.path }
        default: break   // source：由 runner 默认写到源文件所在目录
        }

        for group in groups {
            guard !group.isEmpty else { continue }
            let item = JobItem(file: group.map { ($0 as NSString).lastPathComponent }.joined(separator: " + "),
                               action: slice.label, startedAt: Date())
            jobs.insert(item, at: 0)
            if jobs.count > 5 { jobs = Array(jobs.prefix(5)) }
            let jobID = item.id
            let update: (JobItem) -> Void = { [weak self] newItem in
                guard let self else { return }
                if let idx = self.jobs.firstIndex(where: { $0.id == jobID }) { self.jobs[idx] = newItem }
            }

            WheelPanel.shared.jobStarted()
            log("▶ \(profile.name) / \(slice.label) [\(slice.engine.shortTitle)] ← \(item.file)")
            update(JobItem(id: jobID, file: item.file, action: slice.label,
                           status: .working, detail: "\(slice.engine.shortTitle) 正在执行…",
                           stage: "启动 \(slice.engine.shortTitle)…", startedAt: item.startedAt))

            REngine.run(slice: slice, files: group, config: cfg, outDir: outDir,
                        onStage: { [weak self] msg in
                            guard let self, !self.cancelledJobs.contains(jobID) else { return }
                            if let idx = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                var it = self.jobs[idx]
                                it.stage = msg
                                it.detail = msg
                                self.jobs[idx] = it
                            }
                            self.log("  · \(msg)")
                        },
                        onProcess: { [weak self] proc in
                            self?.runningProcesses[jobID] = proc
                        }) { [weak self] res in
                guard let self else { return }
                // 主动取消后终止进程触发的回调不再覆盖卡片状态
                guard !self.cancelledJobs.contains(jobID) else {
                    self.cancelledJobs.remove(jobID)
                    self.runningProcesses.removeValue(forKey: jobID)
                    return
                }
                self.runningProcesses.removeValue(forKey: jobID)
                let started = Date()
                switch res {
                case .success(let r):
                    var done = JobItem(id: jobID, file: item.file, action: slice.label,
                                       status: .done,
                                       detail: "\(r.message) · \(String(format: "%.2f", r.elapsed))s",
                                       output: r.output.isEmpty ? nil : r.output,
                                       log: r.log, warnings: r.warnings,
                                       stage: "完成", startedAt: item.startedAt)
                    done.output = r.output.isEmpty ? nil : r.output
                    update(done)
                    self.addRecent(RunRecord(time: started, input: group.first ?? "",
                                             action: slice.label, profile: profile.name,
                                             output: r.output, ok: true, message: r.message,
                                             elapsed: r.elapsed,
                                             log: [r.log, r.warnings].filter { !$0.isEmpty }.joined(separator: "\n")))
                    self.log("✓ \(slice.label)：\(r.message)")
                    if !r.log.isEmpty { self.log("  输出：\(String(r.log.prefix(300)))") }
                    if !r.warnings.isEmpty { self.log("  ⚠ \(String(r.warnings.prefix(300)))") }
                    if self.config.autoRevealOutput, !r.output.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.output)])
                    }
                    WheelPanel.shared.jobFinished(detail: r.output.isEmpty ? "执行完成 ✓" : "已写出 ✓")
                case .failure(let err):
                    // 失败也要带上完整执行日志：通知卡片「查看输出」与运行日志页
                    // 才能展开看到 Stata job.log 的全部过程，而不是只有一句摘要。
                    update(JobItem(id: jobID, file: item.file, action: slice.label,
                                   status: .failed, detail: err.message,
                                   log: err.log.isEmpty ? nil : err.log,
                                   stage: "失败", startedAt: item.startedAt))
                    self.addRecent(RunRecord(time: started, input: group.first ?? "",
                                             action: slice.label, profile: profile.name,
                                             output: "", ok: false, message: err.message,
                                             elapsed: 0, log: err.log))
                    self.log("✗ \(slice.label)：\(err.message)")
                    if !err.log.isEmpty {
                        self.log("  执行日志：\(err.log.count) 字符，可在通知卡片或运行日志页展开查看")
                    }
                    WheelPanel.shared.jobFinished(detail: "执行失败")
                }
            }
        }
    }
}
