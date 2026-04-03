import XCTest
@testable import SillycardKit

/// 列表 / 标题展示名：长标题、领头 `_片段_`、全包 `_…_` / `**…**`、数学字母区（𝐀-𝐳）等。
final class CharacterCardTitlePresentationTests: XCTestCase {
    /// U+1D400 / U+1D41A 起的数学粗体拉丁，与常见「花哨」角色名一致。
    private static func mathematicalBoldLatinASCII(_ ascii: String) -> String {
        String(ascii.unicodeScalars.map { u -> Character in
            let v = u.value
            switch v {
            case 0x41...0x5A:
                return Character(UnicodeScalar(0x1D400 + v - 0x41)!)
            case 0x61...0x7A:
                return Character(UnicodeScalar(0x1D41A + v - 0x61)!)
            default:
                return Character(u)
            }
        })
    }

    func testLeadingItalicUnderscoreSegmentIsStrippedForDisplay() {
        let raw = "_Boob Job_ - Nika’s Heartfelt Plea. Nika has always been your sanctuary."
        let out = CharacterCardTitlePresentation.normalizeForDisplay(raw)
        XCTAssertTrue(out.hasPrefix("Boob Job - Nika"), out)
        XCTAssertFalse(out.contains("_Boob Job_"), out)
    }

    func testFullWrapDoubleAsteriskStripped() {
        let raw = "**Short Title**"
        XCTAssertEqual(CharacterCardTitlePresentation.normalizeForDisplay(raw), "Short Title")
    }

    func testMathematicalBoldLatinFoldsToASCII() {
        let fancy = Self.mathematicalBoldLatinASCII("Ian Georgopoulos")
        XCTAssertNotEqual(fancy, "Ian Georgopoulos", "测试数据应含数学字母区码位")
        XCTAssertEqual(CharacterCardTitlePresentation.normalizeForDisplay(fancy), "Ian Georgopoulos")
    }
}
