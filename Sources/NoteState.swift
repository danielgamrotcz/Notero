import SwiftUI
import Combine

@MainActor
final class NoteState: ObservableObject {
    @Published var selectedNoteURL: URL?
    @Published var selectedNoteURLs: Set<URL> = []
    @Published var currentContent: String = ""
    @Published var currentNoteID: String?
    @Published var currentNoteCreated: Date?
    @Published var currentNoteModified: Date?
    @Published var isPreviewMode: Bool = false
    @Published var isEditing: Bool = false
    @Published var pendingSearchHighlight: String?
    @Published var aiStatus: String = ""
    @Published var isAIWorking: Bool = false

    /// Proportional scroll position (0.0–1.0) shared between editor and preview.
    /// Not @Published to avoid triggering SwiftUI re-renders on every scroll event.
    var scrollFraction: CGFloat = 0

    // MARK: - Navigation History
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false

    private var navigationHistory: [URL] = []
    private var navigationIndex: Int = -1
    private let maxHistorySize = 20
    private var isNavigatingHistory = false

    private(set) weak var appState: AppState?

    func configure(appState: AppState) {
        guard self.appState == nil else { return }
        self.appState = appState
        appState.registerNoteState(self)
    }

    // MARK: - Note Operations

    func openNote(url: URL) {
        guard let appState = appState else { return }

        if let currentURL = selectedNoteURL {
            appState.autoSaveService.saveImmediately(content: currentContent, to: currentURL)
        }

        if let content = appState.vaultManager.readNote(at: url) {
            currentContent = content
            selectedNoteURL = url
            selectedNoteURLs = [url]

            let meta = NoteMetadataService.shared.metadata(for: url)
            currentNoteID = meta.id
            currentNoteCreated = meta.created
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            currentNoteModified = attrs?[.modificationDate] as? Date

            let modeKey = "mode-\(url.lastPathComponent)"
            isPreviewMode = UserDefaults.standard.bool(forKey: modeKey)

            scrollFraction = 0
            appState.linkResolver.findBacklinks(for: url)
            persistLastOpenedNote(url: url)
            pushToHistory(url: url)
        }
    }

    func toggleNoteInSelection(_ url: URL) {
        guard let appState = appState else { return }

        if let currentURL = selectedNoteURL {
            appState.autoSaveService.saveImmediately(content: currentContent, to: currentURL)
        }

        if selectedNoteURLs.contains(url) {
            selectedNoteURLs.remove(url)
            if selectedNoteURL == url {
                if let next = selectedNoteURLs.first {
                    loadNoteContent(next)
                } else {
                    selectedNoteURL = nil
                    currentContent = ""
                    currentNoteID = nil
                    currentNoteCreated = nil
                    currentNoteModified = nil
                }
            }
        } else {
            selectedNoteURLs.insert(url)
            loadNoteContent(url)
        }
    }

    func extendSelection(to url: URL, visibleURLs: [URL]) {
        guard let appState = appState else { return }

        if let currentURL = selectedNoteURL {
            appState.autoSaveService.saveImmediately(content: currentContent, to: currentURL)
        }

        let anchor = selectedNoteURL ?? url
        guard let anchorIndex = visibleURLs.firstIndex(of: anchor),
              let targetIndex = visibleURLs.firstIndex(of: url) else {
            openNote(url: url)
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedNoteURLs = Set(visibleURLs[range])
        loadNoteContent(url)
    }

    private func loadNoteContent(_ url: URL) {
        guard let appState = appState,
              let content = appState.vaultManager.readNote(at: url) else { return }

        currentContent = content
        selectedNoteURL = url

        let meta = NoteMetadataService.shared.metadata(for: url)
        currentNoteID = meta.id
        currentNoteCreated = meta.created
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        currentNoteModified = attrs?[.modificationDate] as? Date

        scrollFraction = 0

        let modeKey = "mode-\(url.lastPathComponent)"
        isPreviewMode = UserDefaults.standard.bool(forKey: modeKey)

        appState.linkResolver.findBacklinks(for: url)
        persistLastOpenedNote(url: url)
    }

    func createNewNote(in folderURL: URL? = nil) {
        guard let appState = appState else { return }
        if let url = appState.vaultManager.createNote(named: appState.defaultNoteName, in: folderURL) {
            _ = NoteMetadataService.shared.ensureID(for: url)
            openNote(url: url)
            Task {
                await appState.searchService.reindex(url: url)
            }
        }
    }

    func saveCurrentNote() {
        guard let appState = appState, let url = selectedNoteURL else { return }
        appState.autoSaveService.saveImmediately(content: currentContent, to: url)
        NoteHistoryService.shared.saveSnapshot(content: currentContent, for: url)
        Task {
            await appState.searchService.reindex(url: url)
        }
        autoTitleRenameIfNeeded(content: currentContent, url: url)
    }

    func togglePreview() {
        isPreviewMode.toggle()
        if let url = selectedNoteURL {
            UserDefaults.standard.set(isPreviewMode, forKey: "mode-\(url.lastPathComponent)")
        }
    }

    // MARK: - Navigation History

    func navigateBack() {
        guard canGoBack else { return }
        var targetIndex = navigationIndex - 1
        while targetIndex >= 0 {
            let url = navigationHistory[targetIndex]
            if FileManager.default.fileExists(atPath: url.path) {
                navigationIndex = targetIndex
                isNavigatingHistory = true
                openNote(url: url)
                isNavigatingHistory = false
                updateNavigationFlags()
                return
            }
            navigationHistory.remove(at: targetIndex)
            targetIndex -= 1
            navigationIndex -= 1
        }
        updateNavigationFlags()
    }

    func navigateForward() {
        guard canGoForward else { return }
        var targetIndex = navigationIndex + 1
        while targetIndex < navigationHistory.count {
            let url = navigationHistory[targetIndex]
            if FileManager.default.fileExists(atPath: url.path) {
                navigationIndex = targetIndex
                isNavigatingHistory = true
                openNote(url: url)
                isNavigatingHistory = false
                updateNavigationFlags()
                return
            }
            navigationHistory.remove(at: targetIndex)
        }
        updateNavigationFlags()
    }

    private func pushToHistory(url: URL) {
        guard !isNavigatingHistory else { return }

        if navigationIndex >= 0 && navigationIndex < navigationHistory.count
            && navigationHistory[navigationIndex] == url {
            return
        }

        // Trim forward history (browser behavior)
        if navigationIndex + 1 < navigationHistory.count {
            navigationHistory.removeSubrange((navigationIndex + 1)...)
        }

        navigationHistory.append(url)

        // Enforce max size
        if navigationHistory.count > maxHistorySize {
            navigationHistory.removeFirst()
        }

        navigationIndex = navigationHistory.count - 1
        updateNavigationFlags()
    }

    private func updateNavigationFlags() {
        canGoBack = navigationIndex > 0
        canGoForward = navigationIndex < navigationHistory.count - 1
    }

    func updateHistoryURL(from oldURL: URL, to newURL: URL) {
        for i in navigationHistory.indices where navigationHistory[i] == oldURL {
            navigationHistory[i] = newURL
        }
    }

    // MARK: - Last Opened Note Persistence

    private func persistLastOpenedNote(url: URL) {
        guard let vaultPath = appState?.vaultManager.vaultURL.path else { return }
        let relativePath = url.path.replacingOccurrences(of: vaultPath + "/", with: "")
        UserDefaults.standard.set(relativePath, forKey: "lastOpenedNote")
    }

    func clearLastOpenedNote() {
        UserDefaults.standard.removeObject(forKey: "lastOpenedNote")
    }

    func restoreLastOpenedNote() {
        guard let appState = appState,
              let relativePath = UserDefaults.standard.string(forKey: "lastOpenedNote") else { return }
        let url = appState.vaultManager.vaultURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            clearLastOpenedNote()
            return
        }
        openNote(url: url)
    }

    // MARK: - AI

    func improveWithClaude() {
        guard let appState = appState else { return }
        guard let apiKey = KeychainManager.load(key: "NoteroAnthropicKey"), !apiKey.isEmpty else {
            aiStatus = "No API key set. Go to Settings → AI."
            return
        }
        improveText(using: .claude(apiKey: apiKey, model: appState.claudeModel))
    }

    func improveWithOllama() {
        guard let appState = appState else { return }
        improveText(using: .ollama(serverURL: appState.ollamaServerURL, model: appState.ollamaModel))
    }

    private enum AIProvider {
        case claude(apiKey: String, model: String)
        case ollama(serverURL: String, model: String)
    }

    private func improveText(using provider: AIProvider) {
        guard let appState = appState, !currentContent.isEmpty else { return }

        isAIWorking = true
        aiStatus = "AI improving..."

        let textToImprove = currentContent
        let prompt = appState.aiPrompt

        Task {
            do {
                let improved: String
                switch provider {
                case .claude(let apiKey, let model):
                    improved = try await appState.anthropicService.improve(
                        text: textToImprove, model: model,
                        apiKey: apiKey, prompt: prompt
                    )
                case .ollama(let serverURL, let model):
                    improved = try await appState.ollamaService.improve(
                        text: textToImprove, model: model,
                        serverURL: serverURL, prompt: prompt
                    )
                }
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

    // MARK: - Auto-Save Callback

    func handleAutoSaveCompletion(content: String, url: URL) {
        guard url == selectedNoteURL else { return }
        isEditing = false
        currentNoteModified = Date()
        autoTitleRenameIfNeeded(content: content, url: url)
    }

    // MARK: - Auto Title

    private func autoTitleRenameIfNeeded(content: String, url: URL) {
        guard let appState = appState, appState.autoTitleFromH1 else { return }

        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: "^#\\s+(.+)$", options: .regularExpression) != nil else { return }

        let titleStart = trimmed.index(trimmed.startIndex, offsetBy: trimmed.hasPrefix("# ") ? 2 : 0)
        var title = String(trimmed[titleStart...]).trimmingCharacters(in: .whitespaces)

        title = title.replacingOccurrences(of: "\\*+", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "`", with: "")
        title = title.replacingOccurrences(of: "[\\[\\]]", with: "", options: .regularExpression)

        let invalidChars = CharacterSet(charactersIn: ":/\\?*\"<>|")
        title = title.unicodeScalars.map { invalidChars.contains($0) ? "-" : String($0) }.joined()

        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return }

        if title.count > 80 {
            title = String(title.prefix(80))
            if let lastSpace = title.lastIndex(of: " ") {
                title = String(title[..<lastSpace])
            }
        }

        let newFilename = "\(title).md"
        let currentFilename = url.lastPathComponent

        guard newFilename != currentFilename else { return }

        var targetURL = url.deletingLastPathComponent().appendingPathComponent(newFilename)
        if FileManager.default.fileExists(atPath: targetURL.path) && targetURL != url {
            var counter = 2
            while FileManager.default.fileExists(atPath: targetURL.path) {
                targetURL = url.deletingLastPathComponent().appendingPathComponent("\(title) \(counter).md")
                counter += 1
            }
        }

        do {
            try FileManager.default.moveItem(at: url, to: targetURL)
            selectedNoteURL = targetURL
            if selectedNoteURLs.contains(url) {
                selectedNoteURLs.remove(url)
                selectedNoteURLs.insert(targetURL)
            }
            updateHistoryURL(from: url, to: targetURL)
            NoteMetadataService.shared.updatePath(from: url, to: targetURL)
            appState.vaultManager.loadFileTree()
        } catch {
            Log.vault.error("Auto-title rename failed: \(error.localizedDescription)")
        }
    }
}
