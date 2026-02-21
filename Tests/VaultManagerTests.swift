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
}
