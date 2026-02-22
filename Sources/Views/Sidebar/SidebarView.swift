import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var noteState: NoteState
    @State private var searchText = ""
    @State private var focusedSearchResultIndex: Int = -1
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        Task { await appState.searchService.search(query: searchText) }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        appState.searchService.results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    ForEach(NoteSortOrder.allCases, id: \.self) { order in
                        Button {
                            appState.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.label)
                                if appState.sortOrder == order {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(appState.sortOrder == .nameAscending ? .secondary : .accentColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort notes")
            }
            .padding(8)
            .background(.ultraThinMaterial)

            Divider()

            // Content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !searchText.isEmpty && !appState.searchService.results.isEmpty {
                        searchResults
                    } else {
                        // Favorites section
                        if !appState.favoritesManager.orderedFavorites.isEmpty {
                            favoritesSection
                        }

                        // Folders section
                        foldersSection

                        // Inbox section (root-level files)
                        if !appState.vaultManager.fileTree.filter({ !$0.isFolder }).isEmpty {
                            inboxSection
                        }
                    }
                }
                .padding(8)
            }
            .contextMenu {
                Button("New Note") { noteState.createNewNote() }
                Button("New Folder") {
                    appState.createNewFolder()
                }
            }

            // Activity heatmap widget
            if appState.showActivityHeatmapInSidebar {
                Divider()
                sidebarHeatmap
            }
        }
        .frame(minWidth: 180, maxWidth: 400)
        .onChange(of: searchText) { _, newValue in
            focusedSearchResultIndex = 0
            Task {
                try? await Task.sleep(nanoseconds: 80_000_000)
                await appState.searchService.search(query: newValue)
            }
        }
        .onChange(of: appState.focusSidebarSearch) { _, newValue in
            if newValue {
                isSearchFieldFocused = true
                appState.focusSidebarSearch = false
            }
        }
    }

    // MARK: - Favorites Section

    @State private var favoritesExpanded = true

    private var favoritesSection: some View {
        DisclosureGroup(isExpanded: $favoritesExpanded) {
            ForEach(appState.favoritesManager.orderedFavorites, id: \.self) { path in
                let itemURL = appState.vaultManager.vaultURL.appendingPathComponent(path)
                if let node = findNode(for: itemURL, in: appState.vaultManager.fileTree),
                   node.isFolder {
                    favoriteFolderRow(node: node, path: path)
                } else {
                    favoriteFileRow(path: path, url: itemURL)
                }
            }
        } label: {
            Text("Favorites")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func favoriteFileRow(path: String, url: URL) -> some View {
        let noteName = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? path
        let selected = noteState.selectedNoteURL == url
        HStack(spacing: 7) {
            Image(systemName: "star.fill")
                .foregroundColor(selected ? .white : .yellow)
                .font(.system(size: 11))
                .frame(width: 16, alignment: .center)
            Text(noteName)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 13))
                .foregroundColor(selected ? .white : .primary)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            noteState.openNote(url: url)
        }
        .contextMenu {
            Button("Remove from Favorites") {
                appState.favoritesManager.removeFavorite(path)
            }
        }
    }

    @ViewBuilder
    private func favoriteFolderRow(node: FileTreeNode, path: String) -> some View {
        if case .folder(let folderNode) = node {
            let isExpanded = Binding<Bool>(
                get: { appState.expandedFolders.contains(folderNode.url) },
                set: { newValue in
                    if newValue {
                        appState.expandedFolders.insert(folderNode.url)
                    } else {
                        appState.expandedFolders.remove(folderNode.url)
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
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 11))
                            .frame(width: 16, alignment: .center)
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))
                            .frame(width: 16, alignment: .center)
                        Text(folderNode.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 4)
                        Text("\(folderNode.noteCount)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.wrappedValue.toggle()
                        }
                    }
                }
                .contextMenu {
                    Button("Remove from Favorites") {
                        appState.favoritesManager.removeFavorite(path)
                    }
                }
                if isExpanded.wrappedValue {
                    FileTreeView(
                        nodes: folderNode.children,
                        expandedFolders: $appState.expandedFolders
                    )
                    .environmentObject(appState)
                    .environmentObject(noteState)
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func findNode(for url: URL, in nodes: [FileTreeNode]) -> FileTreeNode? {
        for node in nodes {
            if node.url == url { return node }
            if case .folder(let f) = node,
               let found = findNode(for: url, in: f.children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Folders Section

    @State private var foldersExpanded = true

    private var foldersSection: some View {
        DisclosureGroup(isExpanded: $foldersExpanded) {
            FileTreeView(
                nodes: appState.vaultManager.fileTree.filter(\.isFolder),
                expandedFolders: $appState.expandedFolders
            )
            .environmentObject(appState)
            .environmentObject(noteState)
        } label: {
            Text("Folders")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Inbox Section

    @State private var inboxExpanded = true

    private var inboxSection: some View {
        DisclosureGroup(isExpanded: $inboxExpanded) {
            FileTreeView(
                nodes: appState.vaultManager.fileTree.filter { !$0.isFolder },
                expandedFolders: $appState.expandedFolders
            )
            .environmentObject(appState)
            .environmentObject(noteState)
        } label: {
            Text("Inbox")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Sidebar Heatmap

    @State private var heatmapExpanded = true

    private var sidebarHeatmap: some View {
        DisclosureGroup(isExpanded: $heatmapExpanded) {
            let data = loadRecentActivity(weeks: 12)
            ActivityHeatmapView(data: data)
                .frame(height: 7 * 16)
                .padding(.vertical, 4)
        } label: {
            Text("Activity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func loadRecentActivity(weeks: Int) -> [DailyWordCount] {
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        let days = weeks * 7
        var result: [DailyWordCount] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let key = "goal-\(formatter.string(from: date))"
            let count = defaults.integer(forKey: key)
            result.append(DailyWordCount(date: date, words: count))
        }
        return result
    }

    // MARK: - Search Results

    private var searchResults: some View {
        ForEach(Array(appState.searchService.results.enumerated()), id: \.element.id) { index, result in
            Button {
                noteState.openNote(url: result.noteURL)
                focusedSearchResultIndex = index
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(result.noteName)
                            .font(.system(size: 13, weight: .medium))
                    }
                    if !result.folderPath.isEmpty {
                        Text(result.folderPath)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text(result.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(index == focusedSearchResultIndex
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear)
            )
        }
    }
}
