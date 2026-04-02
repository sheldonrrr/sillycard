import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var libraryRoot: URL?
    @Published var cardItems: [CardItem] = []
    @Published var selection: CardItem?
    @Published var inspectorMode: InspectorEditMode = .preview

    /// Filter: empty string = all folders; otherwise relative folder path prefix
    @Published var selectedCategoryFolder: String?
    /// Tags must all appear on card (AND).
    @Published var selectedTags: Set<String> = []

    @Published private(set) var metadataCache: [URL: CachedCardMetadata] = [:]
    @Published private(set) var parseState: [URL: CardParseState] = [:]
    @Published private(set) var allTagsInLibrary: [String] = []

    /// Live JSON string in Inspector / editor (synced when selection changes or after load).
    @Published var editingJSON: String = ""
    @Published var isDirty: Bool = false

    /// 用户透过系统面板选定的资料库根目录对应的安全作用域（沙盒下须保持直至换库）。
    private var securityScopedLibraryRoot: URL?
    /// 独立窗口打开单张 PNG 时，对其文件 URL 的作用域（与资料库内路径无关）。
    private var securityScopedStandalonePNG: URL?

    var filteredItems: [CardItem] {
        cardItems.filter { item in
            if let cat = selectedCategoryFolder {
                if cat.isEmpty {
                    if !item.relativeFolder.isEmpty { return false }
                } else {
                    if item.relativeFolder != cat && !item.relativeFolder.hasPrefix(cat + "/") { return false }
                }
            }
            if selectedTags.isEmpty { return true }
            guard let meta = metadataCache[item.fileURL],
                  let root = jsonDataDict(meta.jsonString),
                  let dataObj = root["data"] as? [String: Any],
                  let tags = dataObj["tags"] as? [String]
            else { return false }
            let set = Set(tags.map { $0.lowercased() })
            return selectedTags.allSatisfy { set.contains($0.lowercased()) }
        }
    }

    /// Non-empty relative paths only; root-level cards use `""` via separate sidebar row.
    var categoryFolders: [String] {
        Set(cardItems.map(\.relativeFolder)).filter { !$0.isEmpty }.sorted()
    }

    var hasRootLevelCards: Bool {
        cardItems.contains { $0.relativeFolder.isEmpty }
    }

    /// 弹出系统文件夹选择面板并载入资料库（沙盒下须由此取得访问权）。
    func pickAndOpenLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "选择资料库文件夹"
        panel.message = "请选择包含 PNG 角色卡的文件夹。选择后即表示你授权本 App 读取并保存该文件夹内的卡片文件。"
        panel.prompt = "打开"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLibrary(at: url)
    }

    /// 弹出打开单张角色卡 PNG（用于未开资料库时）。
    func pickAndOpenStandalonePNG() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png]
        panel.title = "打开 PNG 角色卡"
        panel.message = "请选择一张 PNG。选择后本 App 仅此文件获得读写授权（用于编辑与另存）。"
        panel.prompt = "打开"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let key = url.standardizedFileURL
        if let prev = securityScopedStandalonePNG {
            prev.stopAccessingSecurityScopedResource()
            securityScopedStandalonePNG = nil
        }
        if key.startAccessingSecurityScopedResource() {
            securityScopedStandalonePNG = key
        } else {
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: "无法获得该 PNG 的访问权限，读取或保存可能失败。\n\n请关闭后再用「打开 PNG」重选文件。"
            )
        }
        openSingleCardEditor(url: key)
    }

    func openLibrary(at url: URL) {
        let standardized = url.standardizedFileURL
        if let prev = securityScopedLibraryRoot {
            prev.stopAccessingSecurityScopedResource()
            securityScopedLibraryRoot = nil
        }
        if let solo = securityScopedStandalonePNG {
            solo.stopAccessingSecurityScopedResource()
            securityScopedStandalonePNG = nil
        }

        let accessOK = standardized.startAccessingSecurityScopedResource()
        if accessOK {
            securityScopedLibraryRoot = standardized
        } else {
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: """
                未能获得文件夹访问权限，无法列出或保存卡片。

                请使用工具栏或侧栏的「打开文件夹」通过系统窗口重新选择资料库。不要期望在未授权时直接访问任意路径。
                若仍失败，可在「系统设置 → 隐私与安全性」中检查是否有限制本 App 访问文件的描述文件或安全软件拦截。
                """
            )
        }

        libraryRoot = standardized
        do {
            cardItems = try LibraryScanner.scan(root: standardized)
        } catch {
            cardItems = []
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: "无法读取文件夹：\(error.localizedDescription)"
            )
        }
        selection = nil
        editingJSON = ""
        isDirty = false
        selectedCategoryFolder = nil
        selectedTags = []
        metadataCache = [:]
        parseState = [:]
        allTagsInLibrary = []
        Task { await prewarmMetadataForTags() }
    }

    func select(_ item: CardItem?) {
        selection = item
        inspectorMode = .preview
        isDirty = false
        if let item {
            Task { await loadMetadata(for: item.fileURL, forceReload: false, updateEditingString: true) }
        } else {
            editingJSON = ""
        }
    }

    func loadMetadata(for url: URL, forceReload: Bool, updateEditingString: Bool) async {
        let key = url.standardizedFileURL
        if !forceReload, let c = metadataCache[key] {
            let mtime = try? key.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if c.sourceFileMTime == nil || c.sourceFileMTime == mtime {
                if updateEditingString { editingJSON = c.jsonString }
                var ps = parseState
                ps[key] = .ok
                parseState = ps
                return
            }
        }

        do {
            let data = try Data(contentsOf: key)
            let json = try CharacterCardPNG.readCharacterJSON(from: data)
            let mtime = try key.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let entry = CachedCardMetadata(jsonString: json, lastReadAt: Date(), sourceFileMTime: mtime)
            var mc = metadataCache
            mc[key] = entry
            metadataCache = mc
            var ps = parseState
            ps[key] = .ok
            parseState = ps
            if updateEditingString, selection?.fileURL.standardizedFileURL == key {
                editingJSON = json
            }
            recomputeAllTags()
        } catch let e as CharacterCardPNGError {
            var ps = parseState
            switch e {
            case .noTextChunks, .noCharacterData:
                ps[key] = .noMetadata
            default:
                ps[key] = .error(e.localizedDescription)
            }
            parseState = ps
            if updateEditingString, selection?.fileURL.standardizedFileURL == key {
                editingJSON = ""
            }
        } catch {
            var ps = parseState
            ps[key] = .error(error.localizedDescription)
            parseState = ps
            if updateEditingString, selection?.fileURL.standardizedFileURL == key {
                editingJSON = ""
            }
        }
    }

    func refreshMetadataForSelection() {
        guard let url = selection?.fileURL else { return }
        Task { await loadMetadata(for: url, forceReload: true, updateEditingString: true) }
    }

    func refreshMetadata(for url: URL) async {
        await loadMetadata(for: url, forceReload: true, updateEditingString: false)
    }

    /// After successful save: update cache and UI without re-reading PNG.
    func applySavedJSON(_ json: String, to url: URL) {
        let key = url.standardizedFileURL
        let mtime = try? key.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        var mc = metadataCache
        mc[key] = CachedCardMetadata(jsonString: json, lastReadAt: Date(), sourceFileMTime: mtime)
        metadataCache = mc
        if selection?.fileURL.standardizedFileURL == key {
            editingJSON = json
        }
        isDirty = false
        inspectorMode = .preview
        recomputeAllTags()
    }

    func markEditingChanged(_ newValue: String) {
        editingJSON = newValue
        isDirty = true
    }

    func validateJSON(_ string: String) -> Bool {
        guard let d = string.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: d)) != nil
    }

    func saveCurrentSelection() async throws {
        guard let url = selection?.fileURL else { return }
        try await save(url: url, jsonString: editingJSON)
    }

    func save(url: URL, jsonString: String) async throws {
        guard validateJSON(jsonString) else {
            throw NSError(domain: "Sillycard", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON 无效"])
        }
        let key = url.standardizedFileURL
        let pngData = try Data(contentsOf: key)
        let out = try CharacterCardPNG.writeCharacterData(pngData: pngData, jsonString: jsonString)
        try out.write(to: key, options: .atomic)
        applySavedJSON(jsonString, to: key)
    }

    func saveAs(url: URL, jsonString: String, to destination: URL) async throws {
        guard validateJSON(jsonString) else {
            throw NSError(domain: "Sillycard", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON 无效"])
        }
        let pngData = try Data(contentsOf: url)
        let out = try CharacterCardPNG.writeCharacterData(pngData: pngData, jsonString: jsonString)
        try out.write(to: destination, options: .atomic)
        // New file: cache under destination
        let mtime = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let dkey = destination.standardizedFileURL
        var mc = metadataCache
        mc[dkey] = CachedCardMetadata(
            jsonString: jsonString,
            lastReadAt: Date(),
            sourceFileMTime: mtime
        )
        metadataCache = mc
    }

    private func prewarmMetadataForTags() async {
        for item in cardItems {
            await loadMetadata(for: item.fileURL, forceReload: false, updateEditingString: false)
        }
        recomputeAllTags()
    }

    private func recomputeAllTags() {
        var set = Set<String>()
        for item in cardItems {
            guard let meta = metadataCache[item.fileURL],
                  let d = jsonDataDict(meta.jsonString),
                  let dataObj = d["data"] as? [String: Any],
                  let tags = dataObj["tags"] as? [String]
            else { continue }
            tags.forEach { set.insert($0) }
        }
        allTagsInLibrary = set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func jsonDataDict(_ string: String) -> [String: Any]? {
        guard let d = string.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return nil }
        return obj
    }

    func displayName(from json: String) -> String? {
        guard let d = jsonDataDict(json),
              let dataObj = d["data"] as? [String: Any],
              let name = dataObj["name"] as? String, !name.isEmpty
        else { return nil }
        return name
    }

    /// 生成可导出的 PNG 数据（嵌入当前 JSON），供 `fileExporter` 使用。
    func pngDataForExport(source: URL, jsonString: String) throws -> Data {
        guard validateJSON(jsonString) else {
            throw NSError(domain: "Sillycard", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON 无效"])
        }
        let key = source.standardizedFileURL
        let pngData = try Data(contentsOf: key)
        return try CharacterCardPNG.writeCharacterData(pngData: pngData, jsonString: jsonString)
    }

    func openSingleCardEditor(url: URL) {
        let key = url.standardizedFileURL
        NotificationCenter.default.post(name: .sillycardOpenSingleCard, object: key)
    }
}
