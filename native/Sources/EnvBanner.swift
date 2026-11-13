// GlazeR — R 环境状态横幅
import SwiftUI

struct EnvBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        switch state.envState {
        case .checking, .ok:
            EmptyView()
        case .missing(let pkgs):
            banner(icon: "exclamationmark.triangle.fill", color: Color(hex: 0xF59E0B),
                   text: "缺少 R 包：\(pkgs.joined(separator: "、"))",
                   detail: "请在 R 中执行 install.packages(...) 安装后重新检测",
                   title: "前往设置") { state.page = .settings }
        case .failed(let msg):
            banner(icon: "xmark.octagon.fill", color: Color(hex: 0xDC2626),
                   text: "R 环境不可用", detail: msg, title: "前往设置") { state.page = .settings }
        }
    }

    @ViewBuilder
    private func banner(icon: String, color: Color, text: String,
                        detail: String, title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: text).font(.system(size: 12, weight: .semibold)).foregroundColor(inkColor)
                Text(verbatim: detail).font(.system(size: 10.5)).foregroundColor(hintColor).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(title, action: action).buttonStyle(.borderedProminent)
                .controlSize(.small).tint(brandColor)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)
            .shadow(color: Color.black.opacity(0.10), radius: 10, y: 3)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xE6E9EE), lineWidth: 1)))
    }
}
