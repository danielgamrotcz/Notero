import SwiftUI
import Sparkle
import WebKit

@main
struct NoteroApp: App {
    @StateObject private var appState = AppState()
    @FocusedObject private var noteState: NoteState?
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .commands {
            // App menu
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates(nil)
                }
            }

            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    noteState?.createNewNote(in: appState.focusedFolderURL)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Folder") {
                    appState.createNewFolder(in: appState.focusedFolderURL)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Open...") {
                    appState.showQuickOpen = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Vault in Finder") {
                    appState.vaultManager.revealInFinder(url: appState.vaultManager.vaultURL)
                }

                Button("Change Vault Location...") {
                    changeVaultLocation()
                }

                Divider()

                Button("Add to Favorites") {
                    toggleFavorite()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Rename") {
                    // Handled in sidebar
                }
                .keyboardShortcut(KeyEquivalent.init(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: [])

                Button("Move to Trash") {
                    if let url = noteState?.selectedNoteURL {
                        appState.vaultManager.moveToTrash(url: url)
                        noteState?.selectedNoteURL = nil
                        noteState?.currentContent = ""
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Note History...") {
                    appState.showNoteHistory = true
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])

                Divider()

                Button("Export as PDF") {
                    exportAsPDF()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as DOCX") {
                    exportAsDOCX()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Export as HTML") {
                    exportAsHTML()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Copy as HTML") {
                    let html = MarkdownRenderer.renderHTML(from: noteState?.currentContent ?? "")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(html, forType: .string)
                }
            }

            // Edit menu additions
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    appState.showFindReplaceWithReplace = false
                    appState.showFindReplace = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace...") {
                    appState.showFindReplaceWithReplace = true
                    appState.showFindReplace = true
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("Bold") {
                    insertMarkdown("**", "**")
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    insertMarkdown("*", "*")
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Insert Link") {
                    insertMarkdown("[", "](url)")
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Insert Code Block") {
                    insertMarkdown("```\n", "\n```")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Insert Heading 1") {
                    insertLinePrefix("# ")
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Insert Heading 2") {
                    insertLinePrefix("## ")
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Insert Heading 3") {
                    insertLinePrefix("### ")
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Insert Task") {
                    insertLinePrefix("- [ ] ")
                }
                .keyboardShortcut(.return, modifiers: .command)
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    appState.showSidebar.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Toggle Preview") {
                    noteState?.togglePreview()
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Toggle Backlinks") {
                    appState.showBacklinks.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Toggle Line Numbers") {
                    appState.showLineNumbers.toggle()
                }

                Button("Refresh Vault") {
                    appState.vaultManager.loadFileTree()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Increase Font Size") {
                    appState.fontSize = min(20, appState.fontSize + 1)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    appState.fontSize = max(12, appState.fontSize - 1)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    appState.fontSize = 14
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Command Palette") {
                    appState.showCommandPalette = true
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Graph View") {
                    openGraphView()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Vault Statistics") {
                    openVaultStatistics()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Search Notes") {
                    appState.focusSidebarSearch = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates(nil)
                }
            }

            // Save
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    noteState?.saveCurrentNote()
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            // AI menu
            CommandMenu("AI") {
                Button("Improve with Claude") {
                    noteState?.improveWithClaude()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Button("Improve with Local AI") {
                    noteState?.improveWithOllama()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                SettingsLink {
                    Text("AI Settings...")
                }
            }
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView(updater: updaterController.updater)
                .environmentObject(appState)
        }
    }

    private func changeVaultLocation() {
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

    private func exportAsPDF() {
        guard let selectedURL = noteState?.selectedNoteURL else { return }
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

        let content = noteState?.currentContent ?? ""
        let firstLine = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        var titleHTML = ""
        if !firstLine.hasPrefix("# ") {
            titleHTML = "<h1>\(noteName)</h1>"
        }

        var html = MarkdownRenderer.renderHTML(from: content)
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

    private func exportAsDOCX() {
        guard let selectedURL = noteState?.selectedNoteURL else { return }
        let noteName = selectedURL.deletingPathExtension().lastPathComponent

        // Check for pandoc
        let pandocAvailable = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/pandoc")
            || FileManager.default.fileExists(atPath: "/usr/local/bin/pandoc")

        let currentContent = noteState?.currentContent ?? ""

        if pandocAvailable {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "docx")!]
            panel.nameFieldStringValue = noteName
            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            // Write temp markdown file
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
            // RTF fallback
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

    private func exportAsHTML() {
        guard let selectedURL = noteState?.selectedNoteURL else { return }
        let noteName = selectedURL.deletingPathExtension().lastPathComponent

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = noteName
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        let content = noteState?.currentContent ?? ""
        let htmlContent = MarkdownRenderer.renderHTML(from: content)
        let description = String(content.prefix(160)).replacingOccurrences(of: "\n", with: " ")

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

    private func openGraphView() {
        let graphView = GraphView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: graphView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Graph View"
        window.setContentSize(NSSize(width: 900, height: 600))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openVaultStatistics() {
        let statsView = VaultStatisticsView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: statsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Vault Statistics"
        window.setContentSize(NSSize(width: 900, height: 650))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func toggleFavorite() {
        guard let url = noteState?.selectedNoteURL else { return }
        let path = appState.favoritesManager.relativePath(
            for: url, vaultURL: appState.vaultManager.vaultURL
        )
        appState.favoritesManager.toggleFavorite(path)
    }

    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        noteState?.currentContent += prefix + suffix
    }

    private func insertLinePrefix(_ prefix: String) {
        if let content = noteState?.currentContent {
            noteState?.currentContent = prefix + content
        }
    }

    // MARK: - URL Scheme

    private func handleURL(_ url: URL) {
        guard url.scheme == "notero" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems?.reduce(into: [String: String]()) { dict, item in
            dict[item.name] = item.value
        } ?? [:]

        switch url.host {
        case "open":
            if let id = params["id"] {
                openNoteByID(id)
            } else if let name = params["name"] {
                openNoteByName(name)
            }
        case "new":
            let title = params["title"] ?? appState.defaultNoteName
            let content = params["content"] ?? ""
            createNoteFromURL(title: title, content: content)
        case "search":
            if let query = params["q"] {
                appState.showQuickOpen = true
                Task {
                    await appState.searchService.search(query: query)
                }
            }
        default:
            break
        }
    }

    private func openNoteByID(_ id: String) {
        let files = appState.vaultManager.allMarkdownFiles()
        for file in files {
            let meta = NoteMetadataService.shared.metadata(for: file)
            if meta.id == id {
                appState.openNoteInActiveWindow(url: file)
                return
            }
        }
        showNoteNotFoundAlert(identifier: id)
    }

    private func openNoteByName(_ name: String) {
        let nameLower = name.lowercased()
        let files = appState.vaultManager.allMarkdownFiles()

        // Exact match
        if let exact = files.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased() == nameLower
        }) {
            appState.openNoteInActiveWindow(url: exact)
            return
        }

        // Fuzzy match
        if let fuzzy = files.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased().contains(nameLower)
        }) {
            appState.openNoteInActiveWindow(url: fuzzy)
            return
        }

        showNoteNotFoundAlert(identifier: name)
    }

    private func createNoteFromURL(title: String, content: String) {
        let sanitized = title.replacingOccurrences(of: "[:/\\\\?*\"<>|]", with: "-", options: .regularExpression)
        var fileURL = appState.vaultManager.vaultURL.appendingPathComponent("\(sanitized).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = appState.vaultManager.vaultURL.appendingPathComponent("\(sanitized) \(counter).md")
            counter += 1
        }
        let noteContent = content.isEmpty ? "# \(title)\n" : "# \(title)\n\n\(content)"
        try? noteContent.write(to: fileURL, atomically: true, encoding: .utf8)
        _ = NoteMetadataService.shared.ensureID(for: fileURL)
        appState.vaultManager.loadFileTree()
        appState.openNoteInActiveWindow(url: fileURL)
    }

    private func showNoteNotFoundAlert(identifier: String) {
        let alert = NSAlert()
        alert.messageText = "Note not found"
        alert.informativeText = "Could not find a note matching '\(identifier)'."
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - PDF Exporter

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
