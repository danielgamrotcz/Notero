import Foundation
import AppKit
import Combine

@MainActor
final class VaultManager: ObservableObject {
    @Published var fileTree: [FileTreeNode] = []
    @Published var vaultURL: URL

    private var fsEventStream: FSEventStreamRef?
    private let fileManager = FileManager.default
    var currentSortOrder: NoteSortOrder = .nameAscending
    var onFileSystemChange: (() -> Void)?

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: "vaultPath") {
            self.vaultURL = URL(fileURLWithPath: savedPath)
        } else {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.vaultURL = documentsURL.appendingPathComponent("Notero")
        }
        ensureVaultExists()
        loadFileTree()
        startWatching()
    }

    func changeVault(to url: URL) {
        stopWatching()
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: "vaultPath")
        ensureVaultExists()
        loadFileTree()
        startWatching()
    }

    func ensureVaultExists() {
        if !fileManager.fileExists(atPath: vaultURL.path) {
            try? fileManager.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        }
    }

    func loadFileTree(sortOrder: NoteSortOrder? = nil) {
        if let sortOrder { currentSortOrder = sortOrder }
        fileTree = buildTree(at: vaultURL, sortOrder: currentSortOrder)
    }

    func buildTree(at url: URL, sortOrder: NoteSortOrder = .nameAscending) -> [FileTreeNode] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FileTreeNode] = []
        var files: [FileTreeNode] = []

        for itemURL in contents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                let children = buildTree(at: itemURL, sortOrder: sortOrder)
                folders.append(.folder(FolderNode(url: itemURL, children: children)))
            } else if itemURL.pathExtension == "md" {
                let modDate = resourceValues?.contentModificationDate ?? Date()
                // Use metadata created date if available, fall back to filesystem
                let meta = NoteMetadataService.shared.metadata(for: itemURL)
                let createdDate = meta.created
                files.append(.file(FileNode(url: itemURL, modificationDate: modDate, createdDate: createdDate)))
            }
        }

        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        switch sortOrder {
        case .nameAscending:
            files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .modifiedNewest:
            files.sort {
                guard case .file(let a) = $0, case .file(let b) = $1 else { return false }
                return a.modificationDate > b.modificationDate
            }
        case .modifiedOldest:
            files.sort {
                guard case .file(let a) = $0, case .file(let b) = $1 else { return false }
                return a.modificationDate < b.modificationDate
            }
        case .createdNewest:
            files.sort {
                guard case .file(let a) = $0, case .file(let b) = $1 else { return false }
                return a.createdDate > b.createdDate
            }
        case .createdOldest:
            files.sort {
                guard case .file(let a) = $0, case .file(let b) = $1 else { return false }
                return a.createdDate < b.createdDate
            }
        }

        return folders + files
    }

    // MARK: - File Operations

    func createNote(named name: String, in folderURL: URL? = nil) -> URL? {
        let folder = folderURL ?? vaultURL
        var fileName = name.hasSuffix(".md") ? name : "\(name).md"
        var targetURL = folder.appendingPathComponent(fileName)

        var counter = 1
        while fileManager.fileExists(atPath: targetURL.path) {
            let baseName = name.hasSuffix(".md")
                ? String(name.dropLast(3)) : name
            fileName = "\(baseName) \(counter).md"
            targetURL = folder.appendingPathComponent(fileName)
            counter += 1
        }

        let created = fileManager.createFile(atPath: targetURL.path, contents: Data())
        if created {
            loadFileTree()
            return targetURL
        }
        return nil
    }

    func createFolder(named name: String, in folderURL: URL? = nil) -> URL? {
        let parent = folderURL ?? vaultURL
        let targetURL = parent.appendingPathComponent(name)

        do {
            try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            loadFileTree()
            return targetURL
        } catch {
            Log.vault.error("Failed to create folder: \(error.localizedDescription)")
            return nil
        }
    }

    func readNote(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func saveNote(content: String, to url: URL) {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            // Fallback: direct write
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func renameItem(at url: URL, to newName: String) -> URL? {
        let ext = url.pathExtension
        let finalName: String
        if ext == "md" && !newName.hasSuffix(".md") {
            finalName = "\(newName).md"
        } else {
            finalName = newName
        }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(finalName)

        do {
            try fileManager.moveItem(at: url, to: newURL)
            loadFileTree()
            return newURL
        } catch {
            Log.vault.error("Rename failed: \(error.localizedDescription)")
            return nil
        }
    }

    func moveToTrash(url: URL) {
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            loadFileTree()
        } catch {
            Log.vault.error("Trash failed: \(error.localizedDescription)")
        }
    }

    func duplicateNote(at url: URL) -> URL? {
        let baseName = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        var counter = 1
        var newURL = folder.appendingPathComponent("\(baseName) copy.md")
        while fileManager.fileExists(atPath: newURL.path) {
            newURL = folder.appendingPathComponent("\(baseName) copy \(counter).md")
            counter += 1
        }

        do {
            try fileManager.copyItem(at: url, to: newURL)
            loadFileTree()
            return newURL
        } catch {
            Log.vault.error("Duplicate failed: \(error.localizedDescription)")
            return nil
        }
    }

    func moveItem(from sourceURL: URL, to destinationFolderURL: URL) {
        let newURL = destinationFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try fileManager.moveItem(at: sourceURL, to: newURL)
            loadFileTree()
        } catch {
            Log.vault.error("Move failed: \(error.localizedDescription)")
        }
    }

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func allMarkdownFiles() -> [URL] {
        var result: [URL] = []
        collectMarkdownFiles(at: vaultURL, into: &result)
        return result
    }

    private func collectMarkdownFiles(at url: URL, into result: inout [URL]) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for itemURL in contents {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                collectMarkdownFiles(at: itemURL, into: &result)
            } else if itemURL.pathExtension == "md" {
                result.append(itemURL)
            }
        }
    }

    // MARK: - FSEvents Watcher

    private func startWatching() {
        let path = vaultURL.path as CFString
        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let manager = Unmanaged<VaultManager>.fromOpaque(info).takeUnretainedValue()
            print("[VaultManager] FSEvent fired, \(numEvents) events")
            Task { @MainActor in
                manager.loadFileTree()
                manager.onFileSystemChange?()
            }
        }

        fsEventStream = FSEventStreamCreate(
            nil, callback, &context, pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
            )
        )

        if let stream = fsEventStream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    private func stopWatching() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }

    deinit {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
