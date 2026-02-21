import Foundation
import AppKit

struct CommandItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let shortcut: String?
    let action: @MainActor () -> Void

    @MainActor
    static func allCommands(appState: AppState) -> [CommandItem] {
        [
            CommandItem(name: "New Note", icon: "doc.badge.plus", shortcut: "Cmd+N") {
                appState.createNewNote()
            },
            CommandItem(name: "New Folder", icon: "folder.badge.plus", shortcut: "Cmd+Shift+N") {
                _ = appState.vaultManager.createFolder(named: "New Folder")
            },
            CommandItem(name: "Open Vault in Finder", icon: "folder", shortcut: nil) {
                appState.vaultManager.revealInFinder(url: appState.vaultManager.vaultURL)
            },
            CommandItem(name: "Toggle Sidebar", icon: "sidebar.leading", shortcut: "Cmd+Shift+L") {
                appState.showSidebar.toggle()
            },
            CommandItem(name: "Toggle Preview", icon: "eye", shortcut: "Cmd+E") {
                appState.togglePreview()
            },
            CommandItem(name: "Toggle Line Numbers", icon: "list.number", shortcut: nil) {
                appState.showLineNumbers.toggle()
            },
            CommandItem(name: "Toggle Backlinks Panel", icon: "link", shortcut: "Cmd+Shift+B") {
                appState.showBacklinks.toggle()
            },
            CommandItem(name: "Focus Search", icon: "magnifyingglass", shortcut: "Cmd+Shift+F") {
                appState.showSidebar = true
            },
            CommandItem(name: "Improve with AI – Claude", icon: "sparkles", shortcut: "Option+A") {
                appState.improveWithClaude()
            },
            CommandItem(name: "Improve with AI – Local", icon: "cpu", shortcut: "Option+L") {
                appState.improveWithOllama()
            },
            CommandItem(name: "Export Note as PDF", icon: "arrow.down.doc", shortcut: nil) {
                // PDF export handled in menu
            },
            CommandItem(name: "Copy Note as HTML", icon: "doc.richtext", shortcut: nil) {
                let html = MarkdownRenderer.renderHTML(from: appState.currentContent)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(html, forType: .string)
            },
        ]
    }
}
