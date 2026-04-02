import Foundation

enum CharacterCardPNGError: Error, LocalizedError {
    case noTextChunks
    case noCharacterData
    case invalidTextChunk
    case invalidKeyword
    case invalidJSONForV3

    var errorDescription: String? {
        switch self {
        case .noTextChunks: "PNG 中无 tEXt 块"
        case .noCharacterData: "无 chara / ccv3 元数据"
        case .invalidTextChunk: "tEXt 块无效"
        case .invalidKeyword: "tEXt keyword 无效"
        case .invalidJSONForV3: "JSON 无效"
        }
    }
}

/// Matches SillyTavern `src/character-card-parser.js` read/write behavior.
enum CharacterCardPNG {
    static func readCharacterJSON(from pngData: Data) throws -> String {
        let chunks = try PNGChunks.extract(from: pngData)
        let textPayloads: [TEXtChunk] = try chunks
            .filter { $0.name == "tEXt" }
            .map { try TEXtCodec.decode(chunkData: $0.data) }

        guard !textPayloads.isEmpty else { throw CharacterCardPNGError.noTextChunks }

        if let ccv3 = textPayloads.first(where: { $0.keyword.lowercased() == "ccv3" }) {
            return try decodeBase64UTF8(ccv3.text)
        }
        if let chara = textPayloads.first(where: { $0.keyword.lowercased() == "chara" }) {
            return try decodeBase64UTF8(chara.text)
        }
        throw CharacterCardPNGError.noCharacterData
    }

    static func writeCharacterData(pngData: Data, jsonString: String) throws -> Data {
        var chunks = try PNGChunks.extract(from: pngData)
        chunks = chunks.filter { chunk in
            guard chunk.name == "tEXt" else { return true }
            guard let decoded = try? TEXtCodec.decode(chunkData: chunk.data) else { return true }
            let k = decoded.keyword.lowercased()
            return k != "chara" && k != "ccv3"
        }

        guard let iendIndex = chunks.lastIndex(where: { $0.name == "IEND" }) else {
            throw PNGChunkError.invalidChunk
        }

        let base64Encoded = Data(jsonString.utf8).base64EncodedString()
        let charaData = try TEXtCodec.encode(keyword: "chara", text: base64Encoded)
        let charaChunk = PNGChunk(name: "tEXt", data: charaData)
        chunks.insert(charaChunk, at: iendIndex)

        if let v3Data = tryMakeV3ChunkData(from: jsonString) {
            let ccv3Chunk = PNGChunk(name: "tEXt", data: v3Data)
            chunks.insert(ccv3Chunk, at: iendIndex + 1)
        }

        return PNGChunks.encode(chunks: chunks)
    }

    private static func tryMakeV3ChunkData(from jsonString: String) -> Data? {
        guard var obj = try? JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any] else {
            return nil
        }
        obj["spec"] = "chara_card_v3"
        obj["spec_version"] = "3.0"
        guard let out = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: out, encoding: .utf8)
        else { return nil }
        let b64 = Data(s.utf8).base64EncodedString()
        return try? TEXtCodec.encode(keyword: "ccv3", text: b64)
    }

    private static func decodeBase64UTF8(_ base64: String) throws -> String {
        guard let raw = Data(base64Encoded: base64) else {
            throw CharacterCardPNGError.noCharacterData
        }
        guard let s = String(data: raw, encoding: .utf8) else {
            throw CharacterCardPNGError.noCharacterData
        }
        return s
    }
}
