import SwiftUI

struct NoteHistoryView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var snapshots: [NoteSnapshot] = []
    @State private var selectedSnapshot: NoteSnapshot?
    @State private var showDiff = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Note History")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            if snapshots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No history available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Snapshot list
                    List(snapshots, selection: $selectedSnapshot) { snapshot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.relativeTimeString)
                                .font(.system(size: 13))
                            Text("\(snapshot.content.count) characters")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(snapshot)
                        .onTapGesture {
                            selectedSnapshot = snapshot
                            showDiff = false
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 200, maxWidth: 250)

                    // Preview
                    VStack(spacing: 0) {
                        if let snapshot = selectedSnapshot {
                            HStack {
                                Button("Restore this version") {
                                    appState.currentContent = snapshot.content
                                    if let url = appState.selectedNoteURL {
                                        appState.autoSaveService.saveImmediately(
                                            content: snapshot.content, to: url
                                        )
                                    }
                                    isPresented = false
                                }
                                .buttonStyle(.borderedProminent)

                                Button(showDiff ? "Show Preview" : "Compare with current") {
                                    showDiff.toggle()
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }
                            .padding(8)

                            Divider()

                            if showDiff {
                                diffView(snapshot: snapshot)
                            } else {
                                ScrollView {
                                    Text(snapshot.content)
                                        .font(.system(size: 13, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .textSelection(.enabled)
                                }
                            }
                        } else {
                            Text("Select a snapshot to preview")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
        .onAppear {
            guard let url = appState.selectedNoteURL else { return }
            snapshots = NoteHistoryService.shared.loadSnapshots(for: url)
        }
    }

    private func diffView(snapshot: NoteSnapshot) -> some View {
        let diffLines = NoteHistoryService.diff(old: snapshot.content, new: appState.currentContent)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(diffBackground(for: line.type))
                }
            }
            .padding()
        }
    }

    private func diffBackground(for type: DiffLine.DiffType) -> Color {
        switch type {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .context: return .clear
        }
    }
}

extension NoteSnapshot: Hashable {
    static func == (lhs: NoteSnapshot, rhs: NoteSnapshot) -> Bool {
        lhs.filename == rhs.filename
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(filename)
    }
}
