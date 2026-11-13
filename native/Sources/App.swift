// GlazeR — App 入口：主窗口 + 菜单栏常驻 + 服务菜单 + Dock 拖放
import AppKit
import SwiftUI

@MainActor
func findMainWindow() -> NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue == "gz-main" }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        HotkeyMonitor.shared.start()

        GlazeRDocument.ensureDefaultOnLaunch()
        applyDebugHooks()
    }

    /// 开发态调试开关（defaults write com.rstata.glazer <key> <value>）
    ///   gzOpenPageOnLaunch  : home | editor | logs | settings
    ///   gzShowWheelOnLaunch : YES —— 启动时在屏幕中心展示转盘
    ///   gzRunOnLaunch       : 文件路径 —— 启动时用当前转盘第 1 个扇区执行一次
    private func applyDebugHooks() {
        let d = UserDefaults.standard
        if let page = d.string(forKey: "gzOpenPageOnLaunch") {
            AppState.shared.page = AppState.Page(rawValue: page) ?? .home
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if d.bool(forKey: "gzShowWheelOnLaunch") {
                WheelPanel.shared.showClick(paths: [], at: nil)
            }
            if let p = d.string(forKey: "gzRunOnLaunch"), !p.isEmpty {
                AppState.shared.run(paths: [p], sliceIndex: 0)
            }
        }
    }

    /// 右键文件 → 服务 → 用 GlazeR 处理
    @objc func glazeService(_ pboard: NSPasteboard, userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var paths = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []
        if paths.isEmpty {
            let urls = pboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            paths = urls.map { $0.path }
        }
        guard !paths.isEmpty else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            WheelPanel.shared.showClick(paths: paths, at: NSEvent.mouseLocation)
        }
    }

    /// Dock 拖放 / Finder 双击打开。.glazer 用可编辑、带语法高亮的文档窗口打开；其余文件走转盘
    func application(_ application: NSApplication, open urls: [URL]) {
        let wheelURLs = urls.filter { WheelTextCodec.isGlazerFile($0) }
        if !wheelURLs.isEmpty { GlazerDocumentWindows.shared.open(wheelURLs) }

        let dataURLs = urls.filter { !WheelTextCodec.isGlazerFile($0) }.map { $0.path }
        guard !dataURLs.isEmpty else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            WheelPanel.shared.showClick(paths: dataURLs, at: NSEvent.mouseLocation)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let w = findMainWindow() { w.makeKeyAndOrderFront(nil); return false }
        return true
    }
}

@main
struct GlazeRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup("GlazeR", id: "main") {
            ContentView().environmentObject(state)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // 编辑器有三栏 + 两行工具条，默认窗口给足尺寸，避免刚打开时内容被裁掉
        .defaultSize(width: 1320, height: 880)

        MenuBarExtra {
            MenuBarMenu(state: state)
        } label: {
            if let img = Self.menubarImage() {
                Image(nsImage: img)
            } else {
                Image(systemName: "circle.grid.2x2.fill")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    static func menubarImage() -> NSImage? {
        let url: URL? = Bundle.main.url(forResource: "menubar", withExtension: "png")
            ?? Bundle.main.url(forResource: "menubar", withExtension: "png", subdirectory: "Resources")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }
}

struct MenuBarMenu: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 GlazeR") { ensureWindow() }.keyboardShortcut("o")

        Divider()

        Menu {
            ForEach(state.config.profiles) { p in
                Button {
                    state.setActiveProfile(p.id)
                } label: {
                    HStack {
                        Text(p.name)
                        if p.id == state.config.activeProfileId { Text("✓") }
                    }
                }
            }
            Divider()
            Button("打开转盘编辑器…") {
                state.page = .editor
                ensureWindow()
            }
        } label: {
            Text("当前转盘：\(state.config.activeProfile.name)")
        }

        Divider()

        Menu {
            if state.recents.isEmpty {
                Text("暂无记录")
            } else {
                ForEach(state.recents.filter { !$0.output.isEmpty }.prefix(6)) { r in
                    Button((r.output as NSString).lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.output)])
                    }
                }
            }
        } label: { Text("最近输出") }

        Divider()

        Button("设置…") {
            state.page = .settings
            ensureWindow()
        }

        Button("关于 GlazeR") { NSApp.orderFrontStandardAboutPanel(options: [:]) }
        Button("退出 GlazeR") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func ensureWindow() {
        if let w = findMainWindow() {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.async {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
