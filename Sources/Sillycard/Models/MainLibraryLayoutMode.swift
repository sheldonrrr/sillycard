import Foundation

/// 默认库中间区域的展示方式（归档视图仍为表格）。
enum MainLibraryLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "网格"
        case .list: "列表"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet.rectangle"
        }
    }
}
