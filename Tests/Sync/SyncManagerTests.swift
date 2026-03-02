@testable import Notero
import XCTest

final class SyncManagerTests: XCTestCase {
    private var tempDir: URL!
    private var mock: MockSupabaseService!
    private var syncManager: SyncManager!
    private var config: SupabaseService.Config!
    private var pendingSyncURL: URL!
    private let lastSyncKey = "SyncManagerTests_lastSync_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Resolve /var → /private/var symlink so relativePath string matching works
        tempDir = Self.resolvedURL(tempDir)

        pendingSyncURL = tempDir.appendingPathComponent("pending-sync.json")
        mock = MockSupabaseService()
        config = SupabaseService.Config(url: "https://test.supabase.co", serviceKey: "test-key", userId: "user-1")
        syncManager = SyncManager(
            supabaseService: mock,
            pendingSyncURL: pendingSyncURL,
            lastSyncTimeKey: lastSyncKey
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        super.tearDown()
    }

    private func vaultURL() -> URL { tempDir.appendingPathComponent("vault") }

    private func createVault() {
        try? FileManager.default.createDirectory(at: vaultURL(), withIntermediateDirectories: true)
    }

    private func writeLocalNote(_ relativePath: String, content: String, modDate: Date? = nil) {
        let path = relativePath.hasSuffix(".md") ? relativePath : relativePath + ".md"
        let fileURL = vaultURL().appendingPathComponent(path)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        if let modDate {
            try? FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
        }
    }

    private func readLocalNote(_ relativePath: String) -> String? {
        let path = relativePath.hasSuffix(".md") ? relativePath : relativePath + ".md"
        let fileURL = vaultURL().appendingPathComponent(path)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    private func localNoteExists(_ relativePath: String) -> Bool {
        let path = relativePath.hasSuffix(".md") ? relativePath : relativePath + ".md"
        return FileManager.default.fileExists(atPath: vaultURL().appendingPathComponent(path).path)
    }

    private func localFolderExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: vaultURL().appendingPathComponent(relativePath).path)
    }

    /// Resolves /var → /private/var symlink via realpath so path string matching works
    private static func resolvedURL(_ url: URL) -> URL {
        if let rp = realpath(url.path, nil) {
            let resolved = URL(fileURLWithPath: String(cString: rp))
            free(rp)
            return resolved
        }
        return url
    }

    // MARK: - A. Initial Sync (performStartupSync)

    func testA1_remoteNotesDownloadedLocally() async {
        createVault()
        await mock.addRemoteNote(path: "hello", content: "# Hello\nWorld")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertEqual(readLocalNote("hello"), "# Hello\nWorld")
    }

    func testA2_remoteFoldersCreatedLocally() async {
        createVault()
        await mock.addRemoteFolder(path: "notes/journal")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertTrue(localFolderExists("notes/journal"))
    }

    func testA3_localOnlyNotesPushedToRemote() async {
        createVault()
        writeLocalNote("local-only", content: "# Local\nContent")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let calls = await mock.syncNoteCalls
        XCTAssertTrue(calls.contains(where: { $0.path == "local-only" }), "Local-only note should be pushed. Paths: \(calls.map(\.path))")
    }

    func testA4_localNewerFileNotOverwritten() async {
        createVault()
        let futureDate = Date().addingTimeInterval(3600)
        writeLocalNote("note1", content: "local version", modDate: futureDate)
        let pastDate = Date().addingTimeInterval(-3600)
        await mock.addRemoteNote(path: "note1", content: "remote version", updatedAt: pastDate)

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertEqual(readLocalNote("note1"), "local version")
    }

    func testA5_remoteNewerFileOverwritesLocal() async {
        createVault()
        let pastDate = Date().addingTimeInterval(-3600)
        writeLocalNote("note1", content: "old local", modDate: pastDate)
        let futureDate = Date().addingTimeInterval(3600)
        await mock.addRemoteNote(path: "note1", content: "new remote", updatedAt: futureDate)

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertEqual(readLocalNote("note1"), "new remote")
    }

    func testA6_pendingLocalDeletionDeletesFromRemote() async {
        createVault()
        await mock.addRemoteNote(path: "deleted-note", content: "should be deleted")

        var state = PendingSyncState()
        state.pendingDeletionPaths.insert("deleted-note")
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: pendingSyncURL)

        syncManager = SyncManager(
            supabaseService: mock,
            pendingSyncURL: pendingSyncURL,
            lastSyncTimeKey: lastSyncKey
        )

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let deleteCalls = await mock.deleteNoteCalls
        XCTAssertTrue(deleteCalls.contains("deleted-note"))
        XCTAssertFalse(localNoteExists("deleted-note"))
    }

    func testA7_pendingFolderDeletionDeletesFromRemote() async {
        createVault()
        await mock.addRemoteFolder(path: "deleted-folder")

        var state = PendingSyncState()
        state.pendingFolderDeletionPaths.insert("deleted-folder")
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: pendingSyncURL)

        syncManager = SyncManager(
            supabaseService: mock,
            pendingSyncURL: pendingSyncURL,
            lastSyncTimeKey: lastSyncKey
        )

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let deleteCalls = await mock.deleteFolderCalls
        XCTAssertTrue(deleteCalls.contains("deleted-folder"))
    }

    func testA8_startupSyncReturnsFavourites() async {
        createVault()
        await mock.setFavourites(paths: ["note1.md", "note2.md"])

        let favs = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertEqual(favs, ["note1.md", "note2.md"])
    }

    // MARK: - B. Incremental Sync (performPullSync)

    func testB1_newRemoteNotesWrittenToDisk() async {
        createVault()
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        // Use future timestamp to ensure it's after lastSyncTime
        let future = Date().addingTimeInterval(1)
        await mock.addRemoteNote(path: "new-note", content: "# New\nContent", updatedAt: future)

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        XCTAssertEqual(readLocalNote("new-note"), "# New\nContent")
    }

    func testB2_editedNoteSkipped() async {
        createVault()
        writeLocalNote("editing", content: "original")
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let future = Date().addingTimeInterval(1)
        await mock.addRemoteNote(path: "editing", content: "remote update", updatedAt: future)

        _ = await syncManager.triggerPull(
            config: config, vaultURL: vaultURL(),
            editingPaths: Set(["editing"])
        )

        XCTAssertEqual(readLocalNote("editing"), "original")
    }

    func testB3_noteTombstoneDeletesLocalFile() async {
        createVault()
        writeLocalNote("to-delete", content: "will be deleted")
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let future = Date().addingTimeInterval(1)
        await mock.addNoteDeletion(path: "to-delete", deletedAt: future)

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        XCTAssertFalse(localNoteExists("to-delete"))
    }

    func testB4_folderTombstonesDeletedDepthFirst() async {
        createVault()
        let nestedPath = vaultURL().appendingPathComponent("a/b/c")
        try? FileManager.default.createDirectory(at: nestedPath, withIntermediateDirectories: true)
        writeLocalNote("a/b/c/note", content: "deep")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let future = Date().addingTimeInterval(1)
        await mock.addFolderDeletion(path: "a/b/c", deletedAt: future)
        await mock.addFolderDeletion(path: "a/b", deletedAt: future)

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        XCTAssertFalse(localFolderExists("a/b/c"))
        XCTAssertFalse(localFolderExists("a/b"))
    }

    func testB5_newRemoteFoldersCreated() async {
        createVault()
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await mock.addRemoteFolder(path: "new-folder")

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        XCTAssertTrue(localFolderExists("new-folder"))
    }

    func testB6_localNewerFileNotOverwrittenInIncremental() async {
        createVault()
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let futureDate = Date().addingTimeInterval(3600)
        writeLocalNote("local-newer", content: "local version", modDate: futureDate)
        // Remote updated_at must be after lastSyncTime to be fetched, but before local modDate
        let remoteDate = Date().addingTimeInterval(1)
        await mock.addRemoteNote(path: "local-newer", content: "remote version", updatedAt: remoteDate)

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        XCTAssertEqual(readLocalNote("local-newer"), "local version")
    }

    // MARK: - C. Pull Guard

    func testC1_recentlyPulledNoteSuppressesPush() async {
        createVault()
        await mock.addRemoteNote(path: "pulled-note", content: "content")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let noteURL = vaultURL().appendingPathComponent("pulled-note.md")
        let suppressed = await syncManager.shouldSuppressPush(for: noteURL, vaultURL: vaultURL())
        XCTAssertTrue(suppressed)
    }

    func testC2_guardExpiresAfterWindow() async {
        createVault()
        await mock.addRemoteNote(path: "old-pull", content: "content")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let pulledPaths = await syncManager.testingGetRecentlyPulledPaths()
        XCTAssertTrue(pulledPaths.keys.contains("old-pull"))

        // The guard is 10s, so immediately it should still be active
        let noteURL = vaultURL().appendingPathComponent("old-pull.md")
        let suppressed = await syncManager.shouldSuppressPush(for: noteURL, vaultURL: vaultURL())
        XCTAssertTrue(suppressed)
    }

    func testC3_guardOnlyAffectsSpecificPath() async {
        createVault()
        await mock.addRemoteNote(path: "pulled-note", content: "content")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let otherURL = vaultURL().appendingPathComponent("other-note.md")
        let suppressed = await syncManager.shouldSuppressPush(for: otherURL, vaultURL: vaultURL())
        XCTAssertFalse(suppressed)
    }

    // MARK: - H. Robustness

    func testH1_isSyncingGuardPreventsDuplicateSync() async {
        createVault()
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let fetchCalls = await mock.fetchAllNotesCalls
        XCTAssertEqual(fetchCalls, 1, "Should have synced exactly once")
    }

    func testH2_emptyVaultStartupSucceeds() async {
        createVault()

        // With no favourites, result is nil — but sync still completes
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let notesCalls = await mock.fetchAllNotesCalls
        XCTAssertEqual(notesCalls, 1)
    }

    func testH3_emptyRemoteLocalFilesPushed() async {
        createVault()
        writeLocalNote("a", content: "aaa")
        writeLocalNote("b", content: "bbb")
        writeLocalNote("c", content: "ccc")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let calls = await mock.syncNoteCalls
        let paths = Set(calls.map(\.path))
        XCTAssertTrue(paths.contains("a"), "Expected 'a' in pushed paths: \(paths)")
        XCTAssertTrue(paths.contains("b"), "Expected 'b' in pushed paths: \(paths)")
        XCTAssertTrue(paths.contains("c"), "Expected 'c' in pushed paths: \(paths)")
    }

    // MARK: - I. Deletion Bug Fixes

    func testI1_startupSyncRetriesDirtyPaths() async {
        createVault()
        writeLocalNote("dirty-note", content: "updated content")
        await mock.addRemoteNote(path: "dirty-note", content: "old content")

        // Write dirty state to disk
        var state = PendingSyncState()
        state.dirtyNotePaths.insert("dirty-note")
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: pendingSyncURL)

        syncManager = SyncManager(
            supabaseService: mock,
            pendingSyncURL: pendingSyncURL,
            lastSyncTimeKey: lastSyncKey
        )

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let syncCalls = await mock.syncNoteCalls
        XCTAssertTrue(syncCalls.contains(where: { $0.path == "dirty-note" }),
                       "Dirty note should be retried during startup sync")
        let pending = await syncManager.testingGetPendingSync()
        XCTAssertFalse(pending.dirtyNotePaths.contains("dirty-note"),
                        "Dirty path should be cleared after successful retry")
    }

    func testI2_dirtyDeletedNoteNotRestoredDuringInitialSync() async {
        createVault()
        // Note exists on remote but not locally, and is in dirtyNotePaths
        await mock.addRemoteNote(path: "gone-note", content: "should not restore")

        var state = PendingSyncState()
        state.dirtyNotePaths.insert("gone-note")
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: pendingSyncURL)

        syncManager = SyncManager(
            supabaseService: mock,
            pendingSyncURL: pendingSyncURL,
            lastSyncTimeKey: lastSyncKey
        )

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        // Note should NOT be written locally
        XCTAssertFalse(localNoteExists("gone-note"),
                        "Dirty-deleted note should not be restored from remote")
        // deleteNote should have been called
        let deleteCalls = await mock.deleteNoteCalls
        XCTAssertTrue(deleteCalls.contains("gone-note"),
                       "Should attempt to delete dirty note from Supabase")
    }

    func testI3_deleteNoteReturnsFalseWhenNotOnRemote() async {
        createVault()
        // Note does NOT exist in mock's notes dict
        let result = await mock.deleteNote(path: "nonexistent", config: config)
        XCTAssertFalse(result, "deleteNote should return false when no rows were deleted")
    }

    func testI4_deleteFolderReturnsFalseWhenNotOnRemote() async {
        createVault()
        let result = await mock.deleteFolder(path: "nonexistent-folder", config: config)
        XCTAssertFalse(result, "deleteFolder should return false when no rows were deleted")
    }
}
