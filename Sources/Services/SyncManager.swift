import Foundation

actor SyncManager {
    private let supabaseService: SupabaseService
    private var recentlyPulledPaths: [String: Date] = [:]
    private var lastSyncTime: Date
    private var isSyncing = false
    private var pollTask: Task<Void, Never>?

    private static let pullGuardWindow: TimeInterval = 5
    private static let pollInterval: UInt64 = 30_000_000_000 // 30s

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
        let saved = UserDefaults.standard.double(forKey: "lastSupabaseSyncTime")
        self.lastSyncTime = saved > 0 ? Date(timeIntervalSince1970: saved) : .distantPast
    }

    // MARK: - Polling

    func startPolling(
        configProvider: @Sendable @escaping () async -> SupabaseService.Config?,
        vaultURLProvider: @Sendable @escaping () async -> URL,
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
                let favPaths = await self.performPullSync(config: config, vaultURL: vaultURL)
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

    private func performPullSync(config: SupabaseService.Config, vaultURL: URL) async -> [String]? {
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let favPaths: [String]?
            if lastSyncTime == .distantPast {
                try await performInitialSync(config: config, vaultURL: vaultURL)
                favPaths = try await fetchRemoteFavourites(config: config)
            } else {
                try await performIncrementalSync(since: lastSyncTime, config: config, vaultURL: vaultURL)
                favPaths = try await fetchRemoteFavourites(config: config)
            }
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime.timeIntervalSince1970, forKey: "lastSupabaseSyncTime")
            cleanupExpiredGuards()
            return favPaths
        } catch {
            Log.sync.warning("Pull sync failed: \(error)")
            return nil
        }
    }

    // MARK: - Initial Sync

    private func performInitialSync(config: SupabaseService.Config, vaultURL: URL) async throws {
        Log.sync.info("Performing initial sync")

        let folders = try await supabaseService.fetchAllFolders(config: config)
        for folder in folders {
            guard let path = folder["path"] as? String else { continue }
            ensureLocalFolder(path: path, vaultURL: vaultURL)
        }

        let notes = try await supabaseService.fetchAllNotes(config: config)
        for note in notes {
            guard let path = note["path"] as? String,
                  let content = note["content"] as? String else { continue }
            let fileURL = vaultURL.appendingPathComponent(path + ".md")
            // Initial sync: don't overwrite existing local files
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            writeRemoteNote(content: content, to: fileURL, relativePath: path)
        }

        Log.sync.info("Initial sync done: \(folders.count) folders, \(notes.count) notes")
    }

    // MARK: - Incremental Sync

    private func performIncrementalSync(since: Date, config: SupabaseService.Config, vaultURL: URL) async throws {
        let folders = try await supabaseService.fetchChangedFolders(since: since, config: config)
        for folder in folders {
            guard let path = folder["path"] as? String else { continue }
            ensureLocalFolder(path: path, vaultURL: vaultURL)
        }

        let notes = try await supabaseService.fetchChangedNotes(since: since, config: config)
        for note in notes {
            processRemoteNote(note, vaultURL: vaultURL)
        }

        if !folders.isEmpty || !notes.isEmpty {
            Log.sync.info("Incremental sync: \(folders.count) folders, \(notes.count) notes")
        }
    }

    // MARK: - Note Processing

    private func processRemoteNote(_ note: [String: Any], vaultURL: URL) {
        guard let path = note["path"] as? String,
              let content = note["content"] as? String,
              let updatedAtStr = note["updated_at"] as? String else { return }

        let fileURL = vaultURL.appendingPathComponent(path + ".md")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            writeRemoteNote(content: content, to: fileURL, relativePath: path)
            return
        }

        // Conflict resolution: compare remote updated_at vs local mtime
        guard let remoteDate = ISO8601DateFormatter().date(from: updatedAtStr) else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let localMtime = attrs[.modificationDate] as? Date else {
            writeRemoteNote(content: content, to: fileURL, relativePath: path)
            return
        }

        if remoteDate > localMtime {
            writeRemoteNote(content: content, to: fileURL, relativePath: path)
        }
        // Local newer → skip, will be pushed by normal flow
    }

    // MARK: - File Operations

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
            guard let noteDict = row["notes"] as? [String: Any],
                  let notePath = noteDict["path"] as? String else { continue }
            paths.append(notePath + ".md")
        }
        return paths.isEmpty ? nil : paths
    }

    // MARK: - Cleanup

    private func cleanupExpiredGuards() {
        let now = Date()
        recentlyPulledPaths = recentlyPulledPaths.filter { _, date in
            now.timeIntervalSince(date) < Self.pullGuardWindow
        }
    }
}
