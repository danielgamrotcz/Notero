import Foundation

final class ScrollPositionStore {
    static let shared = ScrollPositionStore()

    private var positions: [String: CGFloat] = [:]
    private var accessOrder: [String] = []
    private var isDirty = false
    private let maxEntries = 1000

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Notero")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scrollPositions.json")
    }()

    private init() {
        load()
    }

    func save(fraction: CGFloat, for url: URL, relativeTo vaultURL: URL) {
        let key = relativePath(for: url, relativeTo: vaultURL)
        let clamped = min(1, max(0, fraction))
        positions[key] = clamped
        touchAccessOrder(key)
        isDirty = true
    }

    func fraction(for url: URL, relativeTo vaultURL: URL) -> CGFloat {
        let key = relativePath(for: url, relativeTo: vaultURL)
        return positions[key] ?? 0
    }

    func flush() {
        guard isDirty else { return }
        evictIfNeeded()
        do {
            let data = try JSONEncoder().encode(positions)
            try data.write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            // Silent failure — scroll positions are non-critical
        }
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: CGFloat].self, from: data) else { return }
        positions = decoded
        accessOrder = Array(decoded.keys)
    }

    private func relativePath(for url: URL, relativeTo vaultURL: URL) -> String {
        url.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
    }

    private func touchAccessOrder(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        while positions.count > maxEntries, let oldest = accessOrder.first {
            positions.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }
}
