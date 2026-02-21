import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            NavigationSplitView {
                if appState.showSidebar {
                    SidebarView()
                        .environmentObject(appState)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 400)
                }
            } detail: {
                EditorView()
                    .environmentObject(appState)
            }
            .navigationSplitViewStyle(.balanced)

            // Command Palette overlay
            if appState.showCommandPalette {
                commandPaletteOverlay(notesOnly: false)
            }

            if appState.showQuickOpen {
                commandPaletteOverlay(notesOnly: true)
            }
        }
    }

    private func commandPaletteOverlay(notesOnly: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.showCommandPalette = false
                    appState.showQuickOpen = false
                }

            VStack {
                CommandPaletteView(notesOnly: notesOnly)
                    .environmentObject(appState)
                Spacer()
            }
            .padding(.top, 80)
        }
    }
}
