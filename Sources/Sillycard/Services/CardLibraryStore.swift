import Foundation

/// 多卡库清单与磁盘路径（`Application Support/Sillycard/Libraries`）。请在主线程调用。
final class CardLibraryStore {
    static let shared = CardLibraryStore()

    static let defaultLibraryId = "default"

    private let fm = FileManager.default
    private(set) var manifest: CardLibraryManifest!

    private var sillycardSupportURL: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Sillycard", isDirectory: true)
    }

    /// 所有托管卡库、`libraries.json` 所在的 Sillycard 资料根目录（可向用户展示「这就是导入角色卡的文件夹」）。
    var applicationSupportRootURL: URL {
        sillycardSupportURL.standardizedFileURL
    }

    private var librariesDirectoryURL: URL {
        sillycardSupportURL.appendingPathComponent("Libraries", isDirectory: true)
    }

    private var manifestFileURL: URL {
        librariesDirectoryURL.appendingPathComponent("libraries.json", isDirectory: false)
    }

    /// 旧版单库路径（迁移用）。
    private var legacySingleLibraryURL: URL {
        sillycardSupportURL.appendingPathComponent("Library", isDirectory: true)
    }

    func loadOrCreate() throws {
        if manifest != nil { return }
        try fm.createDirectory(at: sillycardSupportURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: librariesDirectoryURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: manifestFileURL.path) {
            let data = try Data(contentsOf: manifestFileURL)
            manifest = try JSONDecoder().decode(CardLibraryManifest.self, from: data)
            if manifest.libraries.isEmpty {
                try bootstrapDefaultOnly()
            }
            try ensureManagedFoldersExist()
            return
        }

        migrateLegacyIfNeeded()
        if !fm.fileExists(atPath: managedFolderURL(for: Self.defaultLibraryId).path) {
            try fm.createDirectory(at: managedFolderURL(for: Self.defaultLibraryId), withIntermediateDirectories: true)
        }
        manifest = CardLibraryManifest(
            libraries: [
                CardLibraryEntry(id: Self.defaultLibraryId, displayName: "默认卡库", bookmarkData: nil),
            ],
            activeLibraryId: Self.defaultLibraryId
        )
        try save()
    }

    private func bootstrapDefaultOnly() throws {
        manifest.libraries = [
            CardLibraryEntry(id: Self.defaultLibraryId, displayName: "默认卡库", bookmarkData: nil),
        ]
        manifest.activeLibraryId = Self.defaultLibraryId
        try fm.createDirectory(at: managedFolderURL(for: Self.defaultLibraryId), withIntermediateDirectories: true)
        try save()
    }

    private func migrateLegacyIfNeeded() {
        let legacy = legacySingleLibraryURL.standardizedFileURL
        let `default` = managedFolderURL(for: Self.defaultLibraryId).standardizedFileURL
        guard fm.fileExists(atPath: legacy.path) else { return }
        guard !fm.fileExists(atPath: `default`.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: `default`)
        } catch {
            try? fm.copyItem(at: legacy, to: `default`)
        }
    }

    private func ensureManagedFoldersExist() throws {
        for e in manifest.libraries where e.isManaged {
            let u = managedFolderURL(for: e.id)
            if !fm.fileExists(atPath: u.path) {
                try fm.createDirectory(at: u, withIntermediateDirectories: true)
            }
        }
    }

    private func managedFolderURL(for id: String) -> URL {
        librariesDirectoryURL.appendingPathComponent(id, isDirectory: true).standardizedFileURL
    }

    func resolveURL(for entry: CardLibraryEntry) throws -> URL {
        if let data = entry.bookmarkData {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                throw NSError(
                    domain: "Sillycard",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "该卡库的路径书签已失效，本版本无法再次授权该文件夹。请新建托管卡库并将 PNG 拖入导入。"]
                )
            }
            return url.standardizedFileURL
        }
        return managedFolderURL(for: entry.id)
    }

    func createManagedLibrary(displayName: String) throws -> CardLibraryEntry {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "Sillycard", code: 11, userInfo: [NSLocalizedDescriptionKey: "卡库名称不能为空"])
        }
        let id = UUID().uuidString
        let entry = CardLibraryEntry(id: id, displayName: trimmed, bookmarkData: nil)
        try fm.createDirectory(at: managedFolderURL(for: id), withIntermediateDirectories: true)
        manifest.libraries.append(entry)
        manifest.activeLibraryId = id
        try save()
        return entry
    }

    func addExternalLibrary(displayName: String, folderURL: URL) throws -> CardLibraryEntry {
        let std = folderURL.standardizedFileURL
        let data = try std.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let id = UUID().uuidString
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? std.lastPathComponent
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = CardLibraryEntry(id: id, displayName: name, bookmarkData: data)
        manifest.libraries.append(entry)
        manifest.activeLibraryId = id
        try save()
        return entry
    }

    func setActiveLibrary(id: String) throws {
        guard manifest.libraries.contains(where: { $0.id == id }) else { return }
        manifest.activeLibraryId = id
        try save()
    }

    func save() throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestFileURL, options: .atomic)
    }

    func entry(id: String) -> CardLibraryEntry? {
        manifest.libraries.first { $0.id == id }
    }
}
