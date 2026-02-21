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
