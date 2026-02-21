import SwiftUI

extension View {
    func noteroShortcuts(appState: AppState) -> some View {
        self
            .keyboardShortcut("n", modifiers: .command) // handled via commands
    }
}
