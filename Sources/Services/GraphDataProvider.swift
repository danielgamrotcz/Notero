import Foundation

struct GraphNode: Codable {
    let id: String
    let label: String
    let path: String
    let wordCount: Int
    let isFavorite: Bool
    let isPinned: Bool
    let noteID: String
}

struct GraphEdge: Codable {
    let source: String
    let target: String
}

struct GraphData: Codable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
}

@MainActor
enum GraphDataProvider {
    static func buildGraphData(
        vaultManager: VaultManager,
        pinnedManager: PinnedNotesManager,
        favoritesManager: FavoritesManager
    ) -> GraphData {
        let files = vaultManager.allMarkdownFiles()
        let vaultURL = vaultManager.vaultURL

        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var nameToID: [String: String] = [:]

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let relativePath = file.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let wordCount = content.split { $0.isWhitespace || $0.isNewline }.count
            let meta = NoteMetadataService.shared.metadata(for: file)

            let node = GraphNode(
                id: name,
                label: name,
                path: relativePath,
                wordCount: wordCount,
                isFavorite: favoritesManager.isFavorite(relativePath),
                isPinned: pinnedManager.isPinned(relativePath),
                noteID: meta.id
            )
            nodes.append(node)
            nameToID[name.lowercased()] = name
        }

        // Build edges from wikilinks
        for file in files {
            let sourceName = file.deletingPathExtension().lastPathComponent
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let links = content.wikilinks()

            for link in links {
                let targetKey = link.linkName.lowercased()
                if let targetID = nameToID[targetKey] {
                    edges.append(GraphEdge(source: sourceName, target: targetID))
                }
            }
        }

        return GraphData(nodes: nodes, edges: edges)
    }

    static func graphDataJSON(
        vaultManager: VaultManager,
        pinnedManager: PinnedNotesManager,
        favoritesManager: FavoritesManager
    ) -> String {
        let data = buildGraphData(
            vaultManager: vaultManager,
            pinnedManager: pinnedManager,
            favoritesManager: favoritesManager
        )
        guard let jsonData = try? JSONEncoder().encode(data),
              let json = String(data: jsonData, encoding: .utf8) else {
            return "{\"nodes\":[],\"edges\":[]}"
        }
        return json
    }
}
