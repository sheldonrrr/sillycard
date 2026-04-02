import SwiftUI
import UniformTypeIdentifiers

/// 双栏大 JSON 编辑窗口（左图右文）；与主界面共享 `LibraryViewModel` 与缓存。
struct SingleCardEditorView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let fileURL: URL

    @State private var localJSON: String = ""
    @State private var mode: InspectorEditMode = .preview
    @State private var isDirty = false
    @State private var errorMessage: String?
    @State private var showRefreshConfirm = false
    @State private var isSaveAsPresented = false
    @State private var saveAsDocument: PNGDataDocument?
    @State private var saveAsFilename = "card.png"

    var body: some View {
        HSplitView {
            imagePane
            editorPane
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { await loadInitial() }
        .fileExporter(
            isPresented: $isSaveAsPresented,
            document: saveAsDocument,
            contentType: .png,
            defaultFilename: saveAsFilename
        ) { result in
            saveAsDocument = nil
            if case .failure(let err) = result {
                errorMessage = err.localizedDescription
            }
        }
        .alert("未保存的编辑将丢失", isPresented: $showRefreshConfirm) {
            Button("取消", role: .cancel) {}
            Button("刷新", role: .destructive) {
                Task { await refreshFromDisk() }
            }
        } message: {
            Text("将从 PNG 重新读取元数据。")
        }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var imagePane: some View {
        AsyncImage(url: fileURL) { phase in
            switch phase {
            case .empty:
                ProgressView().frame(minWidth: 200, maxWidth: 320)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 420)
                    .padding()
            case .failure:
                ContentUnavailableView("无预览", systemImage: "photo", description: Text("无法加载图像"))
                    .frame(minWidth: 200, maxWidth: 320)
            @unknown default:
                EmptyView()
            }
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Picker("模式", selection: $mode) {
                    ForEach(InspectorEditMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                if let meta = viewModel.metadataCache[fileURL.standardizedFileURL] {
                    Text("上次载入：\(meta.lastReadAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    if isDirty { showRefreshConfirm = true }
                    else { Task { await refreshFromDisk() } }
                } label: {
                    Label("刷新元数据", systemImage: "arrow.clockwise")
                }
            }

            ZStack(alignment: .topLeading) {
                if mode == .preview {
                    TextEditor(text: .constant(localJSON))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .disabled(true)
                } else {
                    TextEditor(text: Binding(
                        get: { localJSON },
                        set: { localJSON = $0; isDirty = true }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

            HStack {
                Button("保存") {
                    Task { await saveCurrent() }
                }
                .disabled(mode == .preview || !isDirty)

                Button("另存为…") {
                    beginSaveAs()
                }
                .disabled(localJSON.isEmpty)

                Spacer()
            }
        }
        .padding(10)
    }

    private func loadInitial() async {
        let key = fileURL.standardizedFileURL
        await viewModel.loadMetadata(for: key, forceReload: false, updateEditingString: false)
        if let j = viewModel.metadataCache[key]?.jsonString {
            localJSON = j
        }
        isDirty = false
    }

    private func refreshFromDisk() async {
        let key = fileURL.standardizedFileURL
        await viewModel.loadMetadata(for: key, forceReload: true, updateEditingString: false)
        if let j = viewModel.metadataCache[key]?.jsonString {
            localJSON = j
        }
        isDirty = false
    }

    private func saveCurrent() async {
        do {
            try await viewModel.save(url: fileURL, jsonString: localJSON)
            isDirty = false
            mode = .preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginSaveAs() {
        do {
            let data = try viewModel.pngDataForExport(source: fileURL, jsonString: localJSON)
            saveAsDocument = PNGDataDocument(data: data)
            saveAsFilename = fileURL.deletingPathExtension().lastPathComponent + ".png"
            isSaveAsPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
