import XCTest
@testable import Notero

@MainActor
final class NoteMetadataServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteMetadataTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testEnsureIDGeneratesUUID() {
        let noteURL = tempDir.appendingPathComponent("test.md")
        try? "# Test".write(to: noteURL, atomically: true, encoding: .utf8)

        let id = NoteMetadataService.shared.ensureID(for: noteURL)
        XCTAssertFalse(id.isEmpty, "ID should not be empty")
        XCTAssertTrue(id.contains("-"), "ID should be a UUID format")
        XCTAssertEqual(id, id.lowercased(), "ID should be lowercase")
    }

    func testMetadataIncludesCreatedDate() {
        let noteURL = tempDir.appendingPathComponent("dated.md")
        try? "Hello".write(to: noteURL, atomically: true, encoding: .utf8)

        let meta = NoteMetadataService.shared.metadata(for: noteURL)
        XCTAssertFalse(meta.id.isEmpty)
        XCTAssertNotNil(meta.created)
        XCTAssertTrue(meta.created.timeIntervalSinceNow < 5, "Created date should be recent")
    }

    func testEnsureIDReturnsSameIDOnRepeatedCalls() {
        let noteURL = tempDir.appendingPathComponent("stable.md")
        try? "Content".write(to: noteURL, atomically: true, encoding: .utf8)

        let id1 = NoteMetadataService.shared.ensureID(for: noteURL)
        let id2 = NoteMetadataService.shared.ensureID(for: noteURL)
        XCTAssertEqual(id1, id2, "ID should be stable across calls")
    }

    func testUpdatePathMigratesMetadata() {
        let noteURL = tempDir.appendingPathComponent("original.md")
        try? "Content".write(to: noteURL, atomically: true, encoding: .utf8)

        let originalID = NoteMetadataService.shared.ensureID(for: noteURL)

        let newURL = tempDir.appendingPathComponent("renamed.md")
        try? FileManager.default.moveItem(at: noteURL, to: newURL)
        NoteMetadataService.shared.updatePath(from: noteURL, to: newURL)

        let newMeta = NoteMetadataService.shared.metadata(for: newURL)
        XCTAssertEqual(newMeta.id, originalID, "ID should survive rename")
    }

    func testCreationDateFallback() {
        let noteURL = tempDir.appendingPathComponent("fallback.md")
        try? "Content".write(to: noteURL, atomically: true, encoding: .utf8)

        let meta = NoteMetadataService.shared.metadata(for: noteURL)
        // Should fall back to filesystem creation date, which is recent
        XCTAssertTrue(abs(meta.created.timeIntervalSinceNow) < 10,
                      "Creation date should be close to now (filesystem fallback)")
    }

    func testIDUniqueness() {
        let noteA = tempDir.appendingPathComponent("unique_a.md")
        let noteB = tempDir.appendingPathComponent("unique_b.md")
        try? "A".write(to: noteA, atomically: true, encoding: .utf8)
        try? "B".write(to: noteB, atomically: true, encoding: .utf8)

        let idA = NoteMetadataService.shared.ensureID(for: noteA)
        let idB = NoteMetadataService.shared.ensureID(for: noteB)
        XCTAssertNotEqual(idA, idB, "Two different notes must get different IDs")
    }
}
