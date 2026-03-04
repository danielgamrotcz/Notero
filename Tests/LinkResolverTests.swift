import XCTest
@testable import Notero

@MainActor
final class LinkResolverTests: XCTestCase {
    var tempDir: URL!
    var vaultManager: VaultManager!
    var linkResolver: LinkResolver!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteroLinkTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vaultManager = VaultManager(overrideURL: tempDir)
        linkResolver = LinkResolver(vaultManager: vaultManager)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testResolveExactMatch() {
        let noteURL = tempDir.appendingPathComponent("My Note.md")
        FileManager.default.createFile(atPath: noteURL.path, contents: nil)
        vaultManager.loadFileTree()

        let resolved = linkResolver.resolve(linkName: "My Note")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "My Note.md")
    }

    func testResolveCaseInsensitive() {
        let noteURL = tempDir.appendingPathComponent("Hello World.md")
        FileManager.default.createFile(atPath: noteURL.path, contents: nil)
        vaultManager.loadFileTree()

        let resolved = linkResolver.resolve(linkName: "hello world")
        XCTAssertNotNil(resolved)
    }

    func testResolveNonExistent() {
        let resolved = linkResolver.resolve(linkName: "Does Not Exist")
        XCTAssertNil(resolved)
    }

    func testFindBacklinks() {
        let noteA = tempDir.appendingPathComponent("Note A.md")
        let noteB = tempDir.appendingPathComponent("Note B.md")

        FileManager.default.createFile(atPath: noteA.path, contents: nil)
        try? "This links to [[Note A]]".write(to: noteB, atomically: true, encoding: .utf8)

        vaultManager.loadFileTree()

        linkResolver.findBacklinks(for: noteA)
        XCTAssertEqual(linkResolver.backlinks.count, 1)
        XCTAssertEqual(linkResolver.backlinks.first?.noteName, "Note B")
    }

    func testStringWikilinks() {
        let text = "Check out [[My Note]] and [[Other|Display Text]]"
        let links = text.wikilinks()
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].linkName, "My Note")
        XCTAssertNil(links[0].displayText)
        XCTAssertEqual(links[1].linkName, "Other")
        XCTAssertEqual(links[1].displayText, "Display Text")
    }

    func testFuzzyMatch() {
        let names: [(name: String, url: URL)] = [
            ("Hello World", URL(fileURLWithPath: "/a")),
            ("Test Note", URL(fileURLWithPath: "/b")),
            ("hello there", URL(fileURLWithPath: "/c")),
        ]

        let matches = linkResolver.fuzzyMatch(query: "hello", in: names)
        XCTAssertEqual(matches.count, 2)
    }

    // Required test names from test suite spec

    func testResolvesWikilinkByFilename() {
        let noteURL = tempDir.appendingPathComponent("Note Name.md")
        FileManager.default.createFile(atPath: noteURL.path, contents: nil)
        vaultManager.loadFileTree()

        let resolved = linkResolver.resolve(linkName: "Note Name")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "Note Name.md")
    }

    func testResolvesWikilinkCaseInsensitive() {
        let noteURL = tempDir.appendingPathComponent("Note Name.md")
        FileManager.default.createFile(atPath: noteURL.path, contents: nil)
        vaultManager.loadFileTree()

        let resolved = linkResolver.resolve(linkName: "note name")
        XCTAssertNotNil(resolved, "Case insensitive wikilink should resolve")
    }

    func testResolvesWikilinkWithoutExtension() {
        let noteURL = tempDir.appendingPathComponent("Note.md")
        FileManager.default.createFile(atPath: noteURL.path, contents: nil)
        vaultManager.loadFileTree()

        let resolved = linkResolver.resolve(linkName: "Note")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "Note.md")
    }

    func testBrokenLinkReturnsNil() {
        let resolved = linkResolver.resolve(linkName: "Nonexistent Note")
        XCTAssertNil(resolved, "Broken wikilink should return nil")
    }

    func testBacklinksDetected() {
        let noteA = tempDir.appendingPathComponent("Target.md")
        let noteB = tempDir.appendingPathComponent("Linker.md")

        FileManager.default.createFile(atPath: noteA.path, contents: nil)
        try? "See [[Target]] for details".write(to: noteB, atomically: true, encoding: .utf8)

        vaultManager.loadFileTree()
        linkResolver.findBacklinks(for: noteA)
        XCTAssertEqual(linkResolver.backlinks.count, 1)
        XCTAssertEqual(linkResolver.backlinks.first?.noteName, "Linker")
    }

    // MARK: - updateWikilinks Tests

    func testUpdateWikilinks_basic() {
        let noteA = tempDir.appendingPathComponent("Old Note.md")
        let noteB = tempDir.appendingPathComponent("Other.md")
        try! "".write(to: noteA, atomically: true, encoding: .utf8)
        try! "See [[Old Note]] for info".write(to: noteB, atomically: true, encoding: .utf8)
        vaultManager.loadFileTree()

        let newURL = tempDir.appendingPathComponent("New Note.md")
        linkResolver.updateWikilinks(oldName: "Old Note", newName: "New Note", excludingNoteAt: newURL)

        let updated = try! String(contentsOf: noteB, encoding: .utf8)
        XCTAssertEqual(updated, "See [[New Note]] for info")
    }

    func testUpdateWikilinks_pipeSyntax() {
        let noteA = tempDir.appendingPathComponent("Old.md")
        let noteB = tempDir.appendingPathComponent("Linker.md")
        try! "".write(to: noteA, atomically: true, encoding: .utf8)
        try! "Check [[Old|my label]] here".write(to: noteB, atomically: true, encoding: .utf8)
        vaultManager.loadFileTree()

        let newURL = tempDir.appendingPathComponent("New.md")
        linkResolver.updateWikilinks(oldName: "Old", newName: "New", excludingNoteAt: newURL)

        let updated = try! String(contentsOf: noteB, encoding: .utf8)
        XCTAssertEqual(updated, "Check [[New|my label]] here")
    }

    func testUpdateWikilinks_multipleLinks() {
        let noteB = tempDir.appendingPathComponent("Multi.md")
        try! "First [[Target]] and second [[Target|x]]".write(to: noteB, atomically: true, encoding: .utf8)
        vaultManager.loadFileTree()

        let newURL = tempDir.appendingPathComponent("Renamed.md")
        linkResolver.updateWikilinks(oldName: "Target", newName: "Renamed", excludingNoteAt: newURL)

        let updated = try! String(contentsOf: noteB, encoding: .utf8)
        XCTAssertEqual(updated, "First [[Renamed]] and second [[Renamed|x]]")
    }

    func testUpdateWikilinks_caseInsensitive() {
        let noteB = tempDir.appendingPathComponent("CaseTest.md")
        try! "Link to [[old note]] here".write(to: noteB, atomically: true, encoding: .utf8)
        vaultManager.loadFileTree()

        let newURL = tempDir.appendingPathComponent("New Note.md")
        linkResolver.updateWikilinks(oldName: "Old Note", newName: "New Note", excludingNoteAt: newURL)

        let updated = try! String(contentsOf: noteB, encoding: .utf8)
        XCTAssertEqual(updated, "Link to [[New Note]] here")
    }

    func testUpdateWikilinks_excludedNote() {
        let noteA = tempDir.appendingPathComponent("Self.md")
        try! "Link to [[Self]] in self".write(to: noteA, atomically: true, encoding: .utf8)
        vaultManager.loadFileTree()

        linkResolver.updateWikilinks(oldName: "Self", newName: "Renamed", excludingNoteAt: noteA)

        let content = try! String(contentsOf: noteA, encoding: .utf8)
        XCTAssertEqual(content, "Link to [[Self]] in self", "Excluded note should not be modified")
    }

    func testUpdateWikilinks_unrelatedUntouched() {
        let noteB = tempDir.appendingPathComponent("Bystander.md")
        try! "Link to [[Other Note]] only".write(to: noteB, atomically: true, encoding: .utf8)
        vaultManager.loadFileTree()

        let newURL = tempDir.appendingPathComponent("New.md")
        linkResolver.updateWikilinks(oldName: "Target", newName: "New", excludingNoteAt: newURL)

        let content = try! String(contentsOf: noteB, encoding: .utf8)
        XCTAssertEqual(content, "Link to [[Other Note]] only", "Unrelated links should not be modified")
    }

    func testPipeSyntax() {
        let noteURL = tempDir.appendingPathComponent("RealNote.md")
        FileManager.default.createFile(atPath: noteURL.path, contents: nil)
        vaultManager.loadFileTree()

        // Parse the wikilink — pipe syntax should give linkName=RealNote
        let text = "[[RealNote|Display Text]]"
        let links = text.wikilinks()
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].linkName, "RealNote")
        XCTAssertEqual(links[0].displayText, "Display Text")

        // Resolve should find RealNote, not "Display Text"
        let resolved = linkResolver.resolve(linkName: links[0].linkName)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "RealNote.md")
    }
}
