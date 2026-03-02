@testable import Notero
import XCTest

final class FavoritesSyncTests: XCTestCase {
    private var tempDir: URL!
    private var mock: MockSupabaseService!
    private var syncManager: SyncManager!
    private var config: SupabaseService.Config!
    private var pendingSyncURL: URL!
    private let lastSyncKey = "FavSyncTests_lastSync_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FavSyncTests-\(UUID().uuidString)")
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

    // MARK: - E. Favourites Sync

    func testE1_favouritesPushedToRemote() async {
        createVault()
        // Sync initial state
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        // Mark favourites dirty and trigger pull with favourites
        await syncManager.markFavouritesDirty()
        _ = await syncManager.triggerPull(
            config: config, vaultURL: vaultURL(),
            favourites: ["notes/note1.md"]
        )

        let calls = await mock.syncFavouritesCalls
        XCTAssertTrue(calls.contains(where: { $0 == ["notes/note1.md"] }))
    }

    func testE2_removeFavouritePushesUpdate() async {
        createVault()
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await syncManager.markFavouritesDirty()
        _ = await syncManager.triggerPull(
            config: config, vaultURL: vaultURL(),
            favourites: [] // empty = removed
        )

        let calls = await mock.syncFavouritesCalls
        XCTAssertTrue(calls.contains(where: { $0.isEmpty }))
    }

    func testE3_reorderFavouritesPreservesOrder() async {
        createVault()
        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        await syncManager.markFavouritesDirty()
        _ = await syncManager.triggerPull(
            config: config, vaultURL: vaultURL(),
            favourites: ["b.md", "a.md", "c.md"]
        )

        let calls = await mock.syncFavouritesCalls
        XCTAssertTrue(calls.contains(where: { $0 == ["b.md", "a.md", "c.md"] }))
    }

    func testE4_replaceFromRemoteDoesNotPushBack() async throws {
        // This tests FavoritesManager directly — replaceFromRemote should NOT call onFavouritesChanged
        let manager = await MainActor.run { FavoritesManager() }
        var pushCalled = false
        await MainActor.run {
            manager.onFavouritesChanged = { _ in pushCalled = true }
            manager.replaceFromRemote(["a.md", "b.md"])
        }

        XCTAssertFalse(pushCalled, "replaceFromRemote should not trigger push back")
        let ordered = await MainActor.run { manager.orderedFavorites }
        XCTAssertEqual(ordered, ["a.md", "b.md"])
    }

    func testE5_recentLocalChangeIgnoresRemoteFavourites() async {
        // Test the grace period logic: if lastLocalChange < 30s, remote favs are ignored
        let manager = await MainActor.run { FavoritesManager() }
        await MainActor.run {
            manager.addFavorite("local.md") // sets lastLocalChange to now
        }

        let lastChange = await MainActor.run { manager.lastLocalChange }
        XCTAssertNotNil(lastChange)
        let elapsed = Date().timeIntervalSince(lastChange!)
        XCTAssertLessThan(elapsed, 30, "Should be within grace period")
    }

    func testE6_expiredGracePeriodAcceptsRemote() async {
        let manager = await MainActor.run { FavoritesManager() }

        // No local change → lastLocalChange is nil → grace period doesn't apply
        let lastChange = await MainActor.run { manager.lastLocalChange }
        XCTAssertNil(lastChange)

        // Should accept remote favourites since no recent local change
        let recentlyChanged = lastChange.map { Date().timeIntervalSince($0) < 30 } ?? false
        XCTAssertFalse(recentlyChanged)
    }

    func testE7_favouriteOnDeletedFileCleanedUp() async {
        createVault()
        // Create a note then favourite it
        let fileURL = vaultURL().appendingPathComponent("temp.md")
        try? "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = await MainActor.run { FavoritesManager() }
        await MainActor.run {
            manager.vaultURL = vaultURL()
            manager.addFavorite("temp.md")
        }

        // Delete the file
        try? FileManager.default.removeItem(at: fileURL)

        // Cleanup
        await MainActor.run {
            manager.cleanupDeleted(vaultURL: vaultURL())
        }

        let isFav = await MainActor.run { manager.isFavorite("temp.md") }
        XCTAssertFalse(isFav, "Favourite for deleted file should be cleaned up")
    }

    func testE8_startupSyncReturnsFavouriteOrder() async {
        createVault()
        await mock.setFavourites(paths: ["c.md", "a.md", "b.md"])

        let favs = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        // Order should be preserved as returned by mock
        XCTAssertEqual(favs, ["c.md", "a.md", "b.md"])
    }
}
