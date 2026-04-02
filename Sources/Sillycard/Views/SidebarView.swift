import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var showFolderAccessHelp = false

    var body: some View {
        List {
            Section("资料库") {
                if let root = viewModel.libraryRoot {
                    Label(root.path, systemImage: "folder.fill")
                        .font(.caption)
                        .lineLimit(2)
                } else {
                    Text(FolderAccessHelp.sidebarHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开文件夹…") {
                        viewModel.pickAndOpenLibraryFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("为什么需要这一步？") {
                        showFolderAccessHelp = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("分类") {
                categoryRow(title: "全部", systemImage: "square.grid.2x2", matches: nil)
                if viewModel.hasRootLevelCards {
                    categoryRow(title: "（根目录）", systemImage: "folder", matches: "")
                }
                ForEach(viewModel.categoryFolders, id: \.self) { folder in
                    categoryRow(title: folder, systemImage: "folder", matches: folder)
                }
            }

            Section("标签（多选 AND）") {
                if viewModel.allTagsInLibrary.isEmpty {
                    Text("载入卡片后显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.allTagsInLibrary, id: \.self) { tag in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedTags.contains(tag) },
                        set: { on in
                            if on {
                                viewModel.selectedTags.insert(tag)
                            } else {
                                viewModel.selectedTags.remove(tag)
                            }
                        }
                    )) {
                        Text(tag)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
    private func categoryRow(title: String, systemImage: String, matches: String?) -> some View {
        let isOn = viewModel.selectedCategoryFolder == matches
        Button {
            viewModel.selectedCategoryFolder = matches
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
    }
}
