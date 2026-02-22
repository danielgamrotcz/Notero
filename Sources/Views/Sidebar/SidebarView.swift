import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var focusedSearchResultIndex: Int = -1
    @State private var focusedItemID: URL?
    @State private var expandedFolders: Set<URL> = []

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
            ZStack {
                SidebarKeyHandler { key in
                    handleSidebarKey(key)
                }
                .frame(width: 0, height: 0)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if !searchText.isEmpty && !appState.searchService.results.isEmpty {
                            searchResults
                        } else {
                            // Favorites section
                            if !appState.favoritesManager.orderedFavorites.isEmpty {
                                favoritesSection
                            }

                            // File tree
                            FileTreeView(
                                nodes: appState.vaultManager.fileTree,
                                focusedItemID: $focusedItemID,
                                expandedFolders: $expandedFolders
                            )
                            .environmentObject(appState)
                        }
                    }
                    .padding(8)
                }
                .contextMenu {
                    Button("New Note") { appState.createNewNote() }
                    Button("New Folder") {
                        appState.createNewFolder()
                    }
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
    }

    // MARK: - Keyboard Navigation

    private func flatVisibleItems() -> [FileTreeNode] {
        var items: [FileTreeNode] = []
        func collect(_ nodes: [FileTreeNode]) {
            for node in nodes {
                items.append(node)
                if case .folder(let folder) = node, expandedFolders.contains(folder.url) {
                    collect(folder.children)
                }
            }
        }
        collect(appState.vaultManager.fileTree)
        return items
    }

    private func handleSidebarKey(_ key: SidebarKeyHandler.ArrowKey) {
        // If search results are showing, handle search navigation
        if !searchText.isEmpty && !appState.searchService.results.isEmpty {
            handleSearchKey(key)
            return
        }

        let items = flatVisibleItems()
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex(where: { $0.url == focusedItemID }) ?? -1

        switch key {
        case .down:
            let next = min(currentIndex + 1, items.count - 1)
            focusedItemID = items[next].url
            updateFocusedFolder(items[next])
        case .up:
            let prev = max(currentIndex - 1, 0)
            focusedItemID = items[prev].url
            updateFocusedFolder(items[prev])
        case .right:
            if let id = focusedItemID,
               let node = items.first(where: { $0.url == id }),
               case .folder(let folder) = node {
                expandedFolders.insert(folder.url)
            }
        case .left:
            if let id = focusedItemID,
               let node = items.first(where: { $0.url == id }) {
                if case .folder(let folder) = node, expandedFolders.contains(folder.url) {
                    expandedFolders.remove(folder.url)
                } else {
                    // Move to parent folder
                    let parentURL = id.deletingLastPathComponent()
                    if let parent = items.first(where: { $0.url == parentURL }) {
                        focusedItemID = parent.url
                    }
                }
            }
        case .enter:
            if let id = focusedItemID,
               let node = items.first(where: { $0.url == id }) {
                switch node {
                case .file:
                    appState.openNote(url: id)
                case .folder(let folder):
                    if expandedFolders.contains(folder.url) {
                        expandedFolders.remove(folder.url)
                    } else {
                        expandedFolders.insert(folder.url)
                    }
                }
            }
        }
    }

    private func updateFocusedFolder(_ node: FileTreeNode) {
        switch node {
        case .folder(let folder):
            appState.focusedFolderURL = folder.url
        case .file:
            appState.focusedFolderURL = node.url.deletingLastPathComponent()
        }
    }

    private func handleSearchKey(_ key: SidebarKeyHandler.ArrowKey) {
        let count = appState.searchService.results.count
        switch key {
        case .up:
            focusedSearchResultIndex = max(0, focusedSearchResultIndex - 1)
        case .down:
            focusedSearchResultIndex = min(count - 1, focusedSearchResultIndex + 1)
        case .enter:
            if focusedSearchResultIndex >= 0 && focusedSearchResultIndex < count {
                let result = appState.searchService.results[focusedSearchResultIndex]
                appState.openNote(url: result.noteURL)
                searchText = ""
                focusedSearchResultIndex = -1
            }
        default:
            break
        }
    }

    // MARK: - Favorites Section

    @State private var favoritesExpanded = true

    private var favoritesSection: some View {
        DisclosureGroup(isExpanded: $favoritesExpanded) {
            ForEach(appState.favoritesManager.orderedFavorites, id: \.self) { path in
                let noteURL = appState.vaultManager.vaultURL.appendingPathComponent(path)
                let noteName = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? path
                let selected = appState.selectedNoteURL == noteURL
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
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.openNote(url: noteURL)
                }
                .contextMenu {
                    Button("Remove from Favorites") {
                        appState.favoritesManager.removeFavorite(path)
                    }
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
                appState.openNote(url: result.noteURL)
                searchText = ""
                appState.searchService.results = []
                focusedSearchResultIndex = -1
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

// MARK: - Sidebar Key Handler

struct SidebarKeyHandler: NSViewRepresentable {
    var onArrowKey: (ArrowKey) -> Void

    enum ArrowKey { case up, down, left, right, enter }

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onArrowKey = onArrowKey
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.onArrowKey = onArrowKey
    }
}

class KeyCaptureView: NSView {
    var onArrowKey: ((SidebarKeyHandler.ArrowKey) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onArrowKey?(.up)
        case 125: onArrowKey?(.down)
        case 123: onArrowKey?(.left)
        case 124: onArrowKey?(.right)
        case 36:  onArrowKey?(.enter)
        default: super.keyDown(with: event)
        }
    }
}
