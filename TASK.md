# Notero – Complete Build Specification

## Overview

Build a native macOS Markdown notes application called **Notero**. This is a keyboard-first, minimal, Apple-style notes app that reads and writes `.md` files from a local folder (iCloud Documents compatible). The app must feel like it was designed by Apple — clean, fast, no clutter.

**Target:** macOS 14+ (Sonoma and later)  
**Language:** Swift 5.9+  
**UI Framework:** SwiftUI  
**Build:** Xcode 15+, Swift Package Manager  
**Bundle ID:** `cz.danielgamrot.Notero`

---

## Project Structure

Create this structure from scratch using XcodeGen (`project.yml`) or directly as an Xcode project:

```
Notero/
├── Notero.xcodeproj
├── CLAUDE.md
├── project.yml              # XcodeGen config (optional but preferred)
├── Sources/
│   ├── NoteroApp.swift      # App entry + scene config
│   ├── AppState.swift       # Shared observable state
│   ├── Models/
│   │   ├── NoteFile.swift           # Represents a .md file
│   │   ├── NoteFolder.swift         # Represents a folder
│   │   ├── FileTreeNode.swift       # Recursive tree node
│   │   └── SearchIndex.swift        # Full-text index model
│   ├── Services/
│   │   ├── VaultManager.swift       # File system operations
│   │   ├── SearchService.swift      # Full-text search engine
│   │   ├── AutoSaveService.swift    # Debounced auto-save
│   │   ├── LinkResolver.swift       # [[note]] link resolution
│   │   ├── AnthropicService.swift   # Claude API integration
│   │   ├── OllamaService.swift      # Local Ollama integration
│   │   └── KeychainManager.swift    # Secure key storage
│   ├── Views/
│   │   ├── ContentView.swift        # Root layout (sidebar + editor)
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift
│   │   │   ├── FileTreeView.swift
│   │   │   └── FileTreeRowView.swift
│   │   ├── Editor/
│   │   │   ├── EditorView.swift     # Main editor container
│   │   │   ├── MarkdownEditorView.swift   # Raw markdown editing
│   │   │   └── MarkdownPreviewView.swift  # Rendered preview (WebKit)
│   │   ├── CommandPalette/
│   │   │   ├── CommandPaletteView.swift
│   │   │   └── CommandItem.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   ├── GeneralSettingsView.swift
│   │   │   └── AISettingsView.swift
│   │   └── Common/
│   │       ├── EmptyStateView.swift
│   │       └── StatusBarView.swift
│   ├── Extensions/
│   │   ├── String+Markdown.swift
│   │   ├── View+Shortcuts.swift
│   │   └── Color+Theme.swift
│   ├── Utilities/
│   │   ├── MarkdownRenderer.swift   # CSS + HTML rendering
│   │   └── Logger.swift
│   └── Resources/
│       ├── Assets.xcassets/         # App icon + accent color
│       └── preview.css              # Markdown preview stylesheet
├── Tests/
│   ├── SearchServiceTests.swift
│   ├── LinkResolverTests.swift
│   └── VaultManagerTests.swift
└── README.md
```

---

## App Icon

Design and generate the app icon programmatically using Swift/CoreGraphics, then export all required sizes. Do NOT use placeholder icons.

**Design specification:**
- Background: near-black `#0D0A14` (same dark tone as VibeTerm and Uttero used across the project suite)
- Foreground: white (`#FFFFFF`) abstract symbol
- Symbol concept: Three horizontal flowing/wavy lines of decreasing length (top longest, middle medium, bottom shortest), slightly curved to suggest handwriting/text flow. Lines have rounded caps. Style is abstract and minimal — consistent with Uttero's wave motif but clearly reading as "text/writing".
- No gradients, no shadows, no realism — flat, minimal, bold white on dark
- macOS rounded rectangle shape (automatic from system)

Generate all required sizes: 16, 32, 64, 128, 256, 512, 1024px (and @2x variants). Create a Swift script at `Scripts/generate_icon.swift` that uses CoreGraphics to draw and export the icon, then run it as part of setup.

---

## Vault (File Storage)

Default vault location: `~/Library/CloudStorage/GoogleDrive-daniel@gamrot.cz/Můj disk/Notero/`

- Create this folder on first launch if it doesn't exist
- Support iCloud Documents (the folder can be inside iCloud Drive/Documents — no special iCloud API needed, just file system access)
- Store vault path in `UserDefaults` — user can change it in Settings
- Watch for external file changes using `FSEventStreamCreate` or `DispatchSource.makeFileSystemObjectSource`; reflect changes in the UI within 1 second
- Support for subfolders (arbitrary depth)
- Only show `.md` files in the UI; other files are ignored but not deleted

---

## Sidebar

Left sidebar showing the file tree of the vault.

**Features:**
- Hierarchical folder/file tree, collapsible folders
- Folders always shown before files (alphabetical within each group)
- Disclosure triangles for folders (standard macOS style)
- Single-click to select/open a note
- Currently open note highlighted
- **Right-click / two-finger tap context menu on files:** Rename, Duplicate, Move to Trash, Reveal in Finder, Copy Link (`[[filename]]`)
- **Right-click / two-finger tap context menu on folders:** New Note, New Folder, Rename, Move to Trash, Reveal in Finder
- **Right-click on empty area:** New Note, New Folder
- Drag-and-drop to move files between folders
- Inline rename (double-click or press Return when selected)
- File icons: folder icon for folders, document icon for notes (SF Symbols: `folder`, `doc.text`)
- Show note count in folder tooltip on hover
- Sidebar can be hidden/shown with `Cmd+Shift+L`
- Sidebar width: resizable, min 180px, default 220px, max 400px

**Keyboard navigation in sidebar:**
- Arrow keys to navigate
- Return to open selected note
- Delete key on selected file: confirm trash dialog
- `Cmd+N` when sidebar is focused: create new note in current folder

---

## Editor

The editor is the core of the app. It must be excellent.

### Raw Markdown Mode (default)

- `NSTextView`-based editor (not SwiftUI TextEditor — too limited) wrapped in `NSViewRepresentable`
- Monospace font: SF Mono, 14pt, line height 1.6
- Syntax highlighting for Markdown:
  - `#` headings → slightly lighter gray, weight semibold
  - `**bold**` → bold text
  - `*italic*` → italic
  - `` `code` `` and ` ```blocks``` ` → monospace, subtle background tint
  - `> blockquote` → left border + indent
  - `[links]()` and `[[wikilinks]]` → colored (accent color)
  - `- [ ]` task checkboxes → tinted
  - URLs → colored
- Apply highlighting without breaking cursor position
- Soft-wrap lines (no horizontal scroll)
- Show line numbers in a gutter (toggleable in Settings, default: off)
- Invisible cursor line highlight (very subtle, 3% opacity background)
- Selection color: system accent color at 30% opacity

### Preview Mode

- Rendered Markdown using `WKWebView`
- Custom CSS in `Resources/preview.css`:
  - Font: `-apple-system` (San Francisco), 16px, line-height 1.7
  - Max-width 700px, centered
  - Dark/light mode aware (CSS `prefers-color-scheme`)
  - Code blocks: `SF Mono`, syntax highlighted using Highlight.js (bundled or CDN)
  - Task checkboxes: clickable (clicking toggles the checkbox in the source file)
  - `[[wikilink]]` rendered as clickable links (clicking opens the linked note)
  - Images: displayed inline if path is valid relative to vault root
  - Tables: clean, minimal borders
- Preview updates in real-time (debounced 300ms after last keystroke)

### Mode Toggle

- `Cmd+E` toggles between Edit and Preview mode
- Animated transition (crossfade, 150ms)
- Mode indicator in status bar (bottom of editor)
- Remember last mode per note (stored in UserDefaults, key: `mode-{filename}`)

### Auto-Save

- Auto-save triggered 1 second after last keystroke (debounced)
- No "unsaved" indicators needed — the app is always saving
- On app quit: synchronous save of current note
- Atomic writes: write to temp file, then rename — prevents data loss
- File modification date preserved using `FileManager.setAttributes`

### Note Linking — `[[wikilinks]]`

- Type `[[` to trigger autocomplete popup showing matching note names
- Autocomplete popup: fuzzy-filtered list of all notes in vault, keyboard-navigable (arrows + Return)
- Links stored in source as `[[Note Name]]` or `[[Note Name|Display Text]]`
- In preview mode: links are clickable and open the referenced note
- `LinkResolver` service resolves links by filename (case-insensitive, without `.md` extension)
- Broken links (no matching file) shown with different color in both modes
- Backlinks panel: show which notes link to the current note (visible in a bottom panel toggled with `Cmd+Shift+B`)

### Word Count & Status Bar

- Bottom status bar: word count, character count, current mode (Edit/Preview), auto-save status ("Saved" with timestamp or "Saving…")
- Status bar height: 24px, small font (11pt), subtle separator line above

---

## Full-Text Search

Fast, indexed full-text search across all notes.

**Implementation:**
- Build an in-memory index on app launch (async, doesn't block UI)
- Index updates incrementally when files change (file watcher triggers re-index of changed file only)
- Search algorithm: tokenize content, support for:
  - Exact phrase search (quoted: `"exact phrase"`)
  - AND search (multiple terms, all must match)
  - Filename search (prefix match on note names)
  - Case-insensitive by default
  - Diacritic-insensitive (Czech/Slovak support: á=a, č=c, etc.)
- Results ranked by: exact title match > title contains > content match
- Results show: note name, folder path, snippet with search term highlighted (±50 chars context)
- Max results displayed: 50 (show "and X more…" if exceeded)

**Search UI:**
- Accessible from Command Palette (`Cmd+P`) and sidebar search field
- Sidebar search field: appears at top of sidebar when focused (or always visible)
- Search happens as user types (debounced 150ms)
- Result list keyboard-navigable

---

## Command Palette (`Cmd+P`)

Modal overlay (like Raycast/VS Code), centered on screen, width 600px.

**Features:**
- Unified search: searches both **commands** and **notes** simultaneously
- Typing shows filtered results in real-time
- First section: matching notes (SF Symbols `doc.text`)
- Second section: matching commands
- Arrow keys navigate, Return executes, Escape dismisses
- Fuzzy matching
- Show keyboard shortcut hint next to each command result

**Available commands:**
- New Note (`Cmd+N`)
- New Folder
- Open Vault in Finder
- Toggle Sidebar (`Cmd+Shift+L`)
- Toggle Preview (`Cmd+E`)
- Toggle Line Numbers
- Toggle Backlinks Panel (`Cmd+Shift+B`)
- Focus Search
- Improve with AI – Claude (`Option+A`)
- Improve with AI – Local (`Option+L`)
- Open Settings (`Cmd+,`)
- Export Note as PDF
- Copy Note as HTML

**Quick Open (`Cmd+O`):**
- Same UI as Command Palette but pre-filtered to notes only
- Typing searches note names (fuzzy) + content preview
- Fast: results in <50ms

---

## Keyboard Shortcuts (Complete List)

| Action | Shortcut |
|---|---|
| New Note | `Cmd+N` |
| New Folder | `Cmd+Shift+N` |
| Open (Quick Open) | `Cmd+O` |
| Command Palette | `Cmd+P` |
| Toggle Preview | `Cmd+E` |
| Toggle Sidebar | `Cmd+Shift+L` |
| Toggle Backlinks | `Cmd+Shift+B` |
| Find in Note | `Cmd+F` |
| Global Search | `Cmd+Shift+F` |
| Save (manual/immediate) | `Cmd+S` |
| Rename Note | `F2` or `Enter` in sidebar |
| Delete Note | `Cmd+Delete` (with confirm dialog) |
| Move to Trash | `Cmd+Backspace` in sidebar |
| Settings | `Cmd+,` |
| Improve with Claude API | `Option+A` |
| Improve with Local AI | `Option+L` |
| Bold | `Cmd+B` |
| Italic | `Cmd+I` |
| Insert Link | `Cmd+K` |
| Insert Code Block | `Cmd+Shift+K` |
| Insert Heading 1 | `Cmd+1` |
| Insert Heading 2 | `Cmd+2` |
| Insert Heading 3 | `Cmd+3` |
| Insert Task | `Cmd+T` |
| Increase Font Size | `Cmd++` |
| Decrease Font Size | `Cmd+-` |
| Reset Font Size | `Cmd+0` |
| Focus Sidebar | `Cmd+Shift+E` |
| Focus Editor | `Escape` (from sidebar) |

---

## macOS Menu Bar

Complete native macOS menu bar. All items must have correct shortcuts and be disabled/enabled based on context.

```
Notero
  About Notero
  Settings…              Cmd+,
  ─────────────────
  Quit Notero            Cmd+Q

File
  New Note               Cmd+N
  New Folder             Cmd+Shift+N
  ─────────────────
  Open…                  Cmd+O
  Open Vault in Finder
  Change Vault Location…
  ─────────────────
  Rename                 F2
  Move to Trash          Cmd+Delete
  ─────────────────
  Export as PDF
  Copy as HTML

Edit
  Undo                   Cmd+Z
  Redo                   Cmd+Shift+Z
  ─────────────────
  Cut / Copy / Paste / Select All
  ─────────────────
  Find                   Cmd+F
  Find and Replace       Cmd+Option+F
  ─────────────────
  Bold                   Cmd+B
  Italic                 Cmd+I
  Insert Link            Cmd+K
  Insert Code Block      Cmd+Shift+K
  Insert Heading 1/2/3   Cmd+1/2/3
  Insert Task            Cmd+T

View
  Toggle Sidebar         Cmd+Shift+L
  Toggle Preview         Cmd+E
  Toggle Backlinks       Cmd+Shift+B
  Toggle Line Numbers
  ─────────────────
  Increase/Decrease/Reset Font Size
  ─────────────────
  Command Palette        Cmd+P

AI
  Improve with Claude    Option+A
  Improve with Local AI  Option+L
  ─────────────────
  AI Settings…

Window
  (standard macOS)

Help
  Notero Help
  Keyboard Shortcuts
```

---

## Settings

Native macOS Settings window (`Settings` scene in SwiftUI).

### General Tab
- **Vault Location:** current path + "Change…" button (NSOpenPanel to pick folder)
- **Default note name:** text field (default: `Untitled`)
- **Font size:** slider or stepper (12–20pt, default 14)
- **Show line numbers:** toggle
- **Auto-save delay:** slider (0.5s – 5s, default 1s)
- **Spell check:** toggle (default: off)

### AI Tab
- **Anthropic API Key:** secure text field, stored in Keychain (`NoteroAnthropicKey`), shows "•••••••" when filled, "Test connection" button
- **Claude model:** picker (claude-opus-4-5, claude-sonnet-4-5, claude-haiku-4-5 — default: sonnet)
- **Local AI (Ollama):** 
  - Server URL: text field (default: `http://localhost:11434`)
  - "Detect available models" button → fetches `/api/tags` and populates model picker
  - Model picker: shows detected models, default: first detected or `llama3` fallback
  - "Test connection" button
- **AI improvement prompt:** multiline text field (default: `Improve the following text for clarity, conciseness, and flow. Keep the same language. Return only the improved text, no explanations.`)
- **Show AI improvements as diff:** toggle (default: off)

---

## AI Text Improvement

When user triggers AI improvement (`Option+A` for Claude, `Option+L` for Local):

1. Take selected text (if selection exists) OR entire note content
2. Show loading indicator in status bar ("AI improving…")
3. Send to respective API with the configured prompt
4. On success: replace selected text / entire content with improved version (undoable with `Cmd+Z`)
5. On error: show non-blocking alert with error message

**Anthropic API:**
```
POST https://api.anthropic.com/v1/messages
Headers: x-api-key, anthropic-version: 2023-06-01, content-type: application/json
Body: { model: <selected>, max_tokens: 4096, messages: [{role: "user", content: "<prompt>\n\n<text>"}] }
```

**Ollama API:**
```
POST http://localhost:11434/api/generate
Body: { model: <selected>, prompt: "<prompt>\n\n<text>", stream: false }
```

Both: async/await, cancellable, 30s timeout, error handling without crash.

---

## Dark/Light Mode

- Follow system appearance by default
- Dark mode: background `#1C1C1E`, editor `#1C1C1E`, text `#F5F5F7`
- Light mode: background `#F5F5F0`, editor `#FFFFFF`, text `#1D1D1F`
- Preview CSS uses `@media (prefers-color-scheme: dark)`
- Accent color: system accent (no custom)

---

## Performance Requirements

- App launch to usable: < 1 second (even with 1000+ notes)
- Search results: < 100ms after index built
- Index build: < 5s for 1000 notes (background)
- File open/switch: < 200ms
- Preview render: < 300ms
- Memory: < 150MB with 1000 notes

---

## Error Handling

- No vault: show onboarding (choose or create vault)
- Note deleted externally while open: banner "This note was deleted. Save a copy?"
- Save failure: NSAlert immediately, don't lose data
- Network errors in AI: non-blocking notification, no crash
- Corrupt file: show as raw text, no crash

---

## What NOT to include in v1

- iCloud sync via CloudKit
- Tags or labels
- Attachments/image paste
- Version history
- Collaboration
- Any onboarding beyond vault picker

---

## Build & Delivery Instructions

After implementing everything, the agent must:

1. Build Debug: `xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Debug 2>&1 | tail -80`
2. Fix ALL build errors and warnings
3. Run tests: `xcodebuild test -project Notero.xcodeproj -scheme Notero -destination 'platform=macOS'`
4. Fix test failures
5. Build Release: `xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Release`
6. Copy app to Desktop: `cp -r ~/Projects/Notero/build/Release/Notero.app ~/Desktop/Notero.app`
7. Create `README.md` with setup, first launch, keyboard shortcuts

---

## Git

Init repo, commit at logical milestones:
- Initial project structure
- Vault + file tree
- Editor with highlighting
- Preview mode
- Search
- Command Palette
- AI services
- Settings
- Icon
- Tests passing
- Final build

---

## CLAUDE.md to create in project root

```markdown
# Notero

Native macOS Markdown notes app. Keyboard-first, minimal, Apple-style.

## Tech Stack
- Swift 5.9+, SwiftUI + NSTextView, macOS 14+
- WKWebView for Markdown preview
- In-memory full-text search index
- Keychain for API keys
- No external dependencies (pure SPM/system frameworks only)

## Commands
xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Debug
xcodebuild test -project Notero.xcodeproj -scheme Notero -destination 'platform=macOS'

## Key Patterns
- VaultManager: all file I/O, FSEvents watcher
- SearchService: in-memory index, incremental updates
- AnthropicService + OllamaService: AI text improvement
- KeychainManager: API keys never in code or UserDefaults
- All async on background queues, UI updates on @MainActor
```

---

## Start Here

Begin by:
1. Creating the Xcode project at `~/Projects/Notero/`
2. Setting up the folder structure above
3. Implementing in this order: **Vault → Sidebar → Editor → Preview → Search → Command Palette → AI → Settings → Icon → Tests → Build**

Do not ask for clarification. Make all decisions based on this spec. When ambiguous, choose the more Apple-native approach.
