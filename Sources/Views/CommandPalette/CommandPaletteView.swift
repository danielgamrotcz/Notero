import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var noteResults: [(name: String, url: URL)] = []
    let notesOnly: Bool

    private var commands: [CommandItem] {
        CommandItem.allCommands(appState: appState)
    }

    private var filteredCommands: [CommandItem] {
        guard !notesOnly else { return [] }
        guard !query.isEmpty else { return commands }
        let lowerQuery = query.lowercased()
        return commands.filter { $0.name.lowercased().contains(lowerQuery) }
    }

    private var totalCount: Int {
        noteResults.count + filteredCommands.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(notesOnly ? "Open note..." : "Type a command or note name...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit { executeSelected() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            // Results
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Notes section
                    if !noteResults.isEmpty {
                        Text("Notes")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)

                        ForEach(Array(noteResults.enumerated()), id: \.offset) { offset, note in
                            paletteRow(
                                icon: "doc.text",
                                title: note.name,
                                shortcut: nil,
                                isSelected: offset == selectedIndex
                            ) {
                                appState.openNote(url: note.url)
                                dismiss()
                            }
                        }
                    }

                    // Commands section
                    if !filteredCommands.isEmpty {
                        Text("Commands")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)

                        ForEach(Array(filteredCommands.enumerated()), id: \.offset) { offset, command in
                            paletteRow(
                                icon: command.icon,
                                title: command.name,
                                shortcut: command.shortcut,
                                isSelected: offset + noteResults.count == selectedIndex
                            ) {
                                command.action()
                                dismiss()
                            }
                        }
                    }

                    if totalCount == 0 {
                        Text("No results")
                            .foregroundColor(.secondary)
                            .padding(12)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 600)
        .background(.ultraThickMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(totalCount - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onChange(of: query) { _, newValue in
            selectedIndex = 0
            updateNoteResults(query: newValue)
        }
        .onAppear {
            updateNoteResults(query: "")
        }
    }

    private func paletteRow(
        icon: String, title: String, shortcut: String?,
        isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 14))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func executeSelected() {
        if selectedIndex < noteResults.count {
            appState.openNote(url: noteResults[selectedIndex].url)
        } else {
            let cmdIndex = selectedIndex - noteResults.count
            if cmdIndex < filteredCommands.count {
                filteredCommands[cmdIndex].action()
            }
        }
        dismiss()
    }

    private func dismiss() {
        appState.showCommandPalette = false
        appState.showQuickOpen = false
    }

    private func updateNoteResults(query: String) {
        let allNotes = appState.linkResolver.allNoteNames()
        if query.isEmpty {
            noteResults = allNotes
        } else {
            noteResults = appState.linkResolver.fuzzyMatch(query: query, in: allNotes)
        }
    }
}
