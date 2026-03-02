import Foundation

actor SupabaseService: SupabaseServiceProtocol {
    struct Config: Codable {
        let url: String
        let serviceKey: String
        let userId: String

        var isValid: Bool { !url.isEmpty && !serviceKey.isEmpty && !userId.isEmpty }
    }

    private let session = URLSession.shared
    private var folderCache: [String: String] = [:]

    private static func nfc(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    // MARK: - Public API

    func syncNote(path: String, title: String, content: String, createdAt: Date? = nil, config: Config) async -> Bool {
        let path = Self.nfc(path)
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
            if let createdAt { body["created_at"] = Self.iso8601Formatter.string(from: createdAt) }

            _ = try await request(method: "POST", table: "notes", data: body,
                                  extraHeaders: ["Prefer": "resolution=merge-duplicates"], config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.syncNote failed: \(error)")
            return false
        }
    }

    func deleteNote(path: String, config: Config) async -> Bool {
        let path = Self.nfc(path)
        guard config.isValid else { return false }
        do {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? path
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)"
            let rows = try await request(method: "DELETE", table: "notes", params: qs,
                                         extraHeaders: ["Prefer": "return=representation"], config: config)
            return !rows.isEmpty
        } catch {
            Log.general.warning("SupabaseService.deleteNote failed: \(error)")
            return false
        }
    }

    func renameNote(oldPath: String, newPath: String, config: Config) async -> Bool {
        let oldPath = Self.nfc(oldPath)
        let newPath = Self.nfc(newPath)
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
        let path = Self.nfc(path)
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
        let path = Self.nfc(path)
        guard config.isValid else { return false }
        do {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? path
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)"
            let rows = try await request(method: "DELETE", table: "folders", params: qs,
                                         extraHeaders: ["Prefer": "return=representation"], config: config)
            folderCache.removeValue(forKey: path)
            return !rows.isEmpty
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
                let pathWithoutMd = Self.nfc(path.hasSuffix(".md") ? String(path.dropLast(3)) : path)
                let encoded = pathWithoutMd.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? pathWithoutMd

                // Try notes table first
                let noteQs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)&select=id"
                let notes = try await request(method: "GET", table: "notes", params: noteQs, config: config)

                var fav: [String: Any] = [
                    "user_id": config.userId,
                    "sort_order": index,
                ]

                if let noteId = notes.first?["id"] as? String {
                    fav["note_id"] = noteId
                } else {
                    // It's a folder — store path directly
                    fav["path"] = pathWithoutMd
                }

                _ = try await request(method: "POST", table: "favourites", data: fav, config: config)
            }
            return true
        } catch {
            Log.general.warning("SupabaseService.syncFavourites failed: \(error)")
            return false
        }
    }

    func testConnection(config: Config) async -> Bool {
        guard config.isValid else {
            Log.general.warning("SupabaseService.testConnection: config invalid")
            return false
        }
        Log.general.info("SupabaseService.testConnection url=\(config.url) keyLen=\(config.serviceKey.count) uid=\(config.userId)")
        do {
            _ = try await request(method: "GET", table: "notes",
                                  params: "?select=id&limit=1", config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.testConnection failed: \(error)")
            return false
        }
    }

    // MARK: - Pull Sync

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func fetchChangedNotes(since: Date, config: Config) async throws -> [[String: Any]] {
        let ts = Self.iso8601Formatter.string(from: since)
        let encoded = ts.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ts
        let qs = "?user_id=eq.\(config.userId)&updated_at=gt.\(encoded)&select=id,title,content,path,updated_at&order=updated_at.asc"
        return try await request(method: "GET", table: "notes", params: qs, config: config)
    }

    func fetchAllNotes(config: Config) async throws -> [[String: Any]] {
        let qs = "?user_id=eq.\(config.userId)&select=id,title,content,path,updated_at&order=path.asc"
        return try await request(method: "GET", table: "notes", params: qs, config: config)
    }

    func fetchChangedFolders(since: Date, config: Config) async throws -> [[String: Any]] {
        let ts = Self.iso8601Formatter.string(from: since)
        let encoded = ts.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ts
        let qs = "?user_id=eq.\(config.userId)&updated_at=gt.\(encoded)&select=id,name,path&order=path.asc"
        return try await request(method: "GET", table: "folders", params: qs, config: config)
    }

    func fetchAllFolders(config: Config) async throws -> [[String: Any]] {
        let qs = "?user_id=eq.\(config.userId)&select=id,name,path&order=path.asc"
        return try await request(method: "GET", table: "folders", params: qs, config: config)
    }

    func fetchFavourites(config: Config) async throws -> [[String: Any]] {
        let qs = "?user_id=eq.\(config.userId)&select=note_id,sort_order,path,notes(path)&order=sort_order.asc"
        return try await request(method: "GET", table: "favourites", params: qs, config: config)
    }

    func fetchNoteDeletions(since: Date, config: Config) async throws -> [[String: Any]] {
        let ts = Self.iso8601Formatter.string(from: since)
        let encoded = ts.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ts
        let qs = "?user_id=eq.\(config.userId)&deleted_at=gt.\(encoded)&select=path,deleted_at"
        return try await request(method: "GET", table: "note_deletions", params: qs, config: config)
    }

    func fetchFolderDeletions(since: Date, config: Config) async throws -> [[String: Any]] {
        let ts = Self.iso8601Formatter.string(from: since)
        let encoded = ts.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ts
        let qs = "?user_id=eq.\(config.userId)&deleted_at=gt.\(encoded)&select=path,deleted_at"
        return try await request(method: "GET", table: "folder_deletions", params: qs, config: config)
    }

    // MARK: - Helpers

    static func fileCreationDate(for url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.creationDate] as? Date else { return nil }
        return date
    }

    func updateNoteCreatedAt(path: String, createdAt: Date, config: Config) async -> Bool {
        let path = Self.nfc(path)
        guard config.isValid else { return false }
        do {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? path
            let qs = "?user_id=eq.\(config.userId)&path=eq.\(encoded)"
            let body: [String: Any] = ["created_at": Self.iso8601Formatter.string(from: createdAt)]
            _ = try await request(method: "PATCH", table: "notes", data: body, params: qs, config: config)
            return true
        } catch {
            Log.general.warning("SupabaseService.updateNoteCreatedAt failed: \(error)")
            return false
        }
    }

    static func relativePath(for url: URL, vaultURL: URL) -> String {
        let path = url.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        let normalized = path.precomposedStringWithCanonicalMapping // NFD → NFC
        if normalized.hasSuffix(".md") {
            return String(normalized.dropLast(3))
        }
        return normalized
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
            Log.general.error("Supabase HTTP \(code) \(method) /\(table): \(body)")
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
