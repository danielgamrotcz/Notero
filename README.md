# Notero

Native macOS Markdown notes app. Keyboard-first, minimal, Apple-style.

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15+

## Build

```bash
xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Release SYMROOT=build
```

## First Launch

1. On first launch, Notero creates a vault at `~/Library/CloudStorage/GoogleDrive-daniel@gamrot.cz/Můj disk/Notero/`
2. You can change the vault location in **Settings > General**
3. Create notes with `Cmd+N`, folders with `Cmd+Shift+N`
4. All notes are saved as `.md` files — compatible with any Markdown editor

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New Note | `Cmd+N` |
| New Folder | `Cmd+Shift+N` |
| Quick Open | `Cmd+O` |
| Command Palette | `Cmd+P` |
| Toggle Preview | `Cmd+E` |
| Toggle Sidebar | `Cmd+Shift+L` |
| Toggle Backlinks | `Cmd+Shift+B` |
| Save | `Cmd+S` |
| Find in Note | `Cmd+F` |
| Bold | `Cmd+B` |
| Italic | `Cmd+I` |
| Insert Link | `Cmd+K` |
| Insert Code Block | `Cmd+Shift+K` |
| Heading 1/2/3 | `Cmd+1/2/3` |
| Insert Task | `Cmd+T` |
| Increase Font | `Cmd++` |
| Decrease Font | `Cmd+-` |
| Reset Font | `Cmd+0` |
| Improve with Claude | `Option+A` |
| Improve with Local AI | `Option+L` |
| Settings | `Cmd+,` |

## Features

- **Editor**: NSTextView-based with Markdown syntax highlighting (headings, bold, italic, code, links, wikilinks)
- **Preview**: WKWebView rendered Markdown with clickable checkboxes and wikilinks
- **Search**: Full-text diacritic-insensitive search across all notes
- **Wikilinks**: `[[Note Name]]` linking with autocomplete and backlinks panel
- **AI**: Text improvement via Anthropic Claude API or local Ollama
- **Auto-save**: Debounced saves with atomic writes
- **File watching**: FSEvents-based, reflects external changes in < 1 second

## Tests

```bash
xcodebuild test -project Notero.xcodeproj -scheme Notero -destination 'platform=macOS'
```
