import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 主窗口：深色模式下背景对齐 Figma `dialogue_bg`（file GF7Wvh…, node 1:7）。
public struct ContentView: View {
    public init() {}

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var showDiscardAlert = false
    @State private var pendingSelection: CardItem?
    @State private var showError: String?
    @State private var showAbout = false
    @State private var showWelcome = false
    @State private var showWhatsNew = false
    @State private var showReleaseNotes = false
    @AppStorage("sillycard.welcome.seen") private var welcomeSeen = false
    @AppStorage("sillycard.lastAcknowledgedVersion") private var lastAcknowledgedVersion = ""
    @State private var isDropTargeted = false

    public var body: some View {
        mainSplitView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backgroundLayer }
            .contentShape(Rectangle())
            .overlay { dropHighlightLayer }
            .onDrop(of: [UTType.png, UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
                viewModel.handleDroppedPNGProviders(providers)
                return true
            }
            .modifier(ContentViewAlerts(
                showDiscardAlert: $showDiscardAlert,
                pendingSelection: $pendingSelection,
                showError: $showError,
                viewModel: viewModel
            ))
            .modifier(ContentViewSheets(
                showAbout: $showAbout,
                showWelcome: $showWelcome,
                showWhatsNew: $showWhatsNew,
                showReleaseNotes: $showReleaseNotes
            ))
            .onAppear(perform: presentIntroIfNeeded)
            .modifier(ContentViewLifecycle(
                showWelcome: $showWelcome,
                showWhatsNew: $showWhatsNew,
                showAbout: $showAbout,
                showReleaseNotes: $showReleaseNotes,
                showError: $showError,
                welcomeSeen: $welcomeSeen,
                lastAcknowledgedVersion: $lastAcknowledgedVersion,
                openWindow: openWindow
            ))
            .overlay(alignment: .top) { transientNoticeLayer }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.transientNotice)
    }

    // MARK: - Sub-views

    private var mainSplitView: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 360, max: 720)
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
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 1100)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 480, max: 1400)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: SillycardDesign.figmaDialogueCornerRadius, style: .continuous)
                .fill(SillycardDesign.figmaDialogueBackground)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    @ViewBuilder
    private var dropHighlightLayer: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: SillycardDesign.figmaDialogueCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(10)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var transientNoticeLayer: some View {
        if let notice = viewModel.transientNotice {
            Text(notice)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .padding(.top, 12)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func presentIntroIfNeeded() {
        let v = Bundle.main.sillycardMarketingVersion
        if !welcomeSeen {
            showWelcome = true
            return
        }
        if lastAcknowledgedVersion != v {
            showWhatsNew = true
        }
    }
}

// MARK: - Alerts modifier (keeps body expression small)

private struct ContentViewAlerts: ViewModifier {
    @Binding var showDiscardAlert: Bool
    @Binding var pendingSelection: CardItem?
    @Binding var showError: String?
    @ObservedObject var viewModel: LibraryViewModel

    func body(content: Content) -> some View {
        content
            .alert("放弃更改？", isPresented: $showDiscardAlert) {
                Button("取消", role: .cancel) { pendingSelection = nil }
                Button("放弃", role: .destructive) {
                    if let p = pendingSelection { viewModel.select(p) } else { viewModel.select(nil) }
                    pendingSelection = nil
                }
            } message: {
                Text("未保存的编辑将丢失。")
            }
            .alert("错误", isPresented: .init(
                get: { showError != nil },
                set: { if !$0 { showError = nil } }
            )) {
                Button("好", role: .cancel) { showError = nil }
            } message: {
                Text(showError ?? "")
            }
    }
}

// MARK: - Sheets modifier

private struct ContentViewSheets: ViewModifier {
    @Binding var showAbout: Bool
    @Binding var showWelcome: Bool
    @Binding var showWhatsNew: Bool
    @Binding var showReleaseNotes: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAbout) { AboutSillycardView() }
            .sheet(isPresented: $showWelcome) {
                WelcomeView(onReleaseNotes: { showReleaseNotes = true })
            }
            .sheet(isPresented: $showWhatsNew) {
                ReleaseNotesView(reason: .whatsNew)
            }
            .sheet(isPresented: $showReleaseNotes) {
                ReleaseNotesView(reason: .manual)
            }
    }
}

// MARK: - Lifecycle (onChange / onReceive) modifier

private struct ContentViewLifecycle: ViewModifier {
    @Binding var showWelcome: Bool
    @Binding var showWhatsNew: Bool
    @Binding var showAbout: Bool
    @Binding var showReleaseNotes: Bool
    @Binding var showError: String?
    @Binding var welcomeSeen: Bool
    @Binding var lastAcknowledgedVersion: String
    var openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        content
            .onChange(of: showWelcome) { _, isShowing in
                guard !isShowing else { return }
                let v = Bundle.main.sillycardMarketingVersion
                if !welcomeSeen { welcomeSeen = true; lastAcknowledgedVersion = v }
            }
            .onChange(of: showWhatsNew) { _, isShowing in
                guard !isShowing else { return }
                lastAcknowledgedVersion = Bundle.main.sillycardMarketingVersion
            }
            .onReceive(NotificationCenter.default.publisher(for: .sillycardShowAbout)) { _ in showAbout = true }
            .onReceive(NotificationCenter.default.publisher(for: .sillycardShowWelcome)) { _ in showWelcome = true }
            .onReceive(NotificationCenter.default.publisher(for: .sillycardShowReleaseNotes)) { _ in showReleaseNotes = true }
            .onReceive(NotificationCenter.default.publisher(for: .sillycardShowError)) { note in
                showError = note.object as? String
            }
            .onReceive(NotificationCenter.default.publisher(for: .sillycardOpenSingleCard)) { note in
                guard let url = note.object as? URL else { return }
                openWindow(id: SillycardSceneIds.singleCardEditor, value: url)
            }
    }
}

// MARK: - 版本说明（与 ContentView 同文件，避免 Xcode 遗漏）

/// 升级提示与菜单「版本介绍」共用。
struct ReleaseNotesView: View {
    enum PresentReason: Equatable {
        case whatsNew
        case manual
    }

    @Environment(\.dismiss) private var dismiss
    var reason: PresentReason = .manual

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SampleCardBannerView(height: 92)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    releaseNotesHeader
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(SillycardReleaseNotes.featureOverview.enumerated()), id: \.offset) { _, row in
                            releaseNotesBullet(title: row.title, detail: row.detail)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 460, idealWidth: 480)
        .frame(minHeight: 420, idealHeight: 520, maxHeight: 720)
    }

    @ViewBuilder
    private var releaseNotesHeader: some View {
        switch reason {
        case .whatsNew:
            Text("版本更新")
                .font(.title2.weight(.semibold))
            Text("当前版本：Sillycard \(SillycardReleaseNotes.marketingVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .manual:
            Text("当前版本介绍")
                .font(.title2.weight(.semibold))
            Text("Sillycard \(SillycardReleaseNotes.marketingVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func releaseNotesBullet(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tertiary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 版本文案（避免 Xcode 工程遗漏独立文件）

enum SillycardReleaseNotes {
    static var marketingVersion: String {
        Bundle.main.sillycardMarketingVersion
    }

    static var featureOverview: [(title: String, detail: String)] {
        [
            ("卡库与角色卡", "本地管理多张角色卡 PNG；多卡库、默认库与归档；拖拽或导入写入卡库。空库自动附示例卡 Meo（可导入 Silly Tavern 试聊）。"),
            ("浏览与筛选", "默认库支持网格与列表；按标签交集筛选；名称展示兼容长标题与常见装饰字符。"),
            ("预览与编辑", "侧栏预览 Silly Tavern 元数据（描述、世界书 character_book 等）；扁平 JSON 与字段编辑；独立窗口单卡编辑。"),
            ("归档与回收", "归档移入专用文件夹，可恢复至原相对路径；删除进系统废纸篓，可在访达撤销。"),
        ]
    }
}
