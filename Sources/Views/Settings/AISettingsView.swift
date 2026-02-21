import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = false
    @State private var testStatus = ""
    @State private var ollamaModels: [String] = []
    @State private var ollamaTestStatus = ""

    var body: some View {
        Form {
            Section("Anthropic (Claude)") {
                HStack {
                    if hasAPIKey {
                        SecureField("API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Clear") {
                            KeychainManager.delete(key: "NoteroAnthropicKey")
                            apiKeyInput = ""
                            hasAPIKey = false
                        }
                    } else {
                        SecureField("Enter API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            if !apiKeyInput.isEmpty {
                                try? KeychainManager.save(key: "NoteroAnthropicKey", value: apiKeyInput)
                                hasAPIKey = true
                            }
                        }
                    }
                }

                Picker("Model:", selection: $appState.claudeModel) {
                    Text("Claude Opus 4.5").tag("claude-opus-4-5-20250514")
                    Text("Claude Sonnet 4.5").tag("claude-sonnet-4-5-20241022")
                    Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                }

                HStack {
                    Button("Test Connection") {
                        testAnthropicConnection()
                    }
                    if !testStatus.isEmpty {
                        Text(testStatus)
                            .font(.system(size: 11))
                            .foregroundColor(testStatus.contains("Success") ? .green : .red)
                    }
                }
            }

            Section("Local AI (Ollama)") {
                TextField("Server URL:", text: $appState.ollamaServerURL)

                HStack {
                    Button("Detect Models") {
                        detectOllamaModels()
                    }

                    if !ollamaModels.isEmpty {
                        Picker("Model:", selection: $appState.ollamaModel) {
                            ForEach(ollamaModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        TextField("Model:", text: $appState.ollamaModel)
                    }
                }

                HStack {
                    Button("Test Connection") {
                        testOllamaConnection()
                    }
                    if !ollamaTestStatus.isEmpty {
                        Text(ollamaTestStatus)
                            .font(.system(size: 11))
                            .foregroundColor(ollamaTestStatus.contains("Success") ? .green : .red)
                    }
                }
            }

            Section("AI Prompt") {
                TextEditor(text: $appState.aiPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 80)

                Toggle("Show AI improvements as diff", isOn: $appState.showAIDiff)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .onAppear {
            hasAPIKey = KeychainManager.load(key: "NoteroAnthropicKey") != nil
            if hasAPIKey {
                apiKeyInput = "••••••••••••"
            }
        }
    }

    private func testAnthropicConnection() {
        guard let apiKey = KeychainManager.load(key: "NoteroAnthropicKey") else {
            testStatus = "No API key saved"
            return
        }
        testStatus = "Testing..."
        Task {
            do {
                let success = try await appState.anthropicService.testConnection(apiKey: apiKey)
                testStatus = success ? "Success!" : "Failed"
            } catch {
                testStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func detectOllamaModels() {
        Task {
            do {
                ollamaModels = try await appState.ollamaService.detectModels(
                    serverURL: appState.ollamaServerURL
                )
                if let first = ollamaModels.first {
                    appState.ollamaModel = first
                }
            } catch {
                ollamaModels = []
            }
        }
    }

    private func testOllamaConnection() {
        ollamaTestStatus = "Testing..."
        Task {
            do {
                let success = try await appState.ollamaService.testConnection(
                    serverURL: appState.ollamaServerURL
                )
                ollamaTestStatus = success ? "Success!" : "No models found"
            } catch {
                ollamaTestStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
}
