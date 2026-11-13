// GlazeR — 主界面：侧边栏 + 首页拖放卡片 + 当前转盘概览 + 运行日志
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 210)
            Rectangle().fill(lineColor).frame(width: 1)
            ZStack(alignment: .top) {
                Group {
                    switch state.page {
                    case .home: HomeView()
                    case .editor: WheelEditorView()
                    case .logs: LogsView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 1200, minHeight: 740)
        .background(canvasColor)
        .background(DropTargetNSView())
        .overlay(alignment: .top) { EnvBanner().padding(.top, 8) }
        .overlay(ToastsView().zIndex(20))
        .background(MainWindowTagger())
    }
}

// MARK: - 主窗口标识

struct MainWindowTagger: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.identifier = NSUserInterfaceItemIdentifier("gz-main")
            w.isReleasedWhenClosed = false
            Self.ensureReadableSize(w)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// SwiftUI 的 defaultSize 只在窗口「首次创建」时生效，系统会恢复上次的
    /// 小 frame。编辑器有三栏 + 两行工具条 + 批量/输出区，旧 frame 会把
    /// 底部内容压出可视区。这里在每次进程启动后做一次性兜底：明显偏小时
    /// 放大到 1320×880（不超过屏幕可见区域），用户之后手动调整不会被覆盖。
    private static var didEnsure = false
    private static let minWidth: CGFloat = 1320
    private static let minHeight: CGFloat = 880

    private static func ensureReadableSize(_ w: NSWindow) {
        guard !didEnsure else { return }
        didEnsure = true
        let visible = (w.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: minWidth, height: minHeight)
        let targetW = min(minWidth, visible.width)
        let targetH = min(minHeight, visible.height)
        var f = w.frame
        guard f.width < targetW - 1 || f.height < targetH - 1 else { return }
        f.size.width = max(f.size.width, targetW)
        f.size.height = max(f.size.height, targetH)
        f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.size.width)
        f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.size.height)
        w.setFrame(f, display: true, animate: false)
    }
}

// MARK: - 侧边栏

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                WheelGlyph().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("GlazeR").font(.system(size: 16, weight: .bold)).foregroundColor(inkColor)
                    Text("Drop a file, run your code · R / Python / Stata")
                        .font(.system(size: 9.5)).foregroundColor(hintColor).lineLimit(1)
                }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 18)

            ForEach(AppState.Page.allCases) { p in
                SidebarItem(icon: p.icon, title: p.title, active: state.page == p) {
                    state.page = p
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text("当前转盘").font(.system(size: 10.5, weight: .semibold)).foregroundColor(hintColor)
                Text(state.config.activeProfile.name)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(inkColor)
                    .lineLimit(1)
                Text("\(state.config.activeProfile.sliceCount) 个扇区 · \(state.config.profiles.count) 套转盘")
                    .font(.system(size: 10.5)).foregroundColor(hintColor)
                Divider()
                Text("Version 1.0 · 本地执行 R / Python / Stata\n数据不上传\n开发：")
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: 0xA6AEBC))
                Link("微信公众号 RStata", destination: URL(string: "https://tidyfriday.cn/")!)
                    .font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: 0x7C6FD0))
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(Color(hex: 0xFBFBFD))
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(active ? brandColor : subInkColor).frame(width: 18)
                Text(title).font(.system(size: 13.5, weight: active ? .semibold : .regular))
                    .foregroundColor(inkColor)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(active ? Color(hex: 0xEEEBFB) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 10)
    }
}

struct WheelGlyph: View {
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { idx in
                Circle().trim(from: 0, to: 0.11)
                    .stroke(idx % 2 == 0 ? brandColor : brandColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90 + Double(idx) * 60))
            }
            Circle().fill(Color.white).frame(width: 10, height: 10)
                .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
        }
        .modifier(SlowSpin())
    }
}

struct SlowSpin: ViewModifier {
    @State private var spinning = false
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - 首页

struct HomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("首页").font(.system(size: 26, weight: .bold)).foregroundColor(inkColor)
                    .padding(.top, 24)

                dropzone
                activeWheel
                recentsHeader
                recents
            }
            .padding(.horizontal, 28).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropzone: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(brandColor).frame(width: 54, height: 54)
                Image(systemName: "arrow.up").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            }
            Text("拖放文件到这里").font(.system(size: 17, weight: .bold)).foregroundColor(inkColor)
            Text("把文件拖入窗口任意位置，转盘在光标处弹出 — 松手到目标扇区，即以该文件为参数执行对应的 R / Python / Stata 函数或代码")
                .font(.system(size: 12.5)).foregroundColor(hintColor).multilineTextAlignment(.center)
            Text("也可以在 Finder 选中文件后按住 \(ModKey.comboLabel(state.config.hotkeyFlags)) 拖动，或长按组合键直接呼出转盘")
                .font(.system(size: 11.5)).foregroundColor(Color(hex: 0xA6AEBC))
            Button("或点按选择文件") { chooseFiles() }
                .buttonStyle(.borderless).font(.system(size: 12.5, weight: .medium))
                .foregroundColor(brandColor).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(RoundedRectangle(cornerRadius: 18).fill(brandSoft)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(brandBorder, lineWidth: 1.5)))
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            WheelPanel.shared.showClick(paths: panel.urls.map { $0.path })
        }
    }

    private var activeWheel: some View {
        let p = state.config.activeProfile
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("当前转盘").font(.system(size: 15, weight: .bold)).foregroundColor(inkColor)
                Text(p.name).font(.system(size: 12.5, weight: .medium)).foregroundColor(brandColor)
                Spacer()
                Button("编辑转盘…") { state.page = .editor }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundColor(brandColor)
            }
            HStack(spacing: 7) {
                ForEach(Array(p.slices.prefix(p.sliceCount))) { s in
                    HStack(spacing: 5) {
                        Circle().fill(s.swiftColor).frame(width: 8, height: 8)
                        Text(s.label).font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(s.isConfigured ? inkColor : hintColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(lineColor, lineWidth: 1))
                }
            }
            Text("快捷键：\(ModKey.comboLabel(p.comboFlags.isEmpty ? state.config.hotkeyFlags : p.comboFlags)) · \(p.sliceCount) 个扇区 · 每格可绑定独立的 R / Python / Stata 动作与默认参数")
                .font(.system(size: 11)).foregroundColor(hintColor)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0xECECF2), lineWidth: 1)))
    }

    private var recentsHeader: some View {
        HStack {
            Text("最近运行").font(.system(size: 16, weight: .bold)).foregroundColor(inkColor)
            Spacer()
            if !state.recents.isEmpty {
                Button("清空") { state.clearRecents() }.buttonStyle(.borderless)
                    .font(.system(size: 12.5)).foregroundColor(brandColor)
            }
        }
    }

    private var recents: some View {
        Group {
            if state.recents.isEmpty {
                Text("运行过的任务会显示在这里")
                    .font(.system(size: 12.5)).foregroundColor(Color(hex: 0xA6AEBC))
            } else {
                VStack(spacing: 6) {
                    ForEach(state.recents.prefix(12)) { r in RecentRow(item: r) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct RecentRow: View {
    let item: RunRecord

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(item.ok ? Color(hex: 0xE8F7EE) : Color(hex: 0xFDECEC))
                    .frame(width: 30, height: 30)
                Image(systemName: item.ok ? "checkmark" : "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(item.ok ? Color(hex: 0x16A34A) : Color(hex: 0xDC2626))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text((item.input as NSString).lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium)).foregroundColor(inkColor)
                    .lineLimit(1).truncationMode(.middle)
                Text(item.message).font(.system(size: 11)).foregroundColor(hintColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.action).font(.system(size: 11, weight: .medium)).foregroundColor(brandColor)
            Text(item.time, style: .time).font(.system(size: 11)).foregroundColor(hintColor)
            if !item.output.isEmpty {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.output)]) } label: {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundColor(brandColor)
                }.buttonStyle(.borderless).help("在 Finder 中显示输出")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(hex: 0xECECF2), lineWidth: 1)))
    }
}

// MARK: - 运行日志

struct LogsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("运行日志").font(.system(size: 24, weight: .bold)).foregroundColor(inkColor)
                Spacer()
                Button("清空日志") { state.clearLogs() }.buttonStyle(.borderless)
                    .font(.system(size: 12)).foregroundColor(brandColor)
                Button("打开日志目录") {
                    NSWorkspace.shared.activateFileViewerSelecting([GlazeConfig.logURL])
                }.buttonStyle(.borderless).font(.system(size: 12)).foregroundColor(brandColor)
            }
            .padding(.top, 24)

            Text("运行输出、警告与错误信息会保留在这里；完整日志写入 ~/Library/Application Support/GlazeR/glazer.log")
                .font(.system(size: 11.5)).foregroundColor(hintColor)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("控制台").font(.system(size: 13, weight: .semibold)).foregroundColor(subInkColor)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(state.logLines, id: \.self) { line in
                                Text(verbatim: line).font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(hex: 0x334155)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineColor, lineWidth: 1)))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("最近任务的输出").font(.system(size: 13, weight: .semibold)).foregroundColor(subInkColor)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if state.recents.filter({ !$0.log.isEmpty }).isEmpty {
                                Text("暂无输出").font(.system(size: 11.5)).foregroundColor(hintColor)
                            }
                            ForEach(state.recents.filter { !$0.log.isEmpty }.prefix(20)) { r in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(r.action).font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(brandColor)
                                        Spacer()
                                        Text(r.time, style: .time).font(.system(size: 10.5))
                                            .foregroundColor(hintColor)
                                    }
                                    Text(verbatim: r.log).font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(Color(hex: 0x334155)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lineColor, lineWidth: 1)))
                            }
                        }.padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xFAFAFD))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineColor, lineWidth: 1)))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 28).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
