import SwiftUI

@main
struct NoteroApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
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

                Button("AI Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        panel.nameFieldStringValue = appState.selectedNoteURL?.deletingPathExtension().lastPathComponent ?? "note"
        if panel.runModal() == .OK, let url = panel.url {
            let html = MarkdownRenderer.renderHTML(from: appState.currentContent)
            let printInfo = NSPrintInfo()
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36

            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            view.string = appState.currentContent

            if let printOp = NSPrintOperation(view: view, printInfo: printInfo) as NSPrintOperation? {
                printOp.showsPrintPanel = false
                printOp.showsProgressPanel = false
                printInfo.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL as NSCopying)
                printOp.run()
            }
        }
    }

    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        appState.currentContent += prefix + suffix
    }

    private func insertLinePrefix(_ prefix: String) {
        appState.currentContent = prefix + appState.currentContent
    }
}
