import SwiftUI

struct CardGridView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let onSelectAttempt: (CardItem?) -> Void
    @State private var showFolderAccessHelp = false

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 160), spacing: 12)]

    var body: some View {
        Group {
            if viewModel.libraryRoot == nil {
                ContentUnavailableView {
                    Label("未打开资料库", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("通过下方按钮或工具栏选取文件夹后，系统才会授权本 App 访问该目录内的 PNG。")
                } actions: {
                    Button("打开文件夹…") {
                        viewModel.pickAndOpenLibraryFolder()
                    }
                    Button("访问权限说明…") {
                        showFolderAccessHelp = true
                    }
                }
            } else if viewModel.filteredItems.isEmpty {
                ContentUnavailableView("无匹配卡片", systemImage: "photo.on.rectangle.angled", description: Text("调整分类或标签筛选"))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.filteredItems) { item in
                            cardCell(item)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(viewModel.libraryRoot?.lastPathComponent ?? "Sillycard")
        .alert(FolderAccessHelp.alertTitle, isPresented: $showFolderAccessHelp) {
            Button("打开文件夹…") {
                showFolderAccessHelp = false
                viewModel.pickAndOpenLibraryFolder()
            }
            Button("好", role: .cancel) {
                showFolderAccessHelp = false
            }
        } message: {
            Text(FolderAccessHelp.alertMessage)
        }
    }

    @ViewBuilder
    private func cardCell(_ item: CardItem) -> some View {
        let name = viewModel.displayName(from: viewModel.metadataCache[item.fileURL]?.jsonString ?? "") ?? item.displayName
        let selected = viewModel.selection?.fileURL == item.fileURL

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail(item.fileURL)
                    .frame(width: 108, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1)
                    )
                stateBadge(for: item.fileURL)
            }
            Text(name)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: 108, alignment: .leading)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                viewModel.openSingleCardEditor(url: item.fileURL)
            }
        )
        .onTapGesture {
            onSelectAttempt(item)
        }
        .contextMenu {
            Button("在独立窗口中编辑…") {
                viewModel.openSingleCardEditor(url: item.fileURL)
            }
        }
    }

    private func thumbnail(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Color.secondary.opacity(0.12)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Color.secondary.opacity(0.15)
            @unknown default:
                Color.secondary.opacity(0.12)
            }
        }
    }

    @ViewBuilder
    private func stateBadge(for url: URL) -> some View {
        switch viewModel.parseState[url.standardizedFileURL] ?? .unknown {
        case .ok:
            EmptyView()
        case .noMetadata:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption2)
                .padding(4)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption2)
                .padding(4)
        case .unknown:
            EmptyView()
        }
    }
}
