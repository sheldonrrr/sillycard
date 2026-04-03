import AppKit
import SwiftUI

/// 与高保真稿一致的暗色面板层级、时间文案等（亮色下退回系统语义色）。
enum SillycardDesign {
    /// Figma 组件 `dialogue_bg`（文件 Sillycard · node `1:7`），用于对话/大卡片容器背景。
    /// 来源：`get_design_context`；与 Code Connect 无关，可在无 Org 套餐时使用。
    static let figmaDialogueBackground = Color(red: 35 / 255, green: 41 / 255, blue: 43 / 255)
    static let figmaDialogueCornerRadius: CGFloat = 20

    static func inspectorFieldFill(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color(white: 0.14)
        case .light: return Color(nsColor: .textBackgroundColor)
        @unknown default: return Color(nsColor: .textBackgroundColor)
        }
    }

    static func inspectorFieldStroke(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color.white.opacity(0.08)
        case .light: return Color.secondary.opacity(0.22)
        @unknown default: return Color.secondary.opacity(0.22)
        }
    }

    /// 主库网格：选中底（替代描边）。
    static func gridTileSelectedBackground(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color.white.opacity(0.10)
        case .light: return Color.accentColor.opacity(0.14)
        @unknown default: return Color.accentColor.opacity(0.14)
        }
    }

    /// 主库网格：指针悬停且未选中。
    static func gridTileHoverBackground(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color.white.opacity(0.05)
        case .light: return Color.primary.opacity(0.06)
        @unknown default: return Color.primary.opacity(0.06)
        }
    }

    /// 用于「最新修改：…」一类相对时间（稿中的 latest version 观感）。
    static func relativeModificationPhrase(for url: URL) -> String? {
        guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return nil
        }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh-Hans")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func inspectorSubtitleLines(st: SillyTavernCardPreview, tags: [String], item: CardItem) -> String {
        var parts: [String] = []
        if !tags.isEmpty {
            parts.append(tags.joined(separator: " · "))
        }
        if let v = st.characterVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            parts.append("v\(v)")
        }
        if st.hasEmbeddedWorldBook {
            parts.append("含嵌入世界书")
        }
        if let c = st.creator?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            parts.append(c)
        }
        if parts.isEmpty {
            let base = item.displayName
            if !base.isEmpty, base != (st.name ?? "") { parts.append(base) }
        }
        return parts.joined(separator: " · ")
    }
}

/// Figma `dialogue_bg` 形状的满铺背景（按需包在内容外层）。
struct FigmaDialogueBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: SillycardDesign.figmaDialogueCornerRadius, style: .continuous)
            .fill(SillycardDesign.figmaDialogueBackground)
    }
}

/// 品牌主视觉（`Assets/SillycardMascot`），用于关于 / 欢迎等。
struct SillycardMascotArtwork: View {
    var maxWidth: CGFloat = 240

    var body: some View {
        Image("SillycardMascot", bundle: .sillycardResources)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel("Sillycard")
    }
}
