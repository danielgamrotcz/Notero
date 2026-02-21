import Foundation
import Combine

@MainActor
final class FavoritesManager: ObservableObject {
    @Published var favorites: Set<String> = [] // vault-relative paths
    @Published var orderedFavorites: [String] = [] // for display order

    private let favoritesKey = "favorites"
    private let orderKey = "favoritesOrder"

    init() {
        let savedFavs = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favorites = Set(savedFavs)
        orderedFavorites = UserDefaults.standard.stringArray(forKey: orderKey) ?? savedFavs
        // Ensure order matches set
        orderedFavorites = orderedFavorites.filter { favorites.contains($0) }
    }

    func isFavorite(_ relativePath: String) -> Bool {
        favorites.contains(relativePath)
    }

    func toggleFavorite(_ relativePath: String) {
        if favorites.contains(relativePath) {
            removeFavorite(relativePath)
        } else {
            addFavorite(relativePath)
        }
    }

    func addFavorite(_ relativePath: String) {
        guard !favorites.contains(relativePath) else { return }
        favorites.insert(relativePath)
        orderedFavorites.append(relativePath)
        save()
    }

    func removeFavorite(_ relativePath: String) {
        favorites.remove(relativePath)
        orderedFavorites.removeAll { $0 == relativePath }
        save()
    }

    func reorder(_ newOrder: [String]) {
        orderedFavorites = newOrder.filter { favorites.contains($0) }
        save()
    }

    func cleanupDeleted(vaultURL: URL) {
        let fm = FileManager.default
        let deleted = favorites.filter { path in
            !fm.fileExists(atPath: vaultURL.appendingPathComponent(path).path)
        }
        for path in deleted {
            favorites.remove(path)
            orderedFavorites.removeAll { $0 == path }
        }
        save()
    }

    func relativePath(for url: URL, vaultURL: URL) -> String {
        url.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
    }

    private func save() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
        UserDefaults.standard.set(orderedFavorites, forKey: orderKey)
    }
}
