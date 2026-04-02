import Foundation
import zlib

/// PNG signature + chunk encode/decode aligned with SillyTavern `src/png/encode.js` and `png-chunks-extract`.
enum PNGChunkError: Error {
    case tooShort
    case invalidSignature
    case invalidChunk
    case truncated
}

struct PNGChunk: Equatable {
    var name: String
    var data: Data
}

enum PNGChunks {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func extract(from png: Data) throws -> [PNGChunk] {
        guard png.count >= 8 else { throw PNGChunkError.tooShort }
        guard Array(png.prefix(8)) == signature else { throw PNGChunkError.invalidSignature }
        var pos = 8
        var chunks: [PNGChunk] = []
        while pos + 12 <= png.count {
            let len = readUInt32BE(png, pos)
            pos += 4
            guard let nameData = png.subdata(pos, length: 4),
                  let name = String(data: nameData, encoding: .ascii),
                  name.count == 4
            else { throw PNGChunkError.invalidChunk }
            pos += 4
            guard let chunkData = png.subdata(pos, length: Int(len)) else { throw PNGChunkError.truncated }
            pos += Int(len)
            guard pos + 4 <= png.count else { throw PNGChunkError.truncated }
            _ = readUInt32BE(png, pos)
            pos += 4
            chunks.append(PNGChunk(name: name, data: chunkData))
            if name == "IEND" { break }
        }
        return chunks
    }

    static func encode(chunks: [PNGChunk]) -> Data {
        var out = Data(signature)
        for chunk in chunks {
            let len = UInt32(chunk.data.count)
            out.append(bigEndian: len)
            guard let typeData = chunk.name.data(using: .ascii), typeData.count == 4 else { continue }
            out.append(typeData)
            out.append(chunk.data)
            let crc = crc32png(type: chunk.name, data: chunk.data)
            out.append(bigEndian: crc)
        }
        return out
    }

    /// CRC32 over chunk type (ASCII) + chunk data, matching `crc` npm as used in ST encode.js.
    private static func crc32png(type: String, data: Data) -> UInt32 {
        var crc = crc32(0, nil, 0)
        for scalar in type.utf8 {
            var b = scalar
            crc = crc32(crc, &b, 1)
        }
        crc = data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return crc }
            return crc32(crc, base, uInt(data.count))
        }
        return UInt32(truncatingIfNeeded: crc)
    }

    private static func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { acc, i in
            (acc << 8) | UInt32(data[offset + i])
        }
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func subdata(_ pos: Int, length: Int) -> Data? {
        guard length >= 0, pos >= 0, pos + length <= count else { return nil }
        return subdata(in: pos..<(pos + length))
    }
}

// MARK: - tEXt (png-chunk-text compatible, Latin-1)

struct TEXtChunk {
    var keyword: String
    var text: String
}

enum TEXtCodec {
    static func decode(chunkData: Data) throws -> TEXtChunk {
        guard let nullIdx = chunkData.firstIndex(of: 0) else {
            throw CharacterCardPNGError.invalidTextChunk
        }
        let keyData = chunkData.subdata(in: chunkData.startIndex..<nullIdx)
        let textStart = chunkData.index(after: nullIdx)
        guard let keyword = String(data: keyData, encoding: .isoLatin1) else {
            throw CharacterCardPNGError.invalidTextChunk
        }
        if textStart >= chunkData.endIndex {
            return TEXtChunk(keyword: keyword, text: "")
        }
        let textData = chunkData.subdata(in: textStart..<chunkData.endIndex)
        let text = String(data: textData, encoding: .isoLatin1) ?? ""
        return TEXtChunk(keyword: keyword, text: text)
    }

    static func encode(keyword: String, text: String) throws -> Data {
        guard keyword.count < 80, !keyword.contains("\u{0}") else {
            throw CharacterCardPNGError.invalidKeyword
        }
        guard !text.contains("\u{0}") else { throw CharacterCardPNGError.invalidTextChunk }
        var out = Data()
        for u in keyword.unicodeScalars {
            guard u.value <= 255 else { throw CharacterCardPNGError.invalidKeyword }
            out.append(UInt8(truncatingIfNeeded: u.value))
        }
        out.append(0)
        for u in text.unicodeScalars {
            guard u.value <= 255 else { throw CharacterCardPNGError.invalidKeyword }
            out.append(UInt8(truncatingIfNeeded: u.value))
        }
        return out
    }
}
