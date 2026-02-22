import XCTest
@testable import Notero

@MainActor
final class EdgeCaseTests: XCTestCase {
    var tempDir: URL!
    var vaultManager: VaultManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteroEdge-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempDir.path, forKey: "vaultPath")
        vaultManager = VaultManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: "vaultPath")
        super.tearDown()
    }

    // MARK: - 5.1 Empty Vault

    func testEmptyVaultNoTreeCrash() {
        // Empty vault should produce empty tree, no crash
        vaultManager.loadFileTree()
        XCTAssertTrue(vaultManager.fileTree.isEmpty, "Empty vault should have empty file tree")
    }

    func testEmptyVaultCreateFirstNote() {
        let url = vaultManager.createNote(named: "First Note", in: tempDir)
        XCTAssertNotNil(url, "Should create first note in empty vault")
        vaultManager.loadFileTree()
        XCTAssertEqual(vaultManager.fileTree.count, 1)
    }

    // MARK: - 5.2 Very Large Note

    func testVeryLargeNote() {
        let words = (0..<100_000).map { _ in "word" }.joined(separator: " ")
        let noteURL = tempDir.appendingPathComponent("large.md")
        vaultManager.saveNote(content: words, to: noteURL)

        // Must load correctly
        let loaded = vaultManager.readNote(at: noteURL)
        XCTAssertEqual(loaded?.count, words.count, "Large note should round-trip correctly")

        // Search should still work
        let index = SearchIndex()
        let expectation = XCTestExpectation(description: "Large note search")

        Task {
            await index.addOrUpdate(url: noteURL, content: words, vaultURL: tempDir)
            let results = await index.search(query: "word")
            XCTAssertFalse(results.isEmpty, "Search should find term in large note")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - 5.3 Special Characters in Filenames

    func testSpecialCharsInFilename() {
        // The auto-title sanitization replaces invalid chars with "-"
        let invalidChars = CharacterSet(charactersIn: ":/\\?*\"<>|")
        let title = "My Note: \"Important\" / Today?"
        let sanitized = title.unicodeScalars
            .map { invalidChars.contains($0) ? "-" : String($0) }
            .joined()
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)

        // Verify sanitization produces no invalid filesystem chars
        XCTAssertFalse(sanitized.contains(":"))
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains("?"))
        XCTAssertFalse(sanitized.contains("*"))
        XCTAssertFalse(sanitized.contains("\""))

        // Test that the note can be created with sanitized name
        let url = vaultManager.createNote(named: sanitized, in: tempDir)
        XCTAssertNotNil(url, "Sanitized filename should be creatable")
    }

    func testUnicodeFilename() {
        // Unicode is valid in HFS+/APFS
        let url = vaultManager.createNote(named: "αβγ日本語", in: tempDir)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.lastPathComponent, "αβγ日本語.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))
    }

    // MARK: - 5.5 Concurrent Note Creation

    func testConcurrentNoteCreation() {
        let expectation = XCTestExpectation(description: "Concurrent notes")
        let group = DispatchGroup()

        var createdURLs: [URL] = []
        let lock = NSLock()

        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async { [vaultManager, tempDir] in
                Task { @MainActor in
                    let url = vaultManager!.createNote(named: "Concurrent", in: tempDir)
                    if let url {
                        lock.lock()
                        createdURLs.append(url)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            // All 10 should have unique filenames
            let uniqueNames = Set(createdURLs.map { $0.lastPathComponent })
            XCTAssertEqual(uniqueNames.count, createdURLs.count,
                          "All concurrent notes should have unique filenames")

            // All should exist on disk
            for url in createdURLs {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - 5.6 Wikilink Autocomplete with Many Notes

    func testWikilinkAutocompleteWith500Notes() {
        // Create 500 notes
        for i in 1...500 {
            let path = tempDir.appendingPathComponent("Note \(i).md")
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
        vaultManager.loadFileTree()

        let resolver = LinkResolver(vaultManager: vaultManager)
        let allNames = resolver.allNoteNames()
        XCTAssertEqual(allNames.count, 500)

        // Fuzzy filter performance
        let start = CFAbsoluteTimeGetCurrent()
        let filtered = resolver.fuzzyMatch(query: "Note 4", in: allNames)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(filtered.isEmpty)
        XCTAssertLessThan(elapsed, 0.1, "Fuzzy filter should complete in <100ms")
    }

    // MARK: - 5.7 Metadata Sidecar Path Consistency

    func testMetadataSidecarPathConsistency() {
        // Create note in a subfolder
        let subfolder = tempDir.appendingPathComponent("Projects")
        try? FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let noteURL = subfolder.appendingPathComponent("Alpha.md")
        try? "Content".write(to: noteURL, atomically: true, encoding: .utf8)

        let originalID = NoteMetadataService.shared.ensureID(for: noteURL)
        XCTAssertFalse(originalID.isEmpty)

        // Move note to root
        let newURL = tempDir.appendingPathComponent("Alpha.md")
        try? FileManager.default.moveItem(at: noteURL, to: newURL)
        NoteMetadataService.shared.updatePath(from: noteURL, to: newURL)

        // ID must be unchanged
        let afterMoveID = NoteMetadataService.shared.ensureID(for: newURL)
        XCTAssertEqual(originalID, afterMoveID, "ID must survive move across folders")
    }
}
