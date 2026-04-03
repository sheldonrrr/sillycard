import AppKit
@testable import SillycardKit
import SwiftUI
import XCTest

/// 验证 HTML 管道中内联 `***` / `**` 会转为可读富文本（见 CharacterCardPreviewFormatting.expandInlineAsteriskMarkdownToHTML）。
final class MarkdownInHTMLPreviewTests: XCTestCase {
    func testTripleStarInsideParagraphHTMLIsNotLiteral() throws {
        let raw = "<p>前 ***粗斜体*** 后</p>"
        let processed = CharacterCardPreviewFormatting.applyPlaceholders(raw, characterName: "C")
        XCTAssertTrue(CharacterCardPreviewFormatting.looksLikeHTML(processed))
        let attr = CharacterCardPreviewFormatting.attributedForPreview(processed, colorScheme: .light)
        XCTAssertNotNil(attr)
        let ns = try XCTUnwrap(try? NSAttributedString(attr!, including: \.appKit))
        XCTAssertFalse(ns.string.contains("***"), "不应再保留字面量三星：\(ns.string.prefix(200))")
        XCTAssertTrue(ns.string.contains("粗斜体"), ns.string)
    }

    func testDoubleStarInsideDiv() throws {
        let raw = "<div>**加粗**</div>"
        let processed = CharacterCardPreviewFormatting.applyPlaceholders(raw, characterName: "C")
        let attr = CharacterCardPreviewFormatting.attributedForPreview(processed, colorScheme: .light)
        XCTAssertNotNil(attr)
        let ns = try XCTUnwrap(try? NSAttributedString(attr!, including: \.appKit))
        XCTAssertFalse(ns.string.contains("**"))
        XCTAssertTrue(ns.string.contains("加粗"), ns.string)
    }

    func testTripleStarStillWorksForPureMarkdown() throws {
        let raw = "纯文本 ***mixed*** 尾巴"
        let processed = CharacterCardPreviewFormatting.applyPlaceholders(raw, characterName: "C")
        XCTAssertFalse(CharacterCardPreviewFormatting.looksLikeHTML(processed))
        let attr = CharacterCardPreviewFormatting.attributedForPreview(processed, colorScheme: .light)
        XCTAssertNotNil(attr)
        let ns = try XCTUnwrap(try? NSAttributedString(attr!, including: \.appKit))
        XCTAssertFalse(ns.string.contains("***"))
        XCTAssertTrue(ns.string.contains("mixed"), ns.string)
    }
}
