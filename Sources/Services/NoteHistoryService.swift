import Foundation

@MainActor
final class NoteHistoryService {
    static let shared = NoteHistoryService()

    private let maxSnapshots = 50
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Snapshot Management

    func saveSnapshot(content: String, for noteURL: URL) {
        let historyDir = historyDirectory(for: noteURL)
        try? fileManager.createDirectory(atPath: historyDir, withIntermediateDirectories: true)

        // Check if content differs from last snapshot
        if let lastSnapshot = loadSnapshots(for: noteURL).first,
           lastSnapshot.content == content {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let snapshotPath = "\(historyDir)/\(timestamp).md"
        try? content.write(toFile: snapshotPath, atomically: true, encoding: .utf8)

        // Enforce retention limit
        pruneOldSnapshots(in: historyDir)
    }

    func loadSnapshots(for noteURL: URL) -> [NoteSnapshot] {
        let historyDir = historyDirectory(for: noteURL)
        guard let files = try? fileManager.contentsOfDirectory(atPath: historyDir) else { return [] }

        return files
            .filter { $0.hasSuffix(".md") }
            .sorted(by: >)  // newest first
            .compactMap { filename -> NoteSnapshot? in
                let path = "\(historyDir)/\(filename)"
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let date = parseSnapshotDate(filename) ?? Date()
                return NoteSnapshot(filename: filename, date: date, content: content)
            }
    }

    func deleteAllHistory(for noteURL: URL) {
        let historyDir = historyDirectory(for: noteURL)
        try? fileManager.removeItem(atPath: historyDir)
    }

    // MARK: - Diff

    static func diff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        let diff = newLines.difference(from: oldLines)

        var result: [DiffLine] = []
        let removals = Set(diff.removals.map { change -> Int in
            if case .remove(let offset, _, _) = change { return offset }
            return -1
        })

        let insertions = Set(diff.insertions.map { change -> Int in
            if case .insert(let offset, _, _) = change { return offset }
            return -1
        })

        // Simple line-by-line diff display
        for (i, line) in oldLines.enumerated() {
            if removals.contains(i) {
                result.append(DiffLine(text: line, type: .removed))
            }
        }

        for (i, line) in newLines.enumerated() {
            if insertions.contains(i) {
                result.append(DiffLine(text: line, type: .added))
            } else {
                result.append(DiffLine(text: line, type: .context))
            }
        }

        return result
    }

    // MARK: - Private

    private func historyDirectory(for noteURL: URL) -> String {
        let vaultURL = vaultURLForNote()
        let vaultHash = vaultURL.path.md5Hash
        let relativePath = noteURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        return "\(homeDir)/.notero/history/\(vaultHash)/\(relativePath)"
    }

    private func vaultURLForNote() -> URL {
        if let savedPath = UserDefaults.standard.string(forKey: "vaultPath") {
            return URL(fileURLWithPath: savedPath)
        }
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Notero")
    }

    private func pruneOldSnapshots(in directory: String) {
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
        let mdFiles = files.filter { $0.hasSuffix(".md") }.sorted()
        if mdFiles.count > maxSnapshots {
            let toDelete = mdFiles.prefix(mdFiles.count - maxSnapshots)
            for file in toDelete {
                try? fileManager.removeItem(atPath: "\(directory)/\(file)")
            }
        }
    }

    private func parseSnapshotDate(_ filename: String) -> Date? {
        // filename format: 2025-03-15T14-32-00Z.md
        let dateStr = String(filename.dropLast(3))
            .replacingOccurrences(of: "T", with: " ")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ssZ"
        if let date = formatter.date(from: dateStr) { return date }

        // Fallback: try ISO8601
        let iso = ISO8601DateFormatter()
        let cleaned = String(filename.dropLast(3))
            .replacingOccurrences(of: "-", with: ":")
        return iso.date(from: cleaned)
    }
}

// MARK: - Models

struct NoteSnapshot: Identifiable {
    let id = UUID()
    let filename: String
    let date: Date
    let content: String

    var relativeTimeString: String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) minutes ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours ago" }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday at \(date.formatted(.dateTime.hour().minute()))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

struct DiffLine: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType

    enum DiffType {
        case added, removed, context
    }
}
