// GlazeR — 配置文本导入预览 / 格式说明
import AppKit
import SwiftUI

struct WheelImportRequest: Identifiable {
    let id = UUID()
    let result: WheelTextParseResult
    let fileName: String
}

// MARK: - 导入预览

struct WheelImportSheet: View {
    let request: WheelImportRequest
    let onCancel: () -> Void
    let onImport: (WheelImportMode) -> Void

    @State private var mode: WheelImportMode = .replaceMatching

    private var result: WheelTextParseResult { request.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("导入转盘配置")
                    .font(.system(size: 19, weight: .bold)).foregroundColor(inkColor)
                Text("先确认解析结果，再选择如何并入现有转盘。")
                    .font(.system(size: 11.5)).foregroundColor(subInkColor)
            }

            HStack(spacing: 8) {
                Label(request.fileName, systemImage: "doc.text")
                Spacer()
                Text("\(result.profiles.count) 套转盘 · \(result.sliceTotal) 个扇区 · \(result.lineCount) 行")
            }
            .font(.system(size: 11)).foregroundColor(subInkColor)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(brandSoft))

            Text("解析预览").font(.system(size: 12.5, weight: .bold)).foregroundColor(inkColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(result.profiles) { p in
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(Color(hexString: p.slices.first?.color ?? "4F46E5"))
                                .frame(width: 9, height: 9).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(inkColor)
                                Text("\(p.slices.count) 个扇区 · 快捷键 \(hotkeyText(p)) · 编号 \(String(p.id.prefix(8)))")
                                    .font(.system(size: 10)).foregroundColor(hintColor)
                                Text(p.slices.map(\.label).joined(separator: " · "))
                                    .font(.system(size: 10.5)).foregroundColor(subInkColor)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lineColor, lineWidth: 1)))
                    }
                }
            }
            .frame(height: 168)

            if !result.errors.isEmpty || !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(result.errors.prefix(3), id: \.self) { e in
                        Label(e, systemImage: "xmark.circle.fill")
                            .font(.system(size: 10.5)).foregroundColor(Color(hex: 0xDC2626))
                    }
                    ForEach(result.warnings.prefix(4), id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5)).foregroundColor(Color(hex: 0xB45309))
                    }
                    let rest = max(0, result.warnings.count - 4)
                    if rest > 0 {
                        Text("另有 \(rest) 条提示已省略")
                            .font(.system(size: 10)).foregroundColor(hintColor)
                    }
                }
                .frame(maxHeight: 76, alignment: .topLeading)
            }

            Divider()

            Text("导入方式").font(.system(size: 12.5, weight: .bold)).foregroundColor(inkColor)
            Picker("", selection: $mode) {
                ForEach(WheelImportMode.allCases) { m in Text(m.title).tag(m) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(mode.detail)
                .font(.system(size: 10.5)).foregroundColor(subInkColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Spacer()
                Button("取消") { onCancel() }.keyboardShortcut(.cancelAction)
                // 导入会覆盖现有转盘：不能用 .borderedProminent（它会成为窗口默认按钮，
                // 响应系统可能在窗口激活时派发的回车），必须显式点击才生效
                Button("导入 \(result.profiles.count) 套转盘") { onImport(mode) }
                    .buttonStyle(.bordered).foregroundColor(brandColor)
            }
            .font(.system(size: 11.5))
        }
        .padding(22)
        .frame(width: 560, height: 610)
        .background(canvasColor)
    }

    private func hotkeyText(_ p: WheelProfile) -> String {
        p.hotkeyFlags.isEmpty ? "跟随全局" : ModKey.comboLabel(p.hotkeyFlags)
    }
}

// MARK: - 格式说明与示例

struct WheelFormatHelpView: View {
    let onDismiss: () -> Void

    private var sample: String {
        WheelTextCodec.exportText([WheelProfile.demo().normalized])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("转盘配置文件格式（.glazer） · v\(WheelTextCodec.formatVersion)")
                .font(.system(size: 19, weight: .bold)).foregroundColor(inkColor)
            Text("下面是导出得到的真实 .glazer 文件样式：UTF-8 纯文本，文件头部的注释说明了每个字段。保存为任意名称的 .glazer 文件后，双击即可用 GlazeR 的可编辑文档窗口打开（语法高亮、可保存）；窗口菜单里的「应用到转盘…」或编辑器里的「导入…」都可用于更新转盘配置。")
                .font(.system(size: 11.5)).foregroundColor(subInkColor)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(verbatim: sample)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(inkColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lineColor, lineWidth: 1)))

            HStack(spacing: 9) {
                Spacer()
                Button("复制示例文本") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(sample, forType: .string)
                }
                Button("关闭") { onDismiss() }.buttonStyle(.borderedProminent)
            }
            .font(.system(size: 11.5))
        }
        .padding(22)
        .frame(width: 720, height: 640)
        .background(canvasColor)
    }
}
