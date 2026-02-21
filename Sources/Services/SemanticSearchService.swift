import Foundation
import Combine

@MainActor
final class SemanticSearchService: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var isIndexing: Bool = false
    @Published var indexedCount: Int = 0
    @Published var embeddingModel: String = "nomic-embed-text"

    private var embeddings: [String: [Float]] = [:]
    private var updatedAt: [String: Date] = [:]
    private let maxContentLength = 2000

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "semanticSearchEnabled")
        embeddingModel = defaults.string(forKey: "semanticEmbeddingModel") ?? "nomic-embed-text"
        loadEmbeddings()
    }

    // MARK: - Public API

    func search(query: String, vaultURL: URL) async -> [SemanticSearchResult] {
        guard isEnabled else { return [] }

        guard let queryEmbedding = await embed(text: query) else { return [] }

        var results: [SemanticSearchResult] = []
        for (path, embedding) in embeddings {
            let similarity = cosineSimilarity(queryEmbedding, embedding)
            if similarity >= 0.5 {
                let url = vaultURL.appendingPathComponent(path)
                let name = url.deletingPathExtension().lastPathComponent
                results.append(SemanticSearchResult(
                    path: path, noteName: name, noteURL: url, similarity: similarity
                ))
            }
        }

        return results.sorted { $0.similarity > $1.similarity }.prefix(10).map { $0 }
    }

    func indexAll(vaultManager: VaultManager) async {
        guard isEnabled else { return }
        isIndexing = true
        let files = vaultManager.allMarkdownFiles()
        let vaultURL = vaultManager.vaultURL
        var count = 0

        for file in files {
            let relativePath = file.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let truncated = String(content.prefix(maxContentLength))

            if let embedding = await embed(text: truncated) {
                embeddings[relativePath] = embedding
                updatedAt[relativePath] = Date()
                count += 1
                indexedCount = count
            }
        }

        saveEmbeddings()
        isIndexing = false
    }

    func reindexIfNeeded(url: URL, content: String, vaultURL: URL) async {
        guard isEnabled else { return }
        let relativePath = url.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        let truncated = String(content.prefix(maxContentLength))

        if let embedding = await embed(text: truncated) {
            embeddings[relativePath] = embedding
            updatedAt[relativePath] = Date()
            saveEmbeddings()
        }
    }

    func toggle(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "semanticSearchEnabled")
    }

    func setModel(_ model: String) {
        embeddingModel = model
        UserDefaults.standard.set(model, forKey: "semanticEmbeddingModel")
    }

    // MARK: - Embedding API

    private func embed(text: String) async -> [Float]? {
        let serverURL = UserDefaults.standard.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        guard let url = URL(string: "\(serverURL)/api/embeddings") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": embeddingModel,
            "prompt": text
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddingArr = json["embedding"] as? [Double]
        else { return nil }

        return embeddingArr.map { Float($0) }
    }

    // MARK: - Cosine Similarity

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? Double(dot / denom) : 0
    }

    // MARK: - Persistence

    private func storageURL() -> URL {
        let vaultPath = UserDefaults.standard.string(forKey: "vaultPath") ?? ""
        let vaultHash = vaultPath.md5Hash
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let dir = homeDir.appendingPathComponent(".notero/embeddings/\(vaultHash)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("embeddings.json")
    }

    private func saveEmbeddings() {
        let url = storageURL()
        let data: [String: Any] = embeddings.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value.map { Double($0) }
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? jsonData.write(to: url)
        }
    }

    private func loadEmbeddings() {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]]
        else { return }

        embeddings = json.mapValues { $0.map { Float($0) } }
        indexedCount = embeddings.count
    }
}

struct SemanticSearchResult: Identifiable {
    let id = UUID()
    let path: String
    let noteName: String
    let noteURL: URL
    let similarity: Double

    var percentString: String {
        "\(Int(similarity * 100))%"
    }
}
