// GlazeR — 设置中心：权限自检、快捷键、R / Python / Stata 环境、输出位置、后台常驻
import AppKit
import SwiftUI
import Combine
import ServiceManagement
import ApplicationServices

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @State private var hotkeyFlags: Set<String> = ["option"]
    @State private var enableHold = true
    @State private var holdDelay: Double = 0.45
    @State private var rscriptPath = ""
    @State private var pythonPath = ""
    @State private var stataPath = ""
    @State private var skipUserRProfile = true
    @State private var glazerDefaultApp = "检测中…"
    @State private var workingDir = ""
    @State private var outputMode = "source"
    @State private var customOutDir = ""
    @State private var autoReveal = false
    @State private var runTimeout: Double = 300
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var permTick = 0
    @State private var loaded = false

    private let permTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置").font(.system(size: 24, weight: .bold)).foregroundColor(inkColor)
                    .padding(.top, 22)

                permCard

                groupBox("呼出方式") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("全局默认组合键（按住组合键拖文件；或选中文件后长按组合键）")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundColor(subInkColor)
                        HStack(spacing: 8) {
                            ForEach(ModKey.allCases, id: \.self) { m in
                                let on = hotkeyFlags.contains(m.rawValue)
                                Button {
                                    if on { guard hotkeyFlags.count > 1 else { return }; hotkeyFlags.remove(m.rawValue) }
                                    else { hotkeyFlags.insert(m.rawValue) }
                                } label: {
                                    Text(m.label).font(.system(size: 11.5, weight: .medium))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(on ? brandColor.opacity(0.15) : Color(hex: 0xF0F0F4)))
                                        .overlay(Capsule().strokeBorder(on ? brandColor : Color(hex: 0xD8DCE4), lineWidth: 1))
                                        .foregroundColor(on ? brandColor : subInkColor)
                                }.buttonStyle(.plain)
                            }
                        }
                        Toggle("选中文件后长按组合键直接呼出转盘（读取 Finder 选中项）", isOn: $enableHold)
                            .toggleStyle(.switch).controlSize(.small)
                        HStack(spacing: 8) {
                            Text("长按判定延时").font(.system(size: 11.5)).foregroundColor(subInkColor)
                            Slider(value: $holdDelay, in: 0.15...1.5, step: 0.05).frame(width: 180)
                            Text(String(format: "%.2f s", holdDelay))
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(hintColor)
                        }
                        Text("可在「转盘编辑器」里给每套转盘单独绑定组合键；最具体的组合优先命中。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                envCard

                groupBox("R 解释器") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("留空自动探测：/usr/local/bin/Rscript → Homebrew → R.framework", text: $rscriptPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                            Button("浏览…") { pickExecutable($rscriptPath) }
                        }
                        HStack(spacing: 8) {
                            TextField("工作目录（留空 = 源文件所在目录）", text: $workingDir)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                            Button("浏览…") { pickDirectory($workingDir) }
                        }
                        Text("R / Python / Stata 脚本里的相对路径会以这里为基准；GUI 启动的进程 PATH 较窄，应用会自动补上 /usr/local/bin 与 /opt/homebrew/bin。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                        Divider()
                        Toggle("跳过用户 ~/.Rprofile（推荐）", isOn: $skipUserRProfile)
                            .toggleStyle(.switch).controlSize(.small)
                        Text("Rscript 默认会执行 ~/.Rprofile，而它通常是为 RStudio 交互会话配置的（字体、绘图主题、source 脚本）。GUI 后台进程往往没有「文稿」目录授权，读取其中的字体会报错并导致环境检测失败。跳过时仍会加载 .Renviron 与系统级 Rprofile.site；自定义函数请在扇区的「自定义脚本」里显式指定。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        HStack(spacing: 8) {
                            Text("任务超时").font(.system(size: 11.5)).foregroundColor(subInkColor)
                            Slider(value: $runTimeout, in: 30...1800, step: 30).frame(width: 220)
                            Text("\(Int(runTimeout)) 秒")
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(hintColor)
                        }
                        Text("超时自动终止 R 进程并给出明确错误；通知卡片会实时显示阶段与已运行时间，也可随时点「取消」。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                groupBox("输出位置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $outputMode) {
                            Text("源文件所在目录").tag("source")
                            Text("每次询问").tag("ask")
                            Text("固定目录").tag("custom")
                        }.pickerStyle(.radioGroup).labelsHidden()

                        if outputMode == "custom" {
                            HStack {
                                TextField("目录路径", text: $customOutDir)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                                Button("浏览…") { pickDirectory($customOutDir) }
                            }
                        }
                        Toggle("完成后自动在 Finder 中显示输出文件", isOn: $autoReveal)
                            .toggleStyle(.switch).controlSize(.small)
                        Text("同名文件不会覆盖，自动追加 (1)、(2) …；CSV 输出带 UTF-8 BOM，Excel 打开中文不乱码。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                groupBox(".glazer 转盘配置文件") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            if let url = Bundle.main.url(forResource: "glazer-doc", withExtension: "icns"),
                               let img = NSImage(contentsOf: url) {
                                Image(nsImage: img).resizable().frame(width: 42, height: 42)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("GlazeR 转盘配置（.glazer）")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(subInkColor)
                                Text("UTF-8 纯文本，专属文档图标；双击会用 GlazeR 的可编辑文档窗口打开（带语法高亮，可保存 / 应用到转盘）。")
                                    .font(.system(size: 10.5)).foregroundColor(hintColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Text("当前默认打开方式：\(glazerDefaultApp)")
                                .font(.system(size: 11)).foregroundColor(subInkColor)
                            Spacer()
                            Button("重新检测") { checkGlazerDefault() }
                            Button("设为 GlazeR 默认打开") { setGlazerDefault() }
                        }
                        Text("应用安装到 /Applications 后会自动完成设置；也可在这里手动指定。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                groupBox("Python 解释器与格式转换") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("留空自动探测（优先复用已装好 pandas 等依赖的环境）", text: $pythonPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                            Button("浏览…") { pickExecutable($pythonPath) }
                            Button("重新检测") { state.checkPythonEnv() }
                        }
                        if let r = state.pyEnvReport {
                            Text("Python \(r.version) · \(r.python)")
                                .font(.system(size: 10.5, design: .monospaced)).foregroundColor(hintColor)
                                .lineLimit(1).truncationMode(.middle)
                            if r.missing.isEmpty {
                                Text("✓ 格式转换依赖齐全（pandas / pyarrow / pyreadstat / pyreadr / openpyxl / xlsxwriter / xlrd）")
                                    .font(.system(size: 10.5)).foregroundColor(Color(hex: 0x16A34A))
                            } else {
                                Text("缺少依赖：\(r.missing.joined(separator: "、"))")
                                    .font(.system(size: 10.5)).foregroundColor(Color(hex: 0xDC2626))
                                Text("可在所选解释器执行：pip install \(r.missing.joined(separator: " "))")
                                    .font(.system(size: 10.5, design: .monospaced)).foregroundColor(hintColor)
                            }
                        } else {
                            Text("尚未检测到 Python 环境，Python 扇区与格式转换转盘需要可用的解释器。")
                                .font(.system(size: 10.5)).foregroundColor(hintColor)
                        }
                        Text("DataWheel 格式转换转盘与 Python 扇区使用这个解释器；在 .glazer 文件里可直接写 convert(FILE, \"xlsx\")。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                groupBox("Stata 解释器与批处理") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("留空自动探测：/usr/local/bin/stata-mp → StataNow/StataMP.app", text: $stataPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                            Button("浏览…") { pickExecutable($stataPath) }
                            Button("重新检测") { state.checkStataEnv() }
                        }
                        if let r = state.stataEnvReport {
                            Text("Stata \(r.version) · \(r.flavor) · \(r.stata)")
                                .font(.system(size: 10.5, design: .monospaced)).foregroundColor(hintColor)
                                .lineLimit(1).truncationMode(.middle)
                            Text("✓ 批处理模式可用（stata -b do job.do）")
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: 0x16A34A))
                        } else {
                            Text("尚未检测到 Stata 批处理环境；Stata 扇区需要可执行的 stata-mp / stata-se / stata。")
                                .font(.system(size: 10.5)).foregroundColor(hintColor)
                        }
                        // Stata 局部宏以反引号开头，必须用 verbatim，否则 SwiftUI 会把 `…`
                        // 当成 Markdown 行内代码标记解析并吞掉反引号。
                        Text(verbatim: "Stata 自动解析局部宏 `file' / `filename' / `dir' / `filebasename'；`out' 是完整输出文件路径（不是目录），`outdir' 是输出目录；另有 `file1'…`fileN'、`nfiles' 与同名全局宏。失败时完整 job.log 会写入运行日志，并另存到「应用支持目录/logs」。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                groupBox("转盘数字键槽位（0–9，最多 10 套）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在 Finder 选中文件后按住 \(comboLabel)数字，即可直接呼出对应槽位的转盘；呼出后 60 秒内拖文件也会沿用该转盘。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 6) {
                            ForEach(0..<10, id: \.self) { d in
                                let p = state.config.profiles.first { $0.slot == d }
                                HStack(spacing: 7) {
                                    Text("\(comboLabel)\(d)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(brandColor)
                                        .frame(width: 46, alignment: .leading)
                                    Text(p?.name ?? "未分配")
                                        .font(.system(size: 11))
                                        .foregroundColor(p == nil ? hintColor : subInkColor)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(p == nil ? Color(hex: 0xF7F7FA) : brandSoft))
                            }
                        }
                        Text("槽位在「转盘编辑器」里修改；新建、复制或导入转盘会自动补空位，重复槽位会自动去重。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                groupBox("后台常驻") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $launchAtLogin) {
                            Text("登录时自动启动（菜单栏常驻）")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(subInkColor)
                        }.toggleStyle(.switch).controlSize(.small)
                        .onChange(of: launchAtLogin) { on in
                            do {
                                if on { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
                        }
                        Text("开启后随时可用快捷键呼出转盘，无需打开主窗口。")
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                    }
                }

                groupBox("关于") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GlazeR v1.0 · R / Python / Stata 文件转盘").font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(inkColor)
                        Text("参考 DataWheel 转盘交互 · 本地执行 R / Python / Stata，数据不上传")
                            .font(.system(size: 11)).foregroundColor(hintColor)
                        HStack(spacing: 0) {
                            Text("开发：").font(.system(size: 11.5, weight: .medium)).foregroundColor(brandColor)
                            Link("微信公众号 RStata", destination: URL(string: "https://tidyfriday.cn/")!)
                                .font(.system(size: 11.5, weight: .medium)).foregroundColor(brandColor)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("放弃修改") { load() }
                    Button("保存并生效") { save() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !loaded { loaded = true; load() }
            checkGlazerDefault()
        }
        .onChange(of: skipUserRProfile) { _ in
            // 开关切换即刻落盘并重新检测 R 环境，不必再点保存
            guard loaded else { return }
            state.config.skipUserRProfile = skipUserRProfile
            state.config.save()
            state.checkEnv()
        }
        .onReceive(permTimer) { _ in permTick += 1 }
    }

    // MARK: 读写

    private func load() {
        let c = GlazeConfig.load()
        hotkeyFlags = Set(c.hotkeyFlags.isEmpty ? ["option"] : c.hotkeyFlags)
        enableHold = c.enableHoldTrigger
        holdDelay = c.holdDelay
        rscriptPath = c.rscriptPath
        pythonPath = c.pythonPath
        stataPath = c.stataPath
        skipUserRProfile = c.skipUserRProfile
        workingDir = c.workingDir
        outputMode = c.outputMode
        customOutDir = c.customOutDir
        autoReveal = c.autoRevealOutput
        runTimeout = c.runTimeoutSeconds
    }

    private func save() {
        let c = state.config
        c.hotkeyFlags = hotkeyFlags.sorted()
        c.enableHoldTrigger = enableHold
        c.holdDelay = holdDelay
        c.rscriptPath = rscriptPath.trimmingCharacters(in: .whitespaces)
        c.pythonPath = pythonPath.trimmingCharacters(in: .whitespaces)
        c.stataPath = stataPath.trimmingCharacters(in: .whitespaces)
        c.skipUserRProfile = skipUserRProfile
        c.workingDir = workingDir.trimmingCharacters(in: .whitespaces)
        c.outputMode = outputMode
        c.customOutDir = customOutDir.trimmingCharacters(in: .whitespaces)
        c.autoRevealOutput = autoReveal
        c.runTimeoutSeconds = runTimeout
        c.save()
        state.objectWillChange.send()
        HotkeyMonitor.shared.restart()
        state.checkEnv()
        state.checkPythonEnv()
        // Stata 批处理启动较慢，仅在配置了 Stata 扇区或显式指定了解释器时检测
        if !c.stataPath.isEmpty || c.profiles.contains(where: { $0.slices.contains { $0.engine == .stata } }) {
            state.checkStataEnv()
        }
        appendGlazeLog("settings saved · hotkey=\(c.hotkeyFlags.joined(separator: "+")) · rscript=\(c.rscriptPath) · python=\(c.pythonPath) · stata=\(c.stataPath)")
    }

    private var comboLabel: String {
        let flags = state.config.hotkeyFlags.isEmpty ? ["option"] : state.config.hotkeyFlags
        return flags.compactMap { ModKey(rawValue: $0)?.shortLabel }.joined() + "+"
    }

    private func checkGlazerDefault() {
        if let name = GlazeRDocument.defaultAppName() {
            glazerDefaultApp = GlazeRDocument.isDefaultHandler() ? "\(name)（GlazeR ✓）" : name
        } else {
            glazerDefaultApp = "系统按 GlazeR 的 Owner 声明自动选择"
        }
    }

    private func setGlazerDefault() {
        GlazeRDocument.setAsDefault { result in
            switch result {
            case .success:
                glazerDefaultApp = "GlazeR ✓"
                state.log("已将 .glazer 默认打开方式设为 GlazeR")
            case .failure(let err):
                let msg = err.localizedDescription
                glazerDefaultApp = "设置失败：\(msg)"
                state.log("设置 .glazer 默认打开方式失败：\(msg)")
            }
            checkGlazerDefault()
        }
    }

    private func pickExecutable(_ value: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let p = panel.url?.path { value.wrappedValue = p }
    }

    private func pickDirectory(_ value: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let p = panel.url?.path { value.wrappedValue = p }
    }

    // MARK: 通用分组卡片

    private func groupBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12.5, weight: .bold)).foregroundColor(inkColor)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xECECF2), lineWidth: 1)))
    }

    // MARK: 权限卡片

    @ViewBuilder
    private var permCard: some View {
        let listen = HotkeyMonitor.listenEventAccess
        let ax = HotkeyMonitor.isTrusted
        let alive = HotkeyMonitor.shared.isEventFlowAlive()
        let variant = HotkeyMonitor.shared.tapVariant
        let _ = permTick
        groupBox("权限检测") {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("全局快捷键依赖系统「辅助功能 / 输入监控」授权")
                        .font(.system(size: 11)).foregroundColor(hintColor)
                    Spacer()
                    Button("重新检测") {
                        HotkeyMonitor.shared.restart(); permTick += 1
                    }.buttonStyle(.borderless).font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(brandColor)
                }

                HStack(spacing: 8) {
                    Image(systemName: alive ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 13))
                        .foregroundColor(alive ? Color(hex: 0x16A34A) : hintColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("监听自检").font(.system(size: 12, weight: .semibold)).foregroundColor(inkColor)
                        Text(alive ? "事件流正常，转盘可正常呼出" : "移动鼠标自动验证（几秒后更新）")
                            .font(.system(size: 10.5))
                            .foregroundColor(alive ? Color(hex: 0x16A34A) : hintColor)
                    }
                    Spacer(minLength: 0)
                }

                permRow(title: "输入监控", desc: "HID 最佳监听模式必需；后台/隐藏监听全靠它",
                        ok: listen,
                        url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                        requestListen: true)
                permRow(title: "辅助功能", desc: "Session 回退监听模式需要", ok: ax,
                        url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                        requestListen: false)

                HStack(spacing: 6) {
                    Image(systemName: variant == "HID+default" ? "checkmark.seal.fill" : "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(variant == "HID+default" ? Color(hex: 0x16A34A) : Color(hex: 0xF59E0B))
                    Text("当前监听模式：\(variant ?? "未运行")")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(subInkColor)
                    if variant == "HID+default" {
                        Text("（最佳）").font(.system(size: 11)).foregroundColor(Color(hex: 0x16A34A))
                    } else if variant != nil {
                        Text("（降级：授予输入监控后自动升级）")
                            .font(.system(size: 11)).foregroundColor(Color(hex: 0xB45309))
                    }
                }
            }
        }
    }

    private func permRow(title: String, desc: String, ok: Bool, url: String, requestListen: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(ok ? Color(hex: 0x16A34A) : Color(hex: 0xF59E0B))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(inkColor)
                Text(ok ? "已授权" : desc).font(.system(size: 10.5))
                    .foregroundColor(ok ? Color(hex: 0x16A34A) : hintColor)
            }
            Spacer(minLength: 8)
            if !ok {
                if requestListen {
                    Button("申请授权") { CGRequestListenEventAccess() }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("授权提示") {
                        HotkeyMonitor.promptAX()
                        NSWorkspace.shared.open(URL(string: url)!)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                Button("打开系统设置") { NSWorkspace.shared.open(URL(string: url)!) }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(brandColor)
            }
        }
    }

    // MARK: R 环境卡片

    @ViewBuilder
    private var envCard: some View {
        groupBox("R 环境检测") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("重新检测") { state.checkEnv() }
                        .buttonStyle(.borderless).font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(brandColor)
                    Spacer()
                }
                switch state.envState {
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在检测 R 与所用包…").font(.system(size: 11.5)).foregroundColor(hintColor)
                    }
                case .ok:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                            .foregroundColor(Color(hex: 0x16A34A))
                        Text("R 环境就绪，配置中引用的包均已安装")
                            .font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: 0x16A34A))
                    }
                case .missing(let pkgs):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                            .foregroundColor(Color(hex: 0xF59E0B))
                        Text("缺少 \(pkgs.count) 个包：\(pkgs.joined(separator: "、"))")
                            .font(.system(size: 11.5)).foregroundColor(Color(hex: 0xB45309)).lineLimit(2)
                        Spacer(minLength: 8)
                        Button("复制安装命令") {
                            let cmd = "install.packages(c(" + pkgs.map { "\"\($0)\"" }.joined(separator: ", ") + "))"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                case .failed(let msg):
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.octagon.fill").font(.system(size: 12))
                            .foregroundColor(Color(hex: 0xDC2626))
                        Text(msg).font(.system(size: 11.5)).foregroundColor(Color(hex: 0xDC2626)).lineLimit(2)
                    }
                }

                if let r = state.envReport {
                    Text("\(r.rscript) · R \(r.version)")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundColor(hintColor)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    if !r.libPaths.isEmpty {
                        Text("库路径：\(r.libPaths.joined(separator: "；"))")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(hintColor)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    let names = r.packages.keys.sorted()
                    if !names.isEmpty {
                        let rows = stride(from: 0, to: names.count, by: 4).map { Array(names[$0..<min($0 + 4, names.count)]) }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 8) {
                                    ForEach(row, id: \.self) { name in
                                        HStack(spacing: 3) {
                                            Image(systemName: r.packages[name] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(r.packages[name] == true ? Color(hex: 0x16A34A) : Color(hex: 0xDC2626))
                                            Text(name).font(.system(size: 10.5, design: .monospaced))
                                                .foregroundColor(r.packages[name] == true ? inkColor : Color(hex: 0xDC2626))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
