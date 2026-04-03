import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var saveError: String?
    @State private var isSaveAsPresented = false
    @State private var saveAsDocument: PNGDataDocument?
    @State private var saveAsFilename = "card.png"
    @State private var confirmDeleteSingle = false
    @State private var confirmBulkDelete = false
    @State private var confirmArchiveDiscard = false
    @State private var confirmUnarchiveDiscard = false
    @State private var actionError: String?
    /// 角色卡字段：预览（占位符 + HTML/Markdown）与原始元数据字符串切换。
    @State private var metadataFieldsShowRaw = false
    /// 记入 Set 的 sectionId 表示当前为收起状态。
    @State private var collapsedInspectorSections: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.libraryScope == .archive, viewModel.archiveTableSelection.count > 1 {
                bulkArchiveInspector
            } else if let item = viewModel.selection {
                pinnedActionBar(for: item)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        singleCardInspector(for: item)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 28)
                            .id(item.fileURL.path)
                    }
                    .onAppear {
                        // #region agent log
                        SillycardAgentDebug.log(
                            hypothesisId: "H9",
                            location: "InspectorView.swift:nativeScroll",
                            message: "scrollview_active",
                            data: ["path": item.fileURL.lastPathComponent]
                        )
                        // #endregion
                    }
                    .onChange(of: viewModel.selection?.fileURL.path) { _, newPath in
                        guard let newPath else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newPath, anchor: .top)
                        }
                    }
                }
            } else {
                ContentUnavailableView("未选择角色卡", systemImage: "person.crop.rectangle", description: Text("在列表中点选一张；归档中可 ⌘ 多选。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 320)
        .background(Color(nsColor: .controlBackgroundColor))
        .fileExporter(
            isPresented: $isSaveAsPresented,
            document: saveAsDocument,
            contentType: .png,
            defaultFilename: saveAsFilename
        ) { result in
            saveAsDocument = nil
            if case .failure(let err) = result {
                saveError = err.localizedDescription
            }
        }
        .alert("保存失败", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .alert("操作失败", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert(singleDeleteAlertTitle, isPresented: $confirmDeleteSingle) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) {
                Task {
                    do {
                        try viewModel.deleteCurrentSelection()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(singleDeleteAlertMessage)
        }
        .alert("删除这 \(viewModel.archiveTableSelection.count) 张角色卡？", isPresented: $confirmBulkDelete) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) {
                Task {
                    do {
                        try viewModel.deleteArchiveTableSelection()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("文件将进废纸篓，可在访达中恢复。")
        }
        .alert("放弃未保存的更改？", isPresented: $confirmArchiveDiscard) {
            Button("取消", role: .cancel) {}
            Button("归档", role: .destructive) {
                performArchive()
            }
        } message: {
            Text("未保存的 JSON 将丢失。")
        }
        .alert("放弃未保存的更改？", isPresented: $confirmUnarchiveDiscard) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) {
                performUnarchive()
            }
        } message: {
            Text("未保存的 JSON 将丢失。")
        }
        .onChange(of: viewModel.selection?.id) { _, _ in
            metadataFieldsShowRaw = false
            collapsedInspectorSections = []
        }
    }

    private var singleDeleteAlertTitle: String {
        let name = viewModel.selection?.displayName ?? "角色卡"
        return "将「\(name)」移到废纸篓？"
    }

    private var singleDeleteAlertMessage: String {
        "可在访达中恢复。"
    }

    private var bulkArchiveInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            pinnedBulkBar
            Divider()
            let n = viewModel.archiveTableSelection.count
            ContentUnavailableView {
                Label("已选 \(n) 张", systemImage: "square.stack.3d.up")
            } description: {
                Text("在中间列表用工具栏「删除」批量移入废纸篓。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var pinnedBulkBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(viewModel.archiveTableSelection.count) 张")
                .font(.headline)
            Spacer()
            Button(role: .destructive) {
                confirmBulkDelete = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(viewModel.archiveTableSelection.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func pinnedActionBar(for item: CardItem) -> some View {
        let isArchived = LibraryScope.isArchivedRelativeFolder(item.relativeFolder)
        let canArchive = viewModel.libraryScope == .main && !isArchived
        return HStack(spacing: 12) {
            Button {
                viewModel.openSingleCardEditor(url: item.fileURL)
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .labelStyle(.titleAndIcon)
                .help("独立窗口编辑")

            if isArchived {
                Button {
                    if viewModel.isDirty {
                        confirmUnarchiveDiscard = true
                    } else {
                        performUnarchive()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.bordered)
                .help("恢复至原路径")
            } else {
                Button {
                    if viewModel.isDirty {
                        confirmArchiveDiscard = true
                    } else {
                        performArchive()
                    }
                } label: {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.bordered)
                .disabled(!canArchive)
                .help("归档")
            }

            Button(role: .destructive) {
                confirmDeleteSingle = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help("废纸篓")

            Spacer(minLength: 8)

            Button {
                viewModel.refreshMetadataForSelection()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("重新解析元数据")

            Menu {
                Button("另存为 PNG…") {
                    beginSaveAs(for: item)
                }
                .disabled(viewModel.editingJSON.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("更多")
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func inspectorHero(item: CardItem, st: SillyTavernCardPreview, displayName: String, tooltipName: String, tagList: [String]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: item.fileURL) { phase in
                switch phase {
                case .empty:
                    Color.secondary.opacity(0.12)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color.secondary.opacity(0.12)
                @unknown default:
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: 136, height: 182)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 12) {
                Text(displayName)
                    .font(.title.weight(.bold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(tooltipName)

                let sub = SillycardDesign.inspectorSubtitleLines(st: st, tags: tagList, item: item)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let phrase = SillycardDesign.relativeModificationPhrase(for: item.fileURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.small)
                        Text("修改：\(phrase)")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func singleCardInspector(for item: CardItem) -> some View {
        let key = item.fileURL.standardizedFileURL
        let cache = viewModel.metadataCache[key]
        let st = SillyTavernCardPreview(jsonString: viewModel.editingJSON)
        let nameForPlaceholders = st.name
            ?? viewModel.rawDisplayName(from: viewModel.editingJSON)
            ?? CharacterCardPreviewFormatting.normalizeDisplayEscapes(item.displayName)
        let titleForInspector = CharacterCardTitlePresentation.normalizeForDisplay(nameForPlaceholders)
        let tagList: [String] = {
            if !st.tags.isEmpty { return st.tags }
            let line = viewModel.tagsLine(for: item)
            if line == "—" { return [] }
            return line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }()

        return VStack(alignment: .leading, spacing: 20) {
            inspectorHero(item: item, st: st, displayName: titleForInspector, tooltipName: nameForPlaceholders, tagList: tagList)

            if let preLoc = viewModel.preArchiveLocationDescription(for: item) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("归档前路径")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(preLoc)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(colorScheme == .dark ? 0.22 : 0.12))
                )
            }

            stCollapsibleCoreFieldSection(
                sectionId: "description",
                title: "描述",
                icon: "text.alignleft",
                text: st.description,
                characterName: nameForPlaceholders,
                emphasized: true
            )

            Group {
                stCollapsibleCoreFieldSection(
                    sectionId: "personality",
                    title: "性格",
                    icon: "face.smiling",
                    text: st.personality,
                    characterName: nameForPlaceholders
                )
                stCollapsibleCoreFieldSection(
                    sectionId: "scenario",
                    title: "场景",
                    icon: "theatermasks",
                    text: st.scenario,
                    characterName: nameForPlaceholders
                )
                stCollapsibleCoreFieldSection(
                    sectionId: "firstMes",
                    title: "首条消息",
                    icon: "bubble.left.and.bubble.right",
                    text: st.firstMes,
                    characterName: nameForPlaceholders,
                    valueFont: .body
                )
            }

            stCollapsibleCoreFieldSection(
                sectionId: "mesExample",
                title: "对话示例",
                icon: "list.bullet.rectangle",
                text: st.mesExample,
                characterName: nameForPlaceholders
            )
            stCollapsibleCoreFieldSection(
                sectionId: "systemPrompt",
                title: "系统提示",
                icon: "terminal",
                text: st.systemPrompt,
                characterName: nameForPlaceholders
            )
            stCollapsibleCoreFieldSection(
                sectionId: "creatorNotes",
                title: "创作者后记",
                icon: "note.text",
                text: st.creatorNotes,
                characterName: nameForPlaceholders
            )
            stCollapsibleCoreFieldSection(
                sectionId: "postHistory",
                title: "Post-history 指令",
                icon: "arrow.triangle.branch",
                text: st.postHistoryInstructions,
                characterName: nameForPlaceholders
            )

            if !st.alternateGreetings.isEmpty {
                DisclosureGroup(
                    isExpanded: sectionExpandedBinding("altGreetings")
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(st.alternateGreetings.enumerated()), id: \.offset) { i, g in
                            if !g.isEmpty {
                                Text("开场 \(i + 2)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                CharacterCardFieldValuePreview(
                                    rawValue: g,
                                    characterName: nameForPlaceholders,
                                    showRawMetadata: metadataFieldsShowRaw,
                                    displayFont: .body
                                )
                            }
                        }
                    }
                } label: {
                    Label("备选开场（alternate_greetings）", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.headline)
                }
            }

            if st.hasEmbeddedWorldBook {
                DisclosureGroup(
                    isExpanded: sectionExpandedBinding("worldBook")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let bookName = st.worldBookName, !bookName.isEmpty {
                            Text(bookName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("与 Silly Tavern 角色附带嵌入世界书一致；以下为键与正文预览。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        ForEach(st.worldBookEntries) { entry in
                            worldBookEntryBlock(entry, characterName: nameForPlaceholders)
                        }
                    }
                } label: {
                    Label("世界书条目（character_book.entries）", systemImage: "books.vertical.fill")
                        .font(.headline)
                }
            }

            fileInfoBlock(url: item.fileURL)

            if let at = cache?.lastReadAt {
                Text("解析于 \(at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("扁平 JSON 字段")
                        .font(.headline)
                    Spacer()
                    Picker("字段显示", selection: $metadataFieldsShowRaw) {
                        Text("预览").tag(false)
                        Text("原始").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                .help("预览：替换 {{char}} / {{user}}，并尽量渲染 HTML / Markdown。")

                DisclosureGroup("全部路径") {
                    let rows = CharacterCardJSONFlattener.rows(
                        from: viewModel.editingJSON,
                        maxValueLength: metadataFieldsShowRaw ? 32_000 : 800
                    )
                    if rows.isEmpty {
                        Text(viewModel.editingJSON.isEmpty ? "无数据" : "无法解析 JSON")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(row.0)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                        .textSelection(.enabled)
                                    CharacterCardFieldValuePreview(
                                        rawValue: row.1,
                                        characterName: nameForPlaceholders,
                                        showRawMetadata: metadataFieldsShowRaw
                                    )
                                }
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
                .font(.subheadline)
            }

            Text("双击列表或点「编辑」可开大窗口。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .background(
            Color.clear
                .onAppear {
                    // #region agent log
                    SillycardAgentDebug.log(
                        hypothesisId: "H5",
                        location: "InspectorView.swift:singleCardInspector",
                        message: "inspector_content_built",
                        data: [
                            "selection": item.displayName,
                            "mesExampleLen": String(st.mesExample?.count ?? 0),
                            "collapsedSections": String(collapsedInspectorSections.count),
                        ]
                    )
                    // #endregion
                }
        )
    }

    private func sectionExpandedBinding(_ sectionId: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedInspectorSections.contains(sectionId) },
            set: { expanded in
                if expanded {
                    collapsedInspectorSections.remove(sectionId)
                } else {
                    collapsedInspectorSections.insert(sectionId)
                }
            }
        )
    }

    @ViewBuilder
    private func stCollapsibleCoreFieldSection(
        sectionId: String,
        title: String,
        icon: String,
        text: String?,
        characterName: String,
        emphasized: Bool = false,
        valueFont: Font = .body
    ) -> some View {
        if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            DisclosureGroup(isExpanded: sectionExpandedBinding(sectionId)) {
                CharacterCardFieldValuePreview(
                    rawValue: t,
                    characterName: characterName,
                    showRawMetadata: metadataFieldsShowRaw,
                    displayFont: emphasized ? .body : valueFont
                )
                .padding(emphasized ? 14 : 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SillycardDesign.inspectorFieldFill(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SillycardDesign.inspectorFieldStroke(colorScheme), lineWidth: 1)
                )
            } label: {
                Label(title, systemImage: icon)
                    .font(emphasized ? .title3.weight(.semibold) : .headline)
            }
        }
    }

    private func worldBookEntryBlock(_ entry: SillyTavernCardPreview.WorldBookEntryPreview, characterName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if entry.disabled == true {
                    Text("已禁用")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if !entry.keysPrimary.isEmpty {
                Text("主键（keys）· \(entry.keysPrimary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !entry.keysSecondary.isEmpty {
                Text("副键（secondary_keys）· \(entry.keysSecondary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let o = entry.order {
                    Text("order \(o)").font(.caption2).foregroundStyle(.tertiary)
                }
                if let p = entry.priority {
                    Text("priority \(p)").font(.caption2).foregroundStyle(.tertiary)
                }
                if let s = entry.selective {
                    Text(s ? "选择性" : "非选择性")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let c = entry.constant, c {
                    Text("constant")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text("规则正文")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            CharacterCardFieldValuePreview(
                rawValue: entry.content.isEmpty ? "—" : entry.content,
                characterName: characterName,
                showRawMetadata: metadataFieldsShowRaw,
                displayFont: .body
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SillycardDesign.inspectorFieldFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SillycardDesign.inspectorFieldStroke(colorScheme), lineWidth: 1)
        )
    }

    private func fileInfoBlock(url: URL) -> some View {
        let sizeStr: String = {
            guard let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "—" }
            return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
        }()
        let created: String = {
            guard let d = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return "—" }
            return d.formatted(date: .abbreviated, time: .shortened)
        }()
        let modified: String = {
            guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return "—" }
            return d.formatted(date: .abbreviated, time: .shortened)
        }()
        return VStack(alignment: .leading, spacing: 6) {
            keyValueLine(key: "文件大小", value: sizeStr)
            keyValueLine(key: "创建时间", value: created)
            keyValueLine(key: "修改时间", value: modified)
        }
        .font(.caption)
    }

    private func keyValueLine(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func performArchive() {
        do {
            try viewModel.archiveCurrentSelection()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performUnarchive() {
        do {
            try viewModel.unarchiveCurrentSelection()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func beginSaveAs(for item: CardItem) {
        do {
            let data = try viewModel.pngDataForExport(source: item.fileURL, jsonString: viewModel.editingJSON)
            saveAsDocument = PNGDataDocument(data: data)
            saveAsFilename = item.displayName + ".png"
            isSaveAsPresented = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}
