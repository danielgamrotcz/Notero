import Foundation

struct PendingSyncState: Codable {
    var dirtyNotePaths: Set<String> = []
    var dirtyFolderPaths: Set<String> = []
    var favouritesDirty: Bool = false
    var pendingDeletionPaths: Set<String> = []
    var pendingFolderDeletionPaths: Set<String> = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dirtyNotePaths = (try? container.decode(Set<String>.self, forKey: .dirtyNotePaths)) ?? []
        dirtyFolderPaths = (try? container.decode(Set<String>.self, forKey: .dirtyFolderPaths)) ?? []
        favouritesDirty = (try? container.decode(Bool.self, forKey: .favouritesDirty)) ?? false
        pendingDeletionPaths = (try? container.decode(Set<String>.self, forKey: .pendingDeletionPaths)) ?? []
        pendingFolderDeletionPaths = (try? container.decode(Set<String>.self, forKey: .pendingFolderDeletionPaths)) ?? []
    }
}

actor SyncManager {
    private let supabaseService: any SupabaseServiceProtocol
    private var recentlyPulledPaths: [String: Date] = [:]
    private var lastSyncTime: Date
    private var isSyncing = false
    private var pollTask: Task<Void, Never>?
    private var pendingSync = PendingSyncState()

    private static let pullGuardWindow: TimeInterval = 10
    private static let pollInterval: UInt64 = 30_000_000_000 // 30s
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let defaultPendingSyncURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notero/pending-sync.json")
    }()
    let pendingSyncURL: URL
    private let lastSyncTimeKey: String

    init(
        supabaseService: any SupabaseServiceProtocol,
        pendingSyncURL: URL? = nil,
        lastSyncTimeKey: String = "lastSupabaseSyncTime"
    ) {
        self.supabaseService = supabaseService
        self.lastSyncTimeKey = lastSyncTimeKey
        self.pendingSyncURL = pendingSyncURL ?? Self.defaultPendingSyncURL
        let saved = UserDefaults.standard.double(forKey: lastSyncTimeKey)
        self.lastSyncTime = saved > 0 ? Date(timeIntervalSince1970: saved) : .distantPast
        self.pendingSync = Self.loadPendingSync(from: self.pendingSyncURL)
    }

    // MARK: - Dirty State Management

    func markNoteDirty(_ path: String) {
        pendingSync.dirtyNotePaths.insert(path)
        savePendingSync()
        Log.sync.debug("Marked note dirty: \(path)")
    }

    func markFolderDirty(_ path: String) {
        pendingSync.dirtyFolderPaths.insert(path)
        savePendingSync()
        Log.sync.debug("Marked folder dirty: \(path)")
    }

    func markFavouritesDirty() {
        pendingSync.favouritesDirty = true
        savePendingSync()
        Log.sync.debug("Marked favourites dirty")
    }

    func markLocallyDeleted(_ path: String) {
        pendingSync.pendingDeletionPaths.insert(path)
        savePendingSync()
        Log.sync.debug("Marked note locally deleted: \(path)")
    }

    func markFolderLocallyDeleted(_ path: String) {
        pendingSync.pendingFolderDeletionPaths.insert(path)
        savePendingSync()
        Log.sync.debug("Marked folder locally deleted: \(path)")
    }

    func clearLocallyDeleted(_ path: String) {
        pendingSync.pendingDeletionPaths.remove(path)
        savePendingSync()
    }

    func clearFolderLocallyDeleted(_ path: String) {
        pendingSync.pendingFolderDeletionPaths.remove(path)
        savePendingSync()
    }

    func clearAllDirtyPaths() {
        pendingSync.dirtyNotePaths.removeAll()
        pendingSync.dirtyFolderPaths.removeAll()
        savePendingSync()
        Log.sync.info("Cleared all dirty paths")
    }

    // MARK: - Startup Sync

    func performStartupSync(config: SupabaseService.Config, vaultURL: URL, favourites: [String] = []) async -> [String]? {
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        await retryDirtyPaths(config: config, vaultURL: vaultURL, favourites: favourites)

        do {
            try await performInitialSync(config: config, vaultURL: vaultURL)
            let favPaths = try await fetchRemoteFavourites(config: config)
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime.timeIntervalSince1970, forKey: lastSyncTimeKey)
            return favPaths
        } catch {
            Log.sync.warning("Startup sync failed: \(error)")
            return nil
        }
    }

    // MARK: - Polling

    func startPolling(
        configProvider: @Sendable @escaping () async -> SupabaseService.Config?,
        vaultURLProvider: @Sendable @escaping () async -> URL,
        editingPathsProvider: @Sendable @escaping () async -> Set<String>,
        favouritesProvider: @Sendable @escaping () async -> [String],
        onPullComplete: @Sendable @escaping ([String]?) async -> Void
    ) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                guard !Task.isCancelled else { break }
                guard let self else { break }

                guard let config = await configProvider() else { continue }
                let vaultURL = await vaultURLProvider()
                let editingPaths = await editingPathsProvider()
                let favourites = await favouritesProvider()
                let favPaths = await self.performPullSync(
                    config: config, vaultURL: vaultURL,
                    editingPaths: editingPaths, favourites: favourites
                )
                await onPullComplete(favPaths)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Push Guard

    func shouldSuppressPush(for url: URL, vaultURL: URL) -> Bool {
        let path = SupabaseService.relativePath(for: url, vaultURL: vaultURL)
        guard let pulledAt = recentlyPulledPaths[path] else { return false }
        return Date().timeIntervalSince(pulledAt) < Self.pullGuardWindow
    }

    // MARK: - Pull Sync

    private func performPullSync(
        config: SupabaseService.Config,
        vaultURL: URL,
        editingPaths: Set<String>,
        favourites: [String]
    ) async -> [String]? {
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        // Retry dirty paths before pulling
        await retryDirtyPaths(config: config, vaultURL: vaultURL, favourites: favourites)

        do {
            let favPaths: [String]?
            if lastSyncTime == .distantPast {
                try await performInitialSync(config: config, vaultURL: vaultURL)
                favPaths = try await fetchRemoteFavourites(config: config)
            } else {
                try await performIncrementalSync(
                    since: lastSyncTime, config: config,
                    vaultURL: vaultURL, editingPaths: editingPaths
                )
                favPaths = try await fetchRemoteFavourites(config: config)
            }
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime.timeIntervalSince1970, forKey: lastSyncTimeKey)
            cleanupExpiredGuards()
            return favPaths
        } catch {
            Log.sync.warning("Pull sync failed: \(error)")
            return nil
        }
    }

    // MARK: - Retry Dirty Paths

    private func retryDirtyPaths(
        config: SupabaseService.Config,
        vaultURL: URL,
        favourites: [String]
    ) async {
        guard !pendingSync.dirtyNotePaths.isEmpty
            || !pendingSync.dirtyFolderPaths.isEmpty
            || pendingSync.favouritesDirty else { return }

        let noteCount = pendingSync.dirtyNotePaths.count
        let folderCount = pendingSync.dirtyFolderPaths.count
        let favsDirty = pendingSync.favouritesDirty
        Log.sync.info("Retrying dirty paths: \(noteCount) notes, \(folderCount) folders, favs=\(favsDirty)")

        // Retry dirty notes
        for path in pendingSync.dirtyNotePaths {
            let fileURL = vaultURL.appendingPathComponent(path + ".md")
            let success: Bool
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                let title = SupabaseService.extractTitle(from: content, filename: fileURL.lastPathComponent)
                let createdAt = SupabaseService.fileCreationDate(for: fileURL)
                success = await supabaseService.syncNote(path: path, title: title, content: content, createdAt: createdAt, config: config)
            } else {
                success = await supabaseService.deleteNote(path: path, config: config)
            }
            if success {
                pendingSync.dirtyNotePaths.remove(path)
                pendingSync.pendingDeletionPaths.remove(path)
            }
        }

        // Retry dirty folders
        for path in pendingSync.dirtyFolderPaths {
            let folderURL = vaultURL.appendingPathComponent(path)
            let success: Bool
            if FileManager.default.fileExists(atPath: folderURL.path) {
                success = await supabaseService.syncFolder(path: path, parentPath: nil, config: config)
            } else {
                success = await supabaseService.deleteFolder(path: path, config: config)
            }
            if success {
                pendingSync.dirtyFolderPaths.remove(path)
                pendingSync.pendingFolderDeletionPaths.remove(path)
            }
        }

        // Retry dirty favourites
        if pendingSync.favouritesDirty {
            let success = await supabaseService.syncFavourites(paths: favourites, config: config)
            if success {
                pendingSync.favouritesDirty = false
            }
        }

        savePendingSync()
    }

    // MARK: - Initial Sync

    private func performInitialSync(config: SupabaseService.Config, vaultURL: URL) async throws {
        Log.sync.info("Performing initial sync (Supabase-first)")

        let folders = try await supabaseService.fetchAllFolders(config: config)
        for folder in folders {
            guard let path = folder["path"] as? String else { continue }
            if pendingSync.pendingFolderDeletionPaths.contains(path) {
                let ok = await supabaseService.deleteFolder(path: path, config: config)
                if ok {
                    pendingSync.pendingFolderDeletionPaths.remove(path)
                    Log.sync.info("Completed pending folder deletion from Supabase: \(path)")
                }
                continue
            }
            ensureLocalFolder(path: path, vaultURL: vaultURL)
        }

        let notes = try await supabaseService.fetchAllNotes(config: config)
        var remotePaths = Set<String>()
        for note in notes {
            guard let path = note["path"] as? String,
                  let content = note["content"] as? String else { continue }
            remotePaths.insert(path)

            // If locally deleted, complete the deletion from Supabase instead of restoring
            if pendingSync.pendingDeletionPaths.contains(path) {
                let ok = await supabaseService.deleteNote(path: path, config: config)
                if ok {
                    pendingSync.pendingDeletionPaths.remove(path)
                    Log.sync.info("Completed pending deletion from Supabase: \(path)")
                }
                continue
            }

            // If in dirty paths and local file doesn't exist, treat as pending deletion
            let fileURL = vaultURL.appendingPathComponent(path + ".md")
            if pendingSync.dirtyNotePaths.contains(path) && !FileManager.default.fileExists(atPath: fileURL.path) {
                let ok = await supabaseService.deleteNote(path: path, config: config)
                if ok {
                    pendingSync.dirtyNotePaths.remove(path)
                    Log.sync.info("Completed dirty deletion from Supabase: \(path)")
                }
                continue
            }
            guard shouldWriteRemote(note: note, to: fileURL) else {
                Log.sync.debug("Skipped initial sync write (local newer): \(path)")
                continue
            }
            writeRemoteNote(content: content, to: fileURL, relativePath: path)
        }

        // Push local-only files to Supabase
        let localFiles = scanLocalMarkdownFiles(vaultURL: vaultURL)
        for localFile in localFiles {
            let relativePath = SupabaseService.relativePath(for: localFile, vaultURL: vaultURL)
            if !remotePaths.contains(relativePath) {
                let content = (try? String(contentsOf: localFile, encoding: .utf8)) ?? ""
                let title = SupabaseService.extractTitle(from: content, filename: localFile.lastPathComponent)
                let createdAt = SupabaseService.fileCreationDate(for: localFile)
                await supabaseService.syncNote(path: relativePath, title: title, content: content, createdAt: createdAt, config: config)
                Log.sync.debug("Pushed local-only note: \(relativePath)")
            }
        }

        savePendingSync()
        Log.sync.info("Initial sync done: \(folders.count) folders, \(notes.count) notes, pushed \(localFiles.count - remotePaths.count) local-only")
    }

    // MARK: - Incremental Sync

    private func performIncrementalSync(
        since: Date,
        config: SupabaseService.Config,
        vaultURL: URL,
        editingPaths: Set<String>
    ) async throws {
        let folders = try await supabaseService.fetchChangedFolders(since: since, config: config)
        for folder in folders {
            guard let path = folder["path"] as? String else { continue }
            ensureLocalFolder(path: path, vaultURL: vaultURL)
        }

        let notes = try await supabaseService.fetchChangedNotes(since: since, config: config)
        for note in notes {
            processRemoteNote(note, vaultURL: vaultURL, editingPaths: editingPaths)
        }

        // Process tombstones — delete local files for remotely deleted items
        let noteDeletions = try await supabaseService.fetchNoteDeletions(since: since, config: config)
        for deletion in noteDeletions {
            guard let path = deletion["path"] as? String else { continue }
            if editingPaths.contains(path) { continue }
            let fileURL = vaultURL.appendingPathComponent(path + ".md")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
                Log.sync.info("Deleted local note from tombstone: \(path)")
            }
        }

        let folderDeletions = try await supabaseService.fetchFolderDeletions(since: since, config: config)
        // Sort by depth descending so we delete deepest folders first
        let sortedDeletions = folderDeletions
            .compactMap { $0["path"] as? String }
            .sorted { $0.components(separatedBy: "/").count > $1.components(separatedBy: "/").count }
        for path in sortedDeletions {
            let folderURL = vaultURL.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                try? FileManager.default.removeItem(at: folderURL)
                Log.sync.info("Deleted local folder from tombstone: \(path)")
            }
        }

        let totalChanges = folders.count + notes.count + noteDeletions.count + folderDeletions.count
        if totalChanges > 0 {
            Log.sync.info("Incremental sync: \(folders.count) folders, \(notes.count) notes, \(noteDeletions.count) note deletions, \(folderDeletions.count) folder deletions")
        }
    }

    // MARK: - Note Processing

    private func processRemoteNote(_ note: [String: Any], vaultURL: URL, editingPaths: Set<String>) {
        guard let path = note["path"] as? String,
              let content = note["content"] as? String else { return }
        if editingPaths.contains(path) {
            Log.sync.debug("Skipped pull for editing note: \(path)")
            return
        }
        let fileURL = vaultURL.appendingPathComponent(path + ".md")
        guard shouldWriteRemote(note: note, to: fileURL) else {
            Log.sync.debug("Skipped incremental sync write (local newer): \(path)")
            return
        }
        writeRemoteNote(content: content, to: fileURL, relativePath: path)
    }

    // MARK: - File Operations

    /// Returns true if remote note should overwrite the local file.
    /// Skips write when local file is newer than remote `updated_at`.
    private func shouldWriteRemote(note: [String: Any], to fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        guard let updatedStr = note["updated_at"] as? String,
              let remoteDate = Self.iso8601Formatter.date(from: updatedStr) else {
            return false // No remote timestamp → local is authoritative
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let localMod = attrs?[.modificationDate] as? Date else { return true }
        return remoteDate > localMod
    }

    private func writeRemoteNote(content: String, to fileURL: URL, relativePath: String) {
        recentlyPulledPaths[relativePath] = Date()
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        Log.sync.debug("Wrote remote note: \(relativePath)")
    }

    private func ensureLocalFolder(path: String, vaultURL: URL) {
        let folderURL = vaultURL.appendingPathComponent(path)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            Log.sync.debug("Created folder: \(path)")
        }
    }

    // MARK: - Favourites

    private func fetchRemoteFavourites(config: SupabaseService.Config) async throws -> [String]? {
        let rows = try await supabaseService.fetchFavourites(config: config)
        guard !rows.isEmpty else { return nil }

        var paths: [String] = []
        for row in rows {
            if let noteDict = row["notes"] as? [String: Any],
               let notePath = noteDict["path"] as? String {
                // It's a file favourite
                paths.append(notePath + ".md")
            } else if let folderPath = row["path"] as? String {
                // It's a folder favourite — no .md extension
                paths.append(folderPath)
            }
        }
        return paths.isEmpty ? nil : paths
    }

    // MARK: - Local Scan

    private func scanLocalMarkdownFiles(vaultURL: URL) -> [URL] {
        var result: [URL] = []
        collectMarkdownFiles(at: vaultURL, into: &result)
        return result
    }

    private func collectMarkdownFiles(at url: URL, into result: inout [URL]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for itemURL in contents {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                collectMarkdownFiles(at: itemURL, into: &result)
            } else if itemURL.pathExtension == "md" {
                result.append(itemURL)
            }
        }
    }

    // MARK: - Backfill Creation Dates

    func backfillCreationDates(config: SupabaseService.Config, vaultURL: URL) async {
        guard !UserDefaults.standard.bool(forKey: "creationDateBackfillDone") else { return }
        Log.sync.info("Starting creation date backfill")

        let files = scanLocalMarkdownFiles(vaultURL: vaultURL)
        var updated = 0
        for file in files {
            let path = SupabaseService.relativePath(for: file, vaultURL: vaultURL)
            guard let createdAt = SupabaseService.fileCreationDate(for: file) else { continue }
            let ok = await supabaseService.updateNoteCreatedAt(path: path, createdAt: createdAt, config: config)
            if ok { updated += 1 }
        }

        UserDefaults.standard.set(true, forKey: "creationDateBackfillDone")
        Log.sync.info("Creation date backfill done: \(updated)/\(files.count) notes updated")
    }

    // MARK: - Pending Sync Persistence

    private static func loadPendingSync(from url: URL) -> PendingSyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PendingSyncState.self, from: data) else {
            return PendingSyncState()
        }
        return state
    }

    private func savePendingSync() {
        guard let data = try? JSONEncoder().encode(pendingSync) else { return }
        let dir = pendingSyncURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: pendingSyncURL, options: .atomic)
    }

    // MARK: - Cleanup

    private func cleanupExpiredGuards() {
        let now = Date()
        recentlyPulledPaths = recentlyPulledPaths.filter { _, date in
            now.timeIntervalSince(date) < Self.pullGuardWindow
        }
    }

    // MARK: - Testing Hooks

    func triggerPull(
        config: SupabaseService.Config,
        vaultURL: URL,
        editingPaths: Set<String> = [],
        favourites: [String] = []
    ) async -> [String]? {
        return await performPullSync(
            config: config, vaultURL: vaultURL,
            editingPaths: editingPaths, favourites: favourites
        )
    }

    func testingGetPendingSync() -> PendingSyncState {
        return pendingSync
    }

    func testingSetLastSyncTime(_ date: Date) {
        lastSyncTime = date
    }

    func testingGetRecentlyPulledPaths() -> [String: Date] {
        return recentlyPulledPaths
    }

    func testingResetIsSyncing() {
        isSyncing = false
    }
}
