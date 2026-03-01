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
