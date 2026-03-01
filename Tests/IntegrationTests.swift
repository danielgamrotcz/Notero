import XCTest
@testable import Notero

@MainActor
final class IntegrationTests: XCTestCase {
    var tempDir: URL!
    var vaultManager: VaultManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteroIntegration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vaultManager = VaultManager(overrideURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 3.1 Vault Lifecycle

    func testVaultLifecycle() {
        // 1. Vault directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))

        // 2. Create 5 notes, 2 folders, 3 notes inside folders
        _ = vaultManager.createNote(named: "NoteA", in: tempDir)
        _ = vaultManager.createNote(named: "NoteB", in: tempDir)
        _ = vaultManager.createNote(named: "NoteC", in: tempDir)
        _ = vaultManager.createNote(named: "NoteD", in: tempDir)
        _ = vaultManager.createNote(named: "NoteE", in: tempDir)

        let folder1 = vaultManager.createFolder(named: "Folder1", in: tempDir)!
        let folder2 = vaultManager.createFolder(named: "Folder2", in: tempDir)!

        _ = vaultManager.createNote(named: "SubNote1", in: folder1)
        _ = vaultManager.createNote(named: "SubNote2", in: folder1)
        _ = vaultManager.createNote(named: "SubNote3", in: folder2)

        // 3. Verify tree: folders first, then files
        vaultManager.loadFileTree()
        let topLevel = vaultManager.fileTree
        let folders = topLevel.filter { $0.isFolder }
        let files = topLevel.filter { !$0.isFolder }

        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(files.count, 5)

        // Folders should come before files in the array
        if let lastFolderIdx = topLevel.lastIndex(where: { $0.isFolder }),
           let firstFileIdx = topLevel.firstIndex(where: { !$0.isFolder }) {
            XCTAssertLessThan(lastFolderIdx, firstFileIdx, "Folders should appear before files")
        }

        // 4. Test each sort order
        vaultManager.loadFileTree(sortOrder: .nameAscending)
        let namesAsc = vaultManager.fileTree.filter { !$0.isFolder }.map { $0.name }
        XCTAssertEqual(namesAsc, namesAsc.sorted())

        vaultManager.loadFileTree(sortOrder: .nameDescending)
        let namesDesc = vaultManager.fileTree.filter { !$0.isFolder }.map { $0.name }
        XCTAssertEqual(namesDesc, namesDesc.sorted(by: >))

        // 5. Rename a note
        let noteA = tempDir.appendingPathComponent("NoteA.md")
        let renamed = vaultManager.renameItem(at: noteA, to: "RenamedA")
        XCTAssertNotNil(renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed!.path))

        // 6. Move note to subfolder
        let noteB = tempDir.appendingPathComponent("NoteB.md")
        vaultManager.moveItem(from: noteB, to: folder1)
        vaultManager.loadFileTree()
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteB.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder1.appendingPathComponent("NoteB.md").path))

        // 7. Trash a note
        let noteC = tempDir.appendingPathComponent("NoteC.md")
        vaultManager.moveToTrash(url: noteC)
        vaultManager.loadFileTree()
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteC.path))
    }

    // MARK: - 3.2 Auto-save Integrity

    func testAutoSaveIntegrity() {
        // 1. Write and read back
        let noteURL = tempDir.appendingPathComponent("autosave.md")
        let content = "# Test\nThis is content."
        vaultManager.saveNote(content: content, to: noteURL)
        let readBack = vaultManager.readNote(at: noteURL)
        XCTAssertEqual(readBack, content)

        // 2. Special characters round-trip
        let specialChars = "Señor ñ, 你好世界, €100, emoji 🎉🚀"
        vaultManager.saveNote(content: specialChars, to: noteURL)
        let readSpecial = vaultManager.readNote(at: noteURL)
        XCTAssertEqual(readSpecial, specialChars)

        // 3. Large content (1MB)
        let largeContent = String(repeating: "Lorem ipsum dolor sit amet. ", count: 40000)
        let largeURL = tempDir.appendingPathComponent("large.md")
        vaultManager.saveNote(content: largeContent, to: largeURL)
        let readLarge = vaultManager.readNote(at: largeURL)
        XCTAssertEqual(readLarge, largeContent)
    }

    // MARK: - 3.3 Search Index Consistency

    func testSearchIndexConsistency() async {
        let index = SearchIndex()

        // 1. Index 20 notes
        for i in 1...20 {
            let url = tempDir.appendingPathComponent("note\(i).md")
            let content = i == 5 ? "This note contains the special keyword findable" : "Generic content for note \(i)"
            await index.addOrUpdate(url: url, content: content, vaultURL: tempDir)
        }

        // 2. Search for term in note 5
        var results = await index.search(query: "findable")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.noteName == "note5" }))

        // 3. Update note 5 — remove the term, reindex, search again
        let note5URL = tempDir.appendingPathComponent("note5.md")
        await index.addOrUpdate(url: note5URL, content: "Updated content without special word", vaultURL: tempDir)
        results = await index.search(query: "findable")
        XCTAssertFalse(results.contains(where: { $0.noteName == "note5" }))

        // 4. Delete from index
        await index.remove(url: note5URL)
        results = await index.search(query: "updated")
        XCTAssertFalse(results.contains(where: { $0.noteName == "note5" }))

        // 5. Czech diacritics
        let czURL = tempDir.appendingPathComponent("czech.md")
        await index.addOrUpdate(url: czURL, content: "Příliš žluťoučký kůň úpěl ďábelské ódy", vaultURL: tempDir)
        results = await index.search(query: "prilis")
        XCTAssertFalse(results.isEmpty, "Diacritic-insensitive search should work")

        // 6. Results capped at 50
        for i in 1...60 {
            let url = tempDir.appendingPathComponent("bulk\(i).md")
            await index.addOrUpdate(url: url, content: "common term in every note", vaultURL: tempDir)
        }
        results = await index.search(query: "common")
        XCTAssertLessThanOrEqual(results.count, 50, "Results should be capped at 50")
    }

    // MARK: - 3.4 Note ID Stability

    func testNoteIDStability() {
        let noteURL = tempDir.appendingPathComponent("stable_id.md")
        try? "Content".write(to: noteURL, atomically: true, encoding: .utf8)

        // 1. Create note and get ID
        let originalID = NoteMetadataService.shared.ensureID(for: noteURL)
        XCTAssertFalse(originalID.isEmpty)

        // 2. Rename note — same ID
        let renamedURL = tempDir.appendingPathComponent("stable_id_renamed.md")
        try? FileManager.default.moveItem(at: noteURL, to: renamedURL)
        NoteMetadataService.shared.updatePath(from: noteURL, to: renamedURL)
        let afterRenameID = NoteMetadataService.shared.ensureID(for: renamedURL)
        XCTAssertEqual(originalID, afterRenameID, "ID should survive rename")

        // 3. Move note to subfolder — same ID
        let subfolder = tempDir.appendingPathComponent("sub")
        try? FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let movedURL = subfolder.appendingPathComponent("stable_id_renamed.md")
        try? FileManager.default.moveItem(at: renamedURL, to: movedURL)
        NoteMetadataService.shared.updatePath(from: renamedURL, to: movedURL)
        let afterMoveID = NoteMetadataService.shared.ensureID(for: movedURL)
        XCTAssertEqual(originalID, afterMoveID, "ID should survive move")

        // 4. Create 100 notes — all unique IDs
        var ids = Set<String>()
        for i in 1...100 {
            let url = tempDir.appendingPathComponent("unique\(i).md")
            try? "Content \(i)".write(to: url, atomically: true, encoding: .utf8)
            ids.insert(NoteMetadataService.shared.ensureID(for: url))
        }
        XCTAssertEqual(ids.count, 100, "All 100 notes should have unique IDs")
    }

    // MARK: - 3.5 Note History

    func testNoteHistory() {
        let noteURL = tempDir.appendingPathComponent("history_test.md")
        try? "Initial".write(to: noteURL, atomically: true, encoding: .utf8)

        // 1. Save 5 times with different content (need >1s between for unique timestamps)
        for i in 1...5 {
            NoteHistoryService.shared.saveSnapshot(content: "Version \(i)", for: noteURL)
            if i < 5 { Thread.sleep(forTimeInterval: 1.1) }
        }

        // 2. Verify 5 snapshots
        var snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertEqual(snapshots.count, 5)

        // 3. Save same content — only 1 new snapshot (dedup)
        let countBefore = snapshots.count
        NoteHistoryService.shared.saveSnapshot(content: "Version 5", for: noteURL)
        snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertEqual(snapshots.count, countBefore, "Duplicate content should not create new snapshot")

        // 4. Save enough times to test retention — use unique timestamps
        NoteHistoryService.shared.deleteAllHistory(for: noteURL)
        let formatter = ISO8601DateFormatter()
        let historyDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notero/history/\(tempDir.path.md5Hash)/history_test.md")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        // Directly create 55 snapshot files to avoid waiting
        for i in 1...55 {
            let date = Date(timeIntervalSince1970: Double(i) * 10)
            let ts = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
            let path = historyDir.appendingPathComponent("\(ts).md")
            try? "Retention \(i)".write(to: path, atomically: true, encoding: .utf8)
        }
        // Trigger a save to force pruning
        NoteHistoryService.shared.saveSnapshot(content: "Trigger prune", for: noteURL)
        snapshots = NoteHistoryService.shared.loadSnapshots(for: noteURL)
        XCTAssertLessThanOrEqual(snapshots.count, 50)

        // 5. Newest first
        if snapshots.count >= 2 {
            XCTAssertTrue(snapshots[0].date >= snapshots[1].date, "Snapshots should be newest-first")
        }

        // 6. Restore specific content
        let restored = snapshots.first(where: { $0.content.contains("Retention") })
        XCTAssertNotNil(restored)
    }

    // MARK: - 3.6 Wikilink Resolution

    func testWikilinkResolution() {
        // Create vault notes
        let projectAlpha = tempDir.appendingPathComponent("Project Alpha.md")
        let meetingNotes = tempDir.appendingPathComponent("Meeting Notes.md")
        let inbox = tempDir.appendingPathComponent("inbox.md")

        FileManager.default.createFile(atPath: projectAlpha.path, contents: nil)
        try? "Discussed [[Project Alpha]] today".write(to: meetingNotes, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: inbox.path, contents: nil)

        vaultManager.loadFileTree()
        let resolver = LinkResolver(vaultManager: vaultManager)

        // 1. Exact match
        let resolved1 = resolver.resolve(linkName: "Project Alpha")
        XCTAssertNotNil(resolved1)
        XCTAssertEqual(resolved1?.lastPathComponent, "Project Alpha.md")

        // 2. Case insensitive
        let resolved2 = resolver.resolve(linkName: "project alpha")
        XCTAssertNotNil(resolved2)

        // 3. Pipe syntax
        let text = "[[Project Alpha|Alias]]"
        let links = text.wikilinks()
        XCTAssertEqual(links.first?.linkName, "Project Alpha")
        let resolved3 = resolver.resolve(linkName: links.first!.linkName)
        XCTAssertNotNil(resolved3)

        // 4. Nonexistent
        let resolved4 = resolver.resolve(linkName: "Nonexistent Note")
        XCTAssertNil(resolved4)

        // 5. Backlinks
        resolver.findBacklinks(for: projectAlpha)
        XCTAssertEqual(resolver.backlinks.count, 1)
        XCTAssertEqual(resolver.backlinks.first?.noteName, "Meeting Notes")
    }

    // MARK: - 3.7 FSEvent Watcher

    func testFSEventWatcher() async {
        // 1. VaultManager is already watching tempDir
        // 2. Copy a .md file from outside
        let externalFile = tempDir.appendingPathComponent("external.md")
        try? "External content".write(to: externalFile, atomically: true, encoding: .utf8)

        // 3. Wait for FSEvent
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // 4. Verify file appears in tree
        vaultManager.loadFileTree()
        let hasExternal = vaultManager.fileTree.contains(where: { $0.name == "external" })
        XCTAssertTrue(hasExternal, "Externally created file should appear in tree")

        // 5. Delete file
        try? FileManager.default.removeItem(at: externalFile)

        // 6. Wait
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // 7. Verify gone
        vaultManager.loadFileTree()
        let stillHas = vaultManager.fileTree.contains(where: { $0.name == "external" })
        XCTAssertFalse(stillHas, "Deleted file should be gone from tree")

        // 8. .icloud placeholder should not appear
        let icloudFile = tempDir.appendingPathComponent(".note.icloud")
        FileManager.default.createFile(atPath: icloudFile.path, contents: nil)
        vaultManager.loadFileTree()
        let hasIcloud = vaultManager.fileTree.contains(where: {
            $0.url.lastPathComponent.contains(".icloud")
        })
        XCTAssertFalse(hasIcloud, ".icloud files should not appear in tree")
    }
}
