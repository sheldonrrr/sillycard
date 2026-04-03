import AppKit
import Foundation
import SillycardKit

/// 从仓库根目录执行：`swift run EmbedMeo`
/// 读取 `Resources/CardSamples/cat_card.jpg` 与 `Resources/CardSamples/Meo.character.json`，生成 `Resources/CardSamples/Meo.png` 与 `Sources/Sillycard/Resources/Meo.png`。
@main
struct EmbedMeo {
    static func main() throws {
        let cwd = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let samples = cwd.appendingPathComponent("Resources/CardSamples")
        let jpg = samples.appendingPathComponent("cat_card.jpg")
        let jsonURL = samples.appendingPathComponent("Meo.character.json")
        guard FileManager.default.fileExists(atPath: jpg.path) else {
            fputs("缺少 \(jpg.path)\n", stderr)
            throw NSError(domain: "EmbedMeo", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing jpg"])
        }
        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        guard (try? JSONSerialization.jsonObject(with: Data(json.utf8))) is [String: Any] else {
            throw NSError(domain: "EmbedMeo", code: 2, userInfo: [NSLocalizedDescriptionKey: "invalid json"])
        }
        guard let img = NSImage(contentsOf: jpg),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "EmbedMeo", code: 3, userInfo: [NSLocalizedDescriptionKey: "image convert failed"])
        }
        let outData = try CharacterCardPNG.writeCharacterData(pngData: pngData, jsonString: json)
        let sampleOut = samples.appendingPathComponent("Meo.png")
        let bundleDir = cwd.appendingPathComponent("Sources/Sillycard/Resources")
        let bundleOut = bundleDir.appendingPathComponent("Meo.png")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try outData.write(to: sampleOut, options: Data.WritingOptions.atomic)
        try outData.write(to: bundleOut, options: Data.WritingOptions.atomic)
        print("Wrote:\n  \(sampleOut.path)\n  \(bundleOut.path)")
    }
}
