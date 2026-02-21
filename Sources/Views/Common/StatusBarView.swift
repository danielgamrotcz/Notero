import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    @State private var copiedID = false

    var body: some View {
        HStack(spacing: 12) {
            // Dates + word count + ID
            if appState.selectedNoteURL != nil {
                if let created = appState.currentNoteCreated {
                    Text("Created \(created.formatted(.dateTime.month(.abbreviated).day().year()))")
                }

                if let modified = appState.currentNoteModified {
                    Text("Modified \(relativeTime(modified))")
                }

                Text("\(appState.currentContent.wordCount) words")

                // Note ID
                if let noteID = appState.currentNoteID {
                    Text("ID: \(String(noteID.prefix(8)))")
                        .help(noteID)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(noteID, forType: .string)
                            copiedID = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedID = false
                            }
                        }
                        .overlay {
                            if copiedID {
                                Text("Copied!")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThickMaterial)
                                    .cornerRadius(4)
                                    .offset(y: -20)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: copiedID)
                }
            }

            Spacer()

            // AI status
            if !appState.aiStatus.isEmpty {
                Text(appState.aiStatus)
                    .foregroundColor(appState.isAIWorking ? .orange : .secondary)
            }

            // Save status
            saveStatusView

            // Mode indicator
            Text(appState.isPreviewMode ? "Preview" : "Edit")
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(3)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background {
            VStack(spacing: 0) {
                Divider()
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var saveStatusView: some View {
        switch appState.autoSaveService.saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving...")
                .foregroundColor(.orange)
        case .saved(let date):
            Text("Saved \(date.formatted(.dateTime.hour().minute().second()))")
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) min ago"
        } else if Calendar.current.isDateInToday(date) {
            return "today at \(date.formatted(.dateTime.hour().minute()))"
        } else if Calendar.current.isDateInYesterday(date) {
            return "yesterday at \(date.formatted(.dateTime.hour().minute()))"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}

private extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }

    var characterCount: Int {
        count
    }
}
