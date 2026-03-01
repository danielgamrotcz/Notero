import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var noteState = NoteState()

    var body: some View {
        ZStack {
            switch appState.syncState {
            case .needsSetup:
                setupRequiredView
            case .syncing:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Syncing notes...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                mainContentView
            case .error(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Sync Error")
                        .font(.headline)
                    Text(message)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await appState.performStartupSync() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .focusedSceneObject(noteState)
        .navigationTitle(windowTitle)
    }

    private var setupRequiredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Supabase Setup Required")
                .font(.headline)
            Text("Configure your Supabase credentials in Settings to get started.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Text("Open Settings")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var mainContentView: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $appState.sidebarVisibility) {
                SidebarView()
                    .environmentObject(appState)
                    .environmentObject(noteState)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 400)
            } detail: {
                EditorView()
                    .environmentObject(appState)
                    .environmentObject(noteState)
            }
            .navigationSplitViewStyle(.balanced)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                appState.vaultManager.loadFileTree()
            }

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
