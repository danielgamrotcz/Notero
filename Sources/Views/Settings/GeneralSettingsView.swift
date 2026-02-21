import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text(appState.vaultManager.vaultURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change...") {
                        chooseVaultLocation()
                    }
                }
            }

            Section("Editor") {
                TextField("Default note name:", text: $appState.defaultNoteName)

                HStack {
                    Text("Font size:")
                    Slider(value: $appState.fontSize, in: 12...20, step: 1)
                    Text("\(Int(appState.fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 30)
                }

                Toggle("Show line numbers", isOn: $appState.showLineNumbers)

                HStack {
                    Text("Auto-save delay:")
                    Slider(value: $appState.autoSaveDelay, in: 0.5...5.0, step: 0.5)
                    Text("\(appState.autoSaveDelay, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 35)
                }

                Toggle("Spell check", isOn: $appState.spellCheckEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }

    private func chooseVaultLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for your notes vault"
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            appState.vaultManager.changeVault(to: url)
            Task {
                await appState.searchService.buildIndex()
            }
        }
    }
}
