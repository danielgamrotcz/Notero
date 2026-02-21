import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // Services
    let vaultManager: VaultManager
    let searchService: SearchService
    let autoSaveService: AutoSaveService
    let linkResolver: LinkResolver
    let anthropicService = AnthropicService()
    let ollamaService = OllamaService()

    // UI State
    @Published var selectedNoteURL: URL?
    @Published var currentContent: String = ""
    @Published var isPreviewMode: Bool = false
    @Published var showSidebar: Bool = true
    @Published var showBacklinks: Bool = false
    @Published var showCommandPalette: Bool = false
    @Published var showQuickOpen: Bool = false
    @Published var showLineNumbers: Bool = false
    @Published var fontSize: CGFloat = 14
    @Published var aiStatus: String = ""
    @Published var isAIWorking: Bool = false

    // Settings
    @Published var defaultNoteName: String
    @Published var autoSaveDelay: Double
    @Published var spellCheckEnabled: Bool
    @Published var claudeModel: String
    @Published var ollamaServerURL: String
    @Published var ollamaModel: String
    @Published var aiPrompt: String
    @Published var showAIDiff: Bool

    private var cancellables = Set<AnyCancellable>()

    init() {
        let vault = VaultManager()
        self.vaultManager = vault
        self.searchService = SearchService(vaultManager: vault)
        self.autoSaveService = AutoSaveService(vaultManager: vault)
        self.linkResolver = LinkResolver(vaultManager: vault)

        // Load settings
        let defaults = UserDefaults.standard
        self.defaultNoteName = defaults.string(forKey: "defaultNoteName") ?? "Untitled"
        self.autoSaveDelay = defaults.double(forKey: "autoSaveDelay").nonZero ?? 1.0
        self.spellCheckEnabled = defaults.bool(forKey: "spellCheckEnabled")
        self.showLineNumbers = defaults.bool(forKey: "showLineNumbers")
        self.fontSize = CGFloat(defaults.double(forKey: "fontSize").nonZero ?? 14)
        self.claudeModel = defaults.string(forKey: "claudeModel") ?? "claude-sonnet-4-5-20241022"
        self.ollamaServerURL = defaults.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3"
        self.aiPrompt = defaults.string(forKey: "aiPrompt") ?? "Improve the following text for clarity, conciseness, and flow. Keep the same language. Return only the improved text, no explanations."
        self.showAIDiff = defaults.bool(forKey: "showAIDiff")

        setupSettingsSync()

        Task {
            await searchService.buildIndex()
        }
    }

    private func setupSettingsSync() {
        $defaultNoteName.dropFirst().sink { UserDefaults.standard.set($0, forKey: "defaultNoteName") }.store(in: &cancellables)
        $autoSaveDelay.dropFirst().sink { [weak self] val in
            UserDefaults.standard.set(val, forKey: "autoSaveDelay")
            self?.autoSaveService.updateDelay(val)
        }.store(in: &cancellables)
        $spellCheckEnabled.dropFirst().sink { UserDefaults.standard.set($0, forKey: "spellCheckEnabled") }.store(in: &cancellables)
        $showLineNumbers.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showLineNumbers") }.store(in: &cancellables)
        $fontSize.dropFirst().sink { UserDefaults.standard.set(Double($0), forKey: "fontSize") }.store(in: &cancellables)
        $claudeModel.dropFirst().sink { UserDefaults.standard.set($0, forKey: "claudeModel") }.store(in: &cancellables)
        $ollamaServerURL.dropFirst().sink { UserDefaults.standard.set($0, forKey: "ollamaServerURL") }.store(in: &cancellables)
        $ollamaModel.dropFirst().sink { UserDefaults.standard.set($0, forKey: "ollamaModel") }.store(in: &cancellables)
        $aiPrompt.dropFirst().sink { UserDefaults.standard.set($0, forKey: "aiPrompt") }.store(in: &cancellables)
        $showAIDiff.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showAIDiff") }.store(in: &cancellables)
    }

    // MARK: - Note Operations

    func openNote(url: URL) {
        // Save current before switching
        if let currentURL = selectedNoteURL {
            autoSaveService.saveImmediately(content: currentContent, to: currentURL)
        }

        if let content = vaultManager.readNote(at: url) {
            currentContent = content
            selectedNoteURL = url

            // Restore mode preference
            let modeKey = "mode-\(url.lastPathComponent)"
            isPreviewMode = UserDefaults.standard.bool(forKey: modeKey)

            linkResolver.findBacklinks(for: url)
        }
    }

    func createNewNote(in folderURL: URL? = nil) {
        if let url = vaultManager.createNote(named: defaultNoteName, in: folderURL) {
            openNote(url: url)
            Task {
                await searchService.reindex(url: url)
            }
        }
    }

    func saveCurrentNote() {
        guard let url = selectedNoteURL else { return }
        autoSaveService.saveImmediately(content: currentContent, to: url)
        Task {
            await searchService.reindex(url: url)
        }
    }

    func togglePreview() {
        isPreviewMode.toggle()
        if let url = selectedNoteURL {
            UserDefaults.standard.set(isPreviewMode, forKey: "mode-\(url.lastPathComponent)")
        }
    }

    // MARK: - AI

    func improveWithClaude() {
        guard let apiKey = KeychainManager.load(key: "NoteroAnthropicKey"), !apiKey.isEmpty else {
            aiStatus = "No API key set. Go to Settings → AI."
            return
        }
        improveText(using: .claude(apiKey: apiKey, model: claudeModel))
    }

    func improveWithOllama() {
        improveText(using: .ollama(serverURL: ollamaServerURL, model: ollamaModel))
    }

    private enum AIProvider {
        case claude(apiKey: String, model: String)
        case ollama(serverURL: String, model: String)
    }

    private func improveText(using provider: AIProvider) {
        guard !currentContent.isEmpty else { return }

        isAIWorking = true
        aiStatus = "AI improving..."

        let textToImprove = currentContent
        let prompt = aiPrompt

        Task {
            do {
                let improved: String
                switch provider {
                case .claude(let apiKey, let model):
                    improved = try await anthropicService.improve(
                        text: textToImprove, model: model,
                        apiKey: apiKey, prompt: prompt
                    )
                case .ollama(let serverURL, let model):
                    improved = try await ollamaService.improve(
                        text: textToImprove, model: model,
                        serverURL: serverURL, prompt: prompt
                    )
                }
                currentContent = improved
                aiStatus = "AI improvement applied"
                isAIWorking = false
            } catch {
                aiStatus = error.localizedDescription
                isAIWorking = false
            }
        }
    }
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
