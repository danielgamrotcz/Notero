import Foundation

actor OllamaService {
    func improve(text: String, model: String, serverURL: String, prompt: String) async throws -> String {
        let endpoint = "\(serverURL)/api/generate"
        guard let url = URL(string: endpoint) else {
            throw AIError.connectionFailed("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "prompt": "\(prompt)\n\n\(text)",
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIError.connectionFailed("Ollama server returned an error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["response"] as? String
        else {
            throw AIError.invalidResponse
        }

        return result
    }

    func detectModels(serverURL: String) async throws -> [String] {
        let endpoint = "\(serverURL)/api/tags"
        guard let url = URL(string: endpoint) else {
            throw AIError.connectionFailed("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else {
            return []
        }

        return models.compactMap { $0["name"] as? String }
    }

    func testConnection(serverURL: String) async throws -> Bool {
        let models = try await detectModels(serverURL: serverURL)
        return !models.isEmpty
    }
}
