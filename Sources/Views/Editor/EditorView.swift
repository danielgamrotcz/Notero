import SwiftUI

struct EditorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.selectedNoteURL != nil {
                ZStack {
                    if appState.isPreviewMode {
                        MarkdownPreviewView(
                            content: appState.currentContent,
                            onCheckboxToggle: { index in
                                toggleCheckbox(at: index)
                            },
                            onWikilinkClick: { linkName in
                                if let url = appState.linkResolver.resolve(linkName: linkName) {
                                    appState.openNote(url: url)
                                }
                            }
                        )
                        .transition(.opacity)
                    } else {
                        MarkdownEditorView(
                            text: $appState.currentContent,
                            fontSize: appState.fontSize,
                            showLineNumbers: appState.showLineNumbers,
                            spellCheck: appState.spellCheckEnabled,
                            onTextChange: { newText in
                                guard let url = appState.selectedNoteURL else { return }
                                appState.autoSaveService.scheduleSave(content: newText, to: url)
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: appState.isPreviewMode)

                // Backlinks panel
                if appState.showBacklinks {
                    Divider()
                    backlinksPanel
                }

                // Status bar
                StatusBarView()
                    .environmentObject(appState)
            } else {
                EmptyStateView()
                    .environmentObject(appState)
            }
        }
    }

    private var backlinksPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Backlinks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(appState.linkResolver.backlinks.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            if appState.linkResolver.backlinks.isEmpty {
                Text("No backlinks found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(appState.linkResolver.backlinks) { backlink in
                    Button {
                        appState.openNote(url: backlink.noteURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text(backlink.noteName)
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 120)
        .background(.ultraThinMaterial)
    }

    private func toggleCheckbox(at index: Int) {
        var lines = appState.currentContent.components(separatedBy: "\n")
        var checkboxIndex = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                if checkboxIndex == index {
                    if trimmed.hasPrefix("- [ ] ") {
                        lines[i] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
                    } else {
                        lines[i] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                            .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
                    }
                    break
                }
                checkboxIndex += 1
            }
        }
        appState.currentContent = lines.joined(separator: "\n")
        if let url = appState.selectedNoteURL {
            appState.autoSaveService.saveImmediately(content: appState.currentContent, to: url)
        }
    }
}
