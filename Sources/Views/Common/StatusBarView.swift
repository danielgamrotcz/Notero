import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Word and character count
            if appState.selectedNoteURL != nil {
                Text("\(appState.currentContent.wordCount) words")
                Text("\(appState.currentContent.characterCount) chars")
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
}

private extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }

    var characterCount: Int {
        count
    }
}
