import SwiftUI
import Sparkle

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
                    if let noteState = noteState, !noteState.selectedNoteURLs.isEmpty {
                        for url in noteState.selectedNoteURLs {
                            appState.vaultManager.moveToTrash(url: url)
                        }
                        noteState.selectedNoteURLs.removeAll()
                        noteState.selectedNoteURL = nil
                        noteState.currentContent = ""
                        noteState.clearLastOpenedNote()
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
                    noteState?.exportAsPDF()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as DOCX") {
                    noteState?.exportAsDOCX()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Export as HTML") {
                    noteState?.exportAsHTML()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Export as Markdown") {
                    noteState?.exportAsMarkdown()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Button("Send to reMarkable") {
                    noteState?.sendToReMarkable()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(noteState?.selectedNoteURL == nil || noteState?.isSendingToReMarkable == true)

                Divider()

                Button("Copy Note ID") {
                    guard let url = noteState?.selectedNoteURL else { return }
                    let meta = NoteMetadataService.shared.metadata(for: url)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(meta.id, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy Note Path") {
                    guard let url = noteState?.selectedNoteURL else { return }
                    let vaultPath = appState.vaultManager.vaultURL.path
                    let relative = url.path.replacingOccurrences(of: vaultPath + "/", with: "")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(relative, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
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
                    insertMarkdown("[", "]()", cursorOffset: 1)
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
                    appState.sidebarVisibility = appState.sidebarVisibility == .detailOnly ? .automatic : .detailOnly
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

                Button("Back") {
                    noteState?.navigateBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(noteState?.canGoBack != true)

                Button("Forward") {
                    noteState?.navigateForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(noteState?.canGoForward != true)

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

    private func insertMarkdown(_ prefix: String, _ suffix: String, cursorOffset: Int = 0) {
        NotificationCenter.default.post(
            name: .insertMarkdownFormat, object: nil,
            userInfo: ["type": "wrap", "prefix": prefix, "suffix": suffix, "cursorOffset": cursorOffset]
        )
    }

    private func insertLinePrefix(_ prefix: String) {
        NotificationCenter.default.post(
            name: .insertMarkdownFormat, object: nil,
            userInfo: ["type": "linePrefix", "prefix": prefix]
        )
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

