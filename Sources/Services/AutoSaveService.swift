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

    init(vaultManager: VaultManager, delay: TimeInterval = 1.0) {
        self.vaultManager = vaultManager
        self.delay = delay
    }

    func updateDelay(_ newDelay: TimeInterval) {
        delay = newDelay
    }

    func scheduleSave(content: String, to url: URL) {
        saveTask?.cancel()
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

    private func performSave(content: String, to url: URL) {
        saveStatus = .saving
        vaultManager?.saveNote(content: content, to: url)
        saveStatus = .saved(Date())
    }
}
