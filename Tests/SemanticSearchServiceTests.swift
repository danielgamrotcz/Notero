import XCTest
@testable import Notero

@MainActor
final class SemanticSearchServiceTests: XCTestCase {

    func testToggleEnablesAndDisables() {
        let service = SemanticSearchService()
        XCTAssertFalse(service.isEnabled)

        service.toggle(true)
        XCTAssertTrue(service.isEnabled)

        service.toggle(false)
        XCTAssertFalse(service.isEnabled)
    }

    func testSetModelUpdatesModel() {
        let service = SemanticSearchService()
        service.setModel("mxbai-embed-large")
        XCTAssertEqual(service.embeddingModel, "mxbai-embed-large")
    }

    func testSearchReturnsEmptyWhenDisabled() async {
        let service = SemanticSearchService()
        service.toggle(false)

        let tempDir = FileManager.default.temporaryDirectory
        let results = await service.search(query: "test", vaultURL: tempDir)
        XCTAssertTrue(results.isEmpty, "Should return empty when disabled")
    }

    func testInitialState() {
        let service = SemanticSearchService()
        XCTAssertEqual(service.indexedCount, 0)
        XCTAssertFalse(service.isIndexing)
    }
}
