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
    let favoritesManager = FavoritesManager()
    let semanticSearchService = SemanticSearchService()

    // Note State
    @Published var selectedNoteURL: URL?
    @Published var currentContent: String = ""
    @Published var currentNoteID: String?
    @Published var currentNoteCreated: Date?
    @Published var currentNoteModified: Date?
    @Published var isPreviewMode: Bool = false

    // UI State
    @Published var showSidebar: Bool = true
    @Published var showBacklinks: Bool = false
    @Published var showCommandPalette: Bool = false
    @Published var showQuickOpen: Bool = false
    @Published var showFindReplace: Bool = false
    @Published var showFindReplaceWithReplace: Bool = false
    @Published var showNoteHistory: Bool = false
    @Published var showLineNumbers: Bool = false
    @Published var fontSize: CGFloat = 14
    @Published var aiStatus: String = ""
    @Published var isAIWorking: Bool = false
    @Published var renamingItemURL: URL?
    @Published var renamingIsNew: Bool = false
    @Published var isEditing: Bool = false
    @Published var pendingSearchHighlight: String?
    @Published var focusedFolderURL: URL?

    // Settings
    @Published var defaultNoteName: String
    @Published var autoSaveDelay: Double
    @Published var spellCheckEnabled: Bool
    @Published var autoTitleFromH1: Bool
    @Published var claudeModel: String
    @Published var ollamaServerURL: String
    @Published var ollamaModel: String
    @Published var aiPrompt: String
    @Published var showAIDiff: Bool
    @Published var sortOrder: NoteSortOrder
    @Published var dailyGoalEnabled: Bool
    @Published var dailyGoalTarget: Int
    @Published var dailyWordsWritten: Int = 0
    @Published var showActivityHeatmapInSidebar: Bool

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
        self.autoTitleFromH1 = defaults.object(forKey: "autoTitleFromH1") == nil ? true : defaults.bool(forKey: "autoTitleFromH1")
        self.showLineNumbers = defaults.bool(forKey: "showLineNumbers")
        self.fontSize = CGFloat(defaults.double(forKey: "fontSize").nonZero ?? 14)
        self.claudeModel = defaults.string(forKey: "claudeModel") ?? "claude-sonnet-4-6"
        self.ollamaServerURL = defaults.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3"
        self.aiPrompt = defaults.string(forKey: "aiPrompt") ?? "Improve the following text for clarity, conciseness, and flow. Keep the same language. Return only the improved text, no explanations."
        self.showAIDiff = defaults.bool(forKey: "showAIDiff")
        let savedSort = defaults.string(forKey: "noteSortOrder") ?? ""
        self.sortOrder = NoteSortOrder(rawValue: savedSort) ?? .nameAscending
        self.dailyGoalEnabled = defaults.bool(forKey: "dailyGoalEnabled")
        self.dailyGoalTarget = defaults.object(forKey: "dailyGoalTarget") == nil ? 500 : defaults.integer(forKey: "dailyGoalTarget")
        self.showActivityHeatmapInSidebar = defaults.bool(forKey: "showActivityHeatmapInSidebar")

        // Load today's word count
        let todayKey = "goal-\(Self.todayKey())"
        self.dailyWordsWritten = defaults.integer(forKey: todayKey)

        // Forward VaultManager changes into AppState so SwiftUI redraws immediately
        vault.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Forward FavoritesManager changes so favorites toggle updates UI immediately
        favoritesManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        setupSettingsSync()
        syncVaultPathToAppGroup()

        autoSaveService.onDidSave = { [weak self] content, url in
            self?.isEditing = false
            self?.currentNoteModified = Date()
            self?.autoTitleRenameIfNeeded(content: content, url: url)
        }

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
        $autoTitleFromH1.dropFirst().sink { UserDefaults.standard.set($0, forKey: "autoTitleFromH1") }.store(in: &cancellables)
        $showLineNumbers.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showLineNumbers") }.store(in: &cancellables)
        $fontSize.dropFirst().sink { UserDefaults.standard.set(Double($0), forKey: "fontSize") }.store(in: &cancellables)
        $claudeModel.dropFirst().sink { UserDefaults.standard.set($0, forKey: "claudeModel") }.store(in: &cancellables)
        $ollamaServerURL.dropFirst().sink { UserDefaults.standard.set($0, forKey: "ollamaServerURL") }.store(in: &cancellables)
        $ollamaModel.dropFirst().sink { UserDefaults.standard.set($0, forKey: "ollamaModel") }.store(in: &cancellables)
        $aiPrompt.dropFirst().sink { UserDefaults.standard.set($0, forKey: "aiPrompt") }.store(in: &cancellables)
        $showAIDiff.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showAIDiff") }.store(in: &cancellables)
        $dailyGoalEnabled.dropFirst().sink { UserDefaults.standard.set($0, forKey: "dailyGoalEnabled") }.store(in: &cancellables)
        $dailyGoalTarget.dropFirst().sink { UserDefaults.standard.set($0, forKey: "dailyGoalTarget") }.store(in: &cancellables)
        $showActivityHeatmapInSidebar.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showActivityHeatmapInSidebar") }.store(in: &cancellables)
        $sortOrder.dropFirst().sink {
            UserDefaults.standard.set($0.rawValue, forKey: "noteSortOrder")
        }.store(in: &cancellables)
        $sortOrder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] order in
                self?.vaultManager.loadFileTree(sortOrder: order)
            }
            .store(in: &cancellables)
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

            // Assign unique ID lazily and load dates
            let meta = NoteMetadataService.shared.metadata(for: url)
            currentNoteID = meta.id
            currentNoteCreated = meta.created
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            currentNoteModified = attrs?[.modificationDate] as? Date

            // Restore mode preference
            let modeKey = "mode-\(url.lastPathComponent)"
            isPreviewMode = UserDefaults.standard.bool(forKey: modeKey)

            linkResolver.findBacklinks(for: url)
        }
    }

    func createNewNote(in folderURL: URL? = nil) {
        if let url = vaultManager.createNote(named: defaultNoteName, in: folderURL) {
            _ = NoteMetadataService.shared.ensureID(for: url)
            openNote(url: url)
            Task {
                await searchService.reindex(url: url)
            }
        }
    }

    func createNewFolder(in folderURL: URL? = nil) {
        let parent = folderURL ?? vaultManager.vaultURL
        var name = "New Folder"
        var counter = 1
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            counter += 1
            name = "New Folder \(counter)"
        }
        if let url = vaultManager.createFolder(named: name, in: folderURL) {
            renamingIsNew = true
            renamingItemURL = url
        }
    }

    func commitRename(url: URL, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renamingItemURL = nil
            return
        }
        if let newURL = vaultManager.renameItem(at: url, to: trimmed) {
            if selectedNoteURL == url {
                selectedNoteURL = newURL
            }
        }
        renamingIsNew = false
        renamingItemURL = nil
    }

    func saveCurrentNote() {
        guard let url = selectedNoteURL else { return }
        autoSaveService.saveImmediately(content: currentContent, to: url)
        NoteHistoryService.shared.saveSnapshot(content: currentContent, for: url)
        Task {
            await searchService.reindex(url: url)
        }
        autoTitleRenameIfNeeded(content: currentContent, url: url)
    }

    private func autoTitleRenameIfNeeded(content: String, url: URL) {
        guard autoTitleFromH1 else { return }

        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: "^#\\s+(.+)$", options: .regularExpression) != nil else { return }

        let titleStart = trimmed.index(trimmed.startIndex, offsetBy: trimmed.hasPrefix("# ") ? 2 : 0)
        var title = String(trimmed[titleStart...]).trimmingCharacters(in: .whitespaces)

        // Strip remaining Markdown
        title = title.replacingOccurrences(of: "\\*+", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "`", with: "")
        title = title.replacingOccurrences(of: "[\\[\\]]", with: "", options: .regularExpression)

        // Replace invalid filename chars
        let invalidChars = CharacterSet(charactersIn: ":/\\?*\"<>|")
        title = title.unicodeScalars.map { invalidChars.contains($0) ? "-" : String($0) }.joined()

        // Collapse whitespace/hyphens and trim
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return }

        // Truncate at word boundary, max 80 chars
        if title.count > 80 {
            title = String(title.prefix(80))
            if let lastSpace = title.lastIndex(of: " ") {
                title = String(title[..<lastSpace])
            }
        }

        let newFilename = "\(title).md"
        let currentFilename = url.lastPathComponent

        guard newFilename != currentFilename else { return }

        // Check for conflicts
        var targetURL = url.deletingLastPathComponent().appendingPathComponent(newFilename)
        if FileManager.default.fileExists(atPath: targetURL.path) && targetURL != url {
            var counter = 2
            while FileManager.default.fileExists(atPath: targetURL.path) {
                targetURL = url.deletingLastPathComponent().appendingPathComponent("\(title) \(counter).md")
                counter += 1
            }
        }

        // Perform rename
        do {
            try FileManager.default.moveItem(at: url, to: targetURL)
            selectedNoteURL = targetURL
            NoteMetadataService.shared.updatePath(from: url, to: targetURL)
            vaultManager.loadFileTree()
        } catch {
            Log.vault.error("Auto-title rename failed: \(error.localizedDescription)")
        }
    }

    func openNewTab() {
        guard let window = NSApp.keyWindow else { return }
        // Save current note before opening new tab
        if let currentURL = selectedNoteURL {
            autoSaveService.saveImmediately(content: currentContent, to: currentURL)
        }
        window.newWindowForTab(nil)
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
                // Post notification so the editor replaces via undo manager
                NotificationCenter.default.post(
                    name: .aiTextImproved,
                    object: nil,
                    userInfo: ["text": improved]
                )
                aiStatus = "AI improvement applied"
                isAIWorking = false
            } catch {
                aiStatus = error.localizedDescription
                isAIWorking = false
            }
        }
    }
}

// MARK: - App Group Sync

extension AppState {
    func syncVaultPathToAppGroup() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".notero")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pathFile = dir.appendingPathComponent("vault-path.txt")
        try? vaultManager.vaultURL.path.write(to: pathFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - Word Count Tracking

extension AppState {
    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func trackWordDelta(oldContent: String, newContent: String) {
        guard dailyGoalEnabled else { return }
        let oldCount = oldContent.split { $0.isWhitespace || $0.isNewline }.count
        let newCount = newContent.split { $0.isWhitespace || $0.isNewline }.count
        let delta = newCount - oldCount
        guard delta > 0 else { return }

        dailyWordsWritten += delta
        let key = "goal-\(Self.todayKey())"
        UserDefaults.standard.set(dailyWordsWritten, forKey: key)
    }
}

extension Notification.Name {
    static let aiTextImproved = Notification.Name("NoteroAITextImproved")
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
