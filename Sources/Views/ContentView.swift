import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var noteState = NoteState()

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $appState.sidebarVisibility) {
                SidebarView()
                    .environmentObject(appState)
                    .environmentObject(noteState)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 400)
            } detail: {
                EditorView()
                    .environmentObject(appState)
                    .environmentObject(noteState)
            }
            .navigationSplitViewStyle(.balanced)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                appState.vaultManager.loadFileTree()
            }

            // Command Palette overlay
            if appState.showCommandPalette {
                commandPaletteOverlay(notesOnly: false)
            }

            if appState.showQuickOpen {
                commandPaletteOverlay(notesOnly: true)
            }
        }
        .sheet(isPresented: $appState.showNoteHistory) {
            NoteHistoryView(isPresented: $appState.showNoteHistory)
                .environmentObject(appState)
                .environmentObject(noteState)
        }
        .focusedSceneObject(noteState)
        .navigationTitle(windowTitle)
        .onAppear {
            noteState.configure(appState: appState)
            noteState.restoreLastOpenedNote()
            NSApp.windows.first?.tabbingMode = .disallowed
        }
    }

    private var windowTitle: String {
        if let url = noteState.selectedNoteURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Notero"
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
                    .environmentObject(noteState)
                Spacer()
            }
            .padding(.top, 80)
        }
    }
}
