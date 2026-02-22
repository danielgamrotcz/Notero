# Notero – UX Fixes & Polish

Fix all issues below. Do not break any existing functionality.
Build must pass after each numbered fix. Commit after each fix.

---

## Fix 1 — Kurzor rovnou v editoru při otevření poznámky

**Problem:** Po otevření poznámky musí uživatel kliknout do editoru, aby mohl psát.

**Fix in `MarkdownEditorView.swift`:**

In `makeNSView`, after setting `textView.delegate = context.coordinator` and `textView.string = text`, add:

```swift
DispatchQueue.main.async {
    textView.window?.makeFirstResponder(textView)
}
```

In `updateNSView`, when content changes (the `if textView.string != text` block), after restoring `selectedRanges`, also ensure focus:

```swift
if textView.window?.firstResponder != textView {
    DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
    }
}
```

---

## Fix 2 — Automatické pokračování seznamů přes Enter

**Problem:** Po Enteru na řádku se seznamem (`- položka`, `1. položka`, `* položka`) se nepokračuje v seznamu.

**Fix in `MarkdownTextView` class (bottom of `MarkdownEditorView.swift`):**

Override `insertNewline(_:)`:

```swift
override func insertNewline(_ sender: Any?) {
    guard let textStorage = textStorage,
          let selectedRange = selectedRanges.first as? NSRange
    else {
        super.insertNewline(sender)
        return
    }

    let text = textStorage.string as NSString
    // Find start of current line
    let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    let currentLine = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

    // Unordered list: "- ", "* "
    if let match = currentLine.range(of: "^(\\s*)([-*])\\s", options: .regularExpression) {
        let prefix = String(currentLine[match])
        // If line has only the marker (empty item) — end the list
        let content = currentLine.trimmingCharacters(in: .whitespaces)
        if content == "-" || content == "*" {
            // Replace current line with empty line
            if let range = Range(lineRange, in: textStorage.string) {
                textStorage.replaceCharacters(in: lineRange, with: "\n")
            }
            return
        }
        super.insertNewline(sender)
        insertText(prefix, replacementRange: selectedRange(for: selectedRange))
        return
    }

    // Ordered list: "1. ", "2. " etc.
    if let match = currentLine.range(of: "^(\\s*)(\\d+)\\.\\s", options: .regularExpression) {
        let indentAndNumber = String(currentLine[match])
        // Extract the number and indent
        let indent = currentLine.prefix(while: { $0 == " " || $0 == "\t" })
        if let numRange = currentLine.range(of: "\\d+", options: .regularExpression) {
            let num = Int(currentLine[numRange]) ?? 1
            // If line has only the marker — end the list
            let stripped = currentLine.trimmingCharacters(in: .whitespaces)
            if stripped == "\(num)." {
                let lineNSRange = (textStorage.string as NSString).lineRange(
                    for: NSRange(location: selectedRange.location, length: 0)
                )
                textStorage.replaceCharacters(in: lineNSRange, with: "\n")
                return
            }
            super.insertNewline(sender)
            insertText("\(indent)\(num + 1). ", replacementRange: selectedRange(for: selectedRange))
            return
        }
    }

    // Task list: "- [ ] " or "- [x] "
    if currentLine.range(of: "^\\s*- \\[[ x]\\] ", options: .regularExpression) != nil {
        let indent = String(currentLine.prefix(while: { $0 == " " || $0 == "\t" }))
        super.insertNewline(sender)
        insertText("\(indent)- [ ] ", replacementRange: selectedRange(for: selectedRange))
        return
    }

    super.insertNewline(sender)
}

// Helper: current insertion point range after inserting newline
private func selectedRange(for _: NSRange) -> NSRange {
    return selectedRanges.first as? NSRange ?? NSRange(location: 0, length: 0)
}
```

---

## Fix 3 — Otevírání výsledků hledání v sidebaru

**Problem:** Výsledky hledání v sidebaru nejdou otevřít kliknutím.

**Investigate:** In `SidebarView.searchResults`, the `onTapGesture` calls `appState.openNote(url: result.noteURL)`. The bug is likely that `result.noteURL` is constructed incorrectly — the `SearchResult` may store a relative path but `noteURL` might not resolve to an existing file.

**Fix in `SearchService.swift` / `SearchIndex.swift`:** Verify `noteURL` is an absolute URL pointing to the actual file. When indexing, store the full absolute URL, not a relative path. When returning results, make sure `noteURL` resolves to a file that exists.

**Also fix in `SidebarView.searchResults`:** Add visual feedback that the row is clickable:

```swift
.background(
    RoundedRectangle(cornerRadius: 6)
        .fill(Color.clear)
        .contentShape(Rectangle())
)
.cornerRadius(6)
.onHover { hovering in
    // show hover highlight
}
```

Replace the current tap handler with a button for better hit testing:

```swift
Button {
    appState.openNote(url: result.noteURL)
    searchText = ""
    appState.searchService.results = []
} label: {
    VStack(alignment: .leading, spacing: 2) {
        // ... existing content
    }
}
.buttonStyle(.plain)
.padding(.vertical, 4)
.padding(.horizontal, 4)
```

---

## Fix 4 — Navigace v sidebaru kurzorovými šipkami

**Problem:** Složky a soubory v sidebaru nejdou procházet šipkami. Doleva/doprava zavírá/otevírá složky.

**Fix:** Replace the current `ScrollView + LazyVStack` in `SidebarView` with an `NSOutlineView`-backed view, OR implement keyboard navigation in SwiftUI by tracking a `focusedItemID` state.

**SwiftUI approach (preferred, no AppKit required):**

Add to `SidebarView`:

```swift
@State private var focusedItemID: URL? = nil
@FocusState private var sidebarFocused: Bool
```

In `FileTreeView`, propagate `focusedItemID` as a `Binding<URL?>`. In `FileTreeRowView`, apply:

```swift
.background(
    RoundedRectangle(cornerRadius: 4)
        .fill(isFocused ? Color.accentColor.opacity(0.1) : Color.clear)
)
```

Add a hidden focusable `NSView` overlay on the ScrollView that captures key events:

**NSViewRepresentable keyboard capture for sidebar:**

```swift
struct SidebarKeyHandler: NSViewRepresentable {
    var onArrowKey: (ArrowKey) -> Void

    enum ArrowKey { case up, down, left, right, enter }

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onArrowKey = onArrowKey
        return view
    }
    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.onArrowKey = onArrowKey
    }
}

class KeyCaptureView: NSView {
    var onArrowKey: ((SidebarKeyHandler.ArrowKey) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onArrowKey?(.up)
        case 125: onArrowKey?(.down)
        case 123: onArrowKey?(.left)
        case 124: onArrowKey?(.right)
        case 36:  onArrowKey?(.enter)
        default: super.keyDown(with: event)
        }
    }
}
```

Build a flat `visibleItems: [SidebarItem]` list from the current file tree (respecting which folders are expanded) and navigate the `focusedItemID` through this list:

- Up/Down: move focus index ± 1
- Right on folder: expand it (add children to visibleItems)
- Left on folder: collapse it; Left on file: move focus to parent folder
- Enter: open focused note (if file) or toggle expansion (if folder)
- On sidebar focus gained (Cmd+Shift+E): set focus to currently selected note

---

## Fix 5 — Navigace výsledků hledání kurzorovými šipkami

**Problem:** Výsledky hledání nejdou procházet šipkami.

**Fix in `SidebarView`:**

Add state:

```swift
@State private var focusedSearchResultIndex: Int = -1
```

Add `.onKeyPress` or key handler on the search `TextField`:

```swift
TextField("Search notes...", text: $searchText)
    .onKeyPress(.upArrow) {
        focusedSearchResultIndex = max(0, focusedSearchResultIndex - 1)
        return .handled
    }
    .onKeyPress(.downArrow) {
        let max = appState.searchService.results.count - 1
        focusedSearchResultIndex = min(max, focusedSearchResultIndex + 1)
        return .handled
    }
    .onKeyPress(.return) {
        if focusedSearchResultIndex >= 0 &&
           focusedSearchResultIndex < appState.searchService.results.count {
            let result = appState.searchService.results[focusedSearchResultIndex]
            appState.openNote(url: result.noteURL)
            searchText = ""
            focusedSearchResultIndex = -1
        }
        return .handled
    }
```

In `searchResults`, highlight the focused row:

```swift
.background(
    RoundedRectangle(cornerRadius: 6)
        .fill(index == focusedSearchResultIndex
            ? Color.accentColor.opacity(0.15)
            : Color.clear)
)
```

Reset `focusedSearchResultIndex = 0` whenever search results change.

---

## Fix 6 — Zvýraznění hledaného textu a procházení výskytů

**Problem:** Hledaný text není zvýrazněn při procházení výskytů v otevřené poznámce.

**Fix:** The editor has `textView.usesFindBar = true` which gives native macOS Find bar when `Cmd+F` is pressed. This should work out of the box — verify `Cmd+F` triggers `showFindAndReplace` or the native find bar.

If the find bar isn't showing: in `MarkdownTextView`, override:

```swift
override func performFindPanelAction(_ sender: Any?) {
    if let tag = (sender as? NSMenuItem)?.tag {
        switch tag {
        case 1: // Find
            self.window?.makeFirstResponder(self)
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: self, from: sender)
        default:
            super.performFindPanelAction(sender)
        }
    }
}
```

The standard `Cmd+G` / `Cmd+Shift+G` for next/previous match is provided automatically by `usesFindBar = true`.

For the sidebar search → highlight in editor: when user opens a note from search results, pass the search query to the editor and call:

```swift
// After openNote, trigger find bar with the search term
textView.performTextFinderAction(NSTextFinder.Action.setSearchString.rawValue as Any?)
```

In `AppState`, add `pendingSearchHighlight: String?`. After opening note from search, set this. In `MarkdownEditorView.updateNSView`, if `pendingSearchHighlight` is set, activate the find bar with that term.

---

## Fix 7 — CMD+T = nový tab, checkboxy = CMD+Enter

**Problem:** `Cmd+T` dělá checkboxy místo nového tabu. Checkboxy přesunout na `Cmd+Enter`.

**Fix — find every place where `Cmd+T` is registered as "Insert Task":**

Search codebase for `"t"` with `.command` modifier or `insertTask` or keyboard shortcut `T`.

In menu commands (wherever `Insert Task` is defined):
```swift
// Change from:
.keyboardShortcut("t", modifiers: .command)
// To:
.keyboardShortcut(.return, modifiers: .command)
```

In `MarkdownTextView`, if there's a key handler for `Cmd+T` inserting `- [ ] `, change it to `Cmd+Enter`.

Register `Cmd+T` for new tab:
```swift
// In app commands / menu:
Button("New Tab") {
    appState.openNewTab()
}
.keyboardShortcut("t", modifiers: .command)
```

---

## Fix 8 — Nový tab = prázdná stránka (bez obsahu)

**Problem:** Nový tab otevírá existující obsah místo prázdné stránky.

**Fix in `AppState` / `TabStateManager`:**

`openNewTab()` must set `selectedNoteURL = nil` and `currentContent = ""` for the new tab context. The new tab shows `EmptyStateView` — user then creates a new note with `Cmd+N` or opens one via `Cmd+O`.

If tabs are implemented via `NSWindowTabGroup`, opening a new tab creates a new window instance with fresh `AppState`. Ensure the new window starts with `selectedNoteURL = nil`.

If tabs are simulated in SwiftUI: add a `TabState` struct and `currentTabIndex`. New tab = append `TabState(selectedNoteURL: nil, content: "")` and switch to it.

---

## Fix 9 — Standardní práce s kartami (taby)

**Problem:** CMD+klik na poznámku v sidebaru by měl otevřít poznámku v nové kartě. Ostatní standardní zkratky pro taby chybí.

**Fix — complete tab keyboard shortcuts:**

| Shortcut | Action |
|---|---|
| `Cmd+T` | New tab (empty) |
| `Cmd+W` | Close current tab |
| `Cmd+Shift+]` | Next tab |
| `Cmd+Shift+[` | Previous tab |
| `Cmd+Click` in sidebar | Open note in new tab |
| `Cmd+Enter` in Command Palette / Quick Open | Open in new tab |

**Cmd+Click in `FileTreeRowView`:**

```swift
.onTapGesture {
    appState.openNote(url: fileNode.url)
}
.simultaneousGesture(
    TapGesture()
        .modifiers(.command)
        .onEnded {
            appState.openNoteInNewTab(url: fileNode.url)
        }
)
```

Or use `NSClickGestureRecognizer` with modifier flag check:

```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onEnded { _ in
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.command) {
                appState.openNoteInNewTab(url: fileNode.url)
            } else {
                appState.openNote(url: fileNode.url)
            }
        }
)
```

---

## Fix 10 — Preview: pozadí se nemění

**Problem:** Přepnutí do preview režimu mění barvu pozadí.

**Root cause:** `WKWebView` has its own background. Even with `setValue(false, forKey: "drawsBackground")`, the webview may show a white flash or different tint.

**Fix in `MarkdownPreviewView.makeNSView`:**

```swift
webView.setValue(false, forKey: "drawsBackground")
webView.underPageBackgroundColor = .clear  // macOS 12+
```

**Fix in `MarkdownRenderer.defaultCSS`:** Make the body background transparent, not hardcoded:

```css
/* Remove these hardcoded backgrounds: */
@media (prefers-color-scheme: dark) {
    body { background: transparent; color: #F5F5F7; }
}
@media (prefers-color-scheme: light) {
    body { background: transparent; color: #1D1D1F; }
}
```

The `EditorView` already wraps both editor and preview in a `ZStack`. Add a background to that ZStack so both modes share the same visual background:

```swift
ZStack {
    // background layer — same for both modes
    Color(NSColor.textBackgroundColor)
    
    if appState.isPreviewMode {
        MarkdownPreviewView(...)
    } else {
        MarkdownEditorView(...)
    }
}
```

---

## Fix 11 — "Modified X minutes ago" při aktivní editaci

**Problem:** Status bar ukazuje čas poslední modifikace souboru i když právě píšeš. Mělo by zobrazit "Editing..." nebo skrýt modified time během psaní.

**Fix in `AppState`:** Add `@Published var isEditing: Bool = false`

In `AutoSaveService` or where `onTextChange` is called — set `isEditing = true` on any text change, and `isEditing = false` after the file is actually saved (in `saveStatus == .saved`).

**Fix in `StatusBarView`:**

```swift
// Replace:
if let modified = appState.currentNoteModified {
    Text("Modified \(relativeTime(modified))")
}

// With:
if appState.isEditing {
    Text("Editing...")
        .foregroundColor(.secondary)
} else if let modified = appState.currentNoteModified {
    Text("Modified \(relativeTime(modified))")
}
```

Also: `currentNoteModified` should be refreshed from filesystem only after a successful save, not on every render. Cache the value and update it in `AppState.saveCurrentNote()`.

---

## Fix 12 — Exporty (PDF, DOCX, HTML) nefungují

**Problem:** Export nabídne dialog uložení, ale soubor se nevytvoří.

**Diagnose:** Find the export implementation. Search for `Export as PDF`, `NSSavePanel`, `createPDF` in the codebase.

**Common causes and fixes:**

**PDF — `WKWebView.createPDF` is async and requires the webview to be attached to a window:**

```swift
// WRONG — webview not in view hierarchy:
let tempWebView = WKWebView()
tempWebView.loadHTMLString(html, baseURL: nil)
// createPDF called before load completes → empty PDF

// CORRECT:
func exportAsPDF(content: String, filename: String) {
    let config = WKWebViewConfiguration()
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 1000), configuration: config)
    
    // Must add to a window or at least have a non-zero frame
    // Use a delegate to wait for load completion:
    class PDFExporter: NSObject, WKNavigationDelegate {
        var webView: WKWebView
        var saveURL: URL
        
        init(webView: WKWebView, saveURL: URL) {
            self.webView = webView
            self.saveURL = saveURL
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let config = WKPDFConfiguration()
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    try? data.write(to: self.saveURL)
                    NSWorkspace.shared.open(self.saveURL)
                case .failure(let error):
                    print("PDF error: \(error)")
                }
            }
        }
    }
    
    let panel = NSSavePanel()
    panel.nameFieldStringValue = filename + ".pdf"
    panel.allowedContentTypes = [.pdf]
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        let html = MarkdownRenderer.renderHTML(from: content)
        let exporter = PDFExporter(webView: webView, saveURL: url)
        webView.navigationDelegate = exporter
        webView.loadHTMLString(html, baseURL: nil)
        // Keep strong reference to exporter until done
        objc_setAssociatedObject(webView, "exporter", exporter, .OBJC_ASSOCIATION_RETAIN)
    }
}
```

**DOCX/HTML exports:** Find the implementation and check if `Process` (for Pandoc) launches correctly. Common issue: PATH doesn't include `/usr/local/bin` or `/opt/homebrew/bin` in sandboxed apps.

Fix for Pandoc PATH:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = ["-l", "-c", "pandoc \"\(inputPath)\" -o \"\(outputPath)\""]
// -l loads login shell which includes Homebrew PATH
```

For HTML export: verify the template substitution is actually writing the file and not silently failing. Wrap in do-catch and show an NSAlert on error.

---

## Fix 13 — Okamžité zvýraznění nadpisu po `# ` + mezera

**Problem:** Napíšeš `# ` a text se ihned nemění na velký font — změna nastane až s dalším znakem nebo přepnutím.

**Root cause:** `applyEditHighlighting()` is called in `textDidChange`, which fires after the character is typed. But the regex for H1 `^#\s+` requires at least one character after the space. So after typing `# ` (hash + space), there's no match yet — the heading style applies only when you type the first character of the heading text.

**Fix in `MarkdownHighlighter`:** Change the heading pattern to match even an empty heading (just `# ` with no following text):

```swift
// Change from: "^#{1} .+"
// To: "^#{1} .*"  (zero or more chars after the space)

// H1: matches "# " with anything after (including nothing)
if trimmed.hasPrefix("# ") || trimmed == "#" {
    // apply H1 attributes to entire line
}
```

Also: apply heading attributes to the `#` marker line immediately when `# ` is detected, even with empty title text. The heading font size should snap the moment the space after `#` is typed.

Additionally, trigger `applyEditHighlighting()` synchronously (not deferred) when the current line starts with `#`:

```swift
func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }
    let newText = textView.string
    parent.text = newText
    parent.onTextChange?(newText)
    applyEditHighlighting()  // already synchronous — verify this runs immediately
}
```

If there's any `DispatchQueue.main.async` wrapping the highlight call, remove it.

---

## Additional fixes found in code review

### A — Heading H4 missing in renderer

`MarkdownRenderer.processHeadings` handles `###`, `##`, `#` but NOT `####`. Fix:

```swift
if trimmed.hasPrefix("#### ") { return "<h4>\(String(trimmed.dropFirst(5)))</h4>" }
if trimmed.hasPrefix("### ") { return "<h3>\(String(trimmed.dropFirst(4)))</h3>" }
if trimmed.hasPrefix("## ") { return "<h2>\(String(trimmed.dropFirst(3)))</h2>" }
if trimmed.hasPrefix("# ") { return "<h1>\(String(trimmed.dropFirst(2)))</h1>" }
```

### B — Highlight.js načítáno z CDN (nefunguje offline)

`MarkdownRenderer` loads highlight.js from `cdnjs.cloudflare.com`. This fails without internet.

Fix: Bundle highlight.js locally. Download `highlight.min.js` + `github.min.css` + `github-dark.min.css` to `Sources/Resources/`. Load them via `Bundle.main.url(forResource:withExtension:)` and inject as inline `<script>` and `<style>` tags instead of `<link>` / `<script src>`.

### C — Tab key v editoru vkládá \t místo mezer

In `MarkdownTextView`, override `insertTab`:

```swift
override func insertTab(_ sender: Any?) {
    insertText("    ", replacementRange: selectedRange())  // 4 spaces
}
```

### D — Automatický indent na novém řádku

When pressing Enter after an indented line, the new line should have the same indent:

```swift
// In insertNewline override (Fix 2), before the list handling, check for existing indent:
let indent = String(currentLine.prefix(while: { $0 == " " || $0 == "\t" }))
if !indent.isEmpty && !isListLine {
    super.insertNewline(sender)
    insertText(indent, replacementRange: ...)
    return
}
```

### E — Prázdný soubor při auto-title: pokud H1 je první řádek ale je prázdný obsah pod ním

Auto-title should not rename a file to just `.md` if the H1 content is empty (`# `). Guard:

```swift
let title = headingText.trimmingCharacters(in: .whitespaces)
guard !title.isEmpty else { return }  // don't rename to empty title
```

### F — Search neaktualizuje výsledky při mazání písmen (jen přidávání)

In `SidebarView.onChange(of: searchText)`, the debounced search fires on every change including deletion. This should be working already, but verify the `Task.sleep` debounce doesn't cause stale results when user types quickly. If results seem stale, reduce debounce from 150ms to 80ms.

### G — Preview mode: external links

In `MarkdownPreviewView`, links to external URLs (`http://...`) should open in the default browser, not navigate the webview. Add to `Coordinator`:

```swift
func webView(_ webView: WKWebView,
             decidePolicyFor navigationAction: WKNavigationAction,
             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if navigationAction.navigationType == .linkActivated,
       let url = navigationAction.request.url,
       url.scheme == "http" || url.scheme == "https" {
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
        return
    }
    decisionHandler(.allow)
}
```

### H — Sidebar: prázdná sekce Favorites viditelná i když je prázdná

In `SidebarView`, `favoritesSection` is already guarded by `if !appState.favoritesManager.orderedFavorites.isEmpty`. Verify this check actually works — if `orderedFavorites` is `@Published` and the view observes it correctly.

### I — Status bar "Saved HH:MM:SS" je příliš verbose

The save timestamp shows seconds: `"Saved 14:32:07"`. Change to: `"Saved at 14:32"` (no seconds) or just `"Saved"` with a checkmark icon.

```swift
case .saved(let date):
    HStack(spacing: 3) {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.system(size: 10))
        Text("Saved")
    }
```

### J — Cmd+N v sidebaru vytváří poznámku v root místo ve vybrané složce

When a folder is selected/focused in the sidebar and user presses `Cmd+N`, the new note should be created inside that folder, not in the vault root.

Add `@State private var focusedFolderURL: URL?` to `SidebarView`. When user focuses/expands a folder, set `focusedFolderURL`. Pass it to `appState.createNewNote(in: focusedFolderURL)`.

### K — Wikilink autocomplete nereaguje na Escape

When the `[[` autocomplete popup is open, pressing `Escape` should close it without inserting anything. Verify this is handled in the autocomplete implementation.

### L — Rename inline: Enter potvrzuje, Escape ruší

Wherever inline rename is implemented (sidebar double-click), ensure:
- `Enter` → confirms rename
- `Escape` → cancels, restores original name
- Clicking outside → confirms rename

### M — Paste prostého textu místo rich textu

`MarkdownTextView.readablePasteboardTypes` returns only `[.string]` — correct. But verify that pasting from web browsers doesn't insert HTML. The `isRichText = false` setting should handle this, but add explicit override:

```swift
override func paste(_ sender: Any?) {
    let pb = NSPasteboard.general
    if let string = pb.string(forType: .string) {
        insertText(string, replacementRange: selectedRange())
    } else {
        super.paste(sender)
    }
}
```

### N — App nereaguje na Cmd+Z po AI improvement

After AI replaces content, `Cmd+Z` should undo back to the original text. This requires that the AI replacement goes through the NSTextView undo manager, not a direct `currentContent =` assignment.

In `AppState.improveText`: instead of `currentContent = improved`, post a notification or use a callback that calls `textView.insertText(improved, replacementRange: NSRange(0, textView.string.count))` — this registers with undo.

Or: before replacing, call `textView.breakUndoCoalescing()` and replace via `textStorage.replaceCharacters(in: fullRange, with: improved)`.

---

## Build & Delivery

After all fixes:

```bash
cd ~/Projects/Notero
xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Debug 2>&1 | tail -40
```

Fix all errors. Then:

```bash
xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Release
cp -r build/Release/Notero.app ~/Desktop/Notero.app
```

## Git commits

- fix: cursor focus on note open
- fix: auto-continue lists on Enter
- fix: search results openable
- fix: sidebar keyboard navigation with arrow keys
- fix: search results arrow key navigation
- fix: find bar and search highlighting
- fix: Cmd+T new tab, Cmd+Enter for checkboxes
- fix: new tab opens empty state
- fix: Cmd+Click opens note in new tab, full tab shortcuts
- fix: preview background color unchanged
- fix: status bar shows Editing... during active edit
- fix: PDF/DOCX/HTML exports actually save files
- fix: heading formatting on # + space immediately
- fix: H4 heading in renderer
- fix: highlight.js bundled locally
- fix: tab key inserts 4 spaces
- fix: auto-indent on new line
- fix: auto-title guard against empty H1
- fix: external links open in browser from preview
- fix: save status simplified
- fix: Cmd+N creates note in focused folder
- fix: paste always inserts plain text
- fix: AI improvement is undoable

## Start here

```bash
cd ~/Projects/Notero
```

Verify build passes first, then apply fixes in order 1–13, then A–N.
Do not ask for clarification. When in doubt, check how similar apps (Obsidian, iA Writer, Bear) handle the same interaction.
