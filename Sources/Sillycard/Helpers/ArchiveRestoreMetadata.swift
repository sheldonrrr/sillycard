import Darwin
import Foundation

/// 归档前相对卡库根目录的子路径（仅字母/数字/合法文件夹名）；空字符串表示根目录。
enum ArchiveRestoreMetadata {
    /// 与 PNG 文件绑定的扩展属性名（不写入 JSON，避免改动卡内容）。
    static let xattrName = "com.sillycard.preArchiveRelativeFolder"

    static func setPreArchiveRelativeFolder(_ folder: String, on fileURL: URL) throws {
        let normalized = Self.normalizeForStorage(folder)
        let data = Data(normalized.utf8)
        let path = fileURL.path
        let err = data.withUnsafeBytes { raw in
            setxattr(path, xattrName, raw.baseAddress, data.count, 0, 0)
        }
        guard err == 0 else {
            throw NSError(
                domain: "Sillycard",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "无法写入归档来源标记：\(path) errno=\(errno)"]
            )
        }
    }

    /// - `nil`：未写入扩展属性（例如升级前归档的卡片）。
    /// - `""`：归档前位于卡库根目录。
    static func getPreArchiveRelativeFolder(from fileURL: URL) -> String? {
        let path = fileURL.path
        let size = getxattr(path, xattrName, nil, 0, 0, 0)
        if size < 0 { return nil }
        if size == 0 { return "" }
        var buf = [UInt8](repeating: 0, count: size)
        let r = buf.withUnsafeMutableBytes { raw in
            getxattr(path, xattrName, raw.baseAddress, size, 0, 0)
        }
        guard r >= 0, let s = String(bytes: buf.prefix(r), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : t
    }

    static func removePreArchiveMetadata(from fileURL: URL) {
        removexattr(fileURL.path, xattrName, 0)
    }

    static func normalizeForStorage(_ folder: String) -> String {
        folder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析为位于 `libraryRoot` 之下的目标目录；禁止 `..` 与盘外逃逸。
    static func safeDestinationDirectory(libraryRoot: URL, relativeFolder: String) throws -> URL {
        let root = libraryRoot.standardizedFileURL
        var rel = normalizeForStorage(relativeFolder)
        while rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty {
            return root
        }
        let parts = rel.split(separator: "/").map(String.init)
        for p in parts where p == "." || p == ".." || p.isEmpty {
            throw NSError(
                domain: "Sillycard",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "无效的归档原路径标记，无法恢复。"]
            )
        }
        var dir = root
        for p in parts {
            dir = dir.appendingPathComponent(p, isDirectory: true)
        }
        let rootPath = root.path
        let dirPath = dir.standardizedFileURL.path
        guard dirPath == rootPath || dirPath.hasPrefix(rootPath + "/") else {
            throw NSError(
                domain: "Sillycard",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "归档原路径超出卡库范围，已拒绝恢复。"]
            )
        }
        return dir.standardizedFileURL
    }
}
