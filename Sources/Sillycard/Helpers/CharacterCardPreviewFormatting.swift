import AppKit
import Foundation
import SwiftUI

/// 角色卡 Inspector 文字预览：占位符、HTML / Markdown 简单识别与富文本转换。
enum CharacterCardPreviewFormatting {
    /// 暂无用户名设置时的占位（`{{user}}`）。
    static let defaultUserDisplayName = "我"

    /// 将字段里**字面量**的常用转义序列还原为真实字符（JSON 解析后仍会残留 `\` + `n` 等形式；本方法幂等）。
    static func normalizeDisplayEscapes(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        var out = String()
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            guard c == "\\", text.index(after: i) < text.endIndex else {
                out.append(c)
                i = text.index(after: i)
                continue
            }
            let j = text.index(after: i)
            let esc = text[j]
            switch esc {
            case "n":
                out.append("\n")
                i = text.index(after: j)
            case "t":
                out.append("\t")
                i = text.index(after: j)
            case "r":
                let afterR = text.index(after: j)
                if afterR < text.endIndex, text[afterR] == "\n" {
                    out.append("\n")
                    i = text.index(after: afterR)
                } else if afterR < text.endIndex, text[afterR] == "\\", text.index(after: afterR) < text.endIndex, text[text.index(after: afterR)] == "n" {
                    out.append("\n")
                    let k = text.index(after: afterR)
                    i = text.index(after: k)
                } else {
                    out.append("\r")
                    i = afterR
                }
            case "\\":
                out.append("\\")
                i = text.index(after: j)
            case "\"":
                out.append("\"")
                i = text.index(after: j)
            case "'":
                out.append("'")
                i = text.index(after: j)
            case "/":
                out.append("/")
                i = text.index(after: j)
            case "b":
                out.append("\u{08}")
                i = text.index(after: j)
            case "f":
                out.append("\u{0C}")
                i = text.index(after: j)
            case "u":
                let hexStart = text.index(after: j)
                guard let hexEnd = text.index(hexStart, offsetBy: 4, limitedBy: text.endIndex) else {
                    out.append(c)
                    i = j
                    continue
                }
                let hex = String(text[hexStart..<hexEnd])
                guard let code = UInt32(hex, radix: 16) else {
                    out.append(c)
                    i = j
                    continue
                }
                if (0xD800 ... 0xDBFF).contains(code) {
                    let afterHex = hexEnd
                    guard afterHex < text.endIndex,
                          text[afterHex] == "\\",
                          text.index(after: afterHex) < text.endIndex,
                          text[text.index(after: afterHex)] == "u",
                          let hex2Start = text.index(text.index(after: afterHex), offsetBy: 1, limitedBy: text.endIndex),
                          let hex2End = text.index(hex2Start, offsetBy: 4, limitedBy: text.endIndex),
                          let low = UInt32(String(text[hex2Start..<hex2End]), radix: 16),
                          (0xDC00 ... 0xDFFF).contains(low)
                    else {
                        out.append(c)
                        i = j
                        continue
                    }
                    let u = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    if let scalar = UnicodeScalar(u) {
                        out.append(Character(scalar))
                        i = hex2End
                    } else {
                        out.append(c)
                        i = j
                    }
                } else if let scalar = UnicodeScalar(code) {
                    out.append(Character(scalar))
                    i = hexEnd
                } else {
                    out.append(c)
                    i = j
                }
            default:
                out.append(c)
                i = j
            }
        }
        return out
    }

    /// `{{char}}` / `{{user}}`（大小写、内部空格）替换。
    static func applyPlaceholders(_ text: String, characterName: String) -> String {
        let base = normalizeDisplayEscapes(text)
        let charName = characterName.isEmpty ? " " : characterName
        var s = replace(regex: #"\{\{\s*[cC][hH][aA][rR]\s*\}\}"#, in: base) { _ in charName }
        s = replace(regex: #"\{\{\s*[uU][sS][eE][rR]\s*\}\}"#, in: s) { _ in defaultUserDisplayName }
        return s
    }

    private static func replace(regex pattern: String, in string: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
        let ns = string as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: string, options: [], range: full)
        guard !matches.isEmpty else { return string }
        var result = ""
        var lastEnd = 0
        for m in matches {
            if m.range.location > lastEnd {
                result += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            }
            let matched = ns.substring(with: m.range)
            result += transform(matched)
            lastEnd = m.range.location + m.range.length
        }
        if lastEnd < ns.length {
            result += ns.substring(from: lastEnd)
        }
        return result
    }

    /// 粗略检测是否为 HTML 片段。
    static func looksLikeHTML(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.contains("<br") || lower.contains("</p>") || lower.contains("<p>")
            || lower.contains("<div") || lower.contains("<span")
            || lower.contains("<strong") || lower.contains("<b>")
            || lower.contains("<em>") || lower.contains("<i>")
            || lower.contains("<ul") || lower.contains("<ol") || lower.contains("<li")
            || lower.contains("<h1") || lower.contains("<h2") {
            return true
        }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("<") && t.range(of: #"<[a-zA-Z!/?]"#, options: .regularExpression) != nil
    }

    /// 粗略检测是否为 Markdown。
    static func looksLikeMarkdown(_ s: String) -> Bool {
        if s.contains("**") || s.contains("__") || s.contains("~~") { return true }
        if s.range(of: #"\[.+?\]\(.+?\)"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"(?m)^#{1,6}\s+\S"#, options: .regularExpression) != nil { return true }
        for line in s.split(separator: "\n", omittingEmptySubsequences: false).prefix(12) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
            if let first = t.first, first.isNumber, t.contains(". ") { return true }
        }
        return false
    }

    /// 将已套用占位符的文本转为 `AttributedString`（HTML 优先，其次 Markdown）；失败则返回 nil。
    /// `colorScheme` 用于在暗色模式下把 HTML/Markdown 解析出的近黑前景色纠正为标签色，避免在深色卡片底上不可读。
    static func attributedForPreview(_ processedPlain: String, colorScheme: ColorScheme) -> AttributedString? {
        if looksLikeHTML(processedPlain) {
            if let a = attributedFromHTML(processedPlain, colorScheme: colorScheme) { return a }
        }
        if looksLikeMarkdown(processedPlain) {
            if let a = attributedFromMarkdown(processedPlain, colorScheme: colorScheme) { return a }
        }
        return nil
    }

    /// 将 `NSAttributedString` 全文中过暗或与系统标签冲突的前景色在暗色模式下统一为 `labelColor`。
    private static func normalizeAttributedForegroundForColorScheme(_ mutable: NSMutableAttributedString, colorScheme: ColorScheme) {
        guard colorScheme == .dark else { return }
        let full = NSRange(location: 0, length: mutable.length)
        guard full.length > 0 else { return }
        let label = NSColor.labelColor
        mutable.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: label, range: range)
                return
            }
            guard let c = value as? NSColor,
                  let rgb = c.usingColorSpace(.deviceRGB)
            else { return }
            let lum = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            if lum < 0.48 {
                mutable.addAttribute(.foregroundColor, value: label, range: range)
            }
        }
    }

    /// 在 `NSAttributedString` 的 HTML 解析之前，把片段里成对的星号 Markdown 转成真实 HTML 标签。
    /// 原因：`looksLikeHTML` 优先走 WebKit 管道时，内联的 `***` / `**` 不会被当作 Markdown；纯字符串交给 `AttributedString(markdown:)` 时带标签的串也不会解析星号（例如 `<p>***x***</p>` 会原样保留星号）。
    private static func expandInlineAsteriskMarkdownToHTML(_ fragment: String) -> String {
        var t = fragment
        t = replaceRegexCapture(
            pattern: #"\*\*\*([\s\S]+?)\*\*\*"#,
            in: t
        ) { inner in
            "<strong><em>\(escapeHTMLTextForInlineEmphasis(inner))</em></strong>"
        }
        t = replaceRegexCapture(
            pattern: #"(?<!\*)\*\*([\s\S]+?)\*\*(?!\*)"#,
            in: t
        ) { inner in
            "<strong>\(escapeHTMLTextForInlineEmphasis(inner))</strong>"
        }
        return t
    }

    /// 避免强调块内的 `<`、`&` 破坏 HTML 结构或 XSS。
    private static func escapeHTMLTextForInlineEmphasis(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 将首个匹配的捕获组交给 `transform`，拼接匹配外侧原文。
    private static func replaceRegexCapture(pattern: String, in string: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
        let ns = string as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: string, options: [], range: full)
        guard !matches.isEmpty else { return string }
        var result = ""
        var lastEnd = 0
        for m in matches {
            guard m.numberOfRanges > 1 else { continue }
            let cap = m.range(at: 1)
            if cap.location == NSNotFound { continue }
            if m.range.location > lastEnd {
                result += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            }
            let inner = ns.substring(with: cap)
            result += transform(inner)
            lastEnd = m.range.location + m.range.length
        }
        if lastEnd < ns.length {
            result += ns.substring(from: lastEnd)
        }
        return result
    }

    private static func attributedFromHTML(_ fragment: String, colorScheme: ColorScheme) -> AttributedString? {
        let withInlineMD = expandInlineAsteriskMarkdownToHTML(fragment)
        let wrapped = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font: -apple-system-body; font-size: 15px; line-height: 1.45; color: -apple-system-label; }
        p, div, li { margin-bottom: 6px; }
        </style></head><body>\(withInlineMD)</body></html>
        """
        guard let data = wrapped.data(using: .utf8) else { return nil }
        guard let ns = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ), ns.length > 0 else { return nil }
        let mutable = NSMutableAttributedString(attributedString: ns)
        let base = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: base, range: range)
            }
        }
        normalizeAttributedForegroundForColorScheme(mutable, colorScheme: colorScheme)
        return try? AttributedString(mutable, including: \.appKit)
    }

    private static func attributedFromMarkdown(_ s: String, colorScheme: ColorScheme) -> AttributedString? {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .full
        guard let baseAttr = try? AttributedString(markdown: s, options: opts) else { return nil }
        let nsBase = NSAttributedString(baseAttr)
        let mutable = NSMutableAttributedString(attributedString: nsBase)
        normalizeAttributedForegroundForColorScheme(mutable, colorScheme: colorScheme)
        guard let fixed = try? AttributedString(mutable, including: \.appKit) else { return baseAttr }
        return fixed
    }
}
