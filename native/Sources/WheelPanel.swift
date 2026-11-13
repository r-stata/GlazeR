// GlazeR — 浮动转盘：Filee 式白色圆盘楔形扇区，扇区数量与内容全部由用户配置
// 三种入口：窗口内拖放（面板不接收鼠标）/ 全局快捷键拖放（面板直接接收 Finder 拖放）/ 点击扇区
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WheelMode { case drag, click }

// MARK: - 转盘状态（独立于主窗口状态）

final class WheelModel: ObservableObject {
    static let shared = WheelModel()
    @Published var mode: WheelMode = .drag
    @Published var hotIndex = -1
    @Published var fileCount = 0
    @Published var busyCount = 0
    @Published var lastDetail: String?
    @Published var profile: WheelProfile = WheelProfile.demo().normalized
    var pendingPaths: [String] = []
}

// MARK: - 浮动面板

final class WheelPanel: NSPanel {
    static let shared = WheelPanel()
    static let side: CGFloat = WheelGeometry.size + 32

    private var clickOutsideMonitor: Any?
    private var escMonitor: Any?
    private var lastDragPoint: CGPoint = .zero
    private var dragAnchor: CGPoint = .zero
    private var hideWorkItem: DispatchWorkItem?

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func installContent(acceptsDrops: Bool) {
        let hosting = NSHostingView(rootView: WheelContent(model: WheelModel.shared))
        if acceptsDrops {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
            let drop = PanelDropTarget(frame: container.bounds)
            hosting.frame = container.bounds
            drop.autoresizingMask = [.width, .height]
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(drop)
            container.addSubview(hosting)
            contentView = container
        } else {
            contentView = hosting
        }
    }

    private func unhideAppIfNeeded() {
        guard NSApp.isHidden else { return }
        NSApp.unhide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isVisible else { return }
            self.orderFrontRegardless()
        }
    }

    private func prepare(profile: WheelProfile) {
        let m = WheelModel.shared
        m.profile = profile.normalized
        m.hotIndex = -1
        m.lastDetail = nil
        m.pendingPaths = []
        setContentSize(NSSize(width: Self.side, height: Self.side))
        lastDragPoint = .zero
        cancelHide()
    }

    /// 窗口内拖放：锚定在拖入点
    func showDrag(count: Int, at screenPoint: CGPoint, limit: CGRect? = nil,
                  profile: WheelProfile? = nil) {
        unhideAppIfNeeded()
        let m = WheelModel.shared
        m.mode = .drag
        m.fileCount = max(count, 1)
        prepare(profile: profile ?? AppState.shared.config.activeProfile)
        ignoresMouseEvents = true
        removeMonitor()
        installContent(acceptsDrops: false)
        dragAnchor = screenPoint
        place(center: screenPoint, limit: limit)
        orderFrontRegardless()
    }

    /// 全局快捷键拖放：在光标处弹出，面板直接接收 Finder 拖放
    func showHotkey(at screenPoint: CGPoint, profile: WheelProfile? = nil) {
        unhideAppIfNeeded()
        let m = WheelModel.shared
        m.mode = .drag
        m.fileCount = 1
        prepare(profile: profile ?? AppState.shared.config.activeProfile)
        ignoresMouseEvents = false
        removeMonitor()
        installContent(acceptsDrops: true)
        dragAnchor = screenPoint
        place(center: screenPoint)
        orderFrontRegardless()
    }

    /// 点击模式（服务菜单 / 选择文件 / Dock 拖放）
    func showClick(paths: [String], at screenPoint: CGPoint? = nil, profile: WheelProfile? = nil) {
        unhideAppIfNeeded()
        let m = WheelModel.shared
        m.mode = .click
        m.fileCount = max(paths.count, 1)
        prepare(profile: profile ?? AppState.shared.config.activeProfile)
        m.pendingPaths = paths
        ignoresMouseEvents = false
        installContent(acceptsDrops: false)
        let pt = screenPoint ?? {
            let f = NSScreen.main?.visibleFrame ?? .zero
            return CGPoint(x: f.midX, y: f.midY)
        }()
        place(center: pt)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
    }

    /// 长按组合键呼出：有 Finder 选中文件 → 点击扇区执行；无选中 → 拖文件到扇区执行
    func showHold(paths: [String], at screenPoint: CGPoint, profile: WheelProfile? = nil) {
        unhideAppIfNeeded()
        let m = WheelModel.shared
        m.mode = paths.isEmpty ? .drag : .click
        m.fileCount = max(paths.count, 1)
        prepare(profile: profile ?? AppState.shared.config.activeProfile)
        m.pendingPaths = paths
        ignoresMouseEvents = false
        installContent(acceptsDrops: paths.isEmpty)
        place(center: screenPoint)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 无选中文件时要允许用户回到 Finder 拖文件进来，故不装「点击外部即关闭」监听，
        // 改为超时自动关闭（拖入或任务开始时会自动取消）
        installDismissMonitors(clickOutside: !paths.isEmpty)
        if paths.isEmpty { scheduleAutoHide(after: 15) }
    }

    private func installDismissMonitors(clickOutside: Bool = true) {
        removeMonitor()
        if clickOutside {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
        }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
            if ev.keyCode == 53 { self?.hide(); return nil }   // Esc 关闭转盘
            return ev
        }
    }

    private func scheduleAutoHide(after seconds: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// 外部拖入 / 用户交互时取消自动关闭
    func noteUserInteraction() { cancelHide() }

    func moveDrag(to screenPoint: CGPoint, limit: CGRect? = nil) {
        guard isVisible else { return }
        let moved = abs(screenPoint.x - lastDragPoint.x) + abs(screenPoint.y - lastDragPoint.y)
        guard moved >= 2 else { return }
        lastDragPoint = screenPoint
        let nx = max(-14, min(14, (screenPoint.x - dragAnchor.x) * 0.08))
        let ny = max(-14, min(14, (screenPoint.y - dragAnchor.y) * 0.08))
        let center = place(center: CGPoint(x: dragAnchor.x + nx, y: dragAnchor.y + ny), limit: limit)
        let offset = CGPoint(x: screenPoint.x - center.x, y: center.y - screenPoint.y)
        WheelModel.shared.hotIndex = WheelGeometry.sectorIndex(
            offset: offset, count: WheelModel.shared.profile.sliceCount)
    }

    // MARK: 进度反馈

    func jobStarted() {
        WheelModel.shared.busyCount += 1
        cancelHide()
    }

    func jobFinished(detail: String) {
        let m = WheelModel.shared
        m.busyCount = max(0, m.busyCount - 1)
        m.lastDetail = detail
        if m.busyCount == 0, isVisible {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
        }
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
        removeMonitor()
        cancelHide()
        WheelModel.shared.hotIndex = -1
        WheelModel.shared.busyCount = 0
    }

    private func cancelHide() { hideWorkItem?.cancel(); hideWorkItem = nil }

    private func removeMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }

    @discardableResult
    private func place(center pt: CGPoint, limit: CGRect? = nil) -> CGPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        var f = screen.visibleFrame
        if let limit { f = f.intersection(limit) }
        let half = Self.side / 2
        let x = min(max(pt.x - half, f.minX + 4), f.maxX - Self.side - 4)
        let y = min(max(pt.y - half, f.minY + 4), f.maxY - Self.side - 4)
        setFrameOrigin(CGPoint(x: x, y: y))
        return CGPoint(x: x + half, y: y + half)
    }
}

// MARK: - 拖放命中后统一派发

private func dispatchDrop(_ paths: [String], _ index: Int) {
    guard !paths.isEmpty else { return }
    let m = WheelModel.shared
    guard index >= 0, index < m.profile.sliceCount else { WheelPanel.shared.hide(); return }
    m.hotIndex = -1
    AppState.shared.run(paths: paths, sliceIndex: index, profileID: m.profile.id)
}

// MARK: - 面板自身拖放目标（快捷键拖放模式）

final class PanelDropTarget: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 不支持") }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func updateHot(_ sender: NSDraggingInfo) {
        let loc = convert(sender.draggingLocation, from: nil)
        let o = CGPoint(x: loc.x - bounds.midX, y: bounds.midY - loc.y)
        WheelModel.shared.hotIndex = WheelGeometry.sectorIndex(
            offset: o, count: WheelModel.shared.profile.sliceCount)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        WheelPanel.shared.noteUserInteraction()
        updateHot(sender); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateHot(sender); return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { WheelModel.shared.hotIndex = -1 }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dispatchDrop(fileURLs(sender).map { $0.path }.filter { !$0.isEmpty },
                     WheelModel.shared.hotIndex)
        return true
    }
}

// MARK: - 主窗口拖放目标

struct DropTargetNSView: NSViewRepresentable {
    func makeNSView(context: Context) -> FileDropTarget { FileDropTarget() }
    func updateNSView(_ view: FileDropTarget, context: Context) {}
}

final class FileDropTarget: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 不支持") }

    private func hasFiles(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true])
    }
    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    private func screenPoint(_ sender: NSDraggingInfo) -> CGPoint {
        let loc = convert(sender.draggingLocation, from: nil)
        return window?.convertToScreen(NSRect(origin: loc, size: .zero)).origin ?? NSEvent.mouseLocation
    }
    private func windowLimit() -> CGRect? {
        guard let w = window else { return nil }
        return w.convertToScreen(w.contentLayoutRect)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else { return [] }
        WheelPanel.shared.showDrag(count: max(fileURLs(sender).count, 1),
                                   at: screenPoint(sender), limit: windowLimit())
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard WheelPanel.shared.isVisible else { return hasFiles(sender) ? .copy : [] }
        WheelPanel.shared.moveDrag(to: screenPoint(sender), limit: windowLimit())
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { WheelPanel.shared.hide() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dispatchDrop(fileURLs(sender).map { $0.path }.filter { !$0.isEmpty },
                     WheelModel.shared.hotIndex)
        return true
    }
}

// MARK: - 转盘内容

struct WheelContent: View {
    @ObservedObject var model: WheelModel
    @State private var appeared = false

    var body: some View {
        ZStack {
            WheelCoreView(profile: model.profile, hotIndex: model.hotIndex,
                          mode: model.mode, fileCount: model.fileCount,
                          busyCount: model.busyCount, lastDetail: model.lastDetail)
            if model.mode == .click { sectorButtons }
        }
        .frame(width: WheelPanel.side, height: WheelPanel.side)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { appeared = true } }
        .onTapGesture { if model.mode == .click { WheelPanel.shared.hide() } }
    }

    private var sectorButtons: some View {
        ZStack {
            ForEach(0..<model.profile.sliceCount, id: \.self) { idx in
                Button {
                    guard model.mode == .click, !model.pendingPaths.isEmpty else { return }
                    let paths = model.pendingPaths
                    WheelPanel.shared.hide()
                    AppState.shared.run(paths: paths, sliceIndex: idx, profileID: model.profile.id)
                } label: {
                    let hit = WheelGeometry.sectorPath(index: idx, count: model.profile.sliceCount)
                    hit.fill(Color.white.opacity(0.001)).contentShape(hit)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
    }
}

/// 可复用的转盘核心（浮动面板与编辑器预览共用）
struct WheelCoreView: View {
    let profile: WheelProfile
    let hotIndex: Int
    let mode: WheelMode
    let fileCount: Int
    let busyCount: Int
    let lastDetail: String?
    var hover: ((CGPoint?) -> Void)? = nil

    private var count: Int { profile.sliceCount }
    private var slices: [SliceConfig] { profile.normalized.slices }

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
                .shadow(color: Color.black.opacity(0.16), radius: 16, y: 5)
                .overlay(Circle().stroke(Color(hex: 0xE4E4EA), lineWidth: 1.5))

            ForEach(0..<count, id: \.self) { idx in
                let hot = hotIndex == idx
                WheelGeometry.sectorPath(index: idx, count: count)
                    .fill(hot ? slice(idx).swiftColor.opacity(0.16) : Color.clear)
                    .animation(.easeOut(duration: 0.12), value: hot)
            }

            ForEach(0..<count, id: \.self) { idx in
                WheelGeometry.sectorPath(index: idx, count: count)
                    .stroke(Color(hex: 0xE4E4EA), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }

            ForEach(0..<count, id: \.self) { idx in
                let s = slice(idx)
                let hot = hotIndex == idx
                let rad = WheelGeometry.midAngle(index: idx, count: count) * .pi / 180
                let labelR = (WheelGeometry.hubRadius + WheelGeometry.radius) / 2
                VStack(spacing: 2) {
                    Text(verbatim: s.label)
                        .font(.system(size: count > 8 ? 10 : (s.label.count > 7 ? 10.5 : 12.5), weight: .bold))
                        .foregroundColor(hot ? s.swiftColor : (s.enabled ? inkColor : hintColor))
                        .lineLimit(1)
                    if count <= 8, !s.detail.isEmpty {
                        Text(verbatim: s.detail)
                            .font(.system(size: 8.5))
                            .foregroundColor(Color(hex: 0x9AA3B0))
                            .lineLimit(1)
                    }
                }
                .frame(width: count > 8 ? 62 : 82)
                .position(x: WheelGeometry.center.x + cos(rad) * labelR,
                          y: WheelGeometry.center.y + sin(rad) * labelR)
                .opacity(s.enabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.12), value: hot)
            }

            hub.frame(width: WheelGeometry.hubRadius * 2, height: WheelGeometry.hubRadius * 2)
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
        .onContinuousHover { phase in
            guard let hover else { return }
            switch phase {
            case .active(let loc):
                hover(CGPoint(x: loc.x - WheelGeometry.size / 2, y: loc.y - WheelGeometry.size / 2))
            case .ended:
                hover(nil)
            }
        }
    }

    private func slice(_ i: Int) -> SliceConfig {
        i >= 0 && i < slices.count ? slices[i] : SliceConfig.blank(index: max(i, 0))
    }

    private var hub: some View {
        ZStack {
            Circle().fill(Color.white)
                .overlay(Circle().stroke(Color(hex: 0xE4E4EA), lineWidth: 1.5))

            if busyCount > 0 {
                VStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("执行中…").font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(subInkColor)
                }
            } else if hotIndex >= 0, hotIndex < count {
                let s = slice(hotIndex)
                VStack(spacing: 3) {
                    Text(verbatim: s.label)
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundColor(s.swiftColor)
                        .lineLimit(1)
                    Text(verbatim: s.isConfigured
                         ? (s.mode == .call ? s.function : "自定义 \(s.engine.shortTitle) 代码")
                         : "尚未配置")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(hintColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(mode == .drag ? "松开执行" : "点击执行")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(brandColor)
                }
                .padding(.horizontal, 8)
            } else if let detail = lastDetail {
                VStack(spacing: 3) {
                    Image(systemName: detail.contains("失败") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(detail.contains("失败") ? Color(hex: 0xDC2626) : Color(hex: 0x16A34A))
                    Text(verbatim: detail).font(.system(size: 10))
                        .foregroundColor(hintColor).lineLimit(2).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 10)
            } else {
                VStack(spacing: 1) {
                    Text("\(fileCount)")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundColor(inkColor)
                    Text("个文件").font(.system(size: 10.5)).foregroundColor(hintColor)
                }
            }
        }
    }
}
