import AppKit
import SwiftUI

struct CardGridView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @Environment(\.colorScheme) private var colorScheme
    let onSelectAttempt: (CardItem?) -> Void
    @State private var confirmBulkTrash = false

    var body: some View {
        Group {
            if viewModel.libraryRoot == nil {
                ContentUnavailableView {
                    Label("正在载入卡库", systemImage: "folder.badge.gearshape")
                } description: {
                    Text("可点「重试」或把 PNG 拖进窗口导入。")
                } actions: {
                    Button("重试") {
                        viewModel.restoreLibraryOnLaunch()
                    }
                }
            } else if viewModel.cardItems.isEmpty {
                dropChrome {
                    VStack(spacing: 0) {
                        if shouldShowListFilterChrome { listFilterChrome }
                        libraryEmptyPlaceholder
                    }
                }
            } else if viewModel.cardItemsInCurrentScope.isEmpty {
                dropChrome {
                    VStack(spacing: 0) {
                        if shouldShowListFilterChrome { listFilterChrome }
                        scopeEmptyPlaceholder
                    }
                }
            } else if viewModel.filteredItems.isEmpty {
                dropChrome {
                    VStack(spacing: 0) {
                        listFilterChrome
                        ContentUnavailableView("无匹配结果", systemImage: "line.3.horizontal.decrease.circle", description: Text("换个标签组合，或清除筛选。"))
                    }
                }
            } else if viewModel.libraryScope == .archive {
                dropChrome { archiveTableView }
            } else if viewModel.mainLibraryLayoutMode == .list {
                dropChrome { mainCardListView }
            } else {
                dropChrome { mainCardGrid }
            }
        }
        .navigationTitle(viewModel.activeLibraryDisplayName)
        .toolbar {
            if viewModel.libraryScope == .archive {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmBulkTrash = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(viewModel.archiveTableSelection.isEmpty)
                }
            }
        }
        .alert("删除这 \(viewModel.archiveTableSelection.count) 张角色卡？", isPresented: $confirmBulkTrash) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) {
                Task {
                    do {
                        try viewModel.deleteArchiveTableSelection()
                    } catch {
                        NotificationCenter.default.post(name: .sillycardShowError, object: error.localizedDescription)
                    }
                }
            }
        } message: {
            Text("文件将进废纸篓，可在访达中恢复。")
        }
        .onChange(of: viewModel.archiveTableSelection) { _, _ in
            viewModel.applyArchiveSelectionSync()
        }
    }

    /// 默认库 / 归档在对应维度完全无卡时，隐藏「默认库 0」等统计条。
    private var shouldShowListFilterChrome: Bool {
        if viewModel.cardItems.isEmpty { return false }
        if viewModel.libraryScope == .main {
            return viewModel.cardItems.contains { !LibraryScope.isArchivedRelativeFolder($0.relativeFolder) }
        }
        return viewModel.cardItems.contains { LibraryScope.isArchivedRelativeFolder($0.relativeFolder) }
    }

    private var listFilterChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.libraryScope == .main ? "默认库" : "归档")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(viewModel.cardItemsInCurrentScope.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !viewModel.selectedTags.isEmpty {
                HStack(alignment: .center) {
                    Text("筛选：\(viewModel.filteredItems.count) 张")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("清除筛选") {
                        viewModel.selectedTags.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(viewModel.selectedTags).sorted(), id: \.self) { tag in
                            Button {
                                viewModel.selectedTags.remove(tag)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(tag).lineLimit(1)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
    }

    private enum MainGridMetrics {
        /// 缩略图最长边上限：不同比例的角色卡统一限制在框内完整可见。
        static let thumbMaxWidth: CGFloat = 148
        static let thumbMaxHeight: CGFloat = 198
    }

    /// 默认库：设计稿式缩略图网格（归档仍为表格）。
    private var mainCardGrid: some View {
        VStack(spacing: 0) {
            listFilterChrome
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118, maximum: 168), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 20
                ) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                        MainLibraryGridTile(
                            item: item,
                            gridIndex: index,
                            isSelected: viewModel.selection?.id == item.id,
                            onSelectAttempt: onSelectAttempt
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    /// 默认库：与归档类似的表格，单选与网格共用 `selection`。
    private var mainCardListView: some View {
        VStack(spacing: 0) {
            listFilterChrome
            finderListHeader
            Divider()
            Table(
                viewModel.filteredItems,
                selection: Binding(
                    get: {
                        if let s = viewModel.selection,
                           viewModel.filteredItems.contains(where: { $0.id == s.id }) {
                            return [s.id]
                        }
                        return []
                    },
                    set: { ids in
                        guard let id = ids.first,
                              let item = viewModel.filteredItems.first(where: { $0.id == id })
                        else {
                            onSelectAttempt(nil)
                            return
                        }
                        onSelectAttempt(item)
                    }
                )
            ) {
                TableColumn("预览") { item in
                    CardFinderThumb(url: item.fileURL, contentMode: .fill)
                        .frame(width: 40, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(56)

                TableColumn("名称") { item in
                    Text(viewModel.displayedCardTitle(for: item))
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .help(viewModel.rawCardTitle(for: item))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(min: 140, ideal: 220)

                TableColumn("标签") { item in
                    Text(viewModel.tagsLine(for: item))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(min: 100, ideal: 160)

                TableColumn("大小") { item in
                    Text(Self.fileSizeString(url: item.fileURL))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(72)

                TableColumn("修改") { item in
                    Text(Self.fileModifiedString(url: item.fileURL))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(118)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func cardContextMenu(for item: CardItem) -> some View {
        Button("独立窗口编辑…") {
            viewModel.openSingleCardEditor(url: item.fileURL)
        }
        Button("访达中显示") {
            viewModel.revealCardInFinder(url: item.fileURL)
        }
        if viewModel.libraryScope == .main, !LibraryScope.isArchivedRelativeFolder(item.relativeFolder),
           let root = viewModel.libraryRoot {
            Button("归档") {
                try? viewModel.archiveCard(at: item.fileURL, libraryRoot: root)
            }
        }
        if viewModel.libraryScope == .archive, let root = viewModel.libraryRoot {
            Button("恢复至默认库") {
                try? viewModel.unarchiveCard(at: item.fileURL, libraryRoot: root)
            }
        }
        Divider()
        Button("移到废纸篓", role: .destructive) {
            try? viewModel.deleteFiles(at: [item.fileURL])
        }
    }

    private var archiveTableView: some View {
        VStack(spacing: 0) {
            listFilterChrome
            finderListHeader
            Divider()
            Table(viewModel.filteredItems, selection: $viewModel.archiveTableSelection) {
                TableColumn("预览") { item in
                    CardFinderThumb(url: item.fileURL)
                        .frame(width: 40, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(56)

                TableColumn("名称") { item in
                    Text(viewModel.displayedCardTitle(for: item))
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .help(viewModel.rawCardTitle(for: item))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(min: 140, ideal: 220)

                TableColumn("标签") { item in
                    Text(viewModel.tagsLine(for: item))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(min: 100, ideal: 160)

                TableColumn("大小") { item in
                    Text(Self.fileSizeString(url: item.fileURL))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(72)

                TableColumn("修改") { item in
                    Text(Self.fileModifiedString(url: item.fileURL))
                        .contextMenu { cardContextMenu(for: item) }
                }
                .width(118)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var finderListHeader: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 44, height: 1)
            Text("名称")
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text("标签")
                .frame(minWidth: 88, maxWidth: 160, alignment: .leading)
            Text("大小")
                .frame(width: 72, alignment: .trailing)
            Text("修改日期")
                .frame(width: 118, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func stateBadge(for url: URL) -> some View {
        switch viewModel.parseState[url.standardizedFileURL] ?? .unknown {
        case .ok, .unknown:
            EmptyView()
        case .noMetadata:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption2)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption2)
        }
    }

    private var libraryEmptyPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 44))
                .foregroundStyle(Color.secondary)
            VStack(spacing: 10) {
                Text("拖入 PNG 导入角色卡")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("复制进当前卡库，不移动原文件。支持一次多文件。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Text("⌘O 可打开单张查看或编辑。")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var scopeEmptyPlaceholder: some View {
        ContentUnavailableView {
            Label(viewModel.libraryScope == .main ? "默认库为空" : "归档为空", systemImage: "tray")
        } description: {
            if viewModel.libraryScope == .main {
                Text("拖入 PNG 导入；右侧可归档。已在归档的卡片请打开侧栏「归档」。")
            } else {
                Text("在默认库选中卡片后，右侧可移入归档。")
            }
        }
    }

    @ViewBuilder
    private func dropChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func fileSizeString(url: URL) -> String {
        guard let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    private static func fileModifiedString(url: URL) -> String {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return "—"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - 主库网格单元（悬停 / 选中底）

private struct MainLibraryGridTile: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @Environment(\.colorScheme) private var colorScheme
    let item: CardItem
    let gridIndex: Int
    let isSelected: Bool
    let onSelectAttempt: (CardItem?) -> Void
    @State private var isHovered = false
    @State private var gridReveal = false

    private enum Metrics {
        static let thumbW: CGFloat = 148
        static let thumbH: CGFloat = 198
    }

    private var cardContextMenu: some View {
        Group {
            Button("独立窗口编辑…") {
                viewModel.openSingleCardEditor(url: item.fileURL)
            }
            Button("访达中显示") {
                viewModel.revealCardInFinder(url: item.fileURL)
            }
            if viewModel.libraryScope == .main, !LibraryScope.isArchivedRelativeFolder(item.relativeFolder),
               let root = viewModel.libraryRoot {
                Button("归档") {
                    try? viewModel.archiveCard(at: item.fileURL, libraryRoot: root)
                }
            }
            if viewModel.libraryScope == .archive, let root = viewModel.libraryRoot {
                Button("恢复至默认库") {
                    try? viewModel.unarchiveCard(at: item.fileURL, libraryRoot: root)
                }
            }
            Divider()
            Button("移到废纸篓", role: .destructive) {
                try? viewModel.deleteFiles(at: [item.fileURL])
            }
        }
    }

    private var tileBackground: Color {
        if isSelected { return SillycardDesign.gridTileSelectedBackground(colorScheme) }
        if isHovered { return SillycardDesign.gridTileHoverBackground(colorScheme) }
        return .clear
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                CardFinderThumb(url: item.fileURL, contentMode: .fit)
                    .frame(maxWidth: Metrics.thumbW, maxHeight: Metrics.thumbH)
                    .frame(width: Metrics.thumbW, height: Metrics.thumbH)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(
                        color: (isHovered || isSelected) ? Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14) : .clear,
                        radius: (isHovered || isSelected) ? 6 : 0,
                        y: 2
                    )
                CardGridView.stateBadgeBlock(parseState: viewModel.parseState[item.fileURL.standardizedFileURL] ?? .unknown)
                    .padding(6)
            }
            Text(viewModel.displayedCardTitle(for: item))
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.center)
                .frame(width: Metrics.thumbW)
                .help(viewModel.rawCardTitle(for: item))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tileBackground)
        }
        .scaleEffect(gridReveal ? 1.0 : 0.9)
        .opacity(gridReveal ? 1.0 : 0.86)
        .animation(
            .spring(response: 0.44, dampingFraction: 0.84)
                .delay(Double(min(gridIndex, 28)) * 0.035),
            value: gridReveal
        )
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .contentShape(Rectangle())
        .onAppear { gridReveal = true }
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                viewModel.openSingleCardEditor(url: item.fileURL)
            }
        )
        .onTapGesture {
            onSelectAttempt(item)
        }
        .contextMenu {
            cardContextMenu
        }
    }
}

extension CardGridView {
    @ViewBuilder
    fileprivate static func stateBadgeBlock(parseState: CardParseState) -> some View {
        switch parseState {
        case .ok, .unknown:
            EmptyView()
        case .noMetadata:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption2)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption2)
        }
    }
}

// MARK: - Thumb

private struct CardFinderThumb: View {
    let url: URL
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Color.secondary.opacity(0.12)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                Color.secondary.opacity(0.15)
            @unknown default:
                Color.secondary.opacity(0.12)
            }
        }
        .clipped()
    }
}
