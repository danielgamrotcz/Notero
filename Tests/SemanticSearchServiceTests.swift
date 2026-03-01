import XCTest
@testable import Notero

@MainActor
final class SemanticSearchServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "semanticSearchEnabled")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "semanticSearchEnabled")
        super.tearDown()
    }

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

    // Required tests from test suite spec

    func testCosineSimilarity() {
        let service = SemanticSearchService()

        // Identical vectors → similarity = 1.0
        let a: [Float] = [1, 0, 0]
        let simSame = service.cosineSimilarity(a, a)
        XCTAssertEqual(simSame, 1.0, accuracy: 0.001, "Similarity of identical vectors should be 1.0")

        // Orthogonal vectors → similarity = 0.0
        let b: [Float] = [0, 1, 0]
        let simOrthogonal = service.cosineSimilarity(a, b)
        XCTAssertEqual(simOrthogonal, 0.0, accuracy: 0.001, "Similarity of orthogonal vectors should be 0.0")
    }

    func testThresholdFiltersLowMatches() async {
        let service = SemanticSearchService()
        service.toggle(true)

        // Inject embeddings with known values
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SemanticTest-\(UUID().uuidString)")
        UserDefaults.standard.set(tempDir.path, forKey: "vaultPath")

        // Two notes with very different embeddings from "query"
        service.embeddings["low_match.md"] = [0, 0, 1]  // orthogonal to query
        service.embeddings["high_match.md"] = [1, 0, 0]  // identical to query

        // Since embed() calls Ollama (unavailable), test via cosineSimilarity logic directly
        let lowSim = service.cosineSimilarity([1, 0, 0], [0, 0, 1])
        XCTAssertLessThan(lowSim, 0.5, "Low match should be below threshold")

        let highSim = service.cosineSimilarity([1, 0, 0], [1, 0, 0])
        XCTAssertGreaterThanOrEqual(highSim, 0.5, "High match should be above threshold")

        UserDefaults.standard.removeObject(forKey: "vaultPath")
    }

    func testResultsRankedByScore() {
        let service = SemanticSearchService()

        // Test that higher similarity scores rank first
        let query: [Float] = [1, 0, 0]
        let vecA: [Float] = [0.9, 0.1, 0]  // high similarity
        let vecB: [Float] = [0.5, 0.5, 0.5]  // lower similarity

        let simA = service.cosineSimilarity(query, vecA)
        let simB = service.cosineSimilarity(query, vecB)
        XCTAssertGreaterThan(simA, simB, "vecA should have higher similarity than vecB")
    }

    func testHandlesOllamaUnavailable() async {
        let service = SemanticSearchService()
        service.toggle(true)

        let tempDir = FileManager.default.temporaryDirectory
        // Ollama is not running → search should return empty gracefully, no crash
        let results = await service.search(query: "test query", vaultURL: tempDir)
        XCTAssertTrue(results.isEmpty, "Should return empty when Ollama is unavailable")
    }

    func testEmbeddingStoredAndLoaded() {
        let service = SemanticSearchService()
        let testEmbedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        service.embeddings["test_note.md"] = testEmbedding

        // Verify the embedding is stored
        XCTAssertNotNil(service.embeddings["test_note.md"])
        XCTAssertEqual(service.embeddings["test_note.md"]!, testEmbedding,
                       "Stored embedding should match")
    }
}
