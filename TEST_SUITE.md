# Notero – Complete Test Suite

Run all tests systematically. Do not stop on first failure — run everything and produce
a final report at the end. Fix any test failures you can fix automatically (e.g. broken
imports, wrong method signatures, missing test setup). For failures that require UI or
runtime behavior you cannot simulate, document them clearly in the report.

---

## Phase 1 — Build Verification

### 1.1 Debug build
```bash
xcodebuild build \
  -project Notero.xcodeproj \
  -scheme Notero \
  -configuration Debug \
  -destination 'platform=macOS' \
  2>&1 | tee /tmp/notero_build_debug.log | tail -30
```
Expected: `** BUILD SUCCEEDED **`
On failure: fix all errors and warnings before proceeding.

### 1.2 Release build
```bash
xcodebuild build \
  -project Notero.xcodeproj \
  -scheme Notero \
  -configuration Release \
  -destination 'platform=macOS' \
  2>&1 | tee /tmp/notero_build_release.log | tail -30
```
Expected: `** BUILD SUCCEEDED **`

### 1.3 Static analysis
```bash
xcodebuild analyze \
  -project Notero.xcodeproj \
  -scheme Notero \
  -configuration Debug \
  2>&1 | grep -E "warning:|error:|note:" | head -50
```
Document all analyzer warnings. Fix any that indicate real bugs (force unwrap crashes,
memory issues, unreachable code).

---

## Phase 2 — Unit Tests

### 2.1 Run all unit tests
```bash
xcodebuild test \
  -project Notero.xcodeproj \
  -scheme Notero \
  -destination 'platform=macOS' \
  -resultBundlePath /tmp/notero_test_results.xcresult \
  2>&1 | tee /tmp/notero_tests.log | grep -E "Test Case|PASSED|FAILED|error:"
```

### 2.2 Parse results
```bash
# Count passed/failed
grep -c "passed" /tmp/notero_tests.log || echo "0 passed"
grep -c "failed" /tmp/notero_tests.log || echo "0 failed"

# List all failures in detail
grep -A 5 "FAILED" /tmp/notero_tests.log
```

### 2.3 Required test coverage
Verify these test files exist and all their test cases pass.
If a test file is missing, create it with the tests specified below.

#### VaultManagerTests — must pass:
- `testCreateNote` — creates file, correct filename
- `testCreateDuplicateNote` — appends ` 1`, ` 2` on conflict
- `testCreateFolder` — creates directory
- `testReadAndSaveNote` — round-trip content integrity
- `testRenameItem` — file moved, old path gone, new path exists
- `testDuplicateNote` — copy created with "copy" suffix
- `testFileTreeBuild` — folders before files in tree
- `testAllMarkdownFiles` — only .md files returned, not .txt etc.
- `testMoveToTrash` — file removed from filesystem after trash
- `testSortOrder_nameAscending` — files sorted A→Z
- `testSortOrder_nameDescending` — files sorted Z→A
- `testSortOrder_modifiedNewest` — file with newer mtime first

#### SearchServiceTests — must pass:
- `testAddAndSearch` — basic search returns results
- `testExactPhraseSearch` — quoted phrase matches
- `testCaseInsensitiveSearch` — uppercase query matches lowercase content
- `testDiacriticInsensitiveSearch` — "prilis" matches "příliš"
- `testRemoveFromIndex` — removed file no longer appears in results
- `testAllNoteNames` — returns all indexed note names
- `testEmptyQueryReturnsNoResults` — empty string → empty results
- `testTitleMatchRankedHigher` — title match scores above content match
- `testMultiTermAND` — two-term query requires both terms present
- `testSnippetContainsMatchContext` — result snippet contains the matched term

#### NoteMetadataServiceTests — must pass:
- `testEnsureIDGeneratesUUID` — ID is valid UUID format, lowercase
- `testMetadataIncludesCreatedDate` — created date is recent on new notes
- `testEnsureIDReturnsSameIDOnRepeatedCalls` — same ID returned every time
- `testUpdatePathMigratesMetadata` — ID survives rename via updatePath
- `testCreationDateFallback` — files without metadata use filesystem creationDate
- `testIDUniqueness` — two different notes get two different IDs

#### LinkResolverTests — must pass:
- `testResolvesWikilinkByFilename` — `[[Note Name]]` resolves to correct URL
- `testResolvesWikilinkCaseInsensitive` — `[[note name]]` matches `Note Name.md`
- `testResolvesWikilinkWithoutExtension` — `[[Note]]` matches `Note.md`
- `testBrokenLinkReturnsNil` — unresolvable wikilink returns nil
- `testBacklinksDetected` — finds all notes that link to a given note
- `testPipeSyntax` — `[[Note|Display Text]]` resolves Note, not "Display Text"

#### MarkdownHighlighterTests — must pass:
- `testHeading1FontSize` — `# Title` gets 28pt attribute
- `testHeading2FontSize` — `## Title` gets 22pt attribute
- `testBoldAttribute` — `**text**` gets bold trait
- `testItalicAttribute` — `*text*` gets italic trait
- `testMarkersAreDimmed` — `**` markers have 40% opacity foreground color
- `testMarkersAreNotRemoved` — underlying string unchanged after highlighting
- `testCodeInlineBackground` — `` `code` `` has background color attribute
- `testCursorDoesNotShift` — applying attributes does not change string length
- `testBlockquoteIndent` — `>` line has paragraph indent attribute
- `testNoStringMutationInProcessEditing` — assert replaceCharacters is never called

#### NoteHistoryServiceTests — must pass:
- `testSnapshotCreatedOnSave` — saving creates a snapshot file
- `testNoDuplicateSnapshot` — saving same content twice creates only one snapshot
- `testRetentionLimit` — after 51 saves, only 50 snapshots retained
- `testRestoreVersion` — restored content matches snapshot content
- `testSnapshotsListedChronologically` — snapshots returned newest-first

#### SemanticSearchServiceTests — must pass (mock Ollama):
- `testCosineSimilarity` — similarity(A, A) == 1.0, similarity(A, B) where B is orthogonal == 0.0
- `testThresholdFiltersLowMatches` — results below 0.5 similarity not returned
- `testResultsRankedByScore` — highest similarity score is first result
- `testHandlesOllamaUnavailable` — graceful failure when Ollama not reachable (no crash)
- `testEmbeddingStoredAndLoaded` — embedding written to disk and loaded correctly on next call

---

## Phase 3 — Integration Tests

Run these as automated filesystem + logic tests. Do not launch the GUI.

### 3.1 Vault lifecycle
```swift
// Create a temp vault, create notes, verify file structure
let vault = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notero_itest_\(UUID().uuidString)")
// 1. VaultManager.ensureVaultExists() creates the directory
// 2. Create 5 notes, 2 folders, 3 notes inside folders
// 3. Verify fileTree has correct structure: folders first, alphabetical
// 4. loadFileTree() with each sort order — verify order each time
// 5. Rename a note — verify tree updates, old path gone
// 6. Move note to subfolder — verify tree reflects new location
// 7. Trash a note — verify it's gone from tree
// Cleanup: remove temp vault
```

### 3.2 Auto-save integrity
```swift
// 1. Write content to a note via saveNote()
// 2. Read back immediately — verify content matches exactly
// 3. Write content with special chars: ñ, 你好, €, emoji 🎉 — verify round-trip
// 4. Simulate concurrent write: write to tempfile while reading — verify no corruption
// 5. Write 1MB of content — verify it saves and reads back correctly
```

### 3.3 Search index consistency
```swift
// 1. Index 20 notes with varying content
// 2. Search for term in note 5 — verify it appears in results
// 3. Update note 5 content (remove the term) — reindex — search again — verify not in results
// 4. Delete note 5 from index — search — verify completely absent
// 5. Search with Czech diacritics — verify diacritic-insensitive matching works
// 6. Search for term appearing in 15 notes — verify max 50 results cap enforced
```

### 3.4 Note ID stability
```swift
// 1. Create note — get ID
// 2. Rename note — verify same ID
// 3. Move note to subfolder — verify same ID
// 4. Create 100 notes — verify all IDs are unique (no collisions)
// 5. Load metadata from disk after clearing in-memory cache — verify same ID returned
```

### 3.5 Note history
```swift
// 1. Save note 5 times with different content
// 2. Verify 5 snapshot files exist
// 3. Save same content twice — verify only 1 new snapshot (deduplication)
// 4. Save 55 times — verify only 50 snapshots retained
// 5. Retrieve snapshot list — verify newest first
// 6. Restore snapshot 3 — verify content matches that version
```

### 3.6 Wikilink resolution
```swift
// Vault with notes: "Project Alpha.md", "Meeting Notes.md", "inbox.md"
// 1. [[Project Alpha]] resolves to Project Alpha.md
// 2. [[project alpha]] resolves to Project Alpha.md (case-insensitive)
// 3. [[Project Alpha|Alias]] resolves to Project Alpha.md (ignores alias)
// 4. [[Nonexistent Note]] returns nil
// 5. Backlinks: "Meeting Notes" contains [[Project Alpha]] — backlinks for Project Alpha includes Meeting Notes
// 6. Rename "Project Alpha.md" to "Project Beta.md" — [[Project Alpha]] in other notes updated to [[Project Beta]]
```

### 3.7 FSEvent watcher
```swift
// 1. Start VaultManager watching tempDir
// 2. Copy a .md file into tempDir from outside
// 3. Wait 1.5 seconds
// 4. Verify fileTree contains the new file
// 5. Delete the file from outside
// 6. Wait 1.5 seconds
// 7. Verify fileTree no longer contains the file
// 8. Create a .icloud placeholder file — verify it does NOT appear in fileTree
```

---

## Phase 4 — Code Quality Checks

### 4.1 Force unwrap audit
```bash
grep -rn "!\." Sources/ --include="*.swift" | \
  grep -v "//.*!" | \
  grep -v "Tests" | \
  grep -v "IBOutlet" | \
  grep -v "fatalError" \
  > /tmp/notero_force_unwraps.txt

cat /tmp/notero_force_unwraps.txt
echo "Total force unwraps: $(wc -l < /tmp/notero_force_unwraps.txt)"
```
For every force unwrap found: evaluate if it's safe (known non-nil) or a crash risk.
Fix all crash-risk force unwraps.

### 4.2 API keys leak check
```bash
# Ensure no API keys, tokens, or secrets in source code
grep -rn "sk-ant\|api_key\|apiKey.*=.*\"[a-zA-Z0-9]" Sources/ --include="*.swift" | \
  grep -v "Keychain\|UserDefaults\|loadKey\|saveKey\|KeychainManager"
```
Expected: no matches. If any found: this is a critical security issue — move to Keychain immediately.

### 4.3 MainActor isolation check
```bash
# Find async operations that might be updating UI from background thread
grep -rn "DispatchQueue.main\|Task {" Sources/ --include="*.swift" | \
  grep -v "@MainActor\|MainActor.run"
```
Document findings. All UI mutations must happen on MainActor.

### 4.4 Memory leak patterns
```bash
# Find potential retain cycles in closures
grep -rn "self\." Sources/ --include="*.swift" | \
  grep -E "\.sink|\.map|Task {|DispatchQueue" | \
  grep -v "\[weak self\]\|\[unowned self\]" | \
  head -30
```
For each: evaluate whether a retain cycle is possible. Fix where needed with `[weak self]`.

### 4.5 TODO/FIXME audit
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|temp\|temporary" Sources/ --include="*.swift"
```
List all findings. Resolve any that indicate missing functionality or known bugs.

---

## Phase 5 — Edge Case Verification

Write and run code (or manual filesystem tests) to verify these edge cases:

### 5.1 Empty vault
- App launches with empty vault directory → shows EmptyStateView, no crash
- Cmd+N creates first note → note appears in sidebar

### 5.2 Very large note
- Create a note with 100,000 words (~600KB of text)
- Open it — must load in <1 second
- Search must still work
- Auto-save must not block UI

### 5.3 Special characters in filenames
- Note titled `# My Note: "Important" / Today?` → auto-title produces `My Note- -Important- - Today-.md` (no invalid chars)
- Note titled `# αβγ日本語` → filename `αβγ日本語.md` (Unicode is valid in HFS+, keep as-is)
- Note titled `# .hidden` → filename `.hidden.md` (edge case — leading dot makes it hidden in Finder; warn and prefix with underscore: `_hidden.md`)

### 5.4 Vault moved externally
- Simulate vault folder being moved while app is running
- App should detect the missing path and show vault picker, not crash

### 5.5 Concurrent note creation
- Create 10 notes simultaneously (async tasks) — verify no two notes get the same filename
- Verify all 10 notes exist on disk after creation

### 5.6 Wikilink autocomplete with 500 notes
- Create 500 notes in vault
- Type `[[` in editor — autocomplete must appear in <100ms
- Fuzzy filter must narrow results as user types without lag

### 5.7 Metadata sidecar path consistency
- Create note at `~/Library/CloudStorage/GoogleDrive-daniel@gamrot.cz/Můj disk/Notero/Projects/Alpha.md`
- Sidecar must be at `~/.notero/meta/{hash}/Projects/Alpha.md.json`
- Move note to `~/Library/CloudStorage/GoogleDrive-daniel@gamrot.cz/Můj disk/Notero/Alpha.md` via VaultManager
- Call `NoteMetadataService.updatePath(from:to:)`
- Sidecar must now be at `~/.notero/meta/{hash}/Alpha.md.json`
- Old sidecar must be deleted
- ID must be unchanged

---

## Phase 6 — Final Report

After running all phases, create a file at `TEST_REPORT.md` in the project root with this structure:

```markdown
# Notero Test Report
Generated: {date}

## Build
- Debug build: PASS / FAIL
- Release build: PASS / FAIL
- Analyzer warnings: {count} ({list critical ones})

## Unit Tests
- Total: {X} tests
- Passed: {X}
- Failed: {X}
{list each failed test with error message}

## Integration Tests
{for each integration test: PASS / FAIL / SKIP with note}

## Code Quality
- Force unwraps: {count} ({X} safe, {X} fixed, {X} remaining risks}
- API key leaks: NONE FOUND / {details}
- MainActor violations: {count fixed}
- Retain cycles fixed: {count}
- TODOs/FIXMEs: {count} ({list actionable ones})

## Edge Cases
{for each: PASS / FAIL / PARTIAL with notes}

## Critical Issues
{list any issues that could cause data loss, crashes, or security problems}

## Known Limitations
{list behaviors that are incomplete but non-critical}

## Summary
Overall status: GREEN / YELLOW / RED
Ready for use: YES / NO / WITH CAVEATS
```

After generating the report:
1. Fix all CRITICAL issues found
2. Re-run the full test suite
3. Update TEST_REPORT.md with final results
4. Build final Release: `xcodebuild build -project Notero.xcodeproj -scheme Notero -configuration Release`
5. Copy to Desktop: `cp -r build/Release/Notero.app ~/Desktop/Notero.app`
