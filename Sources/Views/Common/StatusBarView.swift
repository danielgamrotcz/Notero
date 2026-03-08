import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var noteState: NoteState

    @State private var copiedID = false

    var body: some View {
        HStack(spacing: 12) {
            // Dates + word count + ID
            if noteState.selectedNoteURL != nil {
                if let created = noteState.currentNoteCreated {
                    Text("Created \(created.formatted(.dateTime.month(.abbreviated).day().year()))")
                }

                if noteState.isEditing {
                    Text("Editing...")
                        .foregroundColor(.secondary)
                } else if let modified = noteState.currentNoteModified {
                    Text("Modified \(relativeTime(modified))")
                }

                Text("\(noteState.currentContent.wordCount) words · ~\(readingTime) read")

                // Note ID
                if let noteID = noteState.currentNoteID {
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

            // Daily goal progress ring
            if appState.dailyGoalEnabled {
                let progress = min(1.0, Double(appState.dailyWordsWritten) / Double(max(1, appState.dailyGoalTarget)))
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            progress >= 1.0 ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                .help("\(appState.dailyWordsWritten) / \(appState.dailyGoalTarget) words today")
            }

            // reMarkable status
            if !noteState.remarkableStatus.isEmpty {
                Text(noteState.remarkableStatus)
                    .foregroundColor(noteState.isSendingToReMarkable ? .orange : .green)
            }

            // AI status
            if !noteState.aiStatus.isEmpty {
                Text(noteState.aiStatus)
                    .foregroundColor(noteState.isAIWorking ? .orange : .secondary)
            }

            // Save status
            saveStatusView

            // Mode indicator
            Text(noteState.isPreviewMode ? "Preview" : "Edit")
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
        case .saved:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text("Saved")
            }
        }
    }

    private var readingTime: String {
        let words = noteState.currentContent.wordCount
        if words == 0 { return "< 1 min" }
        let minutes = Double(words) / 238.0
        if minutes < 1 { return "< 1 min" }
        if minutes < 10 {
            let rounded = (minutes * 2).rounded() / 2
            return "\(rounded == Double(Int(rounded)) ? "\(Int(rounded))" : String(format: "%.1f", rounded)) min"
        }
        return "\(Int(minutes.rounded(.up))) min"
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
