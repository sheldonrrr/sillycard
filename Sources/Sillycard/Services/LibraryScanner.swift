import Foundation

enum LibraryScanner {
    static func scan(root: URL) throws -> [CardItem] {
        let rootStandard = root.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "Sillycard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a directory"])
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [CardItem] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "png" else { continue }
            let vals = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard vals?.isRegularFile == true else { continue }

            let folder: String
            let parent = url.deletingLastPathComponent().standardizedFileURL
            if parent == rootStandard {
                folder = ""
            } else {
                let rel = parent.path.replacingOccurrences(of: rootStandard.path + "/", with: "")
                folder = rel
            }
            items.append(CardItem(fileURL: url, relativeFolder: folder))
        }
        return items.sorted { $0.fileURL.path < $1.fileURL.path }
    }

    /// 递归统计资料库内 PNG 数量（含归档子文件夹）。
    static func countAllPNG(root: URL) throws -> Int {
        try scan(root: root).count
    }
}
