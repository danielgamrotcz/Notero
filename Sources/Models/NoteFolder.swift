import Foundation

struct NoteFolder: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String { url.lastPathComponent }

    init(url: URL) {
        self.id = UUID()
        self.url = url
    }

    var noteCount: Int {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return contents.filter { $0.pathExtension == "md" }.count
    }
}
