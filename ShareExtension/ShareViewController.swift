import Cocoa
import UniformTypeIdentifiers

class ShareViewController: NSViewController {
    private var titleField: NSTextField!
    private var contentView: NSTextView!
    private var folderPicker: NSPopUpButton!
    private var targetPicker: NSPopUpButton!
    private var sharedTitle = ""
    private var sharedContent = ""

    private var vaultURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathFile = home.appendingPathComponent(".notero/vault-path.txt")
        guard let path = try? String(contentsOf: pathFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 340))
        self.view = container

        // Title label + field
        let titleLabel = NSTextField(labelWithString: "Note title:")
        titleLabel.frame = NSRect(x: 16, y: 300, width: 80, height: 20)
        container.addSubview(titleLabel)

        titleField = NSTextField(frame: NSRect(x: 100, y: 298, width: 284, height: 24))
        titleField.placeholderString = "Untitled"
        container.addSubview(titleField)

        // Content
        let contentLabel = NSTextField(labelWithString: "Content:")
        contentLabel.frame = NSRect(x: 16, y: 268, width: 80, height: 20)
        container.addSubview(contentLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 100, y: 120, width: 284, height: 150))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView = NSTextView(frame: scrollView.contentView.bounds)
        contentView.isEditable = true
        contentView.isRichText = false
        contentView.autoresizingMask = [.width, .height]
        contentView.font = NSFont.systemFont(ofSize: 13)
        scrollView.documentView = contentView
        container.addSubview(scrollView)

        // Add to picker
        let addToLabel = NSTextField(labelWithString: "Add to:")
        addToLabel.frame = NSRect(x: 16, y: 86, width: 80, height: 20)
        container.addSubview(addToLabel)

        targetPicker = NSPopUpButton(frame: NSRect(x: 100, y: 84, width: 284, height: 24))
        targetPicker.addItem(withTitle: "New Note")
        loadRecentNotes()
        container.addSubview(targetPicker)

        // Folder picker
        let folderLabel = NSTextField(labelWithString: "Folder:")
        folderLabel.frame = NSRect(x: 16, y: 54, width: 80, height: 20)
        container.addSubview(folderLabel)

        folderPicker = NSPopUpButton(frame: NSRect(x: 100, y: 52, width: 284, height: 24))
        folderPicker.addItem(withTitle: "/")
        loadFolders()
        container.addSubview(folderPicker)

        // Buttons
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.frame = NSRect(x: 200, y: 12, width: 80, height: 30)
        cancelButton.bezelStyle = .rounded
        container.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveButton.frame = NSRect(x: 290, y: 12, width: 80, height: 30)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        container.addSubview(saveButton)

        extractSharedContent()
    }

    private func extractSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else { return }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            self?.sharedTitle = url.host ?? "Link"
                            self?.sharedContent = "[\(url.host ?? "Link")](\(url.absoluteString))"
                            self?.titleField.stringValue = self?.sharedTitle ?? ""
                            self?.contentView.string = self?.sharedContent ?? ""
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                    if let text = item as? String {
                        DispatchQueue.main.async {
                            let firstLine = text.components(separatedBy: .newlines).first ?? "Shared Note"
                            self?.sharedTitle = String(firstLine.prefix(60))
                            self?.sharedContent = text
                            self?.titleField.stringValue = self?.sharedTitle ?? ""
                            self?.contentView.string = self?.sharedContent ?? ""
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.html.identifier) { [weak self] item, _ in
                    if let html = item as? String {
                        let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        DispatchQueue.main.async {
                            let firstLine = plain.components(separatedBy: .newlines)
                                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Shared Note"
                            self?.sharedTitle = String(firstLine.prefix(60))
                            self?.sharedContent = plain
                            self?.titleField.stringValue = self?.sharedTitle ?? ""
                            self?.contentView.string = self?.sharedContent ?? ""
                        }
                    }
                }
            }
        }
    }

    private func loadRecentNotes() {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vault, includingPropertiesForKeys: [.contentModificationDateKey],
                                              options: [.skipsHiddenFiles]) else { return }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            files.append((url, date))
        }
        files.sort { $0.1 > $1.1 }
        for (url, _) in files.prefix(20) {
            targetPicker.addItem(withTitle: url.deletingPathExtension().lastPathComponent)
            targetPicker.lastItem?.representedObject = url
        }
    }

    private func loadFolders() {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vault, includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let relative = url.path.replacingOccurrences(of: vault.path + "/", with: "")
                folderPicker.addItem(withTitle: relative)
                folderPicker.lastItem?.representedObject = url
            }
        }
    }

    @objc private func saveAction() {
        guard let vault = vaultURL else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let title = titleField.stringValue.isEmpty ? "Shared Note" : titleField.stringValue
        let content = contentView.string

        if targetPicker.indexOfSelectedItem == 0 {
            // New note
            let folder: URL
            if let selectedFolder = folderPicker.selectedItem?.representedObject as? URL {
                folder = selectedFolder
            } else {
                folder = vault
            }
            let sanitized = title.replacingOccurrences(of: "[:/\\\\?*\"<>|]", with: "-", options: .regularExpression)
            var fileURL = folder.appendingPathComponent("\(sanitized).md")
            var counter = 2
            while FileManager.default.fileExists(atPath: fileURL.path) {
                fileURL = folder.appendingPathComponent("\(sanitized) \(counter).md")
                counter += 1
            }
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            // Append to existing
            if let noteURL = targetPicker.selectedItem?.representedObject as? URL {
                let existing = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""
                let appended = existing + "\n\n---\n\n" + content
                try? appended.write(to: noteURL, atomically: true, encoding: .utf8)
            }
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func cancelAction() {
        extensionContext?.cancelRequest(withError: NSError(domain: "NoteroShare", code: 0))
    }
}
