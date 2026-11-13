// GlazeR — .glazer 专属文档类型：UTI 查询、系统默认打开方式
//
// .glazer 由 Info.plist 的 UTExportedTypeDeclarations 导出，
// UTI 为 com.rstata.glazer.wheel，遵循 public.utf8-plain-text。
// 双击 .glazer 文件时 AppDelegate 会打开可编辑、带语法高亮的文档窗口。
import AppKit
import UniformTypeIdentifiers

enum GlazeRDocument {
    static let identifier = "com.rstata.glazer.wheel"
    static let fileExtension = "glazer"

    /// 打包后的 app 里是导出的专属 UTI；源码直连运行时退化为按扩展名推断
    static var utType: UTType {
        UTType(identifier) ?? UTType(filenameExtension: fileExtension) ?? .plainText
    }

    /// 仅当 Info.plist 已由 LaunchServices 注册时才返回非 nil
    static var exportedType: UTType? { UTType(identifier) }

    static func isDocument(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }

    /// 当前系统里 .glazer 的默认打开应用；nil 表示系统尚未显式指定
    static func defaultAppName() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: utType) else { return nil }
        let bundle = Bundle(url: url)
        return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    static func isDefaultHandler() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: utType) else { return false }
        return url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// 把 .glazer 的默认打开方式显式设为本应用
    static func setAsDefault(completion: @escaping (Result<Void, Error>) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                 toOpen: utType) { err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)) }
                else { completion(.success(())) }
            }
        }
    }

    /// 正式安装到 /Applications 后自动确保默认打开方式。
    /// 开发态（build/、/tmp 下的临时副本）不改写系统设置，避免默认指向临时 app。
    static func ensureDefaultOnLaunch() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        guard exportedType != nil, !isDefaultHandler() else { return }
        setAsDefault { result in
            switch result {
            case .success:
                appendGlazeLog("已将 .glazer 默认打开方式设为 GlazeR")
            case .failure(let err):
                appendGlazeLog("设置 .glazer 默认打开方式失败：\(err.localizedDescription)")
            }
        }
    }
}
