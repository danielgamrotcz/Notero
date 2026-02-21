import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    private let labelWidth: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Vault
            GroupBox("Vault") {
                HStack {
                    Text("Location")
                        .frame(width: labelWidth, alignment: .trailing)
                    Text(appState.vaultManager.vaultURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Change...") {
                        chooseVaultLocation()
                    }
                }
                .padding(.vertical, 4)
            }

            // Editor
            GroupBox("Editor") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Default note name")
                            .frame(width: labelWidth, alignment: .trailing)
                        TextField("", text: $appState.defaultNoteName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        Spacer()
                    }

                    HStack {
                        Text("Font size")
                            .frame(width: labelWidth, alignment: .trailing)
                        Slider(value: $appState.fontSize, in: 12...20, step: 1)
                            .frame(width: 140)
                        Text("\(Int(appState.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Spacer()
                    }

                    HStack {
                        Text("Auto-save delay")
                            .frame(width: labelWidth, alignment: .trailing)
                        Slider(value: $appState.autoSaveDelay, in: 0.5...5.0, step: 0.5)
                            .frame(width: 140)
                        Text("\(appState.autoSaveDelay, specifier: "%.1f") s")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Spacer()
                    }

                    HStack {
                        Text("")
                            .frame(width: labelWidth, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show line numbers", isOn: $appState.showLineNumbers)
                            Toggle("Spell check", isOn: $appState.spellCheckEnabled)
                            Toggle("Auto-title notes from H1 heading", isOn: $appState.autoTitleFromH1)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
            // Sidebar
            GroupBox("Sidebar") {
                HStack {
                    Text("")
                        .frame(width: labelWidth, alignment: .trailing)
                    Toggle("Show activity heatmap in sidebar", isOn: $appState.showActivityHeatmapInSidebar)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Writing Goal
            GroupBox("Writing Goal") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Daily goal")
                            .frame(width: labelWidth, alignment: .trailing)
                        Toggle("", isOn: $appState.dailyGoalEnabled)
                            .labelsHidden()
                        if appState.dailyGoalEnabled {
                            Stepper(value: $appState.dailyGoalTarget, in: 100...5000, step: 100) {
                                Text("\(appState.dailyGoalTarget) words")
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
