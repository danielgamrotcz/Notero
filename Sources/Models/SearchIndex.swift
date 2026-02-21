import Foundation

struct SearchResult: Identifiable {
    let id = UUID()
    let noteURL: URL
    let noteName: String
    let folderPath: String
    let snippet: String
    let score: Int // higher = better match
}

actor SearchIndex {
    private var entries: [URL: IndexEntry] = [:]

    struct IndexEntry {
        let url: URL
        let name: String
        let folderPath: String
        let tokens: Set<String>
        let content: String
    }

    func addOrUpdate(url: URL, content: String, vaultURL: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let relativeFolderPath = url.deletingLastPathComponent().path
            .replacingOccurrences(of: vaultURL.path, with: "")
        let tokens = tokenize(name + " " + content)
        entries[url] = IndexEntry(
            url: url, name: name, folderPath: relativeFolderPath,
            tokens: tokens, content: content
        )
    }

    func remove(url: URL) {
        entries.removeValue(forKey: url)
    }

    func search(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let isExactPhrase = query.hasPrefix("\"") && query.hasSuffix("\"")
        let normalizedQuery = query
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)

        var results: [SearchResult] = []

        for (_, entry) in entries {
            let normalizedName = entry.name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let normalizedContent = entry.content
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)

            var score = 0

            if isExactPhrase {
                if normalizedName == normalizedQuery {
                    score = 100
                } else if normalizedName.contains(normalizedQuery) {
                    score = 80
                } else if normalizedContent.contains(normalizedQuery) {
                    score = 50
                }
            } else {
                let queryTokens = tokenize(normalizedQuery)
                let allMatch = queryTokens.allSatisfy { token in
                    entry.tokens.contains { $0.contains(token) }
                }

                if allMatch {
                    if normalizedName == normalizedQuery {
                        score = 100
                    } else if normalizedName.contains(normalizedQuery) {
                        score = 80
                    } else if queryTokens.allSatisfy({ normalizedName.contains($0) }) {
                        score = 60
                    } else {
                        score = 40
                    }
                }
            }

            if score > 0 {
                let snippet = makeSnippet(
                    content: entry.content, query: normalizedQuery)
                results.append(SearchResult(
                    noteURL: entry.url, noteName: entry.name,
                    folderPath: entry.folderPath, snippet: snippet,
                    score: score
                ))
            }
        }

        return results.sorted { $0.score > $1.score }.prefix(50).map { $0 }
    }

    func allNoteNames() -> [(name: String, url: URL)] {
        entries.values.map { (name: $0.name, url: $0.url) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func tokenize(_ text: String) -> Set<String> {
        let normalized = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = normalized.components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return Set(words)
    }

    private func makeSnippet(content: String, query: String) -> String {
        let normalized = content.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard let range = normalized.range(of: query) else {
            return String(content.prefix(100))
        }

        let matchStart = content.distance(
            from: content.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - 50)
        let contextEnd = min(content.count, matchStart + query.count + 50)

        let startIdx = content.index(content.startIndex, offsetBy: contextStart)
        let endIdx = content.index(content.startIndex, offsetBy: contextEnd)
        var snippet = String(content[startIdx..<endIdx])

        if contextStart > 0 { snippet = "..." + snippet }
        if contextEnd < content.count { snippet = snippet + "..." }

        return snippet.replacingOccurrences(of: "\n", with: " ")
    }
}
