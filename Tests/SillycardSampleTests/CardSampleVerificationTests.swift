import Foundation
@testable import SillycardKit
import XCTest

/// 使用仓库根目录下 `Resources/CardSamples` 中的 PNG 做无 UI 的回归检查（扫描、读元数据、JSON、扁平化、预览解析、可选写回）。
final class CardSampleVerificationTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var sampleDir: URL {
        repoRoot.appendingPathComponent("Resources/CardSamples", isDirectory: true)
    }

    func testSampleDirectoryExists() throws {
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: sampleDir.path, isDirectory: &isDir), "缺少 Resources/CardSamples，请在仓库根目录保留示例卡源文件或运行 swift run EmbedMeo")
        XCTAssertTrue(isDir.boolValue)
    }

    func testLibraryScannerFindsPNGFiles() throws {
        let items = try LibraryScanner.scan(root: sampleDir)
        XCTAssertGreaterThan(items.count, 0, "Resources/CardSamples 中应至少有一张 .png")
        XCTAssertTrue(items.allSatisfy { $0.fileURL.pathExtension.lowercased() == "png" })
    }

    func testEachSampleCardExtractsValidJSON() throws {
        let items = try LibraryScanner.scan(root: sampleDir)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            let data = try Data(contentsOf: item.fileURL)
            let json: String
            do {
                json = try CharacterCardPNG.readCharacterJSON(from: data)
            } catch {
                XCTFail("「\(item.fileURL.lastPathComponent)」读取 PNG 元数据失败: \(error.localizedDescription)")
                continue
            }
            XCTAssertTrue(
                CharacterCardJSONPretty.isValidJSONString(json),
                "「\(item.fileURL.lastPathComponent)」提取的 JSON 无法被 JSONSerialization 解析"
            )
        }
    }

    func testFlattenAndPreviewSmokeForEachSample() throws {
        let items = try LibraryScanner.scan(root: sampleDir)
        for item in items {
            let data = try Data(contentsOf: item.fileURL)
            let json = try CharacterCardPNG.readCharacterJSON(from: data)
            let rows = CharacterCardJSONFlattener.rows(from: json, maxDepth: 9, maxValueLength: 50_000)
            XCTAssertFalse(rows.isEmpty, "「\(item.fileURL.lastPathComponent)」扁平化结果为空（可能数据结构异常）")
            let preview = SillyTavernCardPreview(jsonString: json)
            let hasPreviewSignal = !(preview.name ?? "").isEmpty || !preview.tags.isEmpty || !(preview.description ?? "").isEmpty
            XCTAssertTrue(hasPreviewSignal, "「\(item.fileURL.lastPathComponent)」SillyTavernCardPreview 未解析出常见展示字段")
        }
    }

    /// 验证紧凑 JSON 可写回 PNG 并再次读出（不写入磁盘，仅内存）。
    func testRoundTripWriteJSONInMemory() throws {
        let items = try LibraryScanner.scan(root: sampleDir)
        guard let first = items.first else {
            throw XCTSkip("无样本文件")
        }
        let data = try Data(contentsOf: first.fileURL)
        let original = try CharacterCardPNG.readCharacterJSON(from: data)
        guard let minified = CharacterCardJSONPretty.minified(original) else {
            XCTFail("无法生成 minified JSON")
            return
        }
        let out = try CharacterCardPNG.writeCharacterData(pngData: data, jsonString: minified)
        let round = try CharacterCardPNG.readCharacterJSON(from: out)
        XCTAssertTrue(CharacterCardJSONPretty.isValidJSONString(round))
        XCTAssertEqual(
            CharacterCardJSONPretty.minified(round),
            CharacterCardJSONPretty.minified(original),
            "写回后再读应得到等价 JSON"
        )
    }

    func testMeoSampleCardMetadata() throws {
        let meoURL = sampleDir.appendingPathComponent("Meo.png")
        guard FileManager.default.fileExists(atPath: meoURL.path) else {
            throw XCTSkip("缺少 Meo.png，可在仓库根执行 swift run EmbedMeo 生成")
        }
        let data = try Data(contentsOf: meoURL)
        let json = try CharacterCardPNG.readCharacterJSON(from: data)
        let preview = SillyTavernCardPreview(jsonString: json)
        XCTAssertEqual(preview.name, "Meo")
        XCTAssertEqual(preview.creator, "Sillycard")
        XCTAssertTrue(preview.tags.contains("Sillycard"), "应含 Sillycard 标签")
        let sys = preview.systemPrompt ?? ""
        XCTAssertTrue(sys.contains("喵"), "系统提示应约束「喵」对白")
    }
}
