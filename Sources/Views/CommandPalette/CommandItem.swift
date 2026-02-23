import Foundation
import AppKit

struct CommandItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let shortcut: String?
    let action: @MainActor () -> Void

    @MainActor
    static func allCommands(appState: AppState, noteState: NoteState) -> [CommandItem] {
        [
            CommandItem(name: "New Note", icon: "doc.badge.plus", shortcut: "Cmd+N") {
                noteState.createNewNote()
            },
            CommandItem(name: "New Folder", icon: "folder.badge.plus", shortcut: "Cmd+Shift+N") {
                _ = appState.vaultManager.createFolder(named: "New Folder")
            },
            CommandItem(name: "Open Vault in Finder", icon: "folder", shortcut: nil) {
                appState.vaultManager.revealInFinder(url: appState.vaultManager.vaultURL)
            },
            CommandItem(name: "Toggle Sidebar", icon: "sidebar.leading", shortcut: "Cmd+Shift+L") {
                appState.sidebarVisibility = appState.sidebarVisibility == .detailOnly ? .automatic : .detailOnly
            },
            CommandItem(name: "Toggle Preview", icon: "eye", shortcut: "Cmd+E") {
                noteState.togglePreview()
            },
            CommandItem(name: "Toggle Line Numbers", icon: "list.number", shortcut: nil) {
                appState.showLineNumbers.toggle()
            },
            CommandItem(name: "Toggle Backlinks Panel", icon: "link", shortcut: "Cmd+Shift+B") {
                appState.showBacklinks.toggle()
            },
            CommandItem(name: "Focus Search", icon: "magnifyingglass", shortcut: "Cmd+Shift+F") {
                appState.sidebarVisibility = .automatic
            },
            CommandItem(name: "Improve with AI – Claude", icon: "sparkles", shortcut: "Option+A") {
                noteState.improveWithClaude()
            },
            CommandItem(name: "Improve with AI – Local", icon: "cpu", shortcut: "Option+L") {
                noteState.improveWithOllama()
            },
            CommandItem(name: "Export Note as PDF", icon: "arrow.down.doc", shortcut: nil) {
                noteState.exportAsPDF()
            },
            CommandItem(name: "Export Note as HTML", icon: "globe", shortcut: nil) {
                noteState.exportAsHTML()
            },
            CommandItem(name: "Export Note as Markdown", icon: "doc.text", shortcut: nil) {
                noteState.exportAsMarkdown()
            },
        ]
    }
}
