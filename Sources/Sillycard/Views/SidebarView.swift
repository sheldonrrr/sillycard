import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showNewLibrarySheet = false
    @State private var newLibraryName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                brandTitle
                Spacer(minLength: 8)
                Button {
                    newLibraryName = ""
                    showNewLibrarySheet = true
                } label: {
                    Text("新库")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            List {
                Section("卡库") {
                    ForEach(viewModel.cardLibraries) { lib in
                        Button {
                            try? viewModel.switchToLibrary(id: lib.id)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                LibraryDiamondMarker(color: SidebarMarkerPalette.color(forKey: lib.id, variant: .library))
                                Text(lib.displayName)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(viewModel.libraryCardCounts[lib.id] ?? 0)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(viewModel.activeLibraryId == lib.id ? Color.accentColor : Color.primary)
                        .help(lib.displayName)
                    }

                    Button {
                        viewModel.setLibraryScope(.main)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "rectangle.stack")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, height: 12)
                            Text("主库")
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.libraryScope == .main ? Color.accentColor : Color.primary)
                    .help("不含归档文件夹")

                    Button {
                        viewModel.setLibraryScope(.archive)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "archivebox")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, height: 12)
                            Text("归档")
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.libraryScope == .archive ? Color.accentColor : Color.primary)
                }

                Section {
                    ForEach(MainLibraryLayoutMode.allCases) { mode in
                        Button {
                            viewModel.mainLibraryLayoutMode = mode
                        } label: {
                            Label(mode.title, systemImage: mode.systemImage)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(viewModel.mainLibraryLayoutMode == mode ? Color.accentColor : Color.primary)
                    }
                } header: {
                    Text("视图")
                } footer: {
                    Text("仅影响默认库；归档固定为列表。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)

            Divider()

            tagFilterPanel
        }
        .frame(minWidth: 240)
        .sheet(isPresented: $showNewLibrarySheet) {
            NavigationStack {
                Form {
                    TextField("卡库名称", text: $newLibraryName)
                        .textFieldStyle(.roundedBorder)
                }
                .formStyle(.grouped)
                .padding()
                .navigationTitle("新卡库")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showNewLibrarySheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") {
                            let name = newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                viewModel.createManagedLibrary(named: name)
                            }
                            showNewLibrarySheet = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .frame(minWidth: 360, minHeight: 160)
        }
    }

    private var brandTitle: some View {
        Text("Sillycard")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private var tagFilterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("标签")
                    .font(.headline)
                Spacer(minLength: 8)
                if viewModel.selectedTags.count >= 2 {
                    Button("清除") {
                        viewModel.selectedTags.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if viewModel.allTagsInLibrary.isEmpty {
                Text("有角色卡后显示标签。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    WrappingTagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(viewModel.allTagsInLibrary, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagChip(_ tag: String) -> some View {
        let selected = viewModel.selectedTags.contains(tag)
        let neutralFill = Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.35 : 0.55)
        let neutralStroke = Color.secondary.opacity(0.35)
        return Button {
            if selected {
                viewModel.selectedTags.remove(tag)
            } else {
                viewModel.selectedTags.insert(tag)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tag)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(viewModel.tagCountsByName[tag] ?? 0)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .opacity(selected ? 0.95 : 0.75)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? Color.accentColor : neutralFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? Color.clear : neutralStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(tag) · \(viewModel.tagCountsByName[tag] ?? 0) 张，多选为且")
    }
}

// MARK: - 标签流式布局（放在本文件内，避免仅 Xcode 打开工程时未包含新增 .swift 导致 “Cannot find in scope”）

private struct WrappingTagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let pl = arrange(proposal: proposal, subviews: subviews)
        for (i, f) in pl.frames.enumerated() {
            let o = CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY)
            subviews[i].place(at: o, proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (bounds: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        let maxW = proposal.width ?? .greatestFiniteMagnitude

        for sub in subviews {
            let sz = sub.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            let useW = min(sz.width, maxW)
            let useH = sz.height
            if x + useW > maxW + 0.5, x > 0 {
                x = 0
                y += rowH + verticalSpacing
                rowH = 0
            }
            frames.append(CGRect(x: x, y: y, width: useW, height: useH))
            rowH = max(rowH, useH)
            x += useW + horizontalSpacing
        }
        let totalH = y + rowH
        let totalW = min(maxW, frames.map(\.maxX).max() ?? 0)
        return (CGSize(width: totalW, height: totalH), frames)
    }
}
