import Foundation

/// 左侧「角色卡库」切换：默认库不包含「归档」子文件夹中的卡片；归档仅展示该文件夹内卡片。
enum LibraryScope: String, CaseIterable, Identifiable {
    case main
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: "默认库"
        case .archive: "归档"
        }
    }

    var systemImage: String {
        switch self {
        case .main: "square.grid.2x2"
        case .archive: "archivebox"
        }
    }

    static let archiveFolderName = "归档"

    /// `relativeFolder` 是否属于归档目录（`归档` 或 `归档/...`）。
    static func isArchivedRelativeFolder(_ relative: String) -> Bool {
        if relative == archiveFolderName { return true }
        return relative.hasPrefix(archiveFolderName + "/")
    }
}
