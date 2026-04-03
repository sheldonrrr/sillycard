import Foundation

/// `WindowGroup(id:for:)` 的固定标识。系统从访达打开文件时若用路径当 Scene id，会找不到已注册 Scene；本 id 与 `openWindow(id:value:)` 必须一致。
public enum SillycardSceneIds {
    public static let singleCardEditor = "xyz.nowtiny.sillycard.scene.single-card-editor"
}
