import Foundation

extension Notification.Name {
    /// 请求打开单卡编辑窗口（由 `ContentView` 调用 `openWindow`）。
    static let sillycardOpenSingleCard = Notification.Name("sillycardOpenSingleCard")
    static let sillycardShowError = Notification.Name("sillycardShowError")
}
