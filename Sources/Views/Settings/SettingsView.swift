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
        }
        .frame(width: 520, height: 620)
    }
}
