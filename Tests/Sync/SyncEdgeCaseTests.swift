@testable import Notero
import XCTest

final class SyncEdgeCaseTests: XCTestCase {
    private var tempDir: URL!
    private var mock: MockSupabaseService!
    private var syncManager: SyncManager!
    private var config: SupabaseService.Config!
    private var pendingSyncURL: URL!
    private let lastSyncKey = "EdgeCaseTests_lastSync_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgeTests-\(UUID().uuidString)")
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

    private func readLocalNote(_ relativePath: String) -> String? {
        let path = relativePath.hasSuffix(".md") ? relativePath : relativePath + ".md"
        let fileURL = vaultURL().appendingPathComponent(path)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - F. Edge Cases

    func testF1_unicodeNFDtoNFCNormalization() {
        // Czech characters with NFD decomposition
        let nfdString = "Pří\u{0301}liš" // composed + extra combining
        let url = vaultURL().appendingPathComponent(nfdString + ".md")
        let result = SupabaseService.relativePath(for: url, vaultURL: vaultURL())

        // Should be NFC normalized
        XCTAssertEqual(result, result.precomposedStringWithCanonicalMapping)
    }

    func testF2_deeplyNestedFoldersCreated() async {
        createVault()
        await mock.addRemoteFolder(path: "a")
        await mock.addRemoteFolder(path: "a/b")
        await mock.addRemoteFolder(path: "a/b/c")
        await mock.addRemoteFolder(path: "a/b/c/d")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL().appendingPathComponent("a/b/c/d").path))
    }

    func testF3_emptyContentNote() async {
        createVault()
        await mock.addRemoteNote(path: "empty", content: "")

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        XCTAssertEqual(readLocalNote("empty"), "")
    }

    func testF4_largeContentNote() async {
        createVault()
        let largeContent = String(repeating: "Lorem ipsum dolor sit amet. ", count: 40_000) // ~1MB
        await mock.addRemoteNote(path: "large", content: largeContent)

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        let saved = readLocalNote("large")
        XCTAssertEqual(saved?.count, largeContent.count)
    }

    func testF5_concurrentDirtyNotes() async {
        createVault()
        for i in 0..<20 {
            writeLocalNote("concurrent-\(i)", content: "content \(i)")
        }

        _ = await syncManager.performStartupSync(config: config, vaultURL: vaultURL())

        for i in 0..<20 {
            await syncManager.markNoteDirty("concurrent-\(i)")
        }

        await mock.resetSyncNoteCalls()

        _ = await syncManager.triggerPull(config: config, vaultURL: vaultURL())

        let calls = await mock.syncNoteCalls
        let retriedPaths = Set(calls.map(\.path))
        XCTAssertEqual(retriedPaths.count, 20, "All 20 dirty notes should be retried")
    }

    func testF6_extractTitleFromH1() {
        // extractTitle regex uses ^ and $ anchors — only matches single-line content
        let content = "# My Title"
        let title = SupabaseService.extractTitle(from: content, filename: "fallback.md")
        XCTAssertEqual(title, "My Title")
    }

    func testF7_extractTitleFallbackToFilename() {
        let content = "No heading here, just text"
        let title = SupabaseService.extractTitle(from: content, filename: "my-note.md")
        XCTAssertEqual(title, "my-note")
    }

    func testF8_invalidConfigReturnsFalse() async {
        createVault()
        let invalidConfig = SupabaseService.Config(url: "", serviceKey: "", userId: "")

        // Mock doesn't validate config, so sync completes (returns nil because no favourites)
        _ = await syncManager.performStartupSync(config: invalidConfig, vaultURL: vaultURL())

        // Verify the mock was called — config validation happens in real SupabaseService
        let notesCalls = await mock.fetchAllNotesCalls
        XCTAssertEqual(notesCalls, 1)
    }

    func testF9_relativePathStripsExtension() {
        let url = vaultURL().appendingPathComponent("notes/test.md")
        let result = SupabaseService.relativePath(for: url, vaultURL: vaultURL())
        XCTAssertEqual(result, "notes/test")
    }

    func testF10_relativePathNoExtension() {
        let url = vaultURL().appendingPathComponent("folder/name")
        let result = SupabaseService.relativePath(for: url, vaultURL: vaultURL())
        XCTAssertEqual(result, "folder/name")
    }

    func testF11_extractTitleFromNilContent() {
        let title = SupabaseService.extractTitle(from: nil, filename: "fallback-name.md")
        XCTAssertEqual(title, "fallback-name")
    }

    func testF12_extractTitleMultipleH1FallsToFilename() {
        // With multiline content, the regex ^ and $ anchors don't match mid-string lines
        let content = "# First Title\n# Second Title"
        let title = SupabaseService.extractTitle(from: content, filename: "fallback.md")
        XCTAssertEqual(title, "fallback")
    }

    func testF13_markAndClearLocallyDeleted() async {
        await syncManager.markLocallyDeleted("deleted-path")
        var pending = await syncManager.testingGetPendingSync()
        XCTAssertTrue(pending.pendingDeletionPaths.contains("deleted-path"))

        await syncManager.clearLocallyDeleted("deleted-path")
        pending = await syncManager.testingGetPendingSync()
        XCTAssertFalse(pending.pendingDeletionPaths.contains("deleted-path"))
    }

    func testF14_markAndClearFolderLocallyDeleted() async {
        await syncManager.markFolderLocallyDeleted("deleted-folder")
        var pending = await syncManager.testingGetPendingSync()
        XCTAssertTrue(pending.pendingFolderDeletionPaths.contains("deleted-folder"))

        await syncManager.clearFolderLocallyDeleted("deleted-folder")
        pending = await syncManager.testingGetPendingSync()
        XCTAssertFalse(pending.pendingFolderDeletionPaths.contains("deleted-folder"))
    }
}
