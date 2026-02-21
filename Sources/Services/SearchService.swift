import Foundation

@MainActor
final class SearchService: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var isIndexing = false

    let index = SearchIndex()
    private weak var vaultManager: VaultManager?

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
    }

    func buildIndex() async {
        guard let vault = vaultManager else { return }
        isIndexing = true
        let files = vault.allMarkdownFiles()
        let vaultURL = vault.vaultURL

        await withTaskGroup(of: (URL, String)?.self) { group in
            for fileURL in files {
                group.addTask {
                    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        return nil
                    }
                    return (fileURL, content)
                }
            }

            for await result in group {
                if let (url, content) = result {
                    await index.addOrUpdate(url: url, content: content, vaultURL: vaultURL)
                }
            }
        }

        isIndexing = false
        Log.search.info("Index built with \(files.count) files")
    }

    func reindex(url: URL) async {
        guard let vault = vaultManager else { return }
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            await index.addOrUpdate(url: url, content: content, vaultURL: vault.vaultURL)
        }
    }

    func removeFromIndex(url: URL) async {
        await index.remove(url: url)
    }

    func search(query: String) async {
        let searchResults = await index.search(query: query)
        results = searchResults
    }

    func allNoteNames() async -> [(name: String, url: URL)] {
        await index.allNoteNames()
    }
}
