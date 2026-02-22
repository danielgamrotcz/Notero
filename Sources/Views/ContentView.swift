import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab bar (only when multiple tabs)
                if appState.tabs.count > 1 {
                    tabBar
                }

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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appState.vaultManager.loadFileTree()
                }
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
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                    let isActive = index == appState.currentTabIndex
                    HStack(spacing: 4) {
                        Text(tab.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundColor(isActive ? .primary : .secondary)

                        if appState.tabs.count > 1 {
                            Button {
                                appState.closeTab(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.switchToTab(at: index)
                    }

                    if index < appState.tabs.count - 1 {
                        Divider().frame(height: 16)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 30)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
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
