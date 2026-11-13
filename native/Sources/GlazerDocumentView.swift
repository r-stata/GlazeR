// GlazeR — .glazer 文档窗口：可编辑文本 + 语法高亮 + 保存 / 另存为 / 应用到转盘
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NSTextView 封装

struct GlazerTextView: NSViewRepresentable {
    @Binding var text: String
    let highlight: Bool
    let theme: GlazerSyntax.Theme
    let onSave: () -> Void
    let onDirty: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = theme.background
        scroll.autoresizingMask = [.width, .height]

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true            // 允许显示语法着色；保存时只取纯文本 string
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.font = GlazerSyntax.mono
        tv.textColor = theme.plain
        tv.backgroundColor = theme.background
        tv.insertionPointColor = theme.key
        tv.typingAttributes = [.font: GlazerSyntax.mono, .foregroundColor: theme.plain]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0,
                                                  height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = text
        tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        context.coordinator.highlight(theme: theme, enabled: highlight)

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        scroll.backgroundColor = theme.background
        tv.backgroundColor = theme.background
        tv.insertionPointColor = theme.key
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(theme: theme, enabled: highlight)
            context.coordinator.scrollToTop(scroll, tv)
        } else if context.coordinator.lastThemeID != theme.id
                    || context.coordinator.lastEnabled != highlight {
            context.coordinator.highlight(theme: theme, enabled: highlight)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GlazerTextView
        weak var textView: NSTextView?
        var lastThemeID = -1
        var lastEnabled = false
        private var isHighlighting = false
        private var monitor: Any?

        init(parent: GlazerTextView) {
            self.parent = parent
            super.init()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
                guard let self,
                      ev.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                      ev.charactersIgnoringModifiers?.lowercased() == "s",
                      let tv = self.textView, tv.window?.isKeyWindow == true else { return ev }
                self.parent.onSave()
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        func highlight(theme: GlazerSyntax.Theme, enabled: Bool) {
            guard let tv = textView, let storage = tv.textStorage, !isHighlighting else { return }
            isHighlighting = true
            let selection = tv.selectedRanges
            GlazerSyntax.apply(storage, theme: theme, enabled: enabled)
            tv.typingAttributes = [.font: GlazerSyntax.mono, .foregroundColor: theme.plain]
            tv.selectedRanges = selection
            isHighlighting = false
            lastThemeID = theme.id
            lastEnabled = enabled
        }

        /// 载入 / 重新载入 / 另存为后把光标与滚动位置都放回文件开头
        func scrollToTop(_ scroll: NSScrollView, _ tv: NSTextView) {
            let zero = NSRange(location: 0, length: 0)
            tv.selectedRanges = [NSValue(range: zero)]
            tv.scrollRangeToVisible(zero)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            // 等 AppKit 完成一次布局后再兜一次，避免窗口尺寸尚未确定时滚动失效
            DispatchQueue.main.async { [weak scroll, weak tv] in
                guard let scroll, let tv else { return }
                tv.scrollRangeToVisible(zero)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onDirty(true)
            highlight(theme: parent.theme, enabled: parent.highlight)
        }
    }
}

// MARK: - 文档编辑器窗口内容

struct GlazerDocumentEditorView: View {
    let onTitleChange: (String) -> Void
    let onCloseRequested: () -> Void

    @State private var currentURL: URL
    @State private var text = ""
    @State private var dirty = false
    @State private var status = ""
    @State private var highlightEnabled = true
    @State private var themeIndex = 0
    @State private var showHelp = false

    init(initialURL: URL,
         onTitleChange: @escaping (String) -> Void,
         onCloseRequested: @escaping () -> Void) {
        self.onTitleChange = onTitleChange
        self.onCloseRequested = onCloseRequested
        _currentURL = State(initialValue: initialURL)
    }

    private var theme: GlazerSyntax.Theme { themeIndex == 1 ? GlazerSyntax.dark : GlazerSyntax.light }
    private var lineCount: Int { text.components(separatedBy: "\n").count }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            GlazerTextView(text: $text, highlight: highlightEnabled, theme: theme,
                           onSave: { _ = save() }, onDirty: { dirty = $0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            legendBar
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(Color(nsColor: theme.background))
        .onAppear { load() }
        .sheet(isPresented: $showHelp) {
            WheelFormatHelpView(onDismiss: { showHelp = false })
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 16)).foregroundColor(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 1) {
                Text(currentURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(1)
                Text(status.isEmpty ? "GlazeR 转盘配置文件 · .glazer" : status)
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
            }
            if dirty {
                Text("● 未保存").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: 0xFDE68A))
            }
            Spacer()
            Toggle("高亮", isOn: $highlightEnabled)
                .toggleStyle(.switch).controlSize(.small)
                .foregroundColor(.white)
            Picker("", selection: $themeIndex) {
                Text("浅色").tag(0)
                Text("深色").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 100)
            Button("保存") { _ = save() }
            Button("另存为…") { saveAs() }
            Menu("更多…") {
                Button("应用到转盘…") { applyToWheels() }
                Button("重新加载文件") { reload() }
                Divider()
                Button("查看格式说明与示例…") { showHelp = true }
                Divider()
                Button("关闭窗口") { onCloseRequested() }
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(LinearGradient(
            colors: [Color(hex: 0x4338CA), Color(hex: 0x1E3A8A)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var legendBar: some View {
        HStack(spacing: 9) {
            Text("\(lineCount) 行 · \(text.count) 字符")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: theme.plain).opacity(0.7))
            Divider().frame(height: 12)
            ForEach(GlazerSyntax.legend(theme)) { item in
                HStack(spacing: 3) {
                    Circle().fill(Color(nsColor: item.color)).frame(width: 7, height: 7)
                    Text(item.title).font(.system(size: 9.5))
                        .foregroundColor(Color(nsColor: theme.plain).opacity(0.7))
                }
            }
            Spacer()
            Text(highlightEnabled ? "语法高亮已开启" : "纯文本模式")
                .font(.system(size: 9.5))
                .foregroundColor(Color(nsColor: theme.plain).opacity(0.55))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(nsColor: theme.legendBar))
    }

    // MARK: 文件操作

    private func load() {
        if let data = try? Data(contentsOf: currentURL),
           let s = String(data: data, encoding: .utf8) {
            text = s
            dirty = false
            status = "已载入 · \(s.components(separatedBy: "\n").count) 行"
        } else {
            text = WheelTextCodec.header + "\n\n【转盘】\n名称 = 新转盘\n槽位 = 1\n扇区数 = 6\n"
            dirty = true
            status = "无法读取原文件，已载入空白模板（可另存为）"
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try text.write(to: currentURL, atomically: true, encoding: .utf8)
            dirty = false
            status = "已保存 · \(Self.timeString())"
            appendGlazeLog("保存 .glazer 文件：\(currentURL.path)")
            return true
        } catch {
            status = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.title = "另存为 .glazer 配置文件"
        panel.nameFieldStringValue = currentURL.lastPathComponent
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        if let t = UTType(WheelTextCodec.typeIdentifier) {
            panel.allowedContentTypes = [t, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentURL = url
        onTitleChange(url.lastPathComponent)
        _ = save()
    }

    private func reload() {
        if dirty {
            let a = NSAlert()
            a.messageText = "有未保存的修改"
            a.informativeText = "重新加载会丢弃当前编辑内容，确定继续？"
            a.addButton(withTitle: "取消")
            a.addButton(withTitle: "重新加载")
            if a.runModal() != .alertSecondButtonReturn { return }
        }
        load()
    }

    /// 保存后交给主窗口的导入预览（替换同名 / 全部新增 / 清空后导入）
    private func applyToWheels() {
        if dirty {
            let a = NSAlert()
            a.messageText = "当前修改尚未保存"
            a.informativeText = "需要先保存文件，再用它更新转盘配置。"
            a.addButton(withTitle: "保存并应用")
            a.addButton(withTitle: "取消")
            if a.runModal() != .alertFirstButtonReturn { return }
            guard save() else { return }
        }
        AppState.shared.openWheelDocuments([currentURL])
        status = "已交给主窗口的导入预览"
    }

    private static func timeString() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

// MARK: - 文档窗口管理（同一文件只打开一个窗口）

@MainActor
final class GlazerDocumentWindows {
    static let shared = GlazerDocumentWindows()
    private var controllers: [NSWindowController] = []
    private var observers: [NSObjectProtocol] = []

    private func key(_ url: URL) -> String { "gz-doc-" + url.standardizedFileURL.path }

    func open(_ urls: [URL]) { for u in urls { openOne(u) } }

    private func openOne(_ url: URL) {
        let k = key(url)
        if let c = controllers.first(where: { $0.window?.identifier?.rawValue == k }) {
            bringToFront(c)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = url.lastPathComponent
        win.identifier = NSUserInterfaceItemIdentifier(k)
        win.minSize = NSSize(width: 680, height: 460)
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: GlazerDocumentEditorView(
            initialURL: url,
            onTitleChange: { [weak win] title in win?.title = title },
            onCloseRequested: { [weak win] in win?.close() }))
        let c = NSWindowController(window: win)
        controllers.append(c)
        let obs = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self, weak c] _ in
            Task { @MainActor [weak self, weak c] in
                guard let self, let c else { return }
                self.controllers.removeAll { $0 === c }
            }
        }
        observers.append(obs)
        bringToFront(c)
    }

    /// Finder 双击打开时 SwiftUI 的 WindowGroup 会把自己重新置前，
    /// 所以激活之后立即、并在下一轮 runloop 再抬一次文档窗口，确保它落在最前面。
    private func bringToFront(_ c: NSWindowController) {
        guard let win = c.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        c.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak win] in
            NSApp.activate(ignoringOtherApps: true)
            win?.makeKeyAndOrderFront(nil)
        }
    }
}
