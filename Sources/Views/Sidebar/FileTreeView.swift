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
                        .padding(.leading, 4)
                } label: {
                    if appState.renamingItemURL == folderNode.url {
                        InlineRenameField(
                            url: folderNode.url,
                            initialName: folderNode.name,
                            isFolder: true
                        )
                        .environmentObject(appState)
                    } else {
                        FileTreeRowView(node: node, isSelected: false)
                    }
                }
                .contextMenu { folderContextMenu(folder: folderNode) }

            case .file(let fileNode):
                let selected = appState.selectedNoteURL == fileNode.url
                if appState.renamingItemURL == fileNode.url {
                    InlineRenameField(
                        url: fileNode.url,
                        initialName: fileNode.name,
                        isFolder: false
                    )
                    .environmentObject(appState)
                } else {
                    FileTreeRowView(
                        node: node,
                        isSelected: selected
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                    .onTapGesture { appState.openNote(url: fileNode.url) }
                    .contextMenu { fileContextMenu(fileNode: fileNode) }
                    .draggable(fileNode.url.absoluteString)
                    .help("Created \(fileNode.createdDate.formatted(.dateTime.month(.abbreviated).day().year()))\nModified \(relativeTime(fileNode.modificationDate))")
                }
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(fileNode: FileNode) -> some View {
        let relativePath = appState.favoritesManager.relativePath(
            for: fileNode.url, vaultURL: appState.vaultManager.vaultURL
        )

        if appState.favoritesManager.isFavorite(relativePath) {
            Button("Remove from Favorites") {
                appState.favoritesManager.removeFavorite(relativePath)
            }
        } else {
            Button("Add to Favorites") {
                appState.favoritesManager.addFavorite(relativePath)
            }
        }

        Divider()

        Button("Rename") {
            appState.renamingItemURL = fileNode.url
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

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if Calendar.current.isDateInToday(date) { return "today at \(date.formatted(.dateTime.hour().minute()))" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday at \(date.formatted(.dateTime.hour().minute()))" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    @ViewBuilder
    private func folderContextMenu(folder: FolderNode) -> some View {
        Button("New Note") {
            appState.createNewNote(in: folder.url)
        }
        Button("New Folder") {
            appState.createNewFolder(in: folder.url)
        }
        Divider()
        Button("Rename") {
            appState.renamingItemURL = folder.url
        }
        Button("Move to Trash") {
            appState.vaultManager.moveToTrash(url: folder.url)
        }
        Divider()
        Button("Reveal in Finder") {
            appState.vaultManager.revealInFinder(url: folder.url)
        }
    }
}

// MARK: - Inline Rename Field

struct InlineRenameField: View {
    @EnvironmentObject var appState: AppState
    let url: URL
    let initialName: String
    let isFolder: Bool

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isFolder ? "folder.fill" : "doc.text.fill")
                .foregroundColor(isFolder ? .accentColor : .secondary.opacity(0.6))
                .font(.system(size: 13))
                .frame(width: 16, alignment: .center)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: isFolder ? .medium : .regular))
                .focused($isFocused)
                .onSubmit { commitRename() }
                .onExitCommand { appState.renamingItemURL = nil }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .onAppear {
            text = appState.renamingIsNew ? "" : initialName
            isFocused = true
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitRename()
            }
        }
    }

    private func commitRename() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != initialName else {
            appState.renamingItemURL = nil
            return
        }
        appState.commitRename(url: url, newName: trimmed)
    }
}
