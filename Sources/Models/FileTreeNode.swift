import Foundation

enum NoteSortOrder: String, CaseIterable {
    case nameAscending = "nameAsc"
    case nameDescending = "nameDesc"
    case modifiedNewest = "modifiedNewest"
    case modifiedOldest = "modifiedOldest"
    case createdNewest = "createdNewest"
    case createdOldest = "createdOldest"

    var label: String {
        switch self {
        case .nameAscending:  return "Name (A → Z)"
        case .nameDescending: return "Name (Z → A)"
        case .modifiedNewest: return "Modified (newest)"
        case .modifiedOldest: return "Modified (oldest)"
        case .createdNewest:  return "Created (newest)"
        case .createdOldest:  return "Created (oldest)"
        }
    }

    var icon: String {
        switch self {
        case .nameAscending:  return "textformat.abc"
        case .nameDescending: return "textformat.abc"
        case .modifiedNewest: return "clock"
        case .modifiedOldest: return "clock"
        case .createdNewest:  return "calendar"
        case .createdOldest:  return "calendar"
        }
    }
}

enum FileTreeNode: Identifiable, Hashable {
    case folder(FolderNode)
    case file(FileNode)

    var id: URL { url }

    var url: URL {
        switch self {
        case .folder(let node): return node.url
        case .file(let node): return node.url
        }
    }

    var name: String {
        switch self {
        case .folder(let node): return node.name
        case .file(let node): return node.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var children: [FileTreeNode]? {
        switch self {
        case .folder(let node): return node.children
        case .file: return nil
        }
    }
}

struct FolderNode: Hashable {
    let url: URL
    var name: String { url.lastPathComponent }
    var children: [FileTreeNode]

    init(url: URL, children: [FileTreeNode] = []) {
        self.url = url
        self.children = children
    }

    var noteCount: Int {
        children.reduce(0) { count, node in
            switch node {
            case .file: return count + 1
            case .folder(let folder): return count + folder.noteCount
            }
        }
    }
}

struct FileNode: Hashable {
    let url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
    var modificationDate: Date
    var createdDate: Date

    init(url: URL, modificationDate: Date = Date(), createdDate: Date = Date()) {
        self.url = url
        self.modificationDate = modificationDate
        self.createdDate = createdDate
    }
}
