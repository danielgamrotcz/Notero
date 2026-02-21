import AppIntents
import AppKit
import Foundation

// MARK: - Create Note

struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note in Notero"
    static var description: IntentDescription = "Creates a new note in your Notero vault"

    @Parameter(title: "Title")
    var noteTitle: String

    @Parameter(title: "Content")
    var content: String?

    @Parameter(title: "Folder")
    var folder: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let vaultURL = resolveVaultURL()
        let sanitized = noteTitle.replacingOccurrences(of: "[:/\\\\?*\"<>|]", with: "-", options: .regularExpression)
        let targetFolder: URL
        if let folder, !folder.isEmpty {
            targetFolder = vaultURL.appendingPathComponent(folder)
            try? FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        } else {
            targetFolder = vaultURL
        }

        var fileURL = targetFolder.appendingPathComponent("\(sanitized).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = targetFolder.appendingPathComponent("\(sanitized) \(counter).md")
            counter += 1
        }

        let body = content ?? ""
        let noteContent = "# \(noteTitle)\n\n\(body)"
        try noteContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let relativePath = fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        return .result(value: "Created: \(relativePath)")
    }
}

// MARK: - Append to Note

struct AppendToNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Append to Note in Notero"
    static var description: IntentDescription = "Appends content to an existing note"

    @Parameter(title: "Note Name")
    var noteName: String

    @Parameter(title: "Content")
    var content: String

    @Parameter(title: "Add Separator", default: true)
    var addSeparator: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let vaultURL = resolveVaultURL()
        guard let noteURL = findNote(named: noteName, in: vaultURL) else {
            throw IntentError.noteNotFound(noteName)
        }
        let existing = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""
        let separator = addSeparator ? "\n\n---\n\n" : "\n\n"
        let appended = existing + separator + content
        try appended.write(to: noteURL, atomically: true, encoding: .utf8)
        return .result(value: "Appended to \(noteURL.deletingPathExtension().lastPathComponent)")
    }
}

// MARK: - Search Notes

struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Notes in Notero"
    static var description: IntentDescription = "Searches notes by content"

    @Parameter(title: "Query")
    var query: String

    @Parameter(title: "Max Results", default: 5)
    var maxResults: Int?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let vaultURL = resolveVaultURL()
        let limit = maxResults ?? 5
        let files = allMarkdownFiles(in: vaultURL)
        let queryLower = query.lowercased()

        var results: [(name: String, path: String, snippet: String)] = []
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if content.lowercased().contains(queryLower) {
                let name = file.deletingPathExtension().lastPathComponent
                let relativePath = file.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
                let snippet = extractSnippet(from: content, query: queryLower)
                results.append((name: name, path: relativePath, snippet: snippet))
                if results.count >= limit { break }
            }
        }

        let json = results.map { "{\"title\":\"\($0.name)\",\"path\":\"\($0.path)\",\"snippet\":\"\($0.snippet)\"}" }
        return .result(value: "[\(json.joined(separator: ","))]")
    }

    private func extractSnippet(from content: String, query: String) -> String {
        guard let range = content.lowercased().range(of: query) else {
            return String(content.prefix(100))
        }
        let start = content.index(range.lowerBound, offsetBy: -40, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: 40, limitedBy: content.endIndex) ?? content.endIndex
        return String(content[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Get Note Content

struct GetNoteContentIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Note Content from Notero"
    static var description: IntentDescription = "Returns the content of a note"

    @Parameter(title: "Note Name")
    var noteName: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let vaultURL = resolveVaultURL()
        guard let noteURL = findNote(named: noteName, in: vaultURL) else {
            throw IntentError.noteNotFound(noteName)
        }
        let content = try String(contentsOf: noteURL, encoding: .utf8)
        return .result(value: content)
    }
}

// MARK: - Open Note

struct OpenNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Note in Notero"
    static var openAppWhenRun = true
    static var description: IntentDescription = "Opens a note in Notero"

    @Parameter(title: "Note Name or ID")
    var noteIdentifier: String

    func perform() async throws -> some IntentResult {
        let vaultURL = resolveVaultURL()

        // Try by name first
        if let noteURL = findNote(named: noteIdentifier, in: vaultURL) {
            let urlString = "notero://open?name=\(noteIdentifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? noteIdentifier)"
            if let url = URL(string: urlString) {
                await NSWorkspace.shared.open(url)
            }
            return .result()
        }

        // Try by ID
        let urlString = "notero://open?id=\(noteIdentifier)"
        if let url = URL(string: urlString) {
            await NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

// MARK: - Helpers

private func resolveVaultURL() -> URL {
    if let path = UserDefaults.standard.string(forKey: "vaultPath") {
        return URL(fileURLWithPath: path)
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent("Notero")
}

private func findNote(named name: String, in vaultURL: URL) -> URL? {
    let files = allMarkdownFiles(in: vaultURL)
    let nameLower = name.lowercased()

    // Exact match
    if let exact = files.first(where: {
        $0.deletingPathExtension().lastPathComponent.lowercased() == nameLower
    }) {
        return exact
    }

    // Fuzzy: contains
    return files.first(where: {
        $0.deletingPathExtension().lastPathComponent.lowercased().contains(nameLower)
    })
}

private func allMarkdownFiles(in vaultURL: URL) -> [URL] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: vaultURL, includingPropertiesForKeys: nil,
                                          options: [.skipsHiddenFiles]) else { return [] }
    var files: [URL] = []
    for case let url as URL in enumerator {
        if url.pathExtension == "md" {
            files.append(url)
        }
    }
    return files
}

// MARK: - Errors

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noteNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noteNotFound(let name):
            return "Note '\(name)' not found"
        }
    }
}

// MARK: - Shortcuts Provider

struct NoteroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: ["Create a note in \(.applicationName)"],
            shortTitle: "Create Note",
            systemImageName: "doc.badge.plus"
        )
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: ["Search \(.applicationName)"],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
    }
}
