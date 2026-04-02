import Foundation

enum FolderAccessHelp {
    static let alertTitle = "资料库文件夹访问说明"

    static let alertMessage = """
    本 App 在沙盒中运行，不会在你未同意的情况下访问磁盘。

    请始终使用「打开文件夹…」或菜单「文件 → 打开文件夹」（快捷键 ⌘O）选取资料库。系统弹出访达窗口后，选中包含 PNG 角色卡的文件夹并确认，即完成授权，之后才能列出、编辑与保存卡片。

    若选取后仍无法载入，请关注随后出现的错误提示，或在「系统设置 → 隐私与安全性」中检查是否有安全软件或描述文件限制本 App。
    """

    static let sidebarHint = "须先通过下方按钮或工具栏「打开文件夹」授权资料库。"
}
