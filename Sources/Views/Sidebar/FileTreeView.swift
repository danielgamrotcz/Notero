import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState
    let nodes: [FileTreeNode]

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case .folder(let folderNode):
                DisclosureGroup {
                    FileTreeView(nodes: folderNode.children)
                        .environmentObject(appState)
                } label: {
                    FileTreeRowView(node: node, isSelected: false)
                        .help("\(folderNode.noteCount) notes")
                }
                .contextMenu { folderContextMenu(folder: folderNode) }

            case .file(let fileNode):
                FileTreeRowView(
                    node: node,
                    isSelected: appState.selectedNoteURL == fileNode.url
                )
                .background(
                    appState.selectedNoteURL == fileNode.url
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .cornerRadius(4)
                .onTapGesture { appState.openNote(url: fileNode.url) }
                .contextMenu { fileContextMenu(fileNode: fileNode) }
                .draggable(fileNode.url.absoluteString)
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(fileNode: FileNode) -> some View {
        Button("Rename") {
            // Inline rename handled by sidebar
        }
        Button("Duplicate") {
            _ = appState.vaultManager.duplicateNote(at: fileNode.url)
        }
        Divider()
        Button("Move to Trash") {
            appState.vaultManager.moveToTrash(url: fileNode.url)
            if appState.selectedNoteURL == fileNode.url {
                appState.selectedNoteURL = nil
                appState.currentContent = ""
            }
        }
        Divider()
        Button("Reveal in Finder") {
            appState.vaultManager.revealInFinder(url: fileNode.url)
        }
        Button("Copy Link") {
            let link = "[[\(fileNode.name)]]"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        }
    }

    @ViewBuilder
    private func folderContextMenu(folder: FolderNode) -> some View {
        Button("New Note") {
            appState.createNewNote(in: folder.url)
        }
        Button("New Folder") {
            _ = appState.vaultManager.createFolder(named: "New Folder", in: folder.url)
        }
        Divider()
        Button("Rename") { }
        Button("Move to Trash") {
            appState.vaultManager.moveToTrash(url: folder.url)
        }
        Divider()
        Button("Reveal in Finder") {
            appState.vaultManager.revealInFinder(url: folder.url)
        }
    }
}
