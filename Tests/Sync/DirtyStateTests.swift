@testable import Notero
import XCTest

final class DirtyStateTests: XCTestCase {
    private var tempDir: URL!
    private var mock: MockSupabaseService!
    private var syncManager: SyncManager!
    private var config: SupabaseService.Config!
    private var pendingSyncURL: URL!
    private let lastSyncKey = "DirtyStateTests_lastSync_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirtyTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        if let rp = realpath(tempDir.path, nil) {
            tempDir = URL(fileURLWithPath: String(cString: rp))
            free(rp)
        }

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

    private func writeLocalNote(_ relativePath: String, content: String) {
        let path = relativePath.hasSuffix(".md") ? relativePath : relativePath + ".md"
        let fileURL = vaultURL().appendingPathComponent(path)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - D. Dirty State Tests

    func testD1_markNoteDirtyPersistsToDisk() async {
        await syncManager.markNoteDirty("test/note")

        let data = try? Data(contentsOf: pendingSyncURL)
        XCTAssertNotNil(data)
        let state = try? JSONDecoder().decode(PendingSyncState.self, from: data!)
        XCTAssertNotNil(state)
        XCTAssertTrue(state!.dirtyNotePaths.contains("test/note"))
    }

    func testD2_dirtyNoteRetriedOnPull() async {
        createVault()
        writeLocalNote("dirty-note", content: "# Dirty\nContent")

        // Do initial sync to set lastSyncTime
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        // Mark dirty
        await syncManager.markNoteDirty("dirty-note")

        // Reset mock call tracking
        await mock.resetSyncNoteCalls()

        // Trigger pull — should retry dirty note
        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        let calls = await mock.syncNoteCalls
        XCTAssertTrue(calls.contains(where: { $0.path == "dirty-note" }))

        // After successful retry, note should no longer be dirty
        let pending = await syncManager.testingGetPendingSync()
        XCTAssertFalse(pending.dirtyNotePaths.contains("dirty-note"))
    }

    func testD3_dirtyNoteForDeletedFileCallsDelete() async {
        createVault()
        // Don't create the file — simulates it was deleted

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await syncManager.markNoteDirty("gone-note")

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        let deleteCalls = await mock.deleteNoteCalls
        XCTAssertTrue(deleteCalls.contains("gone-note"))
    }

    func testD4_dirtyFolderRetried() async {
        createVault()
        let folderURL = vaultURL().appendingPathComponent("dirty-folder")
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await syncManager.markFolderDirty("dirty-folder")

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        let calls = await mock.syncFolderCalls
        XCTAssertTrue(calls.contains(where: { $0.path == "dirty-folder" }))
    }

    func testD5_dirtyFavouritesRetried() async {
        createVault()

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await syncManager.markFavouritesDirty()

        _ = await syncManager.triggerPull(
            config: config, vaultURL: vaultURL(),
            favourites: ["fav1.md", "fav2.md"]
        )

        let calls = await mock.syncFavouritesCalls
        XCTAssertTrue(calls.contains(where: { $0 == ["fav1.md", "fav2.md"] }))

        let pending = await syncManager.testingGetPendingSync()
        XCTAssertFalse(pending.favouritesDirty)
    }

    func testD6_failedRetryKeepsDirtyState() async {
        createVault()
        writeLocalNote("fail-note", content: "content")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await syncManager.markNoteDirty("fail-note")
        await mock.setShouldFail(true)

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        let pending = await syncManager.testingGetPendingSync()
        XCTAssertTrue(pending.dirtyNotePaths.contains("fail-note"))
    }

    func testD7_pendingSyncSurvivesRestart() async {
        await syncManager.markNoteDirty("persist-note")
        await syncManager.markFolderDirty("persist-folder")
        await syncManager.markFavouritesDirty()

        // Create new SyncManager loading from same file
        let newManager = SyncManager(
            supabaseService: mock,
            pendingSyncURL: pendingSyncURL,
            lastSyncTimeKey: lastSyncKey
        )

        let pending = await newManager.testingGetPendingSync()
        XCTAssertTrue(pending.dirtyNotePaths.contains("persist-note"))
        XCTAssertTrue(pending.dirtyFolderPaths.contains("persist-folder"))
        XCTAssertTrue(pending.favouritesDirty)
    }

    func testD8_multipleDirtyPathsAllRetried() async {
        createVault()
        for i in 0..<5 {
            writeLocalNote("multi-\(i)", content: "content \(i)")
        }

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        for i in 0..<5 {
            await syncManager.markNoteDirty("multi-\(i)")
        }

        await mock.resetSyncNoteCalls()

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        let calls = await mock.syncNoteCalls
        let retriedPaths = Set(calls.map(\.path))
        for i in 0..<5 {
            XCTAssertTrue(retriedPaths.contains("multi-\(i)"), "multi-\(i) should have been retried")
        }
    }
}

// MARK: - Mock helpers for tests

extension MockSupabaseService {
    func resetSyncNoteCalls() {
        syncNoteCalls = []
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
}
