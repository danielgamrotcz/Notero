@testable import Notero
import Foundation

actor MockSupabaseService: SupabaseServiceProtocol {
    // In-memory storage
    var notes: [String: [String: Any]] = [:]       // path → note dict
    var folders: [String: [String: Any]] = [:]     // path → folder dict
    var favourites: [[String: Any]] = []
    var noteDeletions: [[String: Any]] = []
    var folderDeletions: [[String: Any]] = []

    // Call tracking
    var syncNoteCalls: [(path: String, title: String, content: String, createdAt: Date?)] = []
    var deleteNoteCalls: [String] = []
    var renameNoteCalls: [(oldPath: String, newPath: String)] = []
    var syncFolderCalls: [(path: String, parentPath: String?)] = []
    var deleteFolderCalls: [String] = []
    var syncFavouritesCalls: [[String]] = []
    var updateNoteCreatedAtCalls: [(path: String, createdAt: Date)] = []
    var testConnectionCalls: Int = 0
    var fetchAllNotesCalls: Int = 0
    var fetchAllFoldersCalls: Int = 0
    var fetchChangedNotesCalls: [Date] = []
    var fetchChangedFoldersCalls: [Date] = []
    var fetchFavouritesCalls: Int = 0
    var fetchNoteDeletionsCalls: [Date] = []
    var fetchFolderDeletionsCalls: [Date] = []

    // Failure simulation
    var shouldFail = false

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - SupabaseServiceProtocol

    func syncNote(path: String, title: String, content: String, createdAt: Date?, config: SupabaseService.Config) async -> Bool {
        syncNoteCalls.append((path, title, content, createdAt))
        guard !shouldFail else { return false }
        let now = Self.iso8601.string(from: Date())
        notes[path] = [
            "id": UUID().uuidString,
            "path": path,
            "title": title,
            "content": content,
            "updated_at": now,
            "user_id": config.userId,
        ]
        return true
    }

    func deleteNote(path: String, config: SupabaseService.Config) async -> Bool {
        deleteNoteCalls.append(path)
        guard !shouldFail else { return false }
        if notes.removeValue(forKey: path) != nil {
            let now = Self.iso8601.string(from: Date())
            noteDeletions.append([
                "path": path,
                "deleted_at": now,
                "user_id": config.userId,
            ])
            return true
        }
        return false
    }

    func renameNote(oldPath: String, newPath: String, config: SupabaseService.Config) async -> Bool {
        renameNoteCalls.append((oldPath, newPath))
        guard !shouldFail else { return false }
        if var note = notes.removeValue(forKey: oldPath) {
            note["path"] = newPath
            note["updated_at"] = Self.iso8601.string(from: Date())
            notes[newPath] = note
        }
        return true
    }

    func syncFolder(path: String, parentPath: String?, config: SupabaseService.Config) async -> Bool {
        syncFolderCalls.append((path, parentPath))
        guard !shouldFail else { return false }
        folders[path] = [
            "id": UUID().uuidString,
            "path": path,
            "name": (path as NSString).lastPathComponent,
            "user_id": config.userId,
        ]
        return true
    }

    func deleteFolder(path: String, config: SupabaseService.Config) async -> Bool {
        deleteFolderCalls.append(path)
        guard !shouldFail else { return false }
        if folders.removeValue(forKey: path) != nil {
            let now = Self.iso8601.string(from: Date())
            folderDeletions.append([
                "path": path,
                "deleted_at": now,
                "user_id": config.userId,
            ])
            return true
        }
        return false
    }

    func syncFavourites(paths: [String], config: SupabaseService.Config) async -> Bool {
        syncFavouritesCalls.append(paths)
        guard !shouldFail else { return false }
        favourites = paths.enumerated().map { index, path in
            let pathWithoutMd = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
            let noteId = notes[pathWithoutMd]?["id"] as? String ?? UUID().uuidString
            return [
                "note_id": noteId,
                "sort_order": index,
                "notes": ["path": pathWithoutMd],
            ] as [String: Any]
        }
        return true
    }

    func updateNoteCreatedAt(path: String, createdAt: Date, config: SupabaseService.Config) async -> Bool {
        updateNoteCreatedAtCalls.append((path, createdAt))
        guard !shouldFail else { return false }
        return true
    }

    func testConnection(config: SupabaseService.Config) async -> Bool {
        testConnectionCalls += 1
        return !shouldFail
    }

    func fetchAllNotes(config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchAllNotesCalls += 1
        if shouldFail { throw URLError(.badServerResponse) }
        return Array(notes.values)
    }

    func fetchAllFolders(config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchAllFoldersCalls += 1
        if shouldFail { throw URLError(.badServerResponse) }
        return Array(folders.values)
    }

    func fetchChangedNotes(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchChangedNotesCalls.append(since)
        if shouldFail { throw URLError(.badServerResponse) }
        let sinceStr = Self.iso8601.string(from: since)
        return notes.values.filter { note in
            guard let ts = note["updated_at"] as? String else { return false }
            return ts > sinceStr
        }
    }

    func fetchChangedFolders(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchChangedFoldersCalls.append(since)
        if shouldFail { throw URLError(.badServerResponse) }
        return Array(folders.values)
    }

    func fetchFavourites(config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchFavouritesCalls += 1
        if shouldFail { throw URLError(.badServerResponse) }
        return favourites
    }

    func fetchNoteDeletions(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchNoteDeletionsCalls.append(since)
        if shouldFail { throw URLError(.badServerResponse) }
        let sinceStr = Self.iso8601.string(from: since)
        return noteDeletions.filter { del in
            guard let ts = del["deleted_at"] as? String else { return false }
            return ts > sinceStr
        }
    }

    func fetchFolderDeletions(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]] {
        fetchFolderDeletionsCalls.append(since)
        if shouldFail { throw URLError(.badServerResponse) }
        let sinceStr = Self.iso8601.string(from: since)
        return folderDeletions.filter { del in
            guard let ts = del["deleted_at"] as? String else { return false }
            return ts > sinceStr
        }
    }

    // MARK: - Test Helpers

    func addRemoteNote(path: String, content: String, updatedAt: Date = Date()) {
        notes[path] = [
            "id": UUID().uuidString,
            "path": path,
            "title": SupabaseService.extractTitle(from: content, filename: (path as NSString).lastPathComponent + ".md"),
            "content": content,
            "updated_at": Self.iso8601.string(from: updatedAt),
        ]
    }

    func addRemoteFolder(path: String) {
        folders[path] = [
            "id": UUID().uuidString,
            "path": path,
            "name": (path as NSString).lastPathComponent,
        ]
    }

    func addNoteDeletion(path: String, deletedAt: Date = Date()) {
        noteDeletions.append([
            "path": path,
            "deleted_at": Self.iso8601.string(from: deletedAt),
        ])
    }

    func addFolderDeletion(path: String, deletedAt: Date = Date()) {
        folderDeletions.append([
            "path": path,
            "deleted_at": Self.iso8601.string(from: deletedAt),
        ])
    }

    func setFavourites(paths: [String]) {
        favourites = paths.enumerated().map { index, path in
            let pathWithoutMd = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
            return [
                "note_id": UUID().uuidString,
                "sort_order": index,
                "notes": ["path": pathWithoutMd],
            ] as [String: Any]
        }
    }
}
