import SwiftUI

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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("打开文件夹…") { viewModel.pickAndOpenLibraryFolder() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sillycardShowError)) { note in
            showError = note.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .sillycardOpenSingleCard)) { note in
            guard let url = note.object as? URL else { return }
            // 必须使用 `value:` 与 `WindowGroup(for: URL.self)` 匹配；`id:` 是 Scene 在 App 里注册的标识符，不能传文件路径。
            openWindow(value: url)
        }
    }
}
