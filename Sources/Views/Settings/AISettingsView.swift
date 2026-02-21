import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = false
    @State private var saveMessage = ""
    @State private var saveMessageIsError = false
    @State private var testStatus = ""
    @State private var ollamaModels: [String] = []
    @State private var ollamaTestStatus = ""

    private let labelWidth: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Claude
            GroupBox("Anthropic (Claude)") {
                VStack(spacing: 12) {
                    HStack {
                        Text("API Key")
                            .frame(width: labelWidth, alignment: .trailing)
                        SecureField(
                            hasAPIKey ? "Replace existing key..." : "sk-ant-...",
                            text: $apiKeyInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                        Button("Save") {
                            saveAPIKey()
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        if hasAPIKey {
                            Button {
                                KeychainManager.delete(key: "NoteroAnthropicKey")
                                apiKeyInput = ""
                                hasAPIKey = false
                                saveMessage = "Key removed"
                                saveMessageIsError = false
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                        }
                    }

                    if hasAPIKey || !saveMessage.isEmpty {
                        HStack {
                            Text("")
                                .frame(width: labelWidth, alignment: .trailing)
                            if !saveMessage.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: saveMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    Text(saveMessage)
                                }
                                .font(.system(size: 11))
                                .foregroundColor(saveMessageIsError ? .red : .green)
                            } else if hasAPIKey {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Key stored")
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    HStack {
                        Text("Model")
                            .frame(width: labelWidth, alignment: .trailing)
                        Picker("", selection: $appState.claudeModel) {
                            Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                            Text("Claude Opus 4.6").tag("claude-opus-4-6")
                            Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Spacer()
                    }

                    HStack {
                        Text("")
                            .frame(width: labelWidth, alignment: .trailing)
                        Button("Test Connection") {
                            testAnthropicConnection()
                        }
                        if !testStatus.isEmpty {
                            Text(testStatus)
                                .font(.system(size: 11))
                                .foregroundColor(testStatus.contains("OK") ? .green : .red)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            // Ollama
            GroupBox("Local AI (Ollama)") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Server URL")
                            .frame(width: labelWidth, alignment: .trailing)
                        TextField("http://localhost:11434", text: $appState.ollamaServerURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Spacer()
                    }

                    HStack {
                        Text("Model")
                            .frame(width: labelWidth, alignment: .trailing)
                        if !ollamaModels.isEmpty {
                            Picker("", selection: $appState.ollamaModel) {
                                ForEach(ollamaModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        } else {
                            TextField("llama3", text: $appState.ollamaModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                        }
                        Button("Detect") {
                            detectOllamaModels()
                        }
                        Spacer()
                    }

                    HStack {
                        Text("")
                            .frame(width: labelWidth, alignment: .trailing)
                        Button("Test Connection") {
                            testOllamaConnection()
                        }
                        if !ollamaTestStatus.isEmpty {
                            Text(ollamaTestStatus)
                                .font(.system(size: 11))
                                .foregroundColor(ollamaTestStatus.contains("OK") ? .green : .red)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            // Semantic Search
            GroupBox("Semantic Search") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Enable")
                            .frame(width: labelWidth, alignment: .trailing)
                        Toggle("", isOn: Binding(
                            get: { appState.semanticSearchService.isEnabled },
                            set: { appState.semanticSearchService.toggle($0) }
                        ))
                        .labelsHidden()
                        Text("Requires Ollama running with embedding model")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    HStack {
                        Text("Model")
                            .frame(width: labelWidth, alignment: .trailing)
                        TextField("nomic-embed-text", text: Binding(
                            get: { appState.semanticSearchService.embeddingModel },
                            set: { appState.semanticSearchService.setModel($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        Spacer()
                    }

                    HStack {
                        Text("")
                            .frame(width: labelWidth, alignment: .trailing)
                        Button("Re-index all notes") {
                            Task {
                                await appState.semanticSearchService.indexAll(vaultManager: appState.vaultManager)
                            }
                        }
                        .disabled(appState.semanticSearchService.isIndexing)

                        if appState.semanticSearchService.isIndexing {
                            ProgressView()
                                .scaleEffect(0.6)
                        }

                        Text("\(appState.semanticSearchService.indexedCount) notes indexed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            // Prompt
            GroupBox("Improvement Prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $appState.aiPrompt)
                        .font(.system(size: 12))
                        .frame(height: 60)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )

                    Toggle("Show improvements as diff", isOn: $appState.showAIDiff)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            hasAPIKey = KeychainManager.hasKey("NoteroAnthropicKey")
        }
    }

    private func saveAPIKey() {
        do {
            try KeychainManager.save(key: "NoteroAnthropicKey", value: apiKeyInput)
            hasAPIKey = true
            apiKeyInput = ""
            saveMessage = "Key saved"
            saveMessageIsError = false
        } catch {
            saveMessage = error.localizedDescription
            saveMessageIsError = true
        }
    }

    private func testAnthropicConnection() {
        guard let apiKey = KeychainManager.load(key: "NoteroAnthropicKey") else {
            testStatus = "No key saved"
            return
        }
        testStatus = "Testing..."
        Task {
            do {
                let success = try await appState.anthropicService.testConnection(apiKey: apiKey)
                testStatus = success ? "OK" : "Failed"
            } catch {
                testStatus = error.localizedDescription
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
                ollamaTestStatus = success ? "OK" : "No models found"
            } catch {
                ollamaTestStatus = error.localizedDescription
            }
        }
    }
}
