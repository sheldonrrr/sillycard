import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var showDiscardAlert = false
    @State private var pendingSelection: CardItem?
    @State private var showError: String?

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            CardGridView(
                onSelectAttempt: { item in
                    if viewModel.isDirty {
                        pendingSelection = item
                        showDiscardAlert = true
                    } else {
                        viewModel.select(item)
                    }
                }
            )
        } detail: {
            InspectorView()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        .alert("未保存的更改", isPresented: $showDiscardAlert) {
            Button("继续编辑", role: .cancel) {
                pendingSelection = nil
            }
            Button("丢弃", role: .destructive) {
                if let p = pendingSelection {
                    viewModel.select(p)
                } else {
                    viewModel.select(nil)
                }
                pendingSelection = nil
            }
        } message: {
            Text("切换卡片将丢失当前未保存的编辑。")
        }
        .alert("错误", isPresented: .init(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("好", role: .cancel) { showError = nil }
        } message: {
            Text(showError ?? "")
        }
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showOpenLibraryImporter },
                set: { viewModel.showOpenLibraryImporter = $0 }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            viewModel.showOpenLibraryImporter = false
            guard case .success(let urls) = result, let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            viewModel.openLibrary(at: url)
        }
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showOpenPNGImporter },
                set: { viewModel.showOpenPNGImporter = $0 }
            ),
            allowedContentTypes: [.png],
            allowsMultipleSelection: false
        ) { result in
            viewModel.showOpenPNGImporter = false
            guard case .success(let urls) = result, let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            viewModel.openSingleCardEditor(url: url)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("打开文件夹…") { viewModel.showOpenLibraryImporter = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sillycardShowError)) { note in
            showError = note.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .sillycardOpenSingleCard)) { note in
            guard let url = note.object as? URL else { return }
            openWindow(id: url.path, value: url)
        }
    }
}
