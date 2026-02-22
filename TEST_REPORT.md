# Notero Test Report
Generated: 2026-02-22

## Build
- Debug build: PASS
- Release build: PASS
- Analyzer warnings: 0

## Unit Tests
- Total: 68 tests (across 7 test suites)
- Passed: 68
- Failed: 0

### VaultManagerTests (12 tests) — ALL PASS
- testCreateNote, testCreateDuplicateNote, testCreateFolder, testReadAndSaveNote
- testRenameItem, testDuplicateNote, testFileTreeBuild, testAllMarkdownFiles
- testMoveToTrash, testSortOrder_nameAscending, testSortOrder_nameDescending, testSortOrder_modifiedNewest

### SearchServiceTests (10 tests) — ALL PASS
- testAddAndSearch, testExactPhraseSearch, testCaseInsensitiveSearch, testDiacriticInsensitiveSearch
- testRemoveFromIndex, testAllNoteNames, testEmptyQueryReturnsNoResults, testTitleMatchRankedHigher
- testMultiTermAND, testSnippetContainsMatchContext

### NoteMetadataServiceTests (6 tests) — ALL PASS
- testEnsureIDGeneratesUUID, testMetadataIncludesCreatedDate, testEnsureIDReturnsSameIDOnRepeatedCalls
- testUpdatePathMigratesMetadata, testCreationDateFallback, testIDUniqueness

### LinkResolverTests (12 tests) — ALL PASS
- testResolveExactMatch, testResolveCaseInsensitive, testResolveNonExistent, testFindBacklinks
- testStringWikilinks, testFuzzyMatch, testResolvesWikilinkByFilename, testResolvesWikilinkCaseInsensitive
- testResolvesWikilinkWithoutExtension, testBrokenLinkReturnsNil, testBacklinksDetected, testPipeSyntax

### MarkdownHighlighterTests (14 tests) — ALL PASS
- testHighlightDoesNotMutateString, testHeadingGetsSemiboldFont, testBoldGetsApplied
- testMarkersAreDimmed, testInlineCodeGetsMonospacedFont, testHeading1FontSize, testHeading2FontSize
- testBoldAttribute, testItalicAttribute, testMarkersAreNotRemoved, testCodeInlineBackground
- testCursorDoesNotShift, testBlockquoteIndent, testNoStringMutationInProcessEditing

### NoteHistoryServiceTests (10 tests) — ALL PASS
- testSaveAndLoadSnapshot, testDeduplication, testMultipleVersions, testDiffBasic, testDeleteAllHistory
- testSnapshotCreatedOnSave, testNoDuplicateSnapshot, testRetentionLimit, testRestoreVersion
- testSnapshotsListedChronologically

### SemanticSearchServiceTests (9 tests) — ALL PASS
- testToggleEnablesAndDisables, testSetModelUpdatesModel, testSearchReturnsEmptyWhenDisabled
- testInitialState, testCosineSimilarity, testThresholdFiltersLowMatches, testResultsRankedByScore
- testHandlesOllamaUnavailable, testEmbeddingStoredAndLoaded

## Integration Tests
- 3.1 Vault lifecycle: PASS — create, sort, rename, move, trash all verified
- 3.2 Auto-save integrity: PASS — round-trip, special chars (ñ, 你好, 🎉), 1MB content
- 3.3 Search index consistency: PASS — index 20 notes, update, remove, diacritics, 50 result cap
- 3.4 Note ID stability: PASS — ID survives rename, move, 100 unique IDs verified
- 3.5 Note history: PASS — 5 versions, dedup, retention limit (50), restore, chronological order
- 3.6 Wikilink resolution: PASS — exact, case-insensitive, pipe syntax, backlinks
- 3.7 FSEvent watcher: PASS — external file create/delete detected, .icloud filtered

## Code Quality
- Force unwraps: 2 (2 safe — known constants: `UnicodeScalar(NSF2FunctionKey)!`, `.init(filenameExtension: "docx")!`; 0 fixed, 0 remaining risks)
- API key leaks: NONE FOUND — all keys stored via KeychainManager
- MainActor violations: 0 — all UI updates properly isolated
- Retain cycles fixed: 0 (none found — weak references already in place)
- TODOs/FIXMEs: 0

## Edge Cases
- 5.1 Empty vault: PASS — empty tree, first note creation works
- 5.2 Very large note (100K words): PASS — saves, loads, and searches correctly
- 5.3 Special characters in filenames: PASS — invalid chars sanitized, Unicode preserved
- 5.4 Vault moved externally: SKIP — requires live GUI interaction to verify vault picker
- 5.5 Concurrent note creation (10 simultaneous): PASS — all unique filenames, all exist on disk
- 5.6 Wikilink autocomplete with 500 notes: PASS — fuzzy filter completes in <100ms
- 5.7 Metadata sidecar path consistency: PASS — ID survives cross-folder move

## Critical Issues
None found.

## Known Limitations
- 5.4 Vault moved externally: Cannot be automated without launching the GUI; requires manual testing
- SemanticSearchService embedding persistence test is simplified (stores/reads in-memory) since Ollama is not available in CI
- `cosineSimilarity` and `embeddings` were changed from `private` to `internal` to enable testing via `@testable import`

## Summary
Overall status: GREEN
Ready for use: YES

Final build deployed to: ~/Desktop/Notero.app
