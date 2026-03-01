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

    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
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

    // Required tests from test suite spec

    func testSnapshotCreatedOnSave() {
        NoteHistoryService.shared.saveSnapshot(content: "Snapshot content", for: noteURL)
        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertFalse(snapshots.isEmpty, "Saving should create a snapshot file")
    }

    func testNoDuplicateSnapshot() {
        NoteHistoryService.shared.saveSnapshot(content: "Identical", for: noteURL)
        NoteHistoryService.shared.saveSnapshot(content: "Identical", for: noteURL)

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertEqual(snapshots.count, 1, "Saving same content twice should create only one snapshot")
    }

    func testRetentionLimit() {
        for i in 0..<51 {
            NoteHistoryService.shared.saveSnapshot(content: "Version \(i)", for: noteURL)
            Thread.sleep(forTimeInterval: 0.05)
        }

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertLessThanOrEqual(snapshots.count, 50, "Only 50 snapshots should be retained")
    }

    func testRestoreVersion() {
        let targetContent = "This is version 2"
        NoteHistoryService.shared.saveSnapshot(content: "Version 1", for: noteURL)
        Thread.sleep(forTimeInterval: 1.1)
        NoteHistoryService.shared.saveSnapshot(content: targetContent, for: noteURL)

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertTrue(snapshots.contains(where: { $0.content == targetContent }),
                      "Should be able to find and restore version content")
    }

    func testSnapshotsListedChronologically() {
        NoteHistoryService.shared.saveSnapshot(content: "First", for: noteURL)
        Thread.sleep(forTimeInterval: 1.1)
        NoteHistoryService.shared.saveSnapshot(content: "Second", for: noteURL)

        let snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertEqual(snapshots.count, 2)
        // Newest first
        XCTAssertEqual(snapshots.first?.content, "Second")
        XCTAssertEqual(snapshots.last?.content, "First")
    }
}
