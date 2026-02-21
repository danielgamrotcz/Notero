import Foundation
import Combine

@MainActor
final class PinnedNotesManager: ObservableObject {
    @Published var pinnedNotes: [String] = [] // vault-relative paths

    private let key = "pinnedNotes"

    init() {
        pinnedNotes = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func isPinned(_ relativePath: String) -> Bool {
        pinnedNotes.contains(relativePath)
    }

    func togglePin(_ relativePath: String) {
        if let index = pinnedNotes.firstIndex(of: relativePath) {
            pinnedNotes.remove(at: index)
        } else {
            pinnedNotes.append(relativePath)
        }
        save()
    }

    func pin(_ relativePath: String) {
        guard !pinnedNotes.contains(relativePath) else { return }
        pinnedNotes.append(relativePath)
        save()
    }

    func unpin(_ relativePath: String) {
        pinnedNotes.removeAll { $0 == relativePath }
        save()
    }

    func reorder(_ newOrder: [String]) {
        pinnedNotes = newOrder.filter { pinnedNotes.contains($0) }
        save()
    }

    func cleanupDeleted(vaultURL: URL) {
        let fm = FileManager.default
        pinnedNotes.removeAll { path in
            !fm.fileExists(atPath: vaultURL.appendingPathComponent(path).path)
        }
        save()
    }

    func relativePath(for url: URL, vaultURL: URL) -> String {
        url.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
    }

    private func save() {
        UserDefaults.standard.set(pinnedNotes, forKey: key)
    }
}
