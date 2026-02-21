import Foundation

struct NoteFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
    var content: String
    var modificationDate: Date

    init(url: URL, content: String = "", modificationDate: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.content = content
        self.modificationDate = modificationDate
    }

    var relativePath: String {
        url.lastPathComponent
    }

    var wordCount: Int {
        content.split { $0.isWhitespace || $0.isNewline }.count
    }

    var characterCount: Int {
        content.count
    }
}
