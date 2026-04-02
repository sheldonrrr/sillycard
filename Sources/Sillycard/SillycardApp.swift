import SwiftUI

@main
struct SillycardApp: App {
    @StateObject private var viewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .importExport) {
                Button("打开文件夹…") {
                    viewModel.showOpenLibraryImporter = true
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("打开 PNG…") {
                    viewModel.showOpenPNGImporter = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        WindowGroup(for: URL.self) { $url in
            if let url {
                SingleCardEditorView(fileURL: url)
                    .environmentObject(viewModel)
            }
        }
        .defaultSize(width: 1180, height: 820)
    }
}
