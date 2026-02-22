import XCTest
@testable import Notero

@MainActor
final class VaultManagerTests: XCTestCase {
    var tempDir: URL!
    var vaultManager: VaultManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteroTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempDir.path, forKey: "vaultPath")
        vaultManager = VaultManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: "vaultPath")
        super.tearDown()
    }

    func testCreateNote() {
        let url = vaultManager.createNote(named: "Test Note", in: tempDir)
        XCTAssertNotNil(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))
        XCTAssertEqual(url!.lastPathComponent, "Test Note.md")
    }

    func testCreateDuplicateNote() {
        _ = vaultManager.createNote(named: "Test", in: tempDir)
        let url2 = vaultManager.createNote(named: "Test", in: tempDir)
        XCTAssertNotNil(url2)
        XCTAssertEqual(url2!.lastPathComponent, "Test 1.md")
    }

    func testCreateFolder() {
        let url = vaultManager.createFolder(named: "SubFolder", in: tempDir)
        XCTAssertNotNil(url)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testReadAndSaveNote() {
        let noteURL = tempDir.appendingPathComponent("test.md")
        let content = "# Hello World\nThis is a test."
        vaultManager.saveNote(content: content, to: noteURL)

        let readContent = vaultManager.readNote(at: noteURL)
        XCTAssertEqual(readContent, content)
    }

    func testRenameItem() {
        let url = vaultManager.createNote(named: "Original", in: tempDir)!
        let newURL = vaultManager.renameItem(at: url, to: "Renamed")
        XCTAssertNotNil(newURL)
        XCTAssertEqual(newURL!.lastPathComponent, "Renamed.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL!.path))
    }

    func testDuplicateNote() {
        let url = vaultManager.createNote(named: "Original", in: tempDir)!
        vaultManager.saveNote(content: "content", to: url)
        let dupURL = vaultManager.duplicateNote(at: url)
        XCTAssertNotNil(dupURL)
        XCTAssertEqual(dupURL!.lastPathComponent, "Original copy.md")
    }

    func testFileTreeBuild() {
        _ = vaultManager.createNote(named: "Note1", in: tempDir)
        _ = vaultManager.createNote(named: "Note2", in: tempDir)
        let folder = vaultManager.createFolder(named: "Sub", in: tempDir)
        _ = vaultManager.createNote(named: "SubNote", in: folder)

        vaultManager.loadFileTree()
        XCTAssertFalse(vaultManager.fileTree.isEmpty)

        let folders = vaultManager.fileTree.filter { $0.isFolder }
        let files = vaultManager.fileTree.filter { !$0.isFolder }
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(files.count, 2)
    }

    func testAllMarkdownFiles() {
        _ = vaultManager.createNote(named: "A", in: tempDir)
        _ = vaultManager.createNote(named: "B", in: tempDir)

        // Create a non-md file
        FileManager.default.createFile(
            atPath: tempDir.appendingPathComponent("readme.txt").path,
            contents: nil
        )

        let mdFiles = vaultManager.allMarkdownFiles()
        XCTAssertEqual(mdFiles.count, 2)
    }

    func testMoveToTrash() {
        let url = vaultManager.createNote(named: "TrashMe", in: tempDir)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        vaultManager.moveToTrash(url: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSortOrder_nameAscending() {
        _ = vaultManager.createNote(named: "Zebra", in: tempDir)
        _ = vaultManager.createNote(named: "Apple", in: tempDir)
        _ = vaultManager.createNote(named: "Mango", in: tempDir)

        vaultManager.loadFileTree(sortOrder: .nameAscending)
        let names = vaultManager.fileTree.filter { !$0.isFolder }.map { $0.name }
        XCTAssertEqual(names, ["Apple", "Mango", "Zebra"])
    }

    func testSortOrder_nameDescending() {
        _ = vaultManager.createNote(named: "Zebra", in: tempDir)
        _ = vaultManager.createNote(named: "Apple", in: tempDir)
        _ = vaultManager.createNote(named: "Mango", in: tempDir)

        vaultManager.loadFileTree(sortOrder: .nameDescending)
        let names = vaultManager.fileTree.filter { !$0.isFolder }.map { $0.name }
        XCTAssertEqual(names, ["Zebra", "Mango", "Apple"])
    }

    func testSortOrder_modifiedNewest() {
        let url1 = vaultManager.createNote(named: "Old", in: tempDir)!
        // Set older modification date
        let oldDate = Date().addingTimeInterval(-3600)
        try? FileManager.default.setAttributes(
            [.modificationDate: oldDate], ofItemAtPath: url1.path
        )

        Thread.sleep(forTimeInterval: 0.1)
        _ = vaultManager.createNote(named: "New", in: tempDir)

        vaultManager.loadFileTree(sortOrder: .modifiedNewest)
        let names = vaultManager.fileTree.filter { !$0.isFolder }.map { $0.name }
        XCTAssertEqual(names.first, "New")
    }
}
