import Foundation
import Combine

@MainActor
final class AutoSaveService: ObservableObject {
    @Published var saveStatus: SaveStatus = .idle

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved(Date)
    }

    private var saveTask: Task<Void, Never>?
    private weak var vaultManager: VaultManager?
    private var delay: TimeInterval
    private var pendingSave: (content: String, url: URL)?
    var onDidSave: ((String, URL) -> Void)?

    init(vaultManager: VaultManager, delay: TimeInterval = 1.0) {
        self.vaultManager = vaultManager
        self.delay = delay
    }

    func updateDelay(_ newDelay: TimeInterval) {
        delay = newDelay
    }

    func scheduleSave(content: String, to url: URL) {
        saveTask?.cancel()
        pendingSave = (content, url)
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            performSave(content: content, to: url)
        }
    }

    func saveImmediately(content: String, to url: URL) {
        saveTask?.cancel()
        performSave(content: content, to: url)
    }

    func flushIfNeeded() {
        guard let pending = pendingSave else { return }
        saveTask?.cancel()
        performSave(content: pending.content, to: pending.url)
    }

    private func performSave(content: String, to url: URL) {
        saveStatus = .saving
        vaultManager?.saveNote(content: content, to: url)
        pendingSave = nil
        saveStatus = .saved(Date())
        onDidSave?(content, url)
    }
}
