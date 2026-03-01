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
    let supabaseService = SupabaseService()
    let syncManager: SyncManager

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
    @Published var favoritesExpandedFolders: Set<URL> = []
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

        self.syncManager = SyncManager(supabaseService: supabaseService)

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

        // Restore persisted expanded folders
        let vaultURL = vault.vaultURL
        if let paths = defaults.stringArray(forKey: "expandedFolderPaths") {
            self.expandedFolders = Set(paths.map { vaultURL.appendingPathComponent($0) })
        }
        if let paths = defaults.stringArray(forKey: "favoritesExpandedFolderPaths") {
            self.favoritesExpandedFolders = Set(paths.map { vaultURL.appendingPathComponent($0) })
        }

        favoritesManager.vaultURL = vault.vaultURL

        setupSettingsSync()
        syncVaultPathToAppGroup()

        // Dispatch auto-save completion to the correct per-window NoteState
        autoSaveService.onDidSave = { [weak self] content, url in
            guard let self = self else { return }
            for noteState in self.noteStates.allObjects {
                noteState.handleAutoSaveCompletion(content: content, url: url)
            }
        }

        setupSupabaseCallbacks()

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

        startSyncPolling()
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

        $expandedFolders.dropFirst().sink { [weak self] folders in
            guard let vaultPath = self?.vaultManager.vaultURL.path else { return }
            let paths = folders.map { $0.path.replacingOccurrences(of: vaultPath + "/", with: "") }
            UserDefaults.standard.set(paths, forKey: "expandedFolderPaths")
        }.store(in: &cancellables)

        $favoritesExpandedFolders.dropFirst().sink { [weak self] folders in
            guard let vaultPath = self?.vaultManager.vaultURL.path else { return }
            let paths = folders.map { $0.path.replacingOccurrences(of: vaultPath + "/", with: "") }
            UserDefaults.standard.set(paths, forKey: "favoritesExpandedFolderPaths")
        }.store(in: &cancellables)
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

    func moveItems(_ urls: [URL], to folderURL: URL) {
        for url in urls {
            guard let newURL = vaultManager.moveItem(from: url, to: folderURL) else { continue }
            for noteState in noteStates.allObjects {
                if noteState.selectedNoteURL == url {
                    noteState.selectedNoteURL = newURL
                }
                if noteState.selectedNoteURLs.contains(url) {
                    noteState.selectedNoteURLs.remove(url)
                    noteState.selectedNoteURLs.insert(newURL)
                }
                noteState.updateHistoryURL(from: url, to: newURL)
            }
            NoteMetadataService.shared.updatePath(from: url, to: newURL)

            let oldRelative = favoritesManager.relativePath(for: url, vaultURL: vaultManager.vaultURL)
            if favoritesManager.isFavorite(oldRelative) {
                let newRelative = favoritesManager.relativePath(for: newURL, vaultURL: vaultManager.vaultURL)
                favoritesManager.removeFavorite(oldRelative)
                favoritesManager.addFavorite(newRelative)
            }
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
                noteState.updateHistoryURL(from: url, to: newURL)
            }
        }
        renamingIsNew = false
        renamingItemURL = nil
    }
}

// MARK: - Supabase Sync

extension AppState {
    var supabaseConfig: SupabaseService.Config? {
        guard let url = KeychainManager.load(key: "NoteroSupabaseURL"),
              let key = KeychainManager.load(key: "NoteroSupabaseKey"),
              let uid = KeychainManager.load(key: "NoteroSupabaseUserID") else {
            return nil
        }
        let config = SupabaseService.Config(url: url, serviceKey: key, userId: uid)
        return config.isValid ? config : nil
    }

    func setupSupabaseCallbacks() {
        let supabase = supabaseService
        let vault = vaultManager
        let favs = favoritesManager
        let sync = syncManager

        // Sync note after auto-save (with pull guard)
        let existingOnDidSave = autoSaveService.onDidSave
        autoSaveService.onDidSave = { [weak self] content, url in
            existingOnDidSave?(content, url)
            guard let self, let config = self.supabaseConfig else { return }
            let vaultURL = vault.vaultURL
            Task.detached {
                if await sync.shouldSuppressPush(for: url, vaultURL: vaultURL) {
                    Log.sync.debug("Suppressed push for recently pulled: \(url.lastPathComponent)")
                    return
                }
                let path = SupabaseService.relativePath(for: url, vaultURL: vaultURL)
                let title = SupabaseService.extractTitle(from: content, filename: url.lastPathComponent)
                await supabase.syncNote(path: path, title: title, content: content, config: config)
            }
        }

        // Note created (with pull guard)
        vault.onNoteCreated = { [weak self] url in
            guard let self, let config = self.supabaseConfig else { return }
            let vaultURL = vault.vaultURL
            let content = vault.readNote(at: url) ?? ""
            Task.detached {
                if await sync.shouldSuppressPush(for: url, vaultURL: vaultURL) {
                    Log.sync.debug("Suppressed push for recently pulled new note: \(url.lastPathComponent)")
                    return
                }
                let path = SupabaseService.relativePath(for: url, vaultURL: vaultURL)
                let title = SupabaseService.extractTitle(from: content, filename: url.lastPathComponent)
                await supabase.syncNote(path: path, title: title, content: content, config: config)
            }
        }

        // Item renamed
        vault.onItemRenamed = { [weak self] oldURL, newURL in
            guard let self, let config = self.supabaseConfig else { return }
            let isDir = (try? newURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let oldPath = SupabaseService.relativePath(for: oldURL, vaultURL: vault.vaultURL)
                let newPath = SupabaseService.relativePath(for: newURL, vaultURL: vault.vaultURL)
                Task.detached {
                    await supabase.deleteFolder(path: oldPath, config: config)
                    await supabase.syncFolder(path: newPath, parentPath: nil, config: config)
                }
            } else {
                let oldPath = SupabaseService.relativePath(for: oldURL, vaultURL: vault.vaultURL)
                let newPath = SupabaseService.relativePath(for: newURL, vaultURL: vault.vaultURL)
                Task.detached { await supabase.renameNote(oldPath: oldPath, newPath: newPath, config: config) }
            }
        }

        // Item moved
        vault.onItemMoved = { [weak self] oldURL, newURL in
            guard let self, let config = self.supabaseConfig else { return }
            let isDir = (try? newURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let oldPath = SupabaseService.relativePath(for: oldURL, vaultURL: vault.vaultURL)
                let newPath = SupabaseService.relativePath(for: newURL, vaultURL: vault.vaultURL)
                Task.detached {
                    await supabase.deleteFolder(path: oldPath, config: config)
                    await supabase.syncFolder(path: newPath, parentPath: nil, config: config)
                }
            } else {
                let oldPath = SupabaseService.relativePath(for: oldURL, vaultURL: vault.vaultURL)
                let newPath = SupabaseService.relativePath(for: newURL, vaultURL: vault.vaultURL)
                Task.detached { await supabase.renameNote(oldPath: oldPath, newPath: newPath, config: config) }
            }
        }

        // Item deleted
        vault.onItemDeleted = { [weak self] url in
            guard let self, let config = self.supabaseConfig else { return }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let path = SupabaseService.relativePath(for: url, vaultURL: vault.vaultURL)
            if isDir {
                Task.detached { await supabase.deleteFolder(path: path, config: config) }
            } else {
                Task.detached { await supabase.deleteNote(path: path, config: config) }
            }
        }

        // Folder created
        vault.onFolderCreated = { [weak self] url in
            guard let self, let config = self.supabaseConfig else { return }
            let path = SupabaseService.relativePath(for: url, vaultURL: vault.vaultURL)
            Task.detached { await supabase.syncFolder(path: path, parentPath: nil, config: config) }
        }

        // Favourites changed
        favs.onFavouritesChanged = { [weak self] paths in
            guard let self, let config = self.supabaseConfig else { return }
            Task.detached { await supabase.syncFavourites(paths: paths, config: config) }
        }
    }

    func startSyncPolling() {
        let vault = vaultManager
        let search = searchService
        let favs = favoritesManager
        let noteStatesTable = noteStates

        Task {
            await syncManager.startPolling(
                configProvider: { [weak self] in
                    await MainActor.run { self?.supabaseConfig }
                },
                vaultURLProvider: { [weak self] in
                    await MainActor.run { self?.vaultManager.vaultURL ?? URL(fileURLWithPath: NSHomeDirectory()) }
                },
                onPullComplete: { [weak self] favPaths in
                    await MainActor.run {
                        guard let self else { return }
                        vault.loadFileTree(sortOrder: self.sortOrder)
                        Task { await search.buildIndex() }

                        if let favPaths {
                            favs.replaceFromRemote(favPaths)
                        }

                        // Refresh open editors if their file was updated
                        for noteState in noteStatesTable.allObjects {
                            guard let url = noteState.selectedNoteURL,
                                  !noteState.isEditing,
                                  let diskContent = vault.readNote(at: url),
                                  diskContent != noteState.currentContent else { continue }
                            noteState.currentContent = diskContent
                        }
                    }
                }
            )
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
    static let insertMarkdownFormat = Notification.Name("NoteroInsertMarkdownFormat")
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
