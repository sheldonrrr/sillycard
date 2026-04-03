import Foundation

enum DefaultLibrary {
    /// 应用托管的默认角色卡目录（Application Support 下，无需通过访达书签授权即可读写）。
    static func directoryURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("Sillycard", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.standardizedFileURL
    }
}
