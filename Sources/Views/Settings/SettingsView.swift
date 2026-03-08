import SwiftUI
import Sparkle

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettingsView(updater: updater)
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AISettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            SyncSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }

            ReMarkableSettingsView()
                .tabItem {
                    Label("reMarkable", systemImage: "tablet")
                }
        }
        .frame(width: 520, height: 620)
    }
}
