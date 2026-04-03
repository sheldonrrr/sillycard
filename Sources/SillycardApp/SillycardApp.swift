#if canImport(SillycardKit)
import SillycardKit
#endif
import SwiftUI

@main
struct SillycardApp: App {
    @NSApplicationDelegateAdaptor(SillycardAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                // 不设置 NSApp.appearance，明暗与强调色跟随系统。
                .task {
                    if viewModel.libraryRoot == nil {
                        viewModel.restoreLibraryOnLaunch()
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("关于 Sillycard") {
                    NotificationCenter.default.post(name: .sillycardShowAbout, object: nil)
                }
                Button("欢迎") {
                    NotificationCenter.default.post(name: .sillycardShowWelcome, object: nil)
                }
                Button("当前版本介绍…") {
                    NotificationCenter.default.post(name: .sillycardShowReleaseNotes, object: nil)
                }
            }
            CommandGroup(after: .importExport) {
                Button("导入 PNG…") {
                    viewModel.pickAndImportPNGsToLibrary()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("打开 PNG…") {
                    viewModel.pickAndOpenStandalonePNG()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        WindowGroup(id: SillycardSceneIds.singleCardEditor, for: URL.self) { $url in
            if let url {
                SingleCardEditorView(fileURL: url)
                    .environmentObject(viewModel)
            }
        }
        .defaultSize(width: 1180, height: 820)
    }
}
