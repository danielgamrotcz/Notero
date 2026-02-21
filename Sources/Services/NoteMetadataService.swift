import Foundation

struct NoteMetadata: Codable {
    var id: String
    var created: Date
}

@MainActor
final class NoteMetadataService {
    static let shared = NoteMetadataService()

    private let queue = DispatchQueue(label: "cz.danielgamrot.Notero.metadata", qos: .utility)
    private var cache: [String: NoteMetadata] = [:]

    private init() {}

    // MARK: - Public API

    func metadata(for url: URL) -> NoteMetadata {
        let key = metadataFilePath(for: url)
        if let cached = cache[key] {
            return cached
        }
        let meta = loadOrCreate(for: url)
        cache[key] = meta
        return meta
    }

    func ensureID(for url: URL) -> String {
        return metadata(for: url).id
    }

    func findNote(byID noteID: String, in vaultURL: URL) -> URL? {
        let metaDir = metadataBaseDir(for: vaultURL)
        guard FileManager.default.fileExists(atPath: metaDir) else { return nil }

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: metaDir),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "json" else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let meta = try? JSONDecoder.metadataDecoder.decode(NoteMetadata.self, from: data),
                  meta.id == noteID
            else { continue }

            // Reconstruct vault-relative path from metadata file path
            let relativePath = fileURL.path
                .replacingOccurrences(of: metaDir + "/", with: "")
                .replacingOccurrences(of: ".json", with: "")
            let noteURL = vaultURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: noteURL.path) {
                return noteURL
            }
        }
        return nil
    }

    func updatePath(from oldURL: URL, to newURL: URL) {
        let oldPath = metadataFilePath(for: oldURL)
        let newPath = metadataFilePath(for: newURL)

        guard FileManager.default.fileExists(atPath: oldPath) else { return }

        let newDir = (newPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: newDir, withIntermediateDirectories: true
        )
        try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)

        if let meta = cache[oldPath] {
            cache.removeValue(forKey: oldPath)
            cache[newPath] = meta
        }
    }

    // MARK: - Private

    private func loadOrCreate(for url: URL) -> NoteMetadata {
        let path = metadataFilePath(for: url)

        if let data = FileManager.default.contents(atPath: path),
           let meta = try? JSONDecoder.metadataDecoder.decode(NoteMetadata.self, from: data) {
            return meta
        }

        // Create new metadata
        let createdDate = fileCreationDate(for: url) ?? Date()
        let meta = NoteMetadata(id: UUID().uuidString.lowercased(), created: createdDate)
        save(meta, to: path)
        return meta
    }

    private func save(_ meta: NoteMetadata, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder.metadataEncoder.encode(meta) {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    private func metadataFilePath(for noteURL: URL) -> String {
        let vaultURL = vaultURLForNote(noteURL)
        let relativePath = noteURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        let baseDir = metadataBaseDir(for: vaultURL)
        return "\(baseDir)/\(relativePath).json"
    }

    private func metadataBaseDir(for vaultURL: URL) -> String {
        let vaultHash = vaultURL.path.md5Hash
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/.notero/meta/\(vaultHash)"
    }

    private func vaultURLForNote(_ noteURL: URL) -> URL {
        if let savedPath = UserDefaults.standard.string(forKey: "vaultPath") {
            return URL(fileURLWithPath: savedPath)
        }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Notero")
    }

    private func fileCreationDate(for url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.creationDate] as? Date
    }
}

// MARK: - JSON Coding

private extension JSONEncoder {
    static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let metadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Simple hash for vault path

extension String {
    var md5Hash: String {
        // Simple hash using hashValue for directory naming
        let hash = abs(self.hashValue)
        return String(format: "%08x", hash)
    }
}
