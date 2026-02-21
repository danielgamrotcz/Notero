import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary)
            Text("No Note Selected")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Select a note from the sidebar or create a new one")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("New Note") {
                appState.createNewNote()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
