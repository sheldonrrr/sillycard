import SwiftUI

/// 角色卡字段值：原始 JSON 文本 vs 预览（占位符 + HTML/Markdown）。
struct CharacterCardFieldValuePreview: View {
    let rawValue: String
    let characterName: String
    /// `true` 为一键切到原始元数据（不做占位符与富文本处理）。
    var showRawMetadata: Bool
    /// 核心字段（描述等）可用 `.title3`；默认与正文对齐，方便长文阅读。
    var displayFont: Font = .body
    /// 超过该字符数（按 `String` 的 `Character` 计数）时显示「收起 / 全文」；`nil` 表示始终全文。
    var longTextCollapseThreshold: Int? = 4000
    /// 收起状态下展示的字符数上限。
    var collapsedVisibleCharacterCount: Int = 2200

    @State private var isCollapsed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fullSource = sourceStringForDisplay
        let needsToggle = longTextCollapseThreshold.map { fullSource.count > $0 } ?? false
        let shown: String = {
            guard needsToggle, isCollapsed else { return fullSource }
            return truncated(fullSource, collapsedVisibleCharacterCount)
        }()

        VStack(alignment: .leading, spacing: 6) {
            renderText(shown, fullIsEmptyPlaceholder: fullSource == "—")
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if needsToggle {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        isCollapsed.toggle()
                    } label: {
                        Text(isCollapsed ? "展开全文" : "收起")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: rawValue) { _, _ in
            isCollapsed = false
        }
        .onChange(of: showRawMetadata) { _, _ in
            isCollapsed = false
        }
    }

    private var sourceStringForDisplay: String {
        if showRawMetadata {
            return rawValue.isEmpty ? "—" : CharacterCardPreviewFormatting.normalizeDisplayEscapes(rawValue)
        }
        let processed = CharacterCardPreviewFormatting.applyPlaceholders(rawValue, characterName: characterName)
        return processed.isEmpty ? "—" : processed
    }

    @ViewBuilder
    private func renderText(_ text: String, fullIsEmptyPlaceholder: Bool) -> some View {
        if showRawMetadata {
            Text(text)
                .font(displayFont)
                .textSelection(.enabled)
        } else if fullIsEmptyPlaceholder && text == "—" {
            Text("—")
                .font(displayFont)
                .foregroundStyle(.secondary)
        } else if let attr = CharacterCardPreviewFormatting.attributedForPreview(text, colorScheme: colorScheme) {
            Text(attr)
                .font(displayFont)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(displayFont)
                .textSelection(.enabled)
        }
    }

    private func truncated(_ s: String, _ maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        let i = s.index(s.startIndex, offsetBy: maxChars, limitedBy: s.endIndex) ?? s.endIndex
        return String(s[..<i]) + "…"
    }
}
