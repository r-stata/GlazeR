// GlazeR — 转盘编辑器：转盘组管理、扇区数量、每个扇区的 R / Python / Stata 动作 / 默认参数 / 输出 / 配色
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WheelEditorView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedProfileID: String = ""
    @State private var draft: WheelProfile = WheelProfile.demo().normalized
    @State private var selectedSlice = 0
    @State private var hoverIndex = -1
    @State private var loaded = false
    @State private var pendingImport: WheelImportRequest? = nil
    @State private var showFormatHelp = false
    @State private var statusText = ""
    @State private var statusIsError = false

    private var safeIndex: Int { min(max(selectedSlice, 0), max(draft.slices.count - 1, 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("转盘编辑器")
                .font(.system(size: 24, weight: .bold)).foregroundColor(inkColor)
                .padding(.top, 22)

            Text("创建最多 10 套转盘，自由设定扇区数量、每个扇区的执行引擎（R / Python / Stata）、函数或代码与默认参数；文件路径会自动解析并注入。")
                .font(.system(size: 11.5)).foregroundColor(hintColor)

            toolbar
            Divider()

            HStack(alignment: .top, spacing: 14) {
                leftColumn.frame(width: 238)
                middleColumn.frame(maxWidth: .infinity)
                rightColumn.frame(width: 250)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !loaded { loaded = true; loadActive() }
            consumeExternalImports()   // 冷启动双击 .glazer 文件：视图就绪后再消费
        }
        .onChange(of: draft) { newValue in
            DispatchQueue.main.async { persist(newValue) }
        }
        .onChange(of: state.externalImportURLs) { _ in consumeExternalImports() }
        .onDisappear { state.checkEnv() }
        .sheet(item: $pendingImport) { request in
            WheelImportSheet(request: request,
                             onCancel: { pendingImport = nil },
                             onImport: { mode in applyImport(request, mode: mode) })
        }
        .sheet(isPresented: $showFormatHelp) {
            WheelFormatHelpView(onDismiss: { showFormatHelp = false })
        }
        .overlay(alignment: .bottomTrailing) {
            if !statusText.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: statusIsError ? "exclamationmark.triangle.fill"
                                                    : "checkmark.circle.fill")
                    Text(verbatim: statusText).font(.system(size: 11.5)).lineLimit(2)
                }
                .foregroundColor(statusIsError ? Color(hex: 0xDC2626) : Color(hex: 0x16A34A))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white)
                    .shadow(color: .black.opacity(0.13), radius: 9, y: 3))
                .padding(18)
                .id(statusText)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation(.easeOut(duration: 0.25)) { statusText = "" }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: statusText)
    }

    // MARK: 配置读写

    private func loadActive() {
        let cfg = state.config
        let p = cfg.profiles.first { $0.id == cfg.activeProfileId } ?? cfg.profiles[0]
        selectedProfileID = p.id
        draft = p.normalized
        selectedSlice = 0
    }

    private func switchProfile(_ id: String) {
        guard let p = state.config.profiles.first(where: { $0.id == id }) else { return }
        selectedProfileID = id
        draft = p.normalized
        selectedSlice = 0
    }

    private func persist(_ p: WheelProfile) {
        state.config.updateProfile(p)
        _ = state.config.normalized()      // 槽位 0–9 去重、自动补空位
        state.config.save()
        state.objectWillChange.send()
    }

    /// 当前转盘实际使用的呼出组合键：单独配置时用它，否则跟随全局设置。
    /// 按修饰键固定顺序输出，保证图标顺序与上方按钮一致。
    private var activeComboIcons: String {
        let flags = draft.hotkeyFlags.isEmpty
            ? (state.config.hotkeyFlags.isEmpty ? ["option"] : state.config.hotkeyFlags)
            : draft.hotkeyFlags
        return ModKey.allCases.compactMap { m in
            flags.contains(m.rawValue) ? m.shortLabel : nil
        }.joined()
    }

    private var followsGlobalCombo: Bool { draft.hotkeyFlags.isEmpty }

    private func commitNow() { persist(draft) }

    // MARK: 顶部工具条

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("转盘组", selection: Binding(get: { selectedProfileID },
                                                    set: { switchProfile($0) })) {
                    ForEach(state.config.profiles) { p in Text(verbatim: p.name).tag(p.id) }
                }
                .labelsHidden().frame(width: 200)

                Menu("新建…") {
                    ForEach(WheelPreset.allCases) { preset in
                        Button(preset.title) { newProfile(preset) }
                    }
                }
                .frame(width: 66)
                .disabled(state.config.profiles.count >= 10)
                Button("复制") { duplicateProfile() }
                    .disabled(state.config.profiles.count >= 10)
                Button("删除") { deleteProfile() }
                    .disabled(state.config.profiles.count <= 1)
                Button("设为当前") { state.setActiveProfile(draft.id) }
                    .disabled(state.config.activeProfileId == draft.id)

                Spacer()
                Menu("导出…") {
                    Button("导出当前转盘…") { exportProfiles([draft]) }
                    Button("导出全部转盘…") { exportProfiles(state.config.profiles) }
                    Divider()
                    Button("复制当前转盘配置") { copyConfigText([draft]) }
                    Button("复制全部转盘配置") { copyConfigText(state.config.profiles) }
                    Divider()
                    Button("查看格式说明与示例…") { showFormatHelp = true }
                }.frame(width: 76)
                Button("导入…") { importFromFile() }
                Button("重新检测环境") {
                    state.checkEnv()
                    state.checkPythonEnv()
                    state.checkStataEnv()
                }
                .buttonStyle(.borderless).foregroundColor(brandColor)
            }
            .font(.system(size: 11.5))

            HStack(spacing: 10) {
                Text("转盘名称").font(.system(size: 11.5, weight: .semibold)).foregroundColor(subInkColor)
                TextField("例如：数据清洗", text: $draft.name)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                    .font(.system(size: 12))
                Text("呼出组合键").font(.system(size: 11.5, weight: .semibold)).foregroundColor(subInkColor)
                // 修饰键按钮固定宽度，窗口变窄时不再被压扁导致图标被裁切
                HStack(spacing: 6) {
                    ForEach(ModKey.allCases, id: \.self) { m in
                        let on = draft.hotkeyFlags.contains(m.rawValue)
                        Button {
                            if on { draft.hotkeyFlags.removeAll { $0 == m.rawValue } }
                            else { draft.hotkeyFlags.append(m.rawValue) }
                        } label: {
                            Text(m.shortLabel).font(.system(size: 13, weight: .medium))
                                .frame(width: 30, height: 22)
                                .background(Capsule().fill(on ? brandColor.opacity(0.15) : Color(hex: 0xF0F0F4)))
                                .overlay(Capsule().strokeBorder(on ? brandColor : Color(hex: 0xD8DCE4), lineWidth: 1))
                                .foregroundColor(on ? brandColor : subInkColor)
                        }.buttonStyle(.plain).frame(width: 30, height: 22)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                if draft.hotkeyFlags.isEmpty {
                    Text("跟随全局设置").font(.system(size: 10.5)).foregroundColor(hintColor)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("数字键槽位").font(.system(size: 11.5, weight: .semibold)).foregroundColor(subInkColor)
                Picker("", selection: Binding(get: { draft.slot ?? 1 },
                                              set: { draft.slot = $0 })) {
                    ForEach(0..<10, id: \.self) { d in Text("\(d)").tag(d) }
                }
                .labelsHidden().frame(width: 58)
                Text("按住 \(activeComboIcons) + 该数字即可呼出本转盘\(followsGlobalCombo ? "（跟随全局组合键）" : "")")
                    .font(.system(size: 10.5)).foregroundColor(hintColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("共 \(state.config.profiles.count)/10 套")
                    .font(.system(size: 10.5)).foregroundColor(hintColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineColor, lineWidth: 1)))
    }

    private func newProfile(_ preset: WheelPreset = .blank) {
        guard state.config.profiles.count < 10 else {
            setStatus("最多只能创建 10 套转盘（数字键槽位 0–9）", isError: true); return
        }
        var p = preset.profile()
        p.id = UUID().uuidString
        p.slot = nil
        p.hotkeyFlags = []
        if preset == .blank { p.name = "新转盘 \(state.config.profiles.count + 1)" }
        state.config.profiles.append(p)
        _ = state.config.normalized()
        state.config.save()
        state.objectWillChange.send()
        switchProfile(p.id)
        let slot = state.config.profiles.first { $0.id == p.id }?.slot.map(String.init) ?? "—"
        setStatus("已新建「\(p.name)」· 数字键槽位 \(slot)")
    }

    private func duplicateProfile() {
        guard state.config.profiles.count < 10 else {
            setStatus("最多只能创建 10 套转盘（数字键槽位 0–9）", isError: true); return
        }
        var p = draft
        p.id = UUID().uuidString
        p.name = draft.name + " 副本"
        p.hotkeyFlags = []
        p.slot = nil
        state.config.profiles.append(p)
        _ = state.config.normalized()
        state.config.save()
        state.objectWillChange.send()
        switchProfile(p.id)
    }

    private func deleteProfile() {
        guard state.config.profiles.count > 1 else { return }
        let id = draft.id
        state.config.profiles.removeAll { $0.id == id }
        state.config.activeProfileId = state.config.profiles[0].id
        state.config.save()
        state.objectWillChange.send()
        loadActive()
    }

    // MARK: 配置文本导出 / 导入

    private func setStatus(_ text: String, isError: Bool = false) {
        statusText = text
        statusIsError = isError
    }

    private func exportProfiles(_ profiles: [WheelProfile]) {
        guard !profiles.isEmpty else { setStatus("没有可导出的转盘", isError: true); return }
        let panel = NSSavePanel()
        panel.title = "导出转盘配置文件"
        panel.message = "导出为 .glazer 文件：双击会用 GlazeR 的可编辑文档窗口打开（语法高亮），保存后可在窗口菜单里「应用到转盘…」。"
        panel.nameFieldStringValue = profiles.count == 1
            ? "\(profiles[0].name).\(WheelTextCodec.fileExtension)"
            : "GlazeR-全部转盘.\(WheelTextCodec.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = false
        if let exported = UTType(WheelTextCodec.typeIdentifier) {
            panel.allowedContentTypes = [exported, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try WheelTextCodec.exportText(profiles).write(to: url, atomically: true, encoding: .utf8)
            setStatus("已导出 \(profiles.count) 套转盘 → \(url.lastPathComponent)")
            state.log("导出转盘配置文件：\(url.path)")
        } catch {
            setStatus("导出失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func copyConfigText(_ profiles: [WheelProfile]) {
        guard !profiles.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(WheelTextCodec.exportText(profiles), forType: .string)
        setStatus("已复制 \(profiles.count) 套转盘的配置文本到剪贴板")
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "选择转盘配置文件"
        panel.message = "选择 .glazer 转盘配置文件，或任意 UTF-8 纯文本（旧版 .glazer.txt 也可导入）。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = true
        var types: [UTType] = [.plainText]
        if let exported = UTType(WheelTextCodec.typeIdentifier) { types.insert(exported, at: 0) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        _ = presentImport(from: panel.urls)
    }

    /// 解析一个或多个 .glazer 文件并弹出导入预览（「导入…」与文档窗口「应用到转盘…」共用）
    @discardableResult
    private func presentImport(from urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        var merged = WheelTextParseResult()
        var names: [String] = []
        var readErrors: [String] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                readErrors.append("无法以 UTF-8 读取 \(url.lastPathComponent)")
                continue
            }
            let r = WheelTextCodec.parse(text)
            merged.profiles.append(contentsOf: r.profiles)
            merged.warnings.append(contentsOf: r.warnings.map { "\(url.lastPathComponent)：\($0)" })
            merged.errors.append(contentsOf: r.errors.map { "\(url.lastPathComponent)：\($0)" })
            merged.lineCount += r.lineCount
            names.append(url.lastPathComponent)
        }
        merged.errors.append(contentsOf: readErrors)
        guard !merged.profiles.isEmpty else {
            let msg = merged.errors.first ?? "文件中没有解析出任何转盘"
            let alert = NSAlert()
            alert.messageText = "无法导入"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
            setStatus(msg, isError: true)
            return false
        }
        // 部分文件解析失败时，成功部分仍可导入，失败原因列进预览的警告区
        if !merged.errors.isEmpty { merged.warnings.append(contentsOf: merged.errors) }
        pendingImport = WheelImportRequest(
            result: merged,
            fileName: names.count == 1 ? names[0] : "\(names.count) 个 .glazer 文件")
        return true
    }

    /// 文档窗口「应用到转盘…」把 .glazer 文件投递到这里再做导入预览
    private func consumeExternalImports() {
        let urls = state.externalImportURLs
        guard !urls.isEmpty else { return }
        state.externalImportURLs = []
        _ = presentImport(from: urls)
    }

    private func applyImport(_ request: WheelImportRequest, mode: WheelImportMode) {
        // 导入可能覆盖现有转盘，先留一份可手动恢复的快照
        let backupURL = GlazeConfig.dir.appendingPathComponent("config.before-import.json")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: GlazeConfig.configURL, to: backupURL)

        let cfg = state.config
        let incoming = request.result.profiles

        switch mode {
        case .replaceAll:
            cfg.profiles = incoming
            cfg.activeProfileId = incoming.first?.id ?? ""

        case .appendAll:
            for var p in incoming {
                p.id = UUID().uuidString
                p.slices = p.slices.map { s in
                    var v = s
                    v.id = UUID().uuidString
                    v.params = v.params.map { q in var w = q; w.id = UUID().uuidString; return w }
                    return v
                }
                cfg.profiles.append(p)
            }

        case .replaceMatching:
            // 以导入前的快照为匹配基准，避免文件内同名转盘互相覆盖
            let original = cfg.profiles
            var used = Set<Int>()
            for var p in incoming {
                var matched: Int?
                if !p.id.isEmpty {
                    matched = original.indices.first { original[$0].id == p.id && !used.contains($0) }
                }
                if matched == nil {
                    matched = original.indices.first { original[$0].name == p.name && !used.contains($0) }
                }
                if let i = matched {
                    used.insert(i)
                    p.id = original[i].id           // 保留原 id，当前转盘引用不会失效
                    cfg.profiles[i] = p
                } else {
                    p.id = UUID().uuidString
                    cfg.profiles.append(p)
                }
            }
        }

        _ = cfg.normalized()
        cfg.save()
        HotkeyMonitor.shared.restart()
        state.objectWillChange.send()
        pendingImport = nil

        // 编辑器切换到刚导入的第一套转盘
        if let first = incoming.first {
            let targetID: String?
            switch mode {
            case .replaceAll:      targetID = cfg.profiles.first?.id
            case .appendAll:       targetID = cfg.profiles.last?.id
            case .replaceMatching: targetID = cfg.profiles.first {
                $0.id == first.id || $0.name == first.name
            }?.id
            }
            if let id = targetID { switchProfile(id) }
        }
        setStatus("已导入 \(incoming.count) 套转盘 · \(mode.title)")
        state.log("导入转盘配置：\(request.fileName) · \(mode.title) · \(incoming.count) 套")
    }

    // MARK: 左栏：扇区数量与列表

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: Binding(get: { draft.sliceCount }, set: { n in
                draft.sliceCount = n
                draft.normalize()
                if selectedSlice >= draft.sliceCount { selectedSlice = draft.sliceCount - 1 }
            }), in: 2...12) {
                Text("扇区数量：\(draft.sliceCount)")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundColor(inkColor)
            }
            Text("可设 2–12 个扇区；减少数量会保留前 N 个配置。")
                .font(.system(size: 10.5)).foregroundColor(hintColor)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(0..<draft.sliceCount, id: \.self) { i in
                        let s = draft.slices[i]
                        Button { selectedSlice = i } label: {
                            HStack(spacing: 8) {
                                Text("\(i + 1)").font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(s.swiftColor))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: s.label).font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(inkColor).lineLimit(1)
                                    Text(verbatim: s.isConfigured ? (s.mode == .call ? s.function : "自定义 \(s.engine.shortTitle) 代码") : "未配置")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundColor(hintColor).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(i == safeIndex ? brandSoft : Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(i == safeIndex ? brandBorder : lineColor, lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                Button("上移") { moveSlice(-1) }.disabled(safeIndex == 0)
                Button("下移") { moveSlice(1) }.disabled(safeIndex == draft.sliceCount - 1)
                Button("清空本格") {
                    draft.slices[safeIndex] = .blank(index: safeIndex)
                }
            }
            .font(.system(size: 11))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineColor, lineWidth: 1)))
    }

    private func moveSlice(_ delta: Int) {
        let i = safeIndex, j = i + delta
        guard j >= 0, j < draft.slices.count else { return }
        draft.slices.swapAt(i, j)
        selectedSlice = j
    }

    // MARK: 中栏：扇区详情表单

    private var middleColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if draft.slices.indices.contains(safeIndex) {
                    sectionTitle("扇区 \(safeIndex + 1) · 执行动作")

                    HStack(spacing: 10) {
                        labeledField("显示名称", text: $draft.slices[safeIndex].label, width: 150)
                        labeledField("悬停说明", text: $draft.slices[safeIndex].detail, width: 170)
                        Toggle("启用", isOn: $draft.slices[safeIndex].enabled)
                            .toggleStyle(.switch).controlSize(.small)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Picker("引擎", selection: $draft.slices[safeIndex].engine) {
                            ForEach(SliceEngine.allCases) { e in Text(e.title).tag(e) }
                        }
                        .pickerStyle(.segmented).frame(width: 330)
                        .labelsHidden()
                        Picker("执行方式", selection: $draft.slices[safeIndex].mode) {
                            ForEach(SliceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 180)
                        .labelsHidden()
                        Spacer()
                    }

                    variableHint(currentEngine)

                    if draft.slices[safeIndex].mode == .call {
                        labeledField(engineCopy.functionTitle,
                                     text: $draft.slices[safeIndex].function, width: .infinity)
                        HStack(spacing: 8) {
                            labeledField(engineCopy.sourceTitle,
                                         text: $draft.slices[safeIndex].sourceFile, width: .infinity)
                            Button("浏览…") { pickSourceFile() }
                                .font(.system(size: 11))
                        }
                        labeledField("文件路径注入到哪个形参（留空则不注入）",
                                     text: $draft.slices[safeIndex].fileArg, width: 240)
                        Text(verbatim: engineCopy.fileArgHint)
                            .font(.system(size: 10.5)).foregroundColor(hintColor)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: engineCopy.codeTitle)
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(subInkColor)
                        TextEditor(text: $draft.slices[safeIndex].code)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(minHeight: 96)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(lineColor, lineWidth: 1))
                        labeledField(engineCopy.sourceShort,
                                     text: $draft.slices[safeIndex].sourceFile, width: .infinity)
                    }

                    sectionTitle("默认参数（值按\(engineCopy.paramExpr)求值）")
                    ParamsEditor(params: $draft.slices[safeIndex].params,
                                 valueLabel: engineCopy.paramValueLabel,
                                 defaultValue: currentEngine == .python ? "True"
                                     : (currentEngine == .stata ? "`file'" : "TRUE"))

                    sectionTitle("批量与输出")
                    HStack(spacing: 12) {
                        Picker("多文件处理", selection: $draft.slices[safeIndex].batch) {
                            ForEach(BatchMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 150)
                        Picker("结果处理", selection: $draft.slices[safeIndex].output) {
                            ForEach(OutputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 190)
                        Spacer()
                    }
                    labeledField("输出文件名后缀（追加到原文件名之后）",
                                 text: $draft.slices[safeIndex].outputSuffix, width: 230)
                    if draft.slices[safeIndex].output == .custom {
                        Text(verbatim: engineCopy.outputCodeTitle)
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(subInkColor)
                        TextEditor(text: $draft.slices[safeIndex].outputCode)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(minHeight: 64)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(lineColor, lineWidth: 1))
                    }

                    sectionTitle("扇区配色")
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 7), count: 6), spacing: 7) {
                        ForEach(slicePalette, id: \.self) { hex in
                            Button {
                                draft.slices[safeIndex].color = hex
                            } label: {
                                Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(
                                        draft.slices[safeIndex].color == hex ? inkColor : Color.clear, lineWidth: 2))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineColor, lineWidth: 1)))
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(verbatim: s).font(.system(size: 12.5, weight: .bold)).foregroundColor(inkColor)
            .padding(.top, 2)
    }

    private var currentEngine: SliceEngine {
        draft.slices.indices.contains(safeIndex) ? draft.slices[safeIndex].engine : .r
    }

    /// 各引擎在表单里的文案（避免界面到处写「只支持 R」的旧措辞）
    private struct EngineCopy {
        let functionTitle: String
        let sourceTitle: String
        let fileArgHint: String
        let codeTitle: String
        let sourceShort: String
        let paramExpr: String
        let paramValueLabel: String
        let outputCodeTitle: String
    }

    private var engineCopy: EngineCopy {
        switch currentEngine {
        case .r:
            return EngineCopy(
                functionTitle: "R 函数（支持 pkg::fun、基础函数名、自定义函数）",
                sourceTitle: "自定义 R 脚本（可选，先 source 再调用）",
                fileArgHint: "例如 readr::read_csv 用 file、readxl::read_excel 用 path；自定义函数里也可直接引用 .file / .dir。",
                codeTitle: "自定义 R 代码（最后一行的值作为结果）",
                sourceShort: "自定义 R 脚本（可选）",
                paramExpr: "R",
                paramValueLabel: "R 表达式",
                outputCodeTitle: "自定义写出代码（可用 .result、.out、.file、.dir、.filebasename）")
        case .python:
            return EngineCopy(
                functionTitle: "Python 函数（支持 module.func、内置函数、自定义函数）",
                sourceTitle: "自定义 Python 脚本（可选，先 exec 再调用）",
                fileArgHint: "例如 def my_fun(file): ... 用 file；也可调用 pandas.read_csv 并把路径参数设为 filepath_or_buffer。",
                codeTitle: "自定义 Python 代码（单表达式直接返回结果；多行代码请把结果赋给 result）",
                sourceShort: "自定义 Python 脚本（可选）",
                paramExpr: "Python",
                paramValueLabel: "Python 表达式",
                outputCodeTitle: "自定义写出代码（可用 result、OUT、FILE、DIR、FILEBASENAME）")
        case .stata:
            return EngineCopy(
                functionTitle: "Stata 命令 / program 名（如 summarize、use、自定义的 myprog）",
                sourceTitle: "自定义 Stata do 文件（可选，内容会在扇区代码前执行）",
                fileArgHint: "留空则不自动传入文件路径；非空时把 `file' 作为命令的第一个位置参数。自定义代码里可直接用 `file' / `dir' / `out'。",
                codeTitle: "自定义 Stata 代码（可直接使用 `file'、`dir'、`out' 等宏）",
                sourceShort: "自定义 Stata do 文件（可选）",
                paramExpr: "Stata 命令行片段",
                paramValueLabel: "Stata 命令行片段",
                outputCodeTitle: "自定义写出代码（`out' 是完整输出路径，也可用 `outdir' 拼自己的文件名）")
        }
    }

    /// 自定义函数 / 代码区上方的路径变量速查表（用户要求明确提示可用参数）
    private func variableHint(_ engine: SliceEngine) -> some View {
        let rows: [String]
        switch engine {
        case .r:
            rows = [
                ".file 完整路径（含路径 + 文件名.后缀）    .filename 文件名.后缀",
                ".dir 所在目录（不含文件名）    .filebasename 纯名称（不含后缀）",
                ".files 全部文件路径向量；写出代码另可用 .result / .out",
            ]
        case .python:
            rows = [
                "FILE 完整路径    FILENAME 文件名.后缀    DIR 所在目录",
                "FILEBASENAME 纯名称（不含后缀）    FILES 全部路径列表",
                "glazer.file 等对象形式 · OUT 建议输出路径 · convert(FILE, \"xlsx\")",
            ]
        case .stata:
            rows = [
                "`file' 输入完整路径    `dir' 输入目录    `filebasename' 纯名称",
                "`out' 输出文件完整路径（不是目录）    `outdir' 输出目录",
                "`file1'…`fileN' / `nfiles' 多文件；同名全局宏 $file / $outdir 可在 program 内使用",
                "自定义写出示例：export delimited using `\"`outdir'/`filebasename'.csv\"', replace",
            ]
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "curlybraces").font(.system(size: 11, weight: .semibold))
                Text("\(engine.variableTitle)（自动解析，自定义函数与代码里都能直接用）")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(brandColor)
            ForEach(rows, id: \.self) { row in
                Text(verbatim: row).font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(subInkColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(brandSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(brandBorder, lineWidth: 1))
    }

    private func labeledField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title).font(.system(size: 10.5)).foregroundColor(hintColor)
            TextField("", text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
        }
        .frame(maxWidth: width == .infinity ? .infinity : width, alignment: .leading)
    }

    private func pickSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let path = panel.url?.path {
            draft.slices[safeIndex].sourceFile = path
        }
    }

    // MARK: 右栏：实时预览

    /// 使用提示跟随当前引擎，避免残留「只支持 R」的旧措辞；Stata 分支含局部宏，
    /// 必须用 verbatim 渲染，否则反引号会被 SwiftUI 的 Markdown 解析吞掉。
    private var usageHint: String {
        let head: String
        switch currentEngine {
        case .r:
            head = "· 参数值写 R 表达式，如 TRUE、NULL、\"utf8\"、c(1, 2)\n"
                 + "· 表达式中可引用 .file（首个文件）与 .files（全部文件）"
        case .python:
            head = "· 参数值写 Python 表达式，如 True、None、\"utf8\"、[1, 2]\n"
                 + "· 表达式中可引用 FILE（首个文件）、FILES（全部文件）与 glazer.file"
        case .stata:
            head = "· 参数值写 Stata 命令行片段，可用 `file'、`dir'、`out' 等局部宏\n"
                 + "· 多文件另可用 `file1'…`fileN' 与 `nfiles'"
        }
        return head + "\n· 输出目录在「设置」中统一配置，默认写到源文件所在目录"
                    + "\n· 不同转盘组绑定不同组合键，按住对应组合键即呼出该转盘"
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("转盘预览").font(.system(size: 12.5, weight: .bold)).foregroundColor(inkColor)
            WheelCoreView(profile: draft, hotIndex: hoverIndex, mode: .drag,
                          fileCount: 1, busyCount: 0, lastDetail: nil,
                          hover: { o in
                              hoverIndex = o.map { WheelGeometry.sectorIndex(offset: $0, count: draft.sliceCount) } ?? -1
                          })
                .frame(width: WheelGeometry.size, height: WheelGeometry.size)
                .scaleEffect(0.62)
                .frame(width: 200, height: 200)
                .onTapGesture { if hoverIndex >= 0 { selectedSlice = hoverIndex } }
                .frame(maxWidth: .infinity)

            Text("悬停高亮，点击定位到该扇区")
                .font(.system(size: 10.5)).foregroundColor(hintColor)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("使用提示").font(.system(size: 11.5, weight: .semibold)).foregroundColor(subInkColor)
                Text(verbatim: usageHint)
                    .font(.system(size: 10.5)).foregroundColor(hintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineColor, lineWidth: 1)))
    }
}

// MARK: - 默认参数编辑

struct ParamsEditor: View {
    @Binding var params: [ParamItem]
    var valueLabel: String = "R 表达式"
    var defaultValue: String = "TRUE"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(verbatim: "参数名 / \(valueLabel)").font(.system(size: 10.5)).foregroundColor(hintColor)
                Spacer()
                Button("+ 添加参数") {
                    params.append(ParamItem(key: "", value: defaultValue))
                }.font(.system(size: 11))
            }
            if params.isEmpty {
                Text("暂无默认参数，函数将只用文件路径调用")
                    .font(.system(size: 10.5)).foregroundColor(hintColor)
            }
            ForEach($params) { $p in
                HStack(spacing: 6) {
                    Toggle("", isOn: $p.enabled).toggleStyle(.checkbox).labelsHidden()
                    TextField("参数名", text: $p.key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 130)
                    Text("=").font(.system(size: 11)).foregroundColor(hintColor)
                    TextField(valueLabel, text: $p.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Button {
                        params.removeAll { $0.id == p.id }
                    } label: {
                        Image(systemName: "minus.circle").foregroundColor(Color(hex: 0xDC2626))
                    }.buttonStyle(.plain)
                }
                .opacity(p.enabled ? 1 : 0.5)
            }
        }
    }
}
