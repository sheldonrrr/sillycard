import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var saveError: String?
    @State private var isSaveAsPresented = false
    @State private var saveAsDocument: PNGDataDocument?
    @State private var saveAsFilename = "card.png"

    var body: some View {
        Group {
            if let item = viewModel.selection {
                inspectorContent(for: item)
            } else {
                ContentUnavailableView("未选择角色卡", systemImage: "person.crop.rectangle", description: Text("在网格中单击一张 PNG"))
            }
        }
        .frame(minWidth: 280)
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
    }

    @ViewBuilder
    private func inspectorContent(for item: CardItem) -> some View {
        let key = item.fileURL.standardizedFileURL
        let cache = viewModel.metadataCache[key]

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("模式", selection: $viewModel.inspectorMode) {
                    ForEach(InspectorEditMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button {
                    viewModel.refreshMetadataForSelection()
                } label: {
                    Label("刷新元数据", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isDirty)
            }

            if let at = cache?.lastReadAt {
                Text("上次载入：\(at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AsyncImage(url: item.fileURL) { phase in
                switch phase {
                case .empty:
                    Color.secondary.opacity(0.1).frame(maxHeight: 240)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    Color.secondary.opacity(0.1).frame(maxHeight: 120)
                @unknown default:
                    EmptyView()
                }
            }

            switch viewModel.inspectorMode {
            case .preview:
                previewFields(json: viewModel.editingJSON)
            case .edit:
                TextEditor(text: Binding(
                    get: { viewModel.editingJSON },
                    set: { viewModel.markEditingChanged($0) }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }

            HStack {
                Button("保存") {
                    Task {
                        do {
                            try await viewModel.saveCurrentSelection()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
                .disabled(!viewModel.isDirty || viewModel.inspectorMode != .edit)

                Button("另存为…") {
                    beginSaveAs(for: item)
                }
                .disabled(viewModel.editingJSON.isEmpty)

                Spacer()

                Button("在独立窗口中编辑…") {
                    viewModel.openSingleCardEditor(url: item.fileURL)
                }
            }
            .controlSize(.regular)

            Text("提示：双击网格可在宽屏窗口编辑大段 JSON。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
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

    @ViewBuilder
    private func previewFields(json: String) -> some View {
        let lines: [(String, String)] = [
            ("名称", field(json, path: ["data", "name"])),
            ("简介", field(json, path: ["data", "description"])),
            ("开场白", field(json, path: ["data", "first_mes"])),
            ("创建者", field(json, path: ["data", "creator"])),
        ]
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.0) { pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.0).font(.caption).foregroundStyle(.secondary)
                    Text(pair.1.isEmpty ? "—" : String(pair.1.prefix(400)))
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func field(_ json: String, path: [String]) -> String {
        guard let d = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return "" }
        var cur: Any = root
        for key in path {
            guard let dict = cur as? [String: Any], let next = dict[key] else { return "" }
            cur = next
        }
        return (cur as? String) ?? ""
    }
}
