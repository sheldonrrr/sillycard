import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class LibraryViewModel: ObservableObject {
    public init() {}

    @Published public var libraryRoot: URL?
    @Published var cardItems: [CardItem] = []
    @Published var selection: CardItem?
    @Published var inspectorMode: InspectorEditMode = .preview

    /// 多卡库与当前选中 id。
    @Published var cardLibraries: [CardLibraryEntry] = []
    @Published var activeLibraryId: String = CardLibraryStore.defaultLibraryId
    /// 各卡库内 PNG 总数（侧栏）。
    @Published private(set) var libraryCardCounts: [String: Int] = [:]

    /// 左侧：默认库（不含「归档」文件夹）或仅「归档」。
    @Published var libraryScope: LibraryScope = .main
    /// 默认库中间区域：网格或列表（归档仍为表格）。
    @Published var mainLibraryLayoutMode: MainLibraryLayoutMode = .grid
    /// 归档视图中列表多选（批量删除）。
    @Published var archiveTableSelection: Set<CardItem.ID> = []

    /// Tags must all appear on card (AND).
    @Published var selectedTags: Set<String> = []

    @Published private(set) var metadataCache: [URL: CachedCardMetadata] = [:]
    @Published private(set) var parseState: [URL: CardParseState] = [:]
    @Published private(set) var allTagsInLibrary: [String] = []
    /// 当前视图、当前已载入元数据中各标签出现次数。
    @Published private(set) var tagCountsByName: [String: Int] = [:]

    /// Live JSON string in Inspector / editor (synced when selection changes or after load).
    @Published var editingJSON: String = ""
    @Published var isDirty: Bool = false

    /// 主窗口短暂提示文案（如成功导入）。
    @Published var transientNotice: String?
    private var transientNoticeResetTask: Task<Void, Never>?

    /// 用户透过系统面板选定的资料库根目录对应的安全作用域（沙盒下须保持直至换库）。
    private var securityScopedLibraryRoot: URL?
    /// 独立窗口打开单张 PNG 时，对其文件 URL 的作用域（与资料库内路径无关）。
    private var securityScopedStandalonePNG: URL?

    var filteredItems: [CardItem] {
        cardItems.filter { item in
            guard scopeMatchesLibrary(item) else { return false }
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

    /// 当前资料库范围内（不含对侧）的卡片，用于标签列表与空状态判断。
    var cardItemsInCurrentScope: [CardItem] {
        cardItems.filter { scopeMatchesLibrary($0) }
    }

    func applyArchiveSelectionSync() {
        guard libraryScope == .archive else { return }
        if archiveTableSelection.count == 1, let id = archiveTableSelection.first,
           let item = cardItems.first(where: { $0.id == id }) {
            if selection?.id != id {
                select(item)
            }
        } else if archiveTableSelection.isEmpty {
            if selection != nil {
                select(nil)
            }
        } else {
            select(nil)
        }
    }

    func setLibraryScope(_ scope: LibraryScope) {
        libraryScope = scope
        archiveTableSelection = []
        if scope == .main {
            if let sel = selection, LibraryScope.isArchivedRelativeFolder(sel.relativeFolder) {
                select(nil)
            }
        } else {
            if let sel = selection, !LibraryScope.isArchivedRelativeFolder(sel.relativeFolder) {
                select(nil)
            }
        }
    }

    private func scopeMatchesLibrary(_ item: CardItem) -> Bool {
        let archived = LibraryScope.isArchivedRelativeFolder(item.relativeFolder)
        switch libraryScope {
        case .main: return !archived
        case .archive: return archived
        }
    }

    var activeLibraryDisplayName: String {
        cardLibraries.first { $0.id == activeLibraryId }?.displayName ?? "Sillycard"
    }

    func reloadLibrariesFromStore() {
        cardLibraries = CardLibraryStore.shared.manifest.libraries
        if let id = CardLibraryStore.shared.manifest.activeLibraryId {
            activeLibraryId = id
        }
    }

    /// 启动：读取卡库清单并打开当前卡库。
    public func restoreLibraryOnLaunch() {
        do {
            try CardLibraryStore.shared.loadOrCreate()
            reloadLibrariesFromStore()
            let id = CardLibraryStore.shared.manifest.activeLibraryId ?? CardLibraryStore.defaultLibraryId
            try switchToLibrary(id: id, persistActive: false)
        } catch {
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: "无法初始化卡库：\(error.localizedDescription)"
            )
        }
    }

    /// 切换到指定卡库。
    func switchToLibrary(id: String, persistActive: Bool = true) throws {
        guard let entry = CardLibraryStore.shared.entry(id: id) else { return }
        if persistActive {
            try CardLibraryStore.shared.setActiveLibrary(id: id)
        }
        activeLibraryId = id
        reloadLibrariesFromStore()
        let url = try CardLibraryStore.shared.resolveURL(for: entry)
        openLibrary(at: url)
    }

    /// 新建托管卡库（仅需名称）。
    func createManagedLibrary(named name: String) {
        do {
            try CardLibraryStore.shared.loadOrCreate()
            _ = try CardLibraryStore.shared.createManagedLibrary(displayName: name)
            reloadLibrariesFromStore()
            if let id = CardLibraryStore.shared.manifest.activeLibraryId {
                try switchToLibrary(id: id, persistActive: false)
            }
            updateAllLibraryCounts()
        } catch {
            NotificationCenter.default.post(name: .sillycardShowError, object: error.localizedDescription)
        }
    }

    func updateAllLibraryCounts() {
        Task { @MainActor in
            var counts: [String: Int] = [:]
            for entry in CardLibraryStore.shared.manifest.libraries {
                do {
                    let u = try CardLibraryStore.shared.resolveURL(for: entry)
                    let ok = u.startAccessingSecurityScopedResource()
                    defer { if ok { u.stopAccessingSecurityScopedResource() } }
                    counts[entry.id] = try LibraryScanner.countAllPNG(root: u)
                } catch {
                    counts[entry.id] = 0
                }
            }
            libraryCardCounts = counts
        }
    }

    /// 弹出打开单张角色卡 PNG（用于未开资料库时）。
    public func pickAndOpenStandalonePNG() {
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

    /// 多选 PNG 复制到当前卡库根目录。
    public func pickAndImportPNGsToLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png]
        panel.title = "导入 PNG 到当前卡库"
        panel.message = "可多选多张角色卡 PNG，将复制到当前卡库（不移动原文件）。"
        panel.prompt = "导入"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls.map(\.standardizedFileURL)
        guard !urls.isEmpty else { return }
        importCharacterPNGs(from: urls)
    }

    func showTransientNotice(_ text: String, durationSeconds: Double = 2.5) {
        transientNoticeResetTask?.cancel()
        transientNotice = text
        transientNoticeResetTask = Task { @MainActor in
            let ns = UInt64(durationSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            transientNotice = nil
        }
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
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir),
                  isDir.boolValue
            else {
                NotificationCenter.default.post(
                    name: .sillycardShowError,
                    object: """
                    未能访问当前卡库目录。

                    若仍失败，可在「系统设置 → 隐私与安全性」中检查本 App 是否被限制访问文件。
                    """
                )
                return
            }
            securityScopedLibraryRoot = nil
        }

        if cardLibraries.first(where: { $0.id == activeLibraryId })?.isManaged == true {
            BundledSampleCard.seedIntoEmptyManagedLibrary(root: standardized)
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
        libraryScope = .main
        archiveTableSelection = []
        selectedTags = []
        metadataCache = [:]
        parseState = [:]
        allTagsInLibrary = []
        tagCountsByName = [:]
        Task { @MainActor in
            await prewarmMetadataForTags()
            selectNewestCardInMainLibraryScopeAfterLoad()
        }
        updateAllLibraryCounts()
    }

    /// 默认库范围内，选「修改日期」最新的一张（批量导入时会对最后一张 bump mtime，等价于最近一张）。
    private func selectNewestCardInMainLibraryScopeAfterLoad() {
        let candidates = cardItems.filter { !LibraryScope.isArchivedRelativeFolder($0.relativeFolder) }
        guard let best = candidates.max(by: { fileModificationDate($0.fileURL) < fileModificationDate($1.fileURL) }) else {
            return
        }
        select(best)
    }

    private func fileModificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
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
        var counts: [String: Int] = [:]
        for item in cardItems where scopeMatchesLibrary(item) {
            guard let meta = metadataCache[item.fileURL],
                  let d = jsonDataDict(meta.jsonString),
                  let dataObj = d["data"] as? [String: Any],
                  let tags = dataObj["tags"] as? [String]
            else { continue }
            for t in tags {
                counts[t, default: 0] += 1
            }
        }
        allTagsInLibrary = counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        tagCountsByName = counts
    }

    private func jsonDataDict(_ string: String) -> [String: Any]? {
        guard let d = string.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return nil }
        return obj
    }

    /// JSON `data.name` 仅做转义还原，供 `{{char}}` 替换与工具提示（保留数学字母等原始展示码位）。
    func rawDisplayName(from json: String) -> String? {
        guard let d = jsonDataDict(json),
              let dataObj = d["data"] as? [String: Any],
              let name = dataObj["name"] as? String, !name.isEmpty
        else { return nil }
        return CharacterCardPreviewFormatting.normalizeDisplayEscapes(name)
    }

    /// 列表 / 标题用展示名（数学字母折叠、装饰性 `_…_` 剥除等）。
    func displayName(from json: String) -> String? {
        rawDisplayName(from: json).map { CharacterCardTitlePresentation.normalizeForDisplay($0) }
    }

    func rawCardTitle(for item: CardItem) -> String {
        let key = item.fileURL.standardizedFileURL
        if let j = metadataCache[key]?.jsonString, let r = rawDisplayName(from: j) {
            return r
        }
        return CharacterCardPreviewFormatting.normalizeDisplayEscapes(item.displayName)
    }

    func displayedCardTitle(for item: CardItem) -> String {
        CharacterCardTitlePresentation.normalizeForDisplay(rawCardTitle(for: item))
    }

    func tagsLine(for item: CardItem) -> String {
        guard let meta = metadataCache[item.fileURL],
              let d = jsonDataDict(meta.jsonString),
              let dataObj = d["data"] as? [String: Any],
              let tags = dataObj["tags"] as? [String],
              !tags.isEmpty
        else { return "—" }
        return tags.map { CharacterCardPreviewFormatting.normalizeDisplayEscapes($0) }.joined(separator: ", ")
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

    /// 在访达中显示文件。
    func revealCardInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
    }

    /// 将当前选中的卡片移入资料库根下的「归档」文件夹（不在默认列表中展示）。
    func archiveCurrentSelection() throws {
        guard let root = libraryRoot, let item = selection else { return }
        try archiveCard(at: item.fileURL, libraryRoot: root)
    }

    func archiveCard(at url: URL, libraryRoot root: URL) throws {
        let std = url.standardizedFileURL
        guard let item = cardItems.first(where: { $0.fileURL.standardizedFileURL == std }) else { return }
        guard !LibraryScope.isArchivedRelativeFolder(item.relativeFolder) else { return }

        try ArchiveRestoreMetadata.setPreArchiveRelativeFolder(item.relativeFolder, on: std)

        let archiveDir = root.appendingPathComponent(LibraryScope.archiveFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let dest = Self.uniqueCopyDestination(in: archiveDir, preferredFileName: std.lastPathComponent)
        try FileManager.default.moveItem(at: std, to: dest)

        removeCaches(for: std)
        try rescanCardList()
        archiveTableSelection = []
        selection = nil
        editingJSON = ""
        isDirty = false
        inspectorMode = .preview
        recomputeAllTags()
        updateAllLibraryCounts()
    }

    /// 将当前选中的已归档卡片移回原相对路径（若无标记则恢复到卡库根目录）。
    func unarchiveCurrentSelection() throws {
        guard let root = libraryRoot, let item = selection else { return }
        try unarchiveCard(at: item.fileURL, libraryRoot: root)
    }

    func unarchiveCard(at url: URL, libraryRoot root: URL) throws {
        let std = url.standardizedFileURL
        guard let item = cardItems.first(where: { $0.fileURL.standardizedFileURL == std }) else { return }
        guard LibraryScope.isArchivedRelativeFolder(item.relativeFolder) else { return }

        let rel = ArchiveRestoreMetadata.getPreArchiveRelativeFolder(from: std) ?? ""
        let destDir = try ArchiveRestoreMetadata.safeDestinationDirectory(libraryRoot: root, relativeFolder: rel)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = Self.uniqueCopyDestination(in: destDir, preferredFileName: std.lastPathComponent)
        try FileManager.default.moveItem(at: std, to: dest)
        ArchiveRestoreMetadata.removePreArchiveMetadata(from: dest)

        removeCaches(for: std)
        selection = nil
        try rescanCardList()
        setLibraryScope(.main)
        editingJSON = ""
        isDirty = false
        inspectorMode = .preview
        let destKey = dest.standardizedFileURL
        if let newItem = cardItems.first(where: { $0.fileURL.standardizedFileURL == destKey }) {
            selection = newItem
        }
        recomputeAllTags()
        updateAllLibraryCounts()
    }

    /// 归档卡片在写回文件 xattr 中记录的「归档前」相对路径说明（用于 Inspector 展示）。
    func preArchiveLocationDescription(for item: CardItem) -> String? {
        guard LibraryScope.isArchivedRelativeFolder(item.relativeFolder) else { return nil }
        guard let rel = ArchiveRestoreMetadata.getPreArchiveRelativeFolder(from: item.fileURL) else {
            return "未记录原路径（恢复时将放入卡库根目录）"
        }
        return rel.isEmpty ? "卡库根目录" : rel
    }

    /// 删除指定文件（废纸篓式直接删除文件）。
    func deleteFiles(at urls: [URL]) throws {
        let fm = FileManager.default
        for u in urls {
            let k = u.standardizedFileURL
            removeCaches(for: k)
            if fm.fileExists(atPath: k.path) {
                try fm.trashItem(at: k, resultingItemURL: nil)
            }
        }
        try rescanCardList()
        let removed = Set(urls.map { $0.standardizedFileURL })
        archiveTableSelection.subtract(removed)
        if let sel = selection, removed.contains(sel.fileURL.standardizedFileURL) {
            selection = nil
            editingJSON = ""
            isDirty = false
            inspectorMode = .preview
        }
        recomputeAllTags()
        updateAllLibraryCounts()
    }

    /// 归档视图中删除当前表格多选。
    func deleteArchiveTableSelection() throws {
        guard libraryScope == .archive, !archiveTableSelection.isEmpty else { return }
        let urls = cardItems.filter { archiveTableSelection.contains($0.id) }.map(\.fileURL)
        try deleteFiles(at: urls)
    }

    /// 删除当前 Inspector 对应的单张卡片。
    func deleteCurrentSelection() throws {
        guard let url = selection?.fileURL else { return }
        try deleteFiles(at: [url])
    }

    private func removeCaches(for url: URL) {
        let k = url.standardizedFileURL
        var mc = metadataCache
        mc.removeValue(forKey: k)
        metadataCache = mc
        var ps = parseState
        ps.removeValue(forKey: k)
        parseState = ps
    }

    private func rescanCardList() throws {
        guard let root = libraryRoot else { return }
        cardItems = try LibraryScanner.scan(root: root)
    }

    /// 将拖入或外部的 PNG **复制**到当前资料库根目录（不移动、不覆盖原文件）；重名时自动追加序号。
    func importCharacterPNGs(from sources: [URL]) {
        if libraryRoot == nil {
            restoreLibraryOnLaunch()
        }
        guard let root = libraryRoot else {
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: "尚未就绪：无法写入当前卡库，请稍后重试或重新启动应用。"
            )
            return
        }
        let fm = FileManager.default
        var copiedAny = false
        var errorLines: [String] = []
        var lastImportedDest: URL?

        let rootStd = root.standardizedFileURL
        for src in sources {
            let srcStd = src.standardizedFileURL
            guard srcStd.pathExtension.lowercased() == "png" else { continue }
            if srcStd.path.hasPrefix(rootStd.path + "/") || srcStd.deletingLastPathComponent().standardizedFileURL == rootStd {
                continue
            }
            let scoped = srcStd.startAccessingSecurityScopedResource()
            defer {
                if scoped { srcStd.stopAccessingSecurityScopedResource() }
            }
            guard fm.isReadableFile(atPath: srcStd.path) else {
                errorLines.append("无法读取：\(srcStd.lastPathComponent)")
                continue
            }
            let preferredName = srcStd.lastPathComponent
            let dest = Self.uniqueCopyDestination(in: root, preferredFileName: preferredName)
            do {
                try fm.copyItem(at: srcStd, to: dest)
                copiedAny = true
                lastImportedDest = dest.standardizedFileURL
                if Self.isStagingDropURL(srcStd) {
                    try? fm.removeItem(at: srcStd)
                }
            } catch {
                errorLines.append("\(preferredName): \(error.localizedDescription)")
            }
        }

        if !errorLines.isEmpty {
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: errorLines.joined(separator: "\n")
            )
        }

        guard copiedAny else { return }
        if let bump = lastImportedDest {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: bump.path)
        }
        do {
            cardItems = try LibraryScanner.scan(root: root)
        } catch {
            NotificationCenter.default.post(
                name: .sillycardShowError,
                object: "已导入，但无法刷新列表：\(error.localizedDescription)"
            )
            return
        }
        Task { @MainActor in
            await prewarmMetadataForTags()
            selectNewestCardInMainLibraryScopeAfterLoad()
        }
        updateAllLibraryCounts()
        showTransientNotice("已导入")
    }

    /// 主窗口级拖拽：解析 PNG 文件 URL 并导入当前卡库。
    func handleDroppedPNGProviders(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            let urls = await Self.collectDroppedPNGURLs(from: providers)
            importCharacterPNGs(from: urls)
        }
    }

    /// 访达 / 浏览器 / 部分 App 拖拽时 `URL` 对象与 `fileURL` 数据表现不一致，这里做多路径解析；必要时拷贝到临时文件再导入（避免 `loadFileRepresentation` 回调返回后源文件被删）。
    private static func collectDroppedPNGURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let u = await resolveDroppedPNGURL(from: provider) {
                urls.append(u)
            }
        }
        return urls
    }

    private static func resolveDroppedPNGURL(from provider: NSItemProvider) async -> URL? {
        if let u = await loadURLObject(from: provider), u.pathExtension.lowercased() == "png" {
            return u
        }
        if let u = await loadFileURLFromUTF8Data(from: provider), u.pathExtension.lowercased() == "png" {
            return u
        }
        if let u = await copyPNGFileRepresentationToStaging(from: provider, type: .png) {
            return u
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let u = await copyPNGFileRepresentationToStaging(from: provider, type: .image),
           u.pathExtension.lowercased() == "png" {
            return u
        }
        return nil
    }

    private static func isStagingDropURL(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL
        let name = std.lastPathComponent
        return std.path.hasPrefix(tmp.path) && name.hasPrefix("sillycard-drop-") && name.hasSuffix(".png")
    }

    private static func loadURLObject(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            guard provider.canLoadObject(ofClass: URL.self) else {
                cont.resume(returning: nil)
                return
            }
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                cont.resume(returning: obj)
            }
        }
    }

    /// `public.file-url` 等以 UTF-8（或带 `file://`）形式给出的路径。
    private static func loadFileURLFromUTF8Data(from provider: NSItemProvider) async -> URL? {
        let id = UTType.fileURL.identifier
        guard provider.hasItemConformingToTypeIdentifier(id) else { return nil }
        return await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: id) { data, _ in
                guard let data,
                      var raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty
                else {
                    cont.resume(returning: nil)
                    return
                }
                raw = raw.trimmingCharacters(in: CharacterSet(["\0"]))
                let url = URL(string: raw) ?? URL(fileURLWithPath: raw)
                cont.resume(returning: url.standardizedFileURL)
            }
        }
    }

    private static func copyPNGFileRepresentationToStaging(from provider: NSItemProvider, type: UTType) async -> URL? {
        let identifier = type.identifier
        guard provider.hasItemConformingToTypeIdentifier(identifier) else { return nil }
        return await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { src, error in
                guard let src, error == nil else {
                    cont.resume(returning: nil)
                    return
                }
                let ext = src.pathExtension.lowercased()
                guard ext == "png" else {
                    cont.resume(returning: nil)
                    return
                }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sillycard-drop-\(UUID().uuidString).png")
                do {
                    try FileManager.default.copyItem(at: src, to: dst)
                    cont.resume(returning: dst.standardizedFileURL)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private static func uniqueCopyDestination(in root: URL, preferredFileName: String) -> URL {
        let fileManager = FileManager.default
        var dest = root.appendingPathComponent(preferredFileName)
        guard fileManager.fileExists(atPath: dest.path) else { return dest }
        let ns = preferredFileName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var i = 2
        while fileManager.fileExists(atPath: dest.path) {
            let name: String
            if ext.isEmpty {
                name = "\(base) \(i)"
            } else {
                name = "\(base) \(i).\(ext)"
            }
            dest = root.appendingPathComponent(name)
            i += 1
        }
        return dest
    }
}

// MARK: - 角色名展示规范化（与本文件同编译单元，避免 Xcode 未收录 `CharacterCardTitlePresentation.swift`）

/// 角色「名称」在列表 / 预览标题中的展示规则：长文件名、`_装饰性 Markdown_`、数学字母区（𝐀-𝐳 等）统一为易读、易排版的字符串；**不**改写 JSON 内原始 `name`。
enum CharacterCardTitlePresentation {
    /// 用于界面标题、网格缩略图下文字（已含 `normalizeDisplayEscapes`、装饰性下划线外壳折叠、数学拉丁字母折叠为 ASCII）。
    static func normalizeForDisplay(_ raw: String) -> String {
        let base = CharacterCardPreviewFormatting.normalizeDisplayEscapes(raw)
        var s = stripOuterCardNameMarkdownDecorations(base)
        s = foldMathematicalAlphanumericLatinToASCII(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripOuterCardNameMarkdownDecorations(_ s: String) -> String {
        var t = s
        if let re = try? NSRegularExpression(pattern: #"^\s*_([^\n_]{1,240})_\s+"#, options: []) {
            let ns = t as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = re.firstMatch(in: t, options: [], range: full), m.numberOfRanges > 1 {
                let inner = ns.substring(with: m.range(at: 1))
                let rest = ns.substring(from: m.range.location + m.range.length)
                let sep = rest.first.map { $0.isWhitespace ? "" : " " } ?? ""
                t = inner + sep + rest.trimmingCharacters(in: .whitespaces)
            }
        }
        for pattern in [#"^_(.+)_$"#, #"^__(.+)__$"#, #"^\*\*(.+)\*\*$"#] {
            if let re = try? NSRegularExpression(pattern: pattern, options: []) {
                let ns = t as NSString
                let full = NSRange(location: 0, length: ns.length)
                if let m = re.firstMatch(in: t, options: [], range: full), m.numberOfRanges > 1 {
                    t = ns.substring(with: m.range(at: 1))
                }
            }
        }
        return t
    }

    private static func foldMathematicalAlphanumericLatinToASCII(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            if let folded = foldMathLatinScalar(scalar) {
                out.unicodeScalars.append(folded)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func foldMathLatinScalar(_ s: UnicodeScalar) -> UnicodeScalar? {
        let v = s.value
        if let u = map26(v, base: 0x1D400, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D41A, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D434, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D44E, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D468, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D482, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D5A0, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D5BA, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D5D4, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D5EE, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D608, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D622, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D63C, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D656, asciiStart: 0x61) { return u }
        if let u = map26(v, base: 0x1D670, asciiStart: 0x41) { return u }
        if let u = map26(v, base: 0x1D68A, asciiStart: 0x61) { return u }
        if let u = mapTen(v, base: 0x1D7CE, asciiStart: 0x30) { return u }
        return nil
    }

    private static func map26(_ v: UInt32, base: UInt32, asciiStart: UInt32) -> UnicodeScalar? {
        guard v >= base, v < base + 26 else { return nil }
        guard let u = UnicodeScalar(asciiStart + (v - base)) else { return nil }
        return u
    }

    private static func mapTen(_ v: UInt32, base: UInt32, asciiStart: UInt32) -> UnicodeScalar? {
        guard v >= base, v < base + 10 else { return nil }
        guard let u = UnicodeScalar(asciiStart + (v - base)) else { return nil }
        return u
    }
}
