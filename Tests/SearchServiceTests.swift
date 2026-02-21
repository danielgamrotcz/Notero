import XCTest
@testable import Notero

final class SearchServiceTests: XCTestCase {
    var index: SearchIndex!
    var vaultURL: URL!

    override func setUp() {
        super.setUp()
        index = SearchIndex()
        vaultURL = URL(fileURLWithPath: "/tmp/vault")
    }

    func testAddAndSearch() async {
        let url1 = vaultURL.appendingPathComponent("hello.md")
        let url2 = vaultURL.appendingPathComponent("world.md")

        await index.addOrUpdate(url: url1, content: "Hello world, this is a test note", vaultURL: vaultURL)
        await index.addOrUpdate(url: url2, content: "Another note about Swift programming", vaultURL: vaultURL)

        let results = await index.search(query: "hello")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.noteName, "hello")
    }

    func testExactPhraseSearch() async {
        let url = vaultURL.appendingPathComponent("test.md")
        await index.addOrUpdate(url: url, content: "The quick brown fox jumps over the lazy dog", vaultURL: vaultURL)

        let results = await index.search(query: "\"quick brown fox\"")
        XCTAssertFalse(results.isEmpty)
    }

    func testCaseInsensitiveSearch() async {
        let url = vaultURL.appendingPathComponent("test.md")
        await index.addOrUpdate(url: url, content: "Hello World", vaultURL: vaultURL)

        let results = await index.search(query: "HELLO")
        XCTAssertFalse(results.isEmpty)
    }

    func testDiacriticInsensitiveSearch() async {
        let url = vaultURL.appendingPathComponent("czech.md")
        await index.addOrUpdate(url: url, content: "Příliš žluťoučký kůň", vaultURL: vaultURL)

        let results = await index.search(query: "prilis")
        XCTAssertFalse(results.isEmpty)
    }

    func testRemoveFromIndex() async {
        let url = vaultURL.appendingPathComponent("test.md")
        await index.addOrUpdate(url: url, content: "test content", vaultURL: vaultURL)

        var results = await index.search(query: "test")
        XCTAssertFalse(results.isEmpty)

        await index.remove(url: url)
        results = await index.search(query: "test")
        XCTAssertTrue(results.isEmpty)
    }

    func testAllNoteNames() async {
        let url1 = vaultURL.appendingPathComponent("alpha.md")
        let url2 = vaultURL.appendingPathComponent("beta.md")

        await index.addOrUpdate(url: url1, content: "a", vaultURL: vaultURL)
        await index.addOrUpdate(url: url2, content: "b", vaultURL: vaultURL)

        let names = await index.allNoteNames()
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(names.first?.name, "alpha")
    }

    func testEmptyQueryReturnsNoResults() async {
        let url = vaultURL.appendingPathComponent("test.md")
        await index.addOrUpdate(url: url, content: "content", vaultURL: vaultURL)

        let results = await index.search(query: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testTitleMatchRankedHigher() async {
        let url1 = vaultURL.appendingPathComponent("swift.md")
        let url2 = vaultURL.appendingPathComponent("notes.md")

        await index.addOrUpdate(url: url1, content: "Swift programming language", vaultURL: vaultURL)
        await index.addOrUpdate(url: url2, content: "Notes about Swift and other languages", vaultURL: vaultURL)

        let results = await index.search(query: "swift")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.noteName, "swift")
    }
}
