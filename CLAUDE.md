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

## Architecture
SwiftUI document-based app that manages a vault (folder) of Markdown files. VaultManager handles all file I/O with FSEvents for live file watching. The editor uses NSTextView (AppKit) wrapped in SwiftUI for performance. Markdown preview renders via WKWebView with highlight.js for code blocks. Search uses an in-memory full-text index with incremental updates. Supabase sync and reMarkable export are optional integrations.

## Key Files
- `Sources/NoteroApp.swift` — App entry point, window configuration
- `Sources/AppState.swift` — Global app state (vault, selected note, UI state)
- `Sources/NoteState.swift` — Per-note editor state
- `Sources/Services/VaultManager.swift` — File I/O, FSEvents watcher, vault operations
- `Sources/Services/SearchService.swift` — In-memory full-text search index
- `Sources/Services/AnthropicService.swift` — Claude API for AI text improvement
- `Sources/Services/OllamaService.swift` — Local Ollama API for offline AI
- `Sources/Services/KeychainManager.swift` — Secure API key storage
- `Sources/Services/SyncManager.swift` — Supabase cloud sync
- `Sources/Services/SupabaseService.swift` — Supabase API client
- `Sources/Services/ReMarkableService.swift` — reMarkable tablet export
- `Sources/Services/AutoSaveService.swift` — Auto-save with debounce
- `Sources/Services/NoteHistoryService.swift` — Note version history
- `Sources/Models/NoteFile.swift` — Note data model
- `Sources/Models/SearchIndex.swift` — Search index data structure
- `Sources/Views/ContentView.swift` — Main split view (sidebar + editor + preview)
- `Sources/Utilities/MarkdownRenderer.swift` — Markdown-to-HTML rendering
- `project.yml` — XcodeGen project definition

## Key Patterns
- VaultManager: all file I/O, FSEvents watcher
- SearchService: in-memory index, incremental updates
- AnthropicService + OllamaService: AI text improvement
- KeychainManager: API keys never in code or UserDefaults
- All async on background queues, UI updates on @MainActor
