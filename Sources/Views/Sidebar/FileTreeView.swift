import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var noteState: NoteState
    let nodes: [FileTreeNode]
    var expandedFolders: Binding<Set<URL>>?

    var body: some View {
        ForEach(nodes) { (node: FileTreeNode) in
            switch node {
            case .folder(let folderNode):
                let isExpanded = Binding<Bool>(
                    get: { expandedFolders?.wrappedValue.contains(folderNode.url) ?? false },
                    set: { newValue in
                        if newValue {
                            expandedFolders?.wrappedValue.insert(folderNode.url)
                        } else {
                            expandedFolders?.wrappedValue.remove(folderNode.url)
                        }
                    }
                )

                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isExpanded.wrappedValue.toggle()
                                }
                            }
                        if appState.renamingItemURL?.path == folderNode.url.path {
                            InlineRenameField(
                                url: folderNode.url,
                                initialName: folderNode.name,
                                isFolder: true
                            )
                            .environmentObject(appState)
                        } else {
                            FileTreeRowView(node: node, isSelected: false)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isExpanded.wrappedValue.toggle()
                                    }
                                }
                        }
                    }
                    .contextMenu { folderContextMenu(folder: folderNode) }
                    if isExpanded.wrappedValue {
                        FileTreeView(
                            nodes: folderNode.children,
                            expandedFolders: expandedFolders
                        )
                        .environmentObject(appState)
                        .environmentObject(noteState)
                        .padding(.leading, 16)
                    }
                }

            case .file(let fileNode):
                let selected = noteState.selectedNoteURL == fileNode.url
                if appState.renamingItemURL?.path == fileNode.url.path {
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
                    .gesture(
                        TapGesture().onEnded {
                            noteState.openNote(url: fileNode.url)
                        }
                    )
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
            if noteState.selectedNoteURL == fileNode.url {
                noteState.selectedNoteURL = nil
                noteState.currentContent = ""
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
        let relativePath = appState.favoritesManager.relativePath(
            for: folder.url, vaultURL: appState.vaultManager.vaultURL
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
        Button("New Note") {
            noteState.createNewNote(in: folder.url)
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
