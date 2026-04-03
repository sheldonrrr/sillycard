import AppKit
@testable import SillycardKit
import SwiftUI
import XCTest

/// 在真实 `Resources/CardSamples` 上扫描「描述类字段 → 预览富文本」管线，汇总统计并输出**可执行的优化结论**（`swift test` 日志中可见）。
final class CardStyleCaptureReportTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var sampleDir: URL {
        repoRoot.appendingPathComponent("Resources/CardSamples", isDirectory: true)
    }

    func testStyleCaptureReportOnSampleCards() throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sampleDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("无 Resources/CardSamples 目录")
        }

        let items = try LibraryScanner.scan(root: sampleDir)
        guard !items.isEmpty else {
            throw XCTSkip("Resources/CardSamples 内无 PNG")
        }

        var report: [String] = []
        report.append("========== Sillycard 样式捕捉报告（Resources/CardSamples）==========")

        var totalFields = 0
        var pathHTML = 0
        var pathMarkdown = 0
        var pathPlain = 0
        var richParseFailures = 0
        var literalTripleAfterRich: [(file: String, field: String, snippet: String)] = []
        var literalDoubleAfterRich: [(file: String, field: String)] = []
        var underscoreInHTMLFields = 0
        var backticksInHTMLFields = 0
        var mdLinkInHTMLFields = 0

        let underscorePair = try NSRegularExpression(pattern: #"(?<!_)__(?!_)[\s\S]{1,800}?__(?!_)"#, options: [])
        let mdLink = try NSRegularExpression(pattern: #"\[[^\]]+\]\([^)]+\)"#, options: [])

        for item in items {
            let data = try Data(contentsOf: item.fileURL)
            let json: String
            do {
                json = try CharacterCardPNG.readCharacterJSON(from: data)
            } catch {
                report.append("跳过（读卡失败）: \(item.fileURL.lastPathComponent) — \(error.localizedDescription)")
                continue
            }

            let preview = SillyTavernCardPreview(jsonString: json)
            let name = preview.name ?? item.displayName
            let slices = Self.previewTextSlices(from: preview)

            for (fieldLabel, raw) in slices {
                guard raw.count >= 2 else { continue }
                totalFields += 1
                let processed = CharacterCardPreviewFormatting.applyPlaceholders(raw, characterName: name)
                let isHTML = CharacterCardPreviewFormatting.looksLikeHTML(processed)
                let isMD = CharacterCardPreviewFormatting.looksLikeMarkdown(processed)

                if isHTML { pathHTML += 1 } else if isMD { pathMarkdown += 1 } else { pathPlain += 1 }

                let attr = CharacterCardPreviewFormatting.attributedForPreview(processed, colorScheme: .light)
                let plainOut: String = {
                    if let attr,
                       let ns = try? NSAttributedString(attr, including: \.appKit)
                    {
                        return ns.string
                    }
                    return processed
                }()

                if (isHTML || isMD), attr == nil {
                    richParseFailures += 1
                }

                if processed.contains("***"), attr != nil, plainOut.contains("***") {
                    let snip = Self.snippetAround(plainOut, marker: "***", width: 40)
                    literalTripleAfterRich.append((item.fileURL.lastPathComponent, fieldLabel, snip))
                }

                if processed.contains("**"), attr != nil, plainOut.contains("**") {
                    literalDoubleAfterRich.append((item.fileURL.lastPathComponent, fieldLabel))
                }

                if isHTML {
                    if underscorePair.firstMatch(in: processed, options: [], range: NSRange(location: 0, length: (processed as NSString).length)) != nil {
                        underscoreInHTMLFields += 1
                    }
                    if processed.contains("`") {
                        backticksInHTMLFields += 1
                    }
                    if mdLink.firstMatch(in: processed, options: [], range: NSRange(location: 0, length: (processed as NSString).length)) != nil {
                        mdLinkInHTMLFields += 1
                    }
                }
            }
        }

        report.append("")
        report.append("— 样本规模 —")
        report.append("卡片张数: \(items.count)")
        report.append("参与统计的非空文本字段数: \(totalFields)")
        report.append("字段走 HTML 判定: \(pathHTML)")
        report.append("字段走 Markdown 判定: \(pathMarkdown)")
        report.append("字段走纯文本（无 HTML/MD 启发）: \(pathPlain)")
        report.append("启发为富文本但 attributedForPreview 返回 nil: \(richParseFailures)")

        report.append("")
        report.append("— 回归检查（三星/双星在富文本结果中仍字面保留）—")
        if literalTripleAfterRich.isEmpty {
            report.append("字面量 ***（渲染后）: 未发现（当前样本下三星强调捕捉正常或未使用）")
        } else {
            report.append("字面量 ***（渲染后）: \(literalTripleAfterRich.count) 处 — 需检查成对/嵌套或预处理边界")
            for e in literalTripleAfterRich.prefix(12) {
                report.append("  · \(e.file) [\(e.field)] … \(e.snippet) …")
            }
        }
        if literalDoubleAfterRich.isEmpty {
            report.append("字面量 **（渲染后）: 未发现")
        } else {
            report.append("字面量 **（渲染后）: \(literalDoubleAfterRich.count) 处（可能为未成对 ** 或代码片段）")
            for e in literalDoubleAfterRich.prefix(8) {
                report.append("  · \(e.file) [\(e.field)]")
            }
        }

        report.append("")
        report.append("— 优化机会（启发式，HTML 管线内尚未预转义的 Markdown 形态）—")
        report.append("含 __…__ 且判定为 HTML 的字段数: \(underscoreInHTMLFields) → 结论: 可考虑对 HTML 片段增加与 ** 类似的下划线强调预转义。")
        report.append("含反引号 ` 且为 HTML 的字段数: \(backticksInHTMLFields) → 结论: 行内代码在 WebKit 管道中通常不渲染；可按需转 <code>。")
        report.append("含 Markdown 链接 [text](url) 且为 HTML 的字段数: \(mdLinkInHTMLFields) → 结论: 可预转为 <a href> 或保留原样由 Tavern 外阅读。")

        report.append("")
        report.append("— 总结 —")
        let critical = !literalTripleAfterRich.isEmpty || !literalDoubleAfterRich.isEmpty
        if critical {
            report.append("状态: 发现渲染后仍含 ** / *** 的字段，建议结合上表路径排查括号是否成对、或是否存在非常规嵌套。")
        } else {
            report.append("状态: 当前 Resources/CardSamples 中，成对 ** / *** 在富文本输出侧未发现明显滞留（在现有 HTML 预转义 + Markdown 回退逻辑下）。")
        }
        if underscoreInHTMLFields > 0 || backticksInHTMLFields > 0 || mdLinkInHTMLFields > 0 {
            report.append("后续优化优先序（按命中量）: ① 下划线强调 ② 行内代码 ③ 链接预转义（均在「先判 HTML」场景下受益）。")
        } else {
            report.append("后续优化: 当前样本未命中 __ / ` / []() 与 HTML 叠加之典型条数；可扩充卡库后再跑本测试更新结论。")
        }

        report.append("============================================================")

        let blob = report.joined(separator: "\n")
        print("\n" + blob + "\n")

        if let data = blob.data(using: .utf8) {
            let attach = XCTAttachment(data: data)
            attach.name = "style-capture-report.txt"
            attach.lifetime = .keepAlways
            add(attach)
        }

        XCTAssertFalse(critical, "存在富文本渲染后仍含 **/*** 的字段，详见附件 style-capture-report.txt 与上文日志。\n\(blob)")
    }

    private static func previewTextSlices(from preview: SillyTavernCardPreview) -> [(String, String)] {
        var out: [(String, String)] = []
        func add(_ key: String, _ v: String?) {
            guard let s = v?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            out.append((key, s))
        }
        add("description", preview.description)
        add("personality", preview.personality)
        add("scenario", preview.scenario)
        add("first_mes", preview.firstMes)
        add("mes_example", preview.mesExample)
        add("creator_notes", preview.creatorNotes)
        add("system_prompt", preview.systemPrompt)
        add("post_history_instructions", preview.postHistoryInstructions)
        for (i, g) in preview.alternateGreetings.enumerated() {
            add("alternate_greeting_\(i)", g)
        }
        for e in preview.worldBookEntries {
            add("world_book:\(e.id)", e.content)
        }
        return out
    }

    private static func snippetAround(_ s: String, marker: String, width: Int) -> String {
        guard let r = s.range(of: marker) else { return "" }
        let lo = s.index(r.lowerBound, offsetBy: -width, limitedBy: s.startIndex) ?? s.startIndex
        let hi = s.index(r.upperBound, offsetBy: width, limitedBy: s.endIndex) ?? s.endIndex
        return String(s[lo..<hi]).replacingOccurrences(of: "\n", with: " ")
    }
}
