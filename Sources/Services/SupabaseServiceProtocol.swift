import Foundation

protocol SupabaseServiceProtocol: Actor {
    func syncNote(path: String, title: String, content: String, createdAt: Date?, config: SupabaseService.Config) async -> Bool
    func deleteNote(path: String, config: SupabaseService.Config) async -> Bool
    func renameNote(oldPath: String, newPath: String, config: SupabaseService.Config) async -> Bool
    func syncFolder(path: String, parentPath: String?, config: SupabaseService.Config) async -> Bool
    func deleteFolder(path: String, config: SupabaseService.Config) async -> Bool
    func syncFavourites(paths: [String], config: SupabaseService.Config) async -> Bool
    func updateNoteCreatedAt(path: String, createdAt: Date, config: SupabaseService.Config) async -> Bool
    func migratePathsToNFC(config: SupabaseService.Config) async
    func testConnection(config: SupabaseService.Config) async -> Bool
    func fetchAllNotes(config: SupabaseService.Config) async throws -> [[String: Any]]
    func fetchAllFolders(config: SupabaseService.Config) async throws -> [[String: Any]]
    func fetchChangedNotes(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]]
    func fetchChangedFolders(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]]
    func fetchFavourites(config: SupabaseService.Config) async throws -> [[String: Any]]
    func fetchNoteDeletions(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]]
    func fetchFolderDeletions(since: Date, config: SupabaseService.Config) async throws -> [[String: Any]]
    func shareNote(path: String, config: SupabaseService.Config) async -> String?
    func unshareNote(path: String, config: SupabaseService.Config) async -> Bool
    func fetchShareStatus(path: String, config: SupabaseService.Config) async -> (isShared: Bool, shareId: String?)
}
