import AppKit
import Foundation

/// 拦截「通过访达打开 / 打开方式」交给本 App 的文件，走统一通知 + `openWindow(id:value:)`。
///
/// 说明：仅声明 `WindowGroup(for: URL.self)` 时，从访达打开 PNG 可能触发运行时按**文件路径**去解析 Scene id，
/// 从而出现 “No Scene with id '/path/to/x.png' …”。本委托接手打开事件并投递固定 Scene。
final class SillycardAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        emitPNGOpenNotifications(paths: [filename])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        emitPNGOpenNotifications(paths: filenames)
    }

    private func emitPNGOpenNotifications(paths: [String]) {
        let urls = paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { $0.pathExtension.lowercased() == "png" }
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async {
            for url in urls {
                NotificationCenter.default.post(name: .sillycardOpenSingleCard, object: url)
            }
        }
    }
}
