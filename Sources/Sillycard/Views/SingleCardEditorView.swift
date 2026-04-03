import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 单卡编辑器等宽区：略大于 body，长 JSON 可读性更好。
private enum SingleCardEditorMonoFont {
    static let reading = Font.system(size: 15, design: .monospaced)
}

/// 编辑窗口：预览 / 仅左(扁平字段) / 仅右(JSON) 互斥编辑，保存后主界面可再次切换。
private enum CardEditorSurface: String, CaseIterable, Identifiable {
    case preview
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: "预览"
        case .left: "字段"
        case .right: "JSON"
        }
    }
}

public struct SingleCardEditorView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    @State private var workingJSON: String = ""
    @State private var baselineJSON: String = ""
    @State private var rightEditorText: String = ""
    @State private var surface: CardEditorSurface = .preview
    @State private var isJSONValid = true
    @State private var errorMessage: String?
    @State private var isSaveAsPresented = false
    @State private var saveAsDocument: PNGDataDocument?
    @State private var saveAsFilename = "card.png"

    private var isDirty: Bool {
        let a = CharacterCardJSONPretty.minified(workingJSON)
        let b = CharacterCardJSONPretty.minified(baselineJSON)
        if let a, let b { return a != b }
        return workingJSON != baselineJSON
    }

    private var flatRows: [(String, String)] {
        guard isJSONValid, !workingJSON.isEmpty else { return [] }
        return CharacterCardJSONFlattener.rows(from: workingJSON, maxDepth: 9, maxValueLength: 2_000_000)
    }

    private var leftLocked: Bool { surface != .left }
    private var rightLocked: Bool { surface != .right }

    public var body: some View {
        VStack(spacing: 0) {
            editorChromeBar
            Divider()
            HSplitView {
                leftPane
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                rightPane
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
        .frame(minWidth: 1020, minHeight: 600)
        .task { await loadInitial() }
        .onChange(of: surface) { old, new in
            syncSurfaceTransition(from: old, to: new)
        }
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
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var editorChromeBar: some View {
        HStack(spacing: 12) {
            Picker("模式", selection: $surface) {
                ForEach(CardEditorSurface.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .accessibilityLabel("编辑表面")

            Spacer(minLength: 12)

            if surface != .preview {
                Text("字段与 JSON 一次编辑其一；切换前已对齐。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var stampThumb: some View {
        AsyncImage(url: fileURL) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 120, height: 120)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                stampThumb
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                Button("格式化") {
                    applyPrettyToWorkingAndMirror()
                }
                .disabled(surface != .left || workingJSON.isEmpty)

                Button("复制 JSON") {
                    let s = CharacterCardJSONPretty.minified(workingJSON) ?? workingJSON
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(s, forType: .string)
                }
                .disabled(workingJSON.isEmpty)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("完整字段列表")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 14)

                    if !isJSONValid {
                        Text("JSON 无效时请到「JSON」表面修正。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 14)
                    } else if flatRows.isEmpty {
                        Text("无解析数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                    } else {
                        ForEach(flatRows, id: \.0) { row in
                            let path = row.0
                            let val = row.1
                            let editable = CharacterCardJSONPathMutation.isEditableFlattenedValue(path: path, displayValue: val)
                            FlatJSONRowEditor(
                                path: path,
                                displayValue: val,
                                isEditable: editable && isJSONValid && !leftLocked,
                                isLocked: leftLocked,
                                onCommit: { newText in
                                    guard surface == .left else { return }
                                    commitPathEdit(path: path, value: newText)
                                }
                            )
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Spacer(minLength: 8)
                Button("保存") {
                    Task { await saveCurrent() }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!isDirty || !isJSONValid)

                Button("另存为…") {
                    beginSaveAs()
                }
                .disabled(workingJSON.isEmpty)
            }
            .controlSize(.regular)

            Group {
                if surface == .preview {
                    ScrollView {
                        Text(verbatim: CharacterCardJSONPretty.format(workingJSON))
                            .font(SingleCardEditorMonoFont.reading)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                } else {
                    TextEditor(text: rightEditorBinding)
                        .font(SingleCardEditorMonoFont.reading)
                        .scrollContentBackground(.hidden)
                        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                        .disabled(rightLocked)
                        .opacity(rightLocked ? 0.55 : 1)
                }
            }
        }
        .padding(12)
    }

    private var rightEditorBinding: Binding<String> {
        Binding(
            get: { rightEditorText },
            set: { new in
                guard surface == .right else { return }
                rightEditorText = new
                let ok = CharacterCardJSONPretty.isValidJSONString(new)
                isJSONValid = ok
                if ok { workingJSON = new }
            }
        )
    }

    private func syncSurfaceTransition(from old: CardEditorSurface, to new: CardEditorSurface) {
        if old == .right, new != .right {
            if CharacterCardJSONPretty.isValidJSONString(rightEditorText) {
                workingJSON = rightEditorText
                isJSONValid = true
            }
        }
        switch new {
        case .preview, .left, .right:
            rightEditorText = CharacterCardJSONPretty.format(workingJSON)
            isJSONValid = CharacterCardJSONPretty.isValidJSONString(workingJSON)
        }
    }

    private func applyPrettyToWorkingAndMirror() {
        let formatted = CharacterCardJSONPretty.format(workingJSON)
        guard !formatted.isEmpty else { return }
        workingJSON = formatted
        rightEditorText = formatted
        isJSONValid = CharacterCardJSONPretty.isValidJSONString(formatted)
    }

    private func commitPathEdit(path: String, value: String) {
        guard isJSONValid, surface == .left else { return }
        do {
            let next = try CharacterCardJSONPathMutation.setLeafString(jsonString: workingJSON, path: path, newValue: value)
            workingJSON = next
            rightEditorText = CharacterCardJSONPretty.format(next)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadInitial() async {
        let key = fileURL.standardizedFileURL
        await viewModel.loadMetadata(for: key, forceReload: false, updateEditingString: false)
        if let j = viewModel.metadataCache[key]?.jsonString {
            baselineJSON = j
            workingJSON = j
            rightEditorText = CharacterCardJSONPretty.format(j)
            isJSONValid = CharacterCardJSONPretty.isValidJSONString(j)
            surface = .preview
        }
    }

    private func saveCurrent() async {
        do {
            let toWrite = CharacterCardJSONPretty.minified(workingJSON) ?? workingJSON
            try await viewModel.save(url: fileURL, jsonString: toWrite)
            baselineJSON = toWrite
            workingJSON = toWrite
            rightEditorText = CharacterCardJSONPretty.format(toWrite)
            surface = .preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginSaveAs() {
        do {
            let payload = CharacterCardJSONPretty.minified(workingJSON) ?? workingJSON
            let data = try viewModel.pngDataForExport(source: fileURL, jsonString: payload)
            saveAsDocument = PNGDataDocument(data: data)
            saveAsFilename = fileURL.deletingPathExtension().lastPathComponent + ".png"
            isSaveAsPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 扁平字段行

private struct FlatJSONRowEditor: View {
    let path: String
    let displayValue: String
    let isEditable: Bool
    var isLocked: Bool = false
    let onCommit: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(path)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if isEditable && !isLocked {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(SingleCardEditorMonoFont.reading)
                    .lineLimit(1...)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .onChange(of: text) { _, new in
                        onCommit(new)
                    }
            } else {
                Text(displayValue)
                    .font(SingleCardEditorMonoFont.reading)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .opacity(isLocked && isEditable ? 0.65 : 1)
        .onAppear { text = displayValue }
        .onChange(of: displayValue) { _, new in
            if new != text { text = new }
        }
    }
}
