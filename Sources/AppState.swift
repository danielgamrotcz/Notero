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

    // Per-window NoteState registry
    private var noteStates = NSHashTable<NoteState>.weakObjects()

    // UI State
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @Published var showBacklinks: Bool = false
    @Published var showCommandPalette: Bool = false
    @Published var showQuickOpen: Bool = false
    @Published var showFindReplace: Bool = false
    @Published var showFindReplaceWithReplace: Bool = false
    @Published var showNoteHistory: Bool = false
    @Published var showLineNumbers: Bool = false
    @Published var fontSize: CGFloat = 14
    @Published var renamingItemURL: URL?
    @Published var renamingIsNew: Bool = false
    @Published var focusedFolderURL: URL?
    @Published var expandedFolders: Set<URL> = []
    @Published var focusSidebarSearch = false

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

        // Dispatch auto-save completion to the correct per-window NoteState
        autoSaveService.onDidSave = { [weak self] content, url in
            guard let self = self else { return }
            for noteState in self.noteStates.allObjects {
                noteState.handleAutoSaveCompletion(content: content, url: url)
            }
        }

        vaultManager.onFileSystemChange = { [weak self] in
            guard let self = self else { return }
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.searchService.buildIndex()
            }
        }

        Task {
            await searchService.buildIndex()
        }
    }

    func registerNoteState(_ noteState: NoteState) {
        noteStates.add(noteState)
    }

    /// Convenience for auxiliary windows (graph, URL scheme) that don't have their own NoteState
    func openNoteInActiveWindow(url: URL) {
        noteStates.allObjects.first?.openNote(url: url)
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

    // MARK: - Folder Operations

    func createNewFolder(in folderURL: URL? = nil) {
        let parent = folderURL ?? vaultManager.vaultURL
        var name = "New Folder"
        var counter = 1
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            counter += 1
            name = "New Folder \(counter)"
        }
        if let url = vaultManager.createFolder(named: name, in: folderURL) {
            expandAncestors(of: parent)
            // Delay rename to allow tree re-render after objectWillChange Combine hop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.renamingIsNew = true
                self?.renamingItemURL = url
            }
        }
    }

    private func expandAncestors(of url: URL) {
        let vaultPath = vaultManager.vaultURL.standardizedFileURL.path
        var current = url.standardizedFileURL
        while current.path != vaultPath && current.path != "/" {
            expandedFolders.insert(current)
            current = current.deletingLastPathComponent()
        }
    }

    func commitRename(url: URL, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renamingItemURL = nil
            return
        }
        if let newURL = vaultManager.renameItem(at: url, to: trimmed) {
            // Update selection in matching NoteState
            for noteState in noteStates.allObjects {
                if noteState.selectedNoteURL == url {
                    noteState.selectedNoteURL = newURL
                }
                if noteState.selectedNoteURLs.contains(url) {
                    noteState.selectedNoteURLs.remove(url)
                    noteState.selectedNoteURLs.insert(newURL)
                }
            }
        }
        renamingIsNew = false
        renamingItemURL = nil
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
