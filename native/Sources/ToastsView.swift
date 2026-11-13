// GlazeR — 右下角任务通知卡片
import AppKit
import SwiftUI

struct ToastsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 9) {
            if state.jobs.count > 1 {
                Button { state.closeAllJobs() } label: {
                    Text("全部关闭 (\(state.jobs.count))")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(hintColor)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.85)))
                        .overlay(Capsule().strokeBorder(Color(hex: 0xE6E9EE), lineWidth: 1))
                }.buttonStyle(.plain)
            }
            ForEach(state.jobs) { job in
                JobCard(job: job,
                        onCancel: { state.cancel(jobID: job.id) }) {
                    withAnimation(.easeOut(duration: 0.25)) { state.jobs.removeAll { $0.id == job.id } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(18)
        .allowsHitTesting(true)
    }
}

struct JobCard: View {
    let job: JobItem
    let onCancel: () -> Void
    let onClose: () -> Void
    @State private var shown = false
    @State private var showLog = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: job.file).font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(verbatim: job.detail).font(.system(size: 11.5))
                    .foregroundColor(detailColor).lineLimit(3)

                if job.status == .working {
                    HStack(spacing: 8) {
                        TimelineView(.periodic(from: job.startedAt, by: 1.0)) { ctx in
                            let secs = max(0, Int(ctx.date.timeIntervalSince(job.startedAt)))
                            Text(String(format: "%@ · 已运行 %02d:%02d",
                                       job.stage, secs / 60, secs % 60))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(brandColor)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button("取消") { onCancel() }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }

                if let warn = job.warnings, !warn.isEmpty {
                    Text("⚠ " + String(warn.prefix(160)))
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: 0xB45309)).lineLimit(2)
                }
                if job.status == .done, let out = job.output, !out.isEmpty {
                    HStack(spacing: 8) {
                        Button("打开") { NSWorkspace.shared.open(URL(fileURLWithPath: out)) }
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: out)])
                        }
                    }
                    .buttonStyle(.borderless).font(.system(size: 11.5)).foregroundColor(brandColor)
                }
                if let lg = job.log, !lg.isEmpty {
                    Button(showLog ? "收起输出" : "查看输出") {
                        withAnimation { showLog.toggle() }
                    }.buttonStyle(.borderless).font(.system(size: 10.5)).foregroundColor(hintColor)
                    if showLog {
                        ScrollView {
                            Text(verbatim: lg).font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(hex: 0x334155)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 110)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(job.action).font(.system(size: 10, weight: .heavy))
                .foregroundColor(.white).padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 5).fill(brandColor))
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: 0x9AA3B0))
            }.buttonStyle(.plain)
        }
        .padding(12).frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white)
            .shadow(color: Color.black.opacity(0.14), radius: 12, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0xE6E9EE), lineWidth: 1)))
        .offset(y: shown ? 0 : 14).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { shown = true } }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .working:
            ProgressView().controlSize(.small).frame(width: 17, height: 17)
        case .done:
            Circle().fill(Color(hex: 0x16A34A)).frame(width: 17, height: 17)
                .overlay(Text("✓").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
        case .failed:
            Circle().fill(Color(hex: 0xDC2626)).frame(width: 17, height: 17)
                .overlay(Text("✕").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
        case .cancelled:
            Circle().fill(Color(hex: 0x9AA3B0)).frame(width: 17, height: 17)
                .overlay(Text("■").font(.system(size: 8, weight: .bold)).foregroundColor(.white))
        }
    }

    private var detailColor: Color {
        switch job.status {
        case .working: return subInkColor
        case .done: return Color(hex: 0x9AA3B0)
        case .failed: return Color(hex: 0xDC2626)
        case .cancelled: return hintColor
        }
    }
}
