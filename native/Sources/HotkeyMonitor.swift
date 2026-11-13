// GlazeR — 全局快捷键监视
// 三种呼出方式：
//   ① 按住组合键 + 拖动文件 → 转盘在光标处弹出，松手到扇区即执行（DataWheel 同款）
//   ② 在 Finder 选中文件后长按组合键 → 转盘在光标处弹出，点击扇区即执行
//   ③ 按住组合键 + 数字 0...9 → 直接呼出该槽位的转盘，并在 60 秒内锁定它
// 多套转盘可各绑不同组合键；最具体的组合优先命中，数字槽位优先级最高。
// 依赖：listen-only CGEventTap 需要系统「辅助功能 / 输入监控」权限。
import AppKit
import ApplicationServices

final class HotkeyMonitor {
    static let shared = HotkeyMonitor()

    private struct Combo {
        let flags: CGEventFlags
        let profileID: String?
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var authorized = true
    private(set) var tapVariant: String?
    private var promptedListen = false
    private var donutShown = false
    private var shownByHold = false
    private var holdWork: DispatchWorkItem?
    private var comboWasHeld = false
    private var eventCount = 0
    private var healthTimer: Timer?
    private var lastReinstallAt = Date.distantPast
    private var comboCache: [Combo] = []
    private var comboCacheAt = Date.distantPast
    private var pinnedProfileID: String?   // 数字键选中的转盘（60 秒内有效）
    private var pinnedAt = Date.distantPast

    private let activityLock = NSLock()
    private var lastEventAt = Date.distantPast

    private init() {}

    // MARK: 组合键

    private func combos() -> [Combo] {
        // 拖拽事件高频到达，缓存 1 秒，避免每次事件都读磁盘解码配置
        if !comboCache.isEmpty, Date().timeIntervalSince(comboCacheAt) < 1.0 { return comboCache }
        let cfg = GlazeConfig.load()
        var out: [Combo] = []
        for p in cfg.profiles where !p.comboFlags.isEmpty {
            let f = ModKey.flags(p.comboFlags)
            if !f.isEmpty { out.append(Combo(flags: f, profileID: p.id)) }
        }
        let def = ModKey.flags(cfg.hotkeyFlags.isEmpty ? ["option"] : cfg.hotkeyFlags)
        if !def.isEmpty { out.append(Combo(flags: def, profileID: nil)) }
        comboCache = out
        comboCacheAt = Date()
        return out
    }

    private func match(_ held: CGEventFlags) -> Combo? {
        let cs = combos()
        if let exact = cs.first(where: { $0.flags == held }) { return exact }
        return cs.filter { held.isSuperset(of: $0.flags) }
            .sorted { $0.flags.rawValue.nonzeroBitCount > $1.flags.rawValue.nonzeroBitCount }
            .first
    }

    private func profile(for combo: Combo) -> WheelProfile? {
        let cfg = GlazeConfig.load()
        if let id = pinnedProfileID, Date().timeIntervalSince(pinnedAt) < 60,
           let p = cfg.profiles.first(where: { $0.id == id }) { return p }
        guard let id = combo.profileID else { return cfg.activeProfile }
        return cfg.profiles.first { $0.id == id }
    }

    /// 主键盘与小键盘的数字键虚拟键码 → 0...9
    static func digit(for keyCode: Int64) -> Int? {
        let table: [Int64: Int] = [
            29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
            82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
        ]
        return table[keyCode]
    }

    private var heldModifiers: CGEventFlags {
        CGEvent(source: nil)?.flags.intersection(ModKey.modifierMask) ?? []
    }

    // MARK: 生命周期

    func start() {
        startHealthCheck()
        guard tap == nil else { return }
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        Self.log("start: AXTrusted=\(Self.isTrusted) ListenEvent=\(Self.listenEventAccess)")
        // 必须用 HID 层：macOS 15 起 Session 层 tap 有焦点过滤，应用隐藏时收不到拖拽事件
        let hid = CGEventTapLocation(rawValue: 0)!
        let session = CGEventTapLocation(rawValue: 1)!
        let attempts: [(String, CGEventTapLocation, CGEventTapOptions)] = [
            ("HID+default", hid, .defaultTap),
            ("HID+listenOnly", hid, .listenOnly),
            ("Session+listenOnly", session, .listenOnly),
        ]
        var port: CFMachPort?
        var used = ""
        for (label, loc, opt) in attempts {
            port = CGEvent.tapCreate(tap: loc, place: .headInsertEventTap, options: opt,
                                     eventsOfInterest: eventMask, callback: Self.tapCallback,
                                     userInfo: Unmanaged.passUnretained(self).toOpaque())
            if port != nil { used = label; break }
            Self.log("start: tapCreate FAILED (\(label))")
        }
        guard let port else {
            authorized = false
            Self.log("start: 所有 tap 层级均创建失败（检查辅助功能/输入监控权限）")
            return
        }
        Self.log("start: tap created & enabled (\(used))")
        authorized = true
        tapVariant = used
        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        if used != "HID+default", !Self.listenEventAccess, !promptedListen {
            promptedListen = true
            Self.log("start: 请求「输入监控」权限")
            CGRequestListenEventAccess()
        }
    }

    static var listenEventAccess: Bool { CGPreflightListenEventAccess() }
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
    }

    static func log(_ s: String) {
        let url = GlazeConfig.dir.appendingPathComponent("hotkey.log")
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(s)\n"
        guard let d = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); try? fh.write(contentsOf: d); try? fh.close()
        } else { try? d.write(to: url) }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        }
        tap = nil
        runLoopSource = nil
        cancelHold()
    }

    func reinstall() { lastReinstallAt = Date(); stop(); start() }
    func restart() { comboCacheAt = .distantPast; stop(); start() }

    private func startHealthCheck() {
        guard healthTimer == nil else { return }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let tap = self.tap else {
                if Self.isTrusted { self.start() }
                return
            }
            if self.tapVariant != "HID+default", Self.listenEventAccess {
                Self.log("health: 「输入监控」已授权，升级为 HID+defaultTap")
                self.reinstall(); return
            }
            guard !CGEvent.tapIsEnabled(tap: tap) else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                Self.log("health: tap 已恢复")
            } else if Date().timeIntervalSince(self.lastReinstallAt) > 3 {
                Self.log("health: tapEnable 未生效，重建 tap")
                self.reinstall()
            }
        }
        healthTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    @discardableResult
    static func promptAX() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    // MARK: 事件流自检

    func noteActivity() {
        activityLock.lock(); lastEventAt = Date(); activityLock.unlock()
    }

    func isEventFlowAlive(within: TimeInterval = 20) -> Bool {
        activityLock.lock(); let t = lastEventAt; activityLock.unlock()
        return tap != nil && Date().timeIntervalSince(t) < within
    }

    // MARK: 长按呼出

    private func cancelHold() { holdWork?.cancel(); holdWork = nil }

    private func scheduleHold(_ combo: Combo) {
        cancelHold()
        let delay = max(0.15, min(2.0, GlazeConfig.load().holdDelay))
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.donutShown else { return }
            self.donutShown = true
            self.shownByHold = true
            let paths = Self.finderSelection()
            Self.log("hold: showHold paths=\(paths.count) combo=\(combo.flags.rawValue)")
            let pt = NSEvent.mouseLocation
            WheelPanel.shared.showHold(paths: paths, at: pt, profile: self.profile(for: combo))
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 读取 Finder 当前选中的文件（AppleScript，失败静默回退为拖放模式）
    static func finderSelection() -> [String] {
        let src = """
        tell application "Finder"
            set sel to selection as alias list
            set out to {}
            repeat with f in sel
                set end of out to POSIX path of f
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let script = NSAppleScript(source: src) else { return [] }
        let desc = script.executeAndReturnError(&err)
        if err != nil || desc.numberOfItems == 0 { return [] }
        var paths: [String] = []
        for i in 1...desc.numberOfItems {
            if let s = desc.atIndex(i)?.stringValue, !s.isEmpty { paths.append(s) }
        }
        return paths
    }

    // MARK: 事件回调

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let monitor = userInfo.map({ Unmanaged<HotkeyMonitor>.fromOpaque($0).takeUnretainedValue() }) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .mouseMoved {
            monitor.noteActivity()
            return Unmanaged.passUnretained(event)
        }
        monitor.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        DispatchQueue.main.async { self.process(type: type, event: event) }
    }

    private func process(type: CGEventType, event: CGEvent) {
        if eventCount < 5 {
            eventCount += 1
            Self.log("event #\(eventCount): \(type.rawValue) flags=\(event.flags.rawValue)")
        }
        let held = event.flags.intersection(ModKey.modifierMask)
        let combo = match(held)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, let tap = self.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
                    Self.log("tap 重新启用无效，重建"); self.reinstall()
                }
                Self.log("tap disabled (\(type.rawValue)), re-enabled")
            }
            return

        case .leftMouseDragged:
            guard combo != nil else { return }
            cancelHold()
            comboWasHeld = true
            guard !donutShown else { return }
            donutShown = true
            shownByHold = false
            Self.log("dragged+mod: showHotkey at \(NSEvent.mouseLocation)")
            WheelPanel.shared.showHotkey(at: NSEvent.mouseLocation, profile: profile(for: combo!))

        case .leftMouseUp:
            cancelHold()
            guard donutShown, !shownByHold else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.donutShown, !self.shownByHold else { return }
                if WheelModel.shared.busyCount == 0 { WheelPanel.shared.hide() }
                self.donutShown = false
            }

        case .keyDown:
            // 按住组合键 + 数字 → 直接呼出该槽位的转盘
            guard combo != nil else { return }
            guard let digit = Self.digit(for: event.getIntegerValueField(.keyboardEventKeycode)) else { return }
            let cfg = GlazeConfig.load()
            guard let p = cfg.profiles.first(where: { $0.slot == digit }) else {
                Self.log("digit \(digit): 该槽位未分配转盘")
                return
            }
            cancelHold()
            pinnedProfileID = p.id
            pinnedAt = Date()
            donutShown = true
            shownByHold = true
            let paths = Self.finderSelection()
            Self.log("digit \(digit): show \(p.name) paths=\(paths.count)")
            WheelPanel.shared.showHold(paths: paths, at: NSEvent.mouseLocation, profile: p)

        case .flagsChanged:
            let isHeld = combo != nil
            if isHeld && !comboWasHeld {
                comboWasHeld = true
                cancelHold()
                if GlazeConfig.load().enableHoldTrigger, !donutShown {
                    scheduleHold(combo!)   // 长按组合键 → 呼出转盘（Finder 选中文件）
                }
            } else if !isHeld && comboWasHeld {
                comboWasHeld = false
                cancelHold()
                if donutShown {
                    if shownByHold {
                        // 长按呼出的转盘保持可见，由点击扇区 / 点击别处 / Esc 关闭
                        shownByHold = false
                        donutShown = false
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            guard let self, self.donutShown else { return }
                            if WheelModel.shared.busyCount == 0 { WheelPanel.shared.hide() }
                            self.donutShown = false
                        }
                    }
                }
            }

        default:
            break
        }
    }
}
