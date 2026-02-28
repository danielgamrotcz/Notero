import Foundation

actor SupabaseService {
    struct Config {
        let url: String
        let serviceKey: String
        let userId: String

        var isValid: Bool { !url.isEmpty && !serviceKey.isEmpty && !userId.isEmpty }
    }

    private let session = URLSession.shared
    private var folderCache: [String: String] = [:]

    // MARK: - Public API

    func syncNote(path: String, title: String, content: String, config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            let folderPath = (path as NSString).deletingLastPathComponent
            let folderId = try await ensureFolder(path: folderPath, config: config)

            var body: [String: Any] = [
                "user_id": config.userId,
                "title": title,
                "content": content,
                "path": path,
            ]
            if let folderId { body["folder_id"] = folderId }

            _ = try await request(method: "POST", table: "notes", data: body,
                                  extraHeaders: ["Prefer": "resolution=merge-duplicates"], config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.syncNote failed: \(error)")
            return false
        }
    }

    func deleteNote(path: String, config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? path
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)"
            _ = try await request(method: "DELETE", table: "notes", params: qs, config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.deleteNote failed: \(error)")
            return false
        }
    }

    func renameNote(oldPath: String, newPath: String, config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            let encoded = oldPath.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? oldPath
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)"
            let newTitle = Self.extractTitle(from: nil, filename: (newPath as NSString).lastPathComponent)
            let newFolderPath = (newPath as NSString).deletingLastPathComponent
            let newFolderId = try await ensureFolder(path: newFolderPath, config: config)

            var body: [String: Any] = [
                "path": newPath,
                "title": newTitle,
            ]
            if let newFolderId { body["folder_id"] = newFolderId }

            _ = try await request(method: "PATCH", table: "notes", data: body, params: qs, config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.renameNote failed: \(error)")
            return false
        }
    }

    func syncFolder(path: String, parentPath: String?, config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            _ = try await ensureFolder(path: path, config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.syncFolder failed: \(error)")
            return false
        }
    }

    func deleteFolder(path: String, config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? path
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)"
            _ = try await request(method: "DELETE", table: "folders", params: qs, config: config)
            folderCache.removeValue(forKey: path)
            return true
        } catch {
            Log.general.warning("SupabaseService.deleteFolder failed: \(error)")
            return false
        }
    }

    func syncFavourites(paths: [String], config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            // Delete existing favourites
            let delQs = "?user_id=eq.\(config.userId)"
            _ = try await request(method: "DELETE", table: "favourites", params: delQs, config: config)

            // Re-insert in order
            for (index, path) in paths.enumerated() {
                let pathWithoutMd = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
                let encoded = pathWithoutMd.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? pathWithoutMd
                let noteQs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)&select=id"
                let notes = try await request(method: "GET", table: "notes", params: noteQs, config: config)
                guard let noteId = notes.first?["id"] as? String else { continue }

                let fav: [String: Any] = [
                    "user_id": config.userId,
                    "note_id": noteId,
                    "sort_order": index,
                ]
                _ = try await request(method: "POST", table: "favourites", data: fav, config: config)
            }
            return true
        } catch {
            Log.general.warning("SupabaseService.syncFavourites failed: \(error)")
            return false
        }
    }

    func testConnection(config: Config) async -> Bool {
        guard config.isValid else { return false }
        do {
            _ = try await request(method: "GET", table: "notes",
                                  params: "?select=id&limit=1", config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.testConnection failed: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    static func relativePath(for url: URL, vaultURL: URL) -> String {
        let path = url.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        if path.hasSuffix(".md") {
            return String(path.dropLast(3))
        }
        return path
    }

    static func extractTitle(from content: String?, filename: String) -> String {
        if let content, let range = content.range(of: "^#\\s+(.+)$", options: .regularExpression) {
            let line = String(content[range])
            let title = line.drop(while: { $0 == "#" || $0 == " " })
            if !title.isEmpty { return String(title) }
        }
        let name = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
        return name
    }

    // MARK: - Folder Chain

    private func ensureFolder(path: String, config: Config) async throws -> String? {
        if path.isEmpty || path == "." { return nil }
        if let cached = folderCache[path] { return cached }

        let parts = path.split(separator: "/").map(String.init)
        var parentId: String?

        for i in 0..<parts.count {
            let currentPath = parts[0...i].joined(separator: "/")
            if let cached = folderCache[currentPath] {
                parentId = cached
                continue
            }

            let encoded = currentPath.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? currentPath
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)&select=id"
            let rows = try await request(method: "GET", table: "folders", params: qs, config: config)

            if let first = rows.first, let id = first["id"] as? String {
                parentId = id
            } else {
                var folderData: [String: Any] = [
                    "user_id": config.userId,
                    "name": parts[i],
                    "path": currentPath,
                ]
                if let parentId { folderData["parent_id"] = parentId }

                let created = try await request(method: "POST", table: "folders", data: folderData,
                                                extraHeaders: ["Prefer": "return=representation"], config: config)
                guard let first = created.first, let id = first["id"] as? String else {
                    throw URLError(.badServerResponse)
                }
                parentId = id
            }
            folderCache[currentPath] = parentId
        }

        return parentId
    }

    // MARK: - HTTP

    private func request(method: String, table: String,
                         data: [String: Any]? = nil, params: String = "",
                         extraHeaders: [String: String] = [:],
                         config: Config) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(config.url)/rest/v1/\(table)\(params)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue(config.serviceKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.serviceKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: key)
        }

        if let data {
            req.httpBody = try JSONSerialization.data(withJSONObject: data)
        }

        let (responseData, response) = try await session.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(code): \(body)"
            ])
        }

        let text = String(data: responseData, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let parsed = try JSONSerialization.jsonObject(with: responseData)
        if let array = parsed as? [[String: Any]] { return array }
        if let dict = parsed as? [String: Any] { return [dict] }
        return []
    }
}
