import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var supabaseURL = ""
    @State private var serviceKeyInput = ""
    @State private var userIdInput = ""
    @State private var hasConfig = false
    @State private var saveMessage = ""
    @State private var saveMessageIsError = false
    @State private var testStatus = ""

    private let labelWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Supabase") {
                VStack(spacing: 12) {
                    HStack {
                        Text("URL")
                            .frame(width: labelWidth, alignment: .trailing)
                        TextField("https://xxx.supabase.co", text: $supabaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        Spacer()
                    }

                    HStack {
                        Text("Service Key")
                            .frame(width: labelWidth, alignment: .trailing)
                        SecureField(
                            hasConfig ? "Replace existing key..." : "eyJ...",
                            text: $serviceKeyInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        Spacer()
                    }

                    HStack {
                        Text("User ID")
                            .frame(width: labelWidth, alignment: .trailing)
                        TextField("uuid", text: $userIdInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        Spacer()
                    }

                    HStack {
                        Text("")
                            .frame(width: labelWidth, alignment: .trailing)
                        Button("Save") { saveConfig() }
                            .disabled(supabaseURL.trimmingCharacters(in: .whitespaces).isEmpty)

                        if hasConfig {
                            Button {
                                deleteConfig()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                        }

                        if !saveMessage.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: saveMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                Text(saveMessage)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(saveMessageIsError ? .red : .green)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("")
                            .frame(width: labelWidth, alignment: .trailing)
                        Button("Test Connection") { testConnection() }
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

            Text("Supabase je hlavní úložiště poznámek. Credentials jsou povinné pro fungování aplikace.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        if let config = KeychainManager.loadCodable(key: "NoteroSupabaseConfig", as: SupabaseService.Config.self) {
            supabaseURL = config.url
            userIdInput = config.userId
            hasConfig = true
        }
    }

    private func saveConfig() {
        do {
            let existing = KeychainManager.loadCodable(key: "NoteroSupabaseConfig", as: SupabaseService.Config.self)
            let url = supabaseURL.trimmingCharacters(in: .whitespaces)
            let uid = userIdInput.trimmingCharacters(in: .whitespaces)
            let cleanKey = serviceKeyInput.filter { !$0.isWhitespace }
            let key = cleanKey.isEmpty ? (existing?.serviceKey ?? "") : cleanKey

            guard !url.isEmpty, !key.isEmpty, !uid.isEmpty else {
                saveMessage = "All fields are required"
                saveMessageIsError = true
                return
            }

            let config = SupabaseService.Config(url: url, serviceKey: key, userId: uid)
            try KeychainManager.save(key: "NoteroSupabaseConfig", codable: config)
            serviceKeyInput = ""
            hasConfig = true
            saveMessage = "Saved"
            saveMessageIsError = false
            appState.invalidateSupabaseConfigCache()
            Task { await appState.performStartupSync() }
        } catch {
            saveMessage = error.localizedDescription
            saveMessageIsError = true
        }
    }

    private func deleteConfig() {
        KeychainManager.delete(key: "NoteroSupabaseConfig")
        // Clean up legacy keys (safety net)
        KeychainManager.delete(key: "NoteroSupabaseURL")
        KeychainManager.delete(key: "NoteroSupabaseKey")
        KeychainManager.delete(key: "NoteroSupabaseUserID")
        supabaseURL = ""
        serviceKeyInput = ""
        userIdInput = ""
        hasConfig = false
        saveMessage = "Config removed"
        saveMessageIsError = false
        appState.invalidateSupabaseConfigCache()
    }

    private func testConnection() {
        guard let config = appState.supabaseConfig else {
            testStatus = "No config saved"
            return
        }
        testStatus = "Testing..."
        Task {
            let ok = await appState.supabaseService.testConnection(config: config)
            testStatus = ok ? "OK" : "Connection failed"
        }
    }
}
