import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !searchText.isEmpty && !appState.searchService.results.isEmpty {
                        searchResults
                    } else {
                        // Pinned section
                        if !appState.pinnedNotesManager.pinnedNotes.isEmpty {
                            pinnedSection
                        }

                        // Favorites section
                        if !appState.favoritesManager.orderedFavorites.isEmpty {
                            favoritesSection
                        }

                        // File tree
                        FileTreeView(nodes: appState.vaultManager.fileTree)
                            .environmentObject(appState)
                    }
                }
                .padding(8)
            }
            .contextMenu {
                Button("New Note") { appState.createNewNote() }
                Button("New Folder") {
                    _ = appState.vaultManager.createFolder(named: "New Folder")
                }
            }
        }
        .frame(minWidth: 180, maxWidth: 400)
        .onChange(of: searchText) { _, newValue in
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                await appState.searchService.search(query: newValue)
            }
        }
    }

    // MARK: - Pinned Section

    @State private var pinnedExpanded = true

    private var pinnedSection: some View {
        DisclosureGroup(isExpanded: $pinnedExpanded) {
            ForEach(appState.pinnedNotesManager.pinnedNotes, id: \.self) { path in
                let noteURL = appState.vaultManager.vaultURL.appendingPathComponent(path)
                let noteName = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? path
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Text(noteName)
                        .lineLimit(1)
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(
                    appState.selectedNoteURL == noteURL
                        ? Color.accentColor.opacity(0.15) : Color.clear
                )
                .cornerRadius(4)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.openNote(url: noteURL)
                }
                .contextMenu {
                    Button("Unpin Note") {
                        appState.pinnedNotesManager.unpin(path)
                    }
                }
            }
        } label: {
            Text("Pinned")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Favorites Section

    @State private var favoritesExpanded = true

    private var favoritesSection: some View {
        DisclosureGroup(isExpanded: $favoritesExpanded) {
            ForEach(appState.favoritesManager.orderedFavorites, id: \.self) { path in
                let noteURL = appState.vaultManager.vaultURL.appendingPathComponent(path)
                let noteName = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? path
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Text(noteName)
                        .lineLimit(1)
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(
                    appState.selectedNoteURL == noteURL
                        ? Color.accentColor.opacity(0.15) : Color.clear
                )
                .cornerRadius(4)
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

    // MARK: - Search Results

    private var searchResults: some View {
        ForEach(appState.searchService.results) { result in
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
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                appState.openNote(url: result.noteURL)
                searchText = ""
            }
        }
    }
}
