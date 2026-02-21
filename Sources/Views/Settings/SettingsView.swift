import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
        }
        .frame(minWidth: 450, minHeight: 400)
    }
}
