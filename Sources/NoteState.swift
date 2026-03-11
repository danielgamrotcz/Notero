import SwiftUI
import Combine
import WebKit

enum ReMarkableDevice: String, CaseIterable {
    case paperPro = "paperPro"
    case paperProMove = "paperProMove"

    var displayName: String {
        switch self {
        case .paperPro: return "Paper Pro (10.3\")"
        case .paperProMove: return "Paper Pro Move (7.3\")"
        }
    }

    var pageWidth: CGFloat {
        switch self {
        case .paperPro: return 595
        case .paperProMove: return 260
        }
    }

    var pageHeight: CGFloat {
        switch self {
        case .paperPro: return 842
        case .paperProMove: return 463
        }
    }
}

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
    @Published var remarkableStatus: String = ""
    @Published var isSendingToReMarkable: Bool = false
    @Published var isNoteShared: Bool = false
    @Published var shareURL: String = ""
    @Published var shareStatus: String = ""

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
            ScrollPositionStore.shared.save(fraction: scrollFraction, for: currentURL, relativeTo: appState.vaultManager.vaultURL)
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

            scrollFraction = ScrollPositionStore.shared.fraction(for: url, relativeTo: appState.vaultManager.vaultURL)
            appState.linkResolver.findBacklinks(for: url)
            persistLastOpenedNote(url: url)
            pushToHistory(url: url)
            loadShareStatus()
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

        if let currentURL = selectedNoteURL {
            ScrollPositionStore.shared.save(fraction: scrollFraction, for: currentURL, relativeTo: appState.vaultManager.vaultURL)
        }

        currentContent = content
        selectedNoteURL = url

        let meta = NoteMetadataService.shared.metadata(for: url)
        currentNoteID = meta.id
        currentNoteCreated = meta.created
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        currentNoteModified = attrs?[.modificationDate] as? Date

        scrollFraction = ScrollPositionStore.shared.fraction(for: url, relativeTo: appState.vaultManager.vaultURL)

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

    // MARK: - Web Sharing

    private static let shareURLBase = "https://danielgamrotcz.github.io/notero-share/"

    func toggleSharing() {
        guard let appState = appState, let url = selectedNoteURL else { return }
        let path = SupabaseService.relativePath(for: url, vaultURL: appState.vaultManager.vaultURL)
        guard let config = appState.supabaseConfig else {
            shareStatus = "Supabase not configured"
            clearShareStatusAfterDelay()
            return
        }

        Task {
            if isNoteShared {
                let ok = await appState.supabaseService.unshareNote(path: path, config: config)
                if ok {
                    isNoteShared = false
                    shareURL = ""
                    shareStatus = "Sharing disabled"
                } else {
                    shareStatus = "Failed to disable sharing"
                }
            } else {
                if let shareId = await appState.supabaseService.shareNote(path: path, config: config) {
                    isNoteShared = true
                    shareURL = "\(Self.shareURLBase)?id=\(shareId)"
                    copyShareLink()
                    shareStatus = "Link copied"
                } else {
                    shareStatus = "Failed to share note"
                }
            }
            clearShareStatusAfterDelay()
        }
    }

    func copyShareLink() {
        guard !shareURL.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareURL, forType: .string)
    }

    func loadShareStatus() {
        guard let appState = appState, let url = selectedNoteURL else {
            isNoteShared = false
            shareURL = ""
            return
        }
        let path = SupabaseService.relativePath(for: url, vaultURL: appState.vaultManager.vaultURL)
        guard let config = appState.supabaseConfig else {
            isNoteShared = false
            shareURL = ""
            return
        }

        Task {
            let status = await appState.supabaseService.fetchShareStatus(path: path, config: config)
            isNoteShared = status.isShared
            if let shareId = status.shareId, status.isShared {
                shareURL = "\(Self.shareURLBase)?id=\(shareId)"
            } else {
                shareURL = ""
            }
        }
    }

    private func clearShareStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.shareStatus = ""
        }
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

    // MARK: - Send to reMarkable

    func sendToReMarkable() {
        guard let selectedURL = selectedNoteURL else { return }
        guard !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let deviceRaw = UserDefaults.standard.string(forKey: "remarkableDevice") ?? ReMarkableDevice.paperPro.rawValue
        let device = ReMarkableDevice(rawValue: deviceRaw) ?? .paperPro

        isSendingToReMarkable = true
        remarkableStatus = "Sending to reMarkable..."

        let noteName = selectedURL.deletingPathExtension().lastPathComponent
        let dateString = Date().formatted(.dateTime.month(.abbreviated).day().year())

        let paginationCSS = """
        h1, h2, h3, h4, h5, h6 {
            break-after: avoid;
            break-inside: avoid;
        }
        h1::after, h2::after, h3::after, h4::after, h5::after, h6::after {
            content: "";
            display: block;
            height: 8em;
            margin-bottom: -8em;
        }
        p:has(> strong:first-child) {
            break-after: avoid;
            break-inside: avoid;
        }
        p:has(> strong:first-child)::after {
            content: "";
            display: block;
            height: 4em;
            margin-bottom: -4em;
        }
        p + ul, p + ol { break-before: avoid; }
        li { break-inside: avoid; }
        pre, blockquote { break-inside: avoid; }
        p { orphans: 3; widows: 3; }
        table { break-inside: avoid; }
        hr { break-before: avoid; break-after: avoid; }
        *:has(+ hr) { break-after: avoid; }
        .notero-footer { break-before: avoid; }
        """

        let deviceCSS: String
        switch device {
        case .paperPro:
            deviceCSS = """
            body { background: white !important; color: black !important; max-width: none !important;
                padding: 0 !important; margin: 0 !important;
                font-family: -apple-system, 'Helvetica Neue', Helvetica, sans-serif;
                font-size: 16pt; line-height: 1.6; }
            code { font-size: 14pt; background: #f0f0f0; }
            pre { background: #f5f5f5; border: 1px solid #ddd; font-size: 13pt; }
            """
        case .paperProMove:
            deviceCSS = """
            body { background: white !important; color: black !important; max-width: none !important;
                padding: 0 !important; margin: 0 !important;
                font-family: -apple-system, 'Helvetica Neue', Helvetica, sans-serif;
                font-size: 15pt; line-height: 1.5; }
            code { font-size: 12pt; background: #f0f0f0; }
            pre { background: #f5f5f5; border: 1px solid #ddd; font-size: 11pt; }
            """
        }

        let einkCSS = """
        \(deviceCSS)
        \(paginationCSS)
        h1:first-child, h2:first-child, h3:first-child { margin-top: 0.3em; }
        blockquote { border-left: 3px solid #333; color: #333; }
        th { background: #e8e8e8; }
        a { color: #000; text-decoration: underline; }
        .notero-footer { margin-top: 2em; padding-top: 0.5em;
            border-top: 1px solid #ccc; font-size: 12pt; color: #666; text-align: center; }
        """

        let firstLine = currentContent.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        var titleHTML = ""
        if !firstLine.hasPrefix("# ") {
            titleHTML = "<h1>\(noteName)</h1>"
        }

        var html = MarkdownRenderer.renderHTML(from: currentContent)
        html = html.replacingOccurrences(of: "</style>", with: "\(einkCSS)</style>")
        html = html.replacingOccurrences(of: "<body>", with: "<body>\(titleHTML)")
        html = html.replacingOccurrences(of: "</body>",
            with: "<div class='notero-footer'>\(noteName) · Exported from Notero · \(dateString)</div></body>")

        let config = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: device.pageWidth, height: device.pageHeight),
            configuration: config
        )

        let sanitizedName = noteName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let uploader = ReMarkablePDFUploader(noteState: self, name: sanitizedName, device: device)
        uploader.webView = webView
        webView.navigationDelegate = uploader
        objc_setAssociatedObject(webView, "remarkableUploader", uploader, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Export

    func exportAsPDF() {
        guard let selectedURL = selectedNoteURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let defaultName = selectedURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = defaultName
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        let noteName = selectedURL.deletingPathExtension().lastPathComponent
        let dateString = Date().formatted(.dateTime.month(.abbreviated).day().year())

        let pdfCSS = """
        body { background: white !important; color: black !important; max-width: none !important; }
        @page { margin: 2.5cm; size: A4; }
        .pdf-footer { position: fixed; bottom: 0; left: 0; right: 0;
            text-align: center; font-size: 10px; color: #999; padding: 10px; }
        """

        let firstLine = currentContent.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        var titleHTML = ""
        if !firstLine.hasPrefix("# ") {
            titleHTML = "<h1>\(noteName)</h1>"
        }

        var html = MarkdownRenderer.renderHTML(from: currentContent)
        html = html.replacingOccurrences(of: "</style>", with: "\(pdfCSS)</style>")
        html = html.replacingOccurrences(of: "<body>", with: "<body>\(titleHTML)")
        html = html.replacingOccurrences(of: "</body>", with: "<div class='pdf-footer'>\(noteName) · Exported \(dateString)</div></body>")

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842), configuration: config)
        let exporter = PDFExporter(saveURL: saveURL)
        webView.navigationDelegate = exporter
        objc_setAssociatedObject(webView, "pdfExporter", exporter, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func exportAsDOCX() {
        guard let selectedURL = selectedNoteURL else { return }
        let noteName = selectedURL.deletingPathExtension().lastPathComponent

        let pandocAvailable = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/pandoc")
            || FileManager.default.fileExists(atPath: "/usr/local/bin/pandoc")

        if pandocAvailable {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "docx")!]
            panel.nameFieldStringValue = noteName
            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            let tempDir = FileManager.default.temporaryDirectory
            let tempMD = tempDir.appendingPathComponent("\(UUID().uuidString).md")
            try? currentContent.write(to: tempMD, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "pandoc \"\(tempMD.path)\" -o \"\(saveURL.path)\""]
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: tempMD)

            if process.terminationStatus == 0 {
                NSWorkspace.shared.open(saveURL)
            }
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.rtf]
            panel.nameFieldStringValue = noteName
            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            let attrString = NSAttributedString(string: currentContent, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            if let rtfData = attrString.rtf(from: NSRange(location: 0, length: attrString.length)) {
                try? rtfData.write(to: saveURL)
                NSWorkspace.shared.open(saveURL)
            }
        }
    }

    func exportAsHTML() {
        guard let selectedURL = selectedNoteURL else { return }
        let noteName = selectedURL.deletingPathExtension().lastPathComponent

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = noteName
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        let htmlContent = MarkdownRenderer.renderHTML(from: currentContent)
        let description = String(currentContent.prefix(160)).replacingOccurrences(of: "\n", with: " ")

        let fullHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="description" content="\(description)">
        <title>\(noteName)</title>
        <style>
        \(MarkdownRenderer.defaultCSS)
        </style>
        </head>
        <body>
        \(htmlContent)
        </body>
        </html>
        """

        do {
            try fullHTML.write(to: saveURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(saveURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "HTML Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func exportAsMarkdown() {
        guard let selectedURL = selectedNoteURL else { return }
        let noteName = selectedURL.deletingPathExtension().lastPathComponent

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(noteName).md"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        do {
            try currentContent.write(to: saveURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(saveURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Markdown Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
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

    // swiftlint:disable:next nesting
    private class PDFExporter: NSObject, WKNavigationDelegate {
        let saveURL: URL

        init(saveURL: URL) {
            self.saveURL = saveURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let config = WKPDFConfiguration()
            webView.createPDF(configuration: config) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: self.saveURL)
                        DispatchQueue.main.async {
                            NSWorkspace.shared.open(self.saveURL)
                        }
                    } catch {
                        Log.general.error("PDF write failed: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    Log.general.error("PDF export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // swiftlint:disable:next nesting
    private class ReMarkablePDFUploader: NSObject, WKNavigationDelegate {
        weak var noteState: NoteState?
        let name: String
        let device: ReMarkableDevice
        /// Strong ref to keep WKWebView alive until PDF generation completes.
        var webView: WKWebView?
        private var pdfURL: URL?
        private var hiddenWindow: NSWindow?

        init(noteState: NoteState, name: String, device: ReMarkableDevice) {
            self.noteState = noteState
            self.name = name
            self.device = device
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let printInfo = NSPrintInfo()
            printInfo.paperSize = NSSize(width: device.pageWidth, height: device.pageHeight)
            switch device {
            case .paperPro:
                printInfo.topMargin = 56.69
                printInfo.bottomMargin = 56.69
                printInfo.leftMargin = 51.02
                printInfo.rightMargin = 51.02
            case .paperProMove:
                printInfo.topMargin = 12
                printInfo.bottomMargin = 12
                printInfo.leftMargin = 14
                printInfo.rightMargin = 14
            }
            printInfo.isHorizontallyCentered = false
            printInfo.isVerticallyCentered = false

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".pdf")
            self.pdfURL = url
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

            let printOp = webView.printOperation(with: printInfo)
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = false

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [], backing: .buffered, defer: true
            )
            window.orderOut(nil)
            self.hiddenWindow = window

            printOp.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }

        @objc func printOperationDidRun(
            _ op: NSPrintOperation,
            success: Bool,
            contextInfo: UnsafeMutableRawPointer?
        ) {
            hiddenWindow = nil
            webView = nil

            guard success, let pdfURL = pdfURL,
                  let data = try? Data(contentsOf: pdfURL) else {
                self.pdfURL = nil
                DispatchQueue.main.async {
                    self.noteState?.isSendingToReMarkable = false
                    self.noteState?.remarkableStatus = "PDF generation failed"
                    self.clearStatusAfterDelay()
                }
                return
            }

            try? FileManager.default.removeItem(at: pdfURL)
            self.pdfURL = nil
            uploadPDF(data: data)
        }

        private func uploadPDF(data: Data) {
            let tempDir = FileManager.default.temporaryDirectory
            let pdfPath = tempDir.appendingPathComponent("\(name).pdf")

            do {
                try data.write(to: pdfPath)
            } catch {
                DispatchQueue.main.async {
                    self.noteState?.isSendingToReMarkable = false
                    self.noteState?.remarkableStatus = "Failed to write PDF"
                    self.clearStatusAfterDelay()
                }
                return
            }

            Task {
                do {
                    try await ReMarkableService.shared.uploadPDF(at: pdfPath, name: name)
                    try? FileManager.default.removeItem(at: pdfPath)
                    await MainActor.run {
                        self.noteState?.isSendingToReMarkable = false
                        self.noteState?.remarkableStatus = "Sent to reMarkable"
                        self.clearStatusAfterDelay()
                    }
                } catch {
                    try? FileManager.default.removeItem(at: pdfPath)
                    await MainActor.run {
                        self.noteState?.isSendingToReMarkable = false
                        self.noteState?.remarkableStatus = error.localizedDescription
                        self.clearStatusAfterDelay()
                    }
                }
            }
        }

        private func clearStatusAfterDelay() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.noteState?.remarkableStatus = ""
            }
        }
    }

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
            let oldName = url.deletingPathExtension().lastPathComponent
            let newName = targetURL.deletingPathExtension().lastPathComponent
            appState.linkResolver.updateWikilinks(
                oldName: oldName, newName: newName, excludingNoteAt: targetURL
            )
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
