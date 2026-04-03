import Foundation

public extension Notification.Name {
    /// 请求打开单卡编辑窗口（由 `ContentView` 调用 `openWindow`）。
    static let sillycardOpenSingleCard = Notification.Name("sillycardOpenSingleCard")
    static let sillycardShowError = Notification.Name("sillycardShowError")
    static let sillycardShowAbout = Notification.Name("sillycardShowAbout")
    static let sillycardShowWelcome = Notification.Name("sillycardShowWelcome")
    /// 版本说明（与升级弹窗同一视图）。
    static let sillycardShowReleaseNotes = Notification.Name("sillycardShowReleaseNotes")
}
