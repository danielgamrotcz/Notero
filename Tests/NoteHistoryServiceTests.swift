import XCTest
@testable import Notero

@MainActor
final class NoteHistoryServiceTests: XCTestCase {
    var tempDir: URL!
    var noteURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        noteURL = tempDir.appendingPathComponent("note.md")
        try? "Initial".write(to: noteURL, atomically: true, encoding: .utf8)

        // Set vault path so history service can resolve it
        UserDefaults.standard.set(tempDir.path, forKey: "vaultPath")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: "vaultPath")
        super.tearDown()
    }

    func testSaveAndLoadSnapshot() {
        NoteHistoryService.shared.saveSnapshot(content: "Version 1", for: noteURL)

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertFalse(snapshots.isEmpty, "Should have at least one snapshot")
        XCTAssertEqual(snapshots.first?.content, "Version 1")
    }

    func testDeduplication() {
        NoteHistoryService.shared.saveSnapshot(content: "Same content", for: noteURL)
        NoteHistoryService.shared.saveSnapshot(content: "Same content", for: noteURL)

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertEqual(snapshots.count, 1, "Identical snapshots should be deduplicated")
    }

    func testMultipleVersions() {
        NoteHistoryService.shared.saveSnapshot(content: "V1", for: noteURL)
        // Need >1s delay for different ISO8601 timestamps
        Thread.sleep(forTimeInterval: 1.1)
        NoteHistoryService.shared.saveSnapshot(content: "V2", for: noteURL)

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertEqual(snapshots.count, 2, "Should have two distinct snapshots")
    }

    func testDiffBasic() {
        let old = "Line 1\nLine 2\nLine 3"
        let new = "Line 1\nLine 2 modified\nLine 3"

        let diff = NoteHistoryService.diff(old: old, new: new)
        XCTAssertFalse(diff.isEmpty, "Diff should produce results")

        let added = diff.filter { $0.type == .added }
        let removed = diff.filter { $0.type == .removed }
        XCTAssertFalse(added.isEmpty, "Should have additions")
        XCTAssertFalse(removed.isEmpty, "Should have removals")
    }

    func testDeleteAllHistory() {
        NoteHistoryService.shared.saveSnapshot(content: "Content", for: noteURL)
        XCTAssertFalse(NoteHistoryService.shared.loadSnapshots(for: noteURL).isEmpty)

        NoteHistoryService.shared.deleteAllHistory(for: noteURL)
        XCTAssertTrue(NoteHistoryService.shared.loadSnapshots(for: noteURL).isEmpty,
                       "History should be empty after deletion")
    }
}
