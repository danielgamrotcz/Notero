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
