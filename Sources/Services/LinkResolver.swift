import Foundation

@MainActor
final class LinkResolver: ObservableObject {
    @Published var backlinks: [BacklinkResult] = []

    private weak var vaultManager: VaultManager?

    struct BacklinkResult: Identifiable {
        let id = UUID()
        let noteURL: URL
        let noteName: String
    }

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
    }

    func resolve(linkName: String) -> URL? {
        guard let vault = vaultManager else { return nil }
        let files = vault.allMarkdownFiles()
        let normalizedLink = linkName.lowercased()

        // Exact match first
        if let match = files.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased() == normalizedLink
        }) {
            return match
        }

        // Partial match
        return files.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased().contains(normalizedLink)
        })
    }

    func findBacklinks(for noteURL: URL) {
        guard let vault = vaultManager else { return }
        let noteName = noteURL.deletingPathExtension().lastPathComponent
        let files = vault.allMarkdownFiles()
        let pattern = "\\[\\[\(NSRegularExpression.escapedPattern(for: noteName))(\\|[^\\]]*)?\\]\\]"

        var results: [BacklinkResult] = []

        for fileURL in files where fileURL != noteURL {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, range: range) != nil {
                    results.append(BacklinkResult(
                        noteURL: fileURL,
                        noteName: fileURL.deletingPathExtension().lastPathComponent
                    ))
                }
            }
        }

        backlinks = results
    }

    func updateWikilinks(oldName: String, newName: String, excludingNoteAt excludedURL: URL) {
        guard let vault = vaultManager else { return }
        let escaped = NSRegularExpression.escapedPattern(for: oldName)
        let pattern = "\\[\\[\(escaped)(\\|[^\\]]*)?\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }

        let excludedStandardized = excludedURL.standardizedFileURL
        for fileURL in vault.allMarkdownFiles() where fileURL.standardizedFileURL != excludedStandardized {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            guard regex.firstMatch(in: content, range: range) != nil else { continue }

            let updated = regex.stringByReplacingMatches(
                in: content, range: range,
                withTemplate: "[[\(NSRegularExpression.escapedTemplate(for: newName))$1]]"
            )
            do {
                try updated.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                Log.vault.error("Failed to update wikilinks in \(fileURL.lastPathComponent): \(error)")
            }
        }
    }

    func allNoteNames() -> [(name: String, url: URL)] {
        guard let vault = vaultManager else { return [] }
        return vault.allMarkdownFiles().map { url in
            (name: url.deletingPathExtension().lastPathComponent, url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fuzzyMatch(query: String, in names: [(name: String, url: URL)]) -> [(name: String, url: URL)] {
        guard !query.isEmpty else { return names }
        let lowerQuery = query.lowercased()
        return names.filter { $0.name.lowercased().contains(lowerQuery) }
    }
}
