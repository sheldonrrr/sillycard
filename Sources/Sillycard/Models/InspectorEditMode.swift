import Foundation

enum InspectorEditMode: String, CaseIterable, Identifiable {
    case preview
    case edit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: "预览"
        case .edit: "编辑"
        }
    }
}
