import SwiftUI
import WebKit

@main
struct NoteroApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = true
                }
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    appState.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Folder") {
                    _ = appState.vaultManager.createFolder(named: "New Folder")
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

                Button("Pin Note") {
                    togglePin()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

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
                    if let url = appState.selectedNoteURL {
                        appState.vaultManager.moveToTrash(url: url)
                        appState.selectedNoteURL = nil
                        appState.currentContent = ""
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Export as PDF") {
                    exportAsPDF()
                }

                Button("Copy as HTML") {
                    let html = MarkdownRenderer.renderHTML(from: appState.currentContent)
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
                .keyboardShortcut("t", modifiers: .command)
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    appState.showSidebar.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Toggle Preview") {
                    appState.togglePreview()
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
            }

            // Save
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveCurrentNote()
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            // AI menu
            CommandMenu("AI") {
                Button("Improve with Claude") {
                    appState.improveWithClaude()
                }
                .keyboardShortcut("a", modifiers: .option)

                Button("Improve with Local AI") {
                    appState.improveWithOllama()
                }
                .keyboardShortcut("l", modifiers: .option)

                Divider()

                SettingsLink {
                    Text("AI Settings...")
                }
            }
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
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
        guard appState.selectedNoteURL != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let defaultName = appState.selectedNoteURL?.deletingPathExtension().lastPathComponent ?? "note"
        panel.nameFieldStringValue = defaultName
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        let noteName = appState.selectedNoteURL?.deletingPathExtension().lastPathComponent ?? "Note"
        let dateString = Date().formatted(.dateTime.month(.abbreviated).day().year())

        let pdfCSS = """
        body { background: white !important; color: black !important; max-width: none !important; }
        @page { margin: 2.5cm; size: A4; }
        .pdf-footer { position: fixed; bottom: 0; left: 0; right: 0;
            text-align: center; font-size: 10px; color: #999; padding: 10px; }
        """

        var content = appState.currentContent
        let firstLine = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        var titleHTML = ""
        if !firstLine.hasPrefix("# ") {
            titleHTML = "<h1>\(noteName)</h1>"
        }

        var html = MarkdownRenderer.renderHTML(from: content)
        // Inject PDF CSS and title
        html = html.replacingOccurrences(of: "</style>", with: "\(pdfCSS)</style>")
        html = html.replacingOccurrences(of: "<body>", with: "<body>\(titleHTML)")
        html = html.replacingOccurrences(of: "</body>", with: "<div class='pdf-footer'>\(noteName) · Exported \(dateString)</div></body>")

        // Use WKWebView to create PDF
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842), configuration: config)
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for load then generate PDF
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            webView.createPDF { result in
                switch result {
                case .success(let data):
                    try? data.write(to: saveURL)
                    NSWorkspace.shared.open(saveURL)
                case .failure(let error):
                    Log.general.error("PDF export failed: \(error.localizedDescription)")
                }
            }
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

    private func togglePin() {
        guard let url = appState.selectedNoteURL else { return }
        let path = appState.pinnedNotesManager.relativePath(
            for: url, vaultURL: appState.vaultManager.vaultURL
        )
        appState.pinnedNotesManager.togglePin(path)
    }

    private func toggleFavorite() {
        guard let url = appState.selectedNoteURL else { return }
        let path = appState.favoritesManager.relativePath(
            for: url, vaultURL: appState.vaultManager.vaultURL
        )
        appState.favoritesManager.toggleFavorite(path)
    }

    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        appState.currentContent += prefix + suffix
    }

    private func insertLinePrefix(_ prefix: String) {
        appState.currentContent = prefix + appState.currentContent
    }
}
