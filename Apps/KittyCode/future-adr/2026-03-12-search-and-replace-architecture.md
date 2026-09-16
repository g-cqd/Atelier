# ADR: Search, Replace, and Search Focus Architecture

Status: Proposed
Date: 2026-03-12
Revised: 2026-03-16

## Goal

Add first-class search and replace to KittyCode with:

- current-file search with live highlighting
- workspace-wide search across all project files
- bulk replace for both scopes
- next/previous occurrence stepping
- result counts and result lists
- a dedicated search pane in the sidebar activity bar
- case-sensitive and regex options

The engine is fully in-house. No external dependencies. No subprocess shells. The editor owns the entire search pipeline from file enumeration to result rendering.

## Product Scope

### V1 Surface

- New `Search` activity bar item and sidebar pane.
- Search targets:
  - current file
  - open buffers
  - workspace
- Search controls:
  - find field
  - replace field
  - toggle replace visibility
  - case-sensitive toggle
  - regex toggle
  - include hidden toggle
  - include gitignored toggle
  - scope selector
  - next/previous match stepper
- Results:
  - total match count
  - per-file result counts for workspace search
  - active match index for current file search
  - selectable results list with context snippets
- Replace:
  - replace current match
  - replace all in current file
  - replace all in workspace with confirmation

### V1 Boundaries

- Plain text and regex search only.
- No external dependencies (no ripgrep, no grep, no subprocess).
- No tree-sitter structural search.
- No quick-open palette.
- No whole-word toggle, exclude editor, or saved search history in V1.

## Codebase Integration Points

### Sidebar and Activity Bar

`SidebarPanel` (EditorStateCore.swift:295) currently has `.explorer` and `.openDocuments`. Adding `.search` requires:

- New case in the enum
- Activity bar icon mapping in RenderActivityBar.swift (the `search` symbol already exists in TerminalSymbolTheme.swift)
- Mouse click routing in MouseInput.swift
- Sidebar render dispatch in Render.swift

### TextEditor Highlight Model

The current selection model (TextEditor.swift:32) uses `selectionRanges: [Int: ClosedRange<Int>]` — exactly one highlighted range per line. ViewRenderer.swift applies this per-character during rendering.

Search needs multiple highlighted ranges per line with distinct styling (inactive match, active match, user selection). This requires replacing the single-range model with a multi-range model.

### File Enumeration

DirectoryScanner.scanAsync() (DirectoryScanner.swift:49) already supports parallel recursive enumeration with `FileVisibility` for hidden/gitignored filtering. Search needs a flat file-path enumerator built on top of this, plus include/exclude glob support.

### Buffer Coordination

BufferManager tracks open files with dirty state. Search must:

- Search open buffers using their in-memory content (not disk)
- Search closed files from disk
- Replace in open buffers through TextBuffer mutation API
- Replace in closed files through direct disk I/O

### Command System

The KeymapResolver + CommandDispatcher system (Phases 1–7) handles all keybindings. Search commands register through the same system with mode-aware defaults for nano, vim, and kittycode presets.

## Architecture

### New SPM Target

Add `Sources/KittySearch` with dependencies on `KittyFileTree` and `KittyText`. Pure search logic lives here. Rendering, keybindings, and shell integration stay in `KittyCode`.

### Core Types (KittySearch)

```swift
/// What the user typed and how to interpret it.
struct SearchQuery: Sendable {
    var text: String
    var isCaseSensitive: Bool
    var isRegex: Bool
}

/// Where to search.
enum SearchTarget: Sendable {
    case currentFile
    case openBuffers
    case workspace
}

/// Filtering options for workspace search.
struct SearchScope: Sendable {
    var includeHidden: Bool
    var includeGitIgnored: Bool
    var includeGlobs: [String]
    var excludeGlobs: [String]
}

/// A compiled, reusable search pattern.
/// Compiles once from SearchQuery, used across all files.
enum SearchPattern: Sendable {
    case literal(text: String, caseSensitive: Bool)
    case regex(Regex<AnyRegexOutput>)
}

/// A single match within a file.
struct SearchMatch: Sendable {
    var row: Int          // 0-based line index
    var colStart: Int     // 0-based column start (inclusive)
    var colEnd: Int       // 0-based column end (exclusive)
}

/// All matches within one file.
struct SearchFileResult: Sendable {
    var filePath: String
    var fileName: String
    var matches: [SearchMatch]
    var contextSnippets: [String]  // one per match, for results list
}

/// Complete search run output.
struct SearchRunResult: Sendable {
    var query: SearchQuery
    var results: [SearchFileResult]
    var totalMatchCount: Int
    var filesSearched: Int
    var filesMatched: Int
    var durationMilliseconds: Double
    var wasCancelled: Bool
}
```

### Search Engine

The engine is a stateless function that takes a compiled pattern and content, returns matches. No global state. No singletons.

```swift
/// Core matching function. Operates on an array of lines.
/// Returns all matches in the content.
func findMatches(
    in lines: [String],
    pattern: SearchPattern
) -> [SearchMatch]

/// Compile a user query into a reusable pattern.
/// Returns nil if the regex is invalid.
func compilePattern(_ query: SearchQuery) -> SearchPattern?
```

#### Literal Search Path

For literal (non-regex) queries — the common case:

1. If case-sensitive: use `String.range(of:)` with no options per line.
2. If case-insensitive: use `String.range(of:options:.caseInsensitive)` per line.
3. Iterate all occurrences per line by advancing the search start index after each match.

This is simple, correct, and fast enough. Swift's String search uses optimized algorithms internally. For a single-project editor (typically <1GB of source), line-by-line literal search completes in under 100ms for most queries.

No SIMD intrinsics. No custom byte scanning. If profiling later reveals a bottleneck, optimization can be added behind the same interface without architectural changes.

#### Regex Search Path

For regex queries:

1. Compile the user's pattern into a `Regex<AnyRegexOutput>` at query time.
2. If case-insensitive, apply `(?i)` prefix or use `.ignoresCase()`.
3. Per line, iterate all matches using `String.matches(of:)`.
4. Extract match ranges and convert to column offsets.

Swift's built-in `Regex` type handles the complexity. No third-party regex library needed.

#### Error Handling

Invalid regex patterns are caught at compile time (`compilePattern` returns nil). The UI shows an error message in the search panel. No crashes, no exceptions propagating.

### Workspace File Enumerator

A flat file enumerator built on DirectoryScanner's infrastructure:

```swift
/// Enumerate all searchable file paths in the workspace.
func enumerateSearchableFiles(
    rootPath: String,
    scope: SearchScope,
    visibility: FileVisibility
) async -> [String]
```

Implementation:

1. Use DirectoryScanner.scanAsync() to get the file tree.
2. Flatten to file paths (skip directories).
3. Apply include/exclude glob filters.
4. Return the list.

Glob matching uses `fnmatch(3)` or a simple pattern matcher — no external library needed.

### Workspace Search Coordinator

Orchestrates parallel search across multiple files:

```swift
func searchWorkspace(
    pattern: SearchPattern,
    files: [String],
    openBuffers: [String: [String]],  // filePath → lines
    maxResults: Int,
    onProgress: @Sendable (SearchFileResult) -> Void
) async -> SearchRunResult
```

Implementation:

1. Partition files into chunks (target ~50 files per chunk).
2. Use `TaskGroup` with bounded concurrency (`ProcessInfo.processInfo.activeProcessorCount` workers).
3. For each file:
   a. If file is in `openBuffers`, search the in-memory lines.
   b. Otherwise, read from disk using buffered `FileHandle` reads.
   c. Split into lines, run `findMatches`, collect results.
4. Call `onProgress` for each file with matches (enables incremental UI updates).
5. Check `Task.isCancelled` between files for responsive cancellation.
6. Aggregate results into `SearchRunResult`.

#### Why Buffered Reads, Not mmap

Memory-mapped I/O has 4-5x higher overhead than buffered reads for multi-file search due to mmap/munmap syscall cost and TLB pressure (documented by ripgrep's author). Buffered reads with a reusable 64KB buffer are simpler and faster for scanning many files.

### Replace Engine

#### Current-File Replace

Replace operates on the active buffer through the existing TextBuffer mutation API:

```swift
/// Replace a single match in the active buffer.
func replaceMatch(
    _ match: SearchMatch,
    with replacement: String,
    in state: EditorState
)

/// Replace all matches in the active buffer.
func replaceAllInFile(
    matches: [SearchMatch],
    with replacement: String,
    in state: EditorState
)
```

Both functions:

1. Record undo snapshots via `activeBufferSnapshot()`.
2. Apply replacements in reverse order (last match first) to preserve earlier match positions.
3. Call `textDidChange` for undo tracking.
4. Re-run search to update match positions after replacement.

#### Workspace Replace

Workspace replace generates a plan, shows confirmation, then applies:

```swift
struct ReplacePlan: Sendable {
    var edits: [FileEdit]
    var totalReplacements: Int
    var filesAffected: Int
}

struct FileEdit: Sendable {
    var filePath: String
    var replacements: [(match: SearchMatch, replacement: String)]
    var isOpenBuffer: Bool
}
```

Application:

1. For open buffers: apply through TextBuffer mutation API (undo-aware).
2. For closed files: read content, apply replacements, write back atomically (write to temp file, rename).
3. Show a confirmation prompt before applying: "Replace N occurrences in M files?"

#### Regex Capture Group Replacement

For regex patterns, the replacement string supports `$1`, `$2`, etc. for capture group substitution. The `Regex` match output provides captured groups which are interpolated into the replacement string at apply time.

### In-File Search State

Search state lives on `EditorState`:

```swift
/// Current search state for in-file search.
struct InFileSearchState {
    var query: SearchQuery
    var pattern: SearchPattern?
    var matches: [SearchMatch]
    var activeMatchIndex: Int  // -1 if no active match
    var totalCount: Int { matches.count }
}
```

When the user types in the search field:

1. Compile the query into a pattern.
2. Run `findMatches` on the current file's lines.
3. Store matches in `InFileSearchState`.
4. Jump to the nearest match from the current cursor position.
5. Render all matches as highlights in the editor.

Next/previous stepping increments/decrements `activeMatchIndex` and scrolls to the match.

## Editor Highlight Generalization

### New Model

Replace `selectionRanges: [Int: ClosedRange<Int>]` with:

```swift
struct TextHighlight: Sendable {
    enum Role {
        case userSelection
        case searchMatch
        case activeSearchMatch
    }
    var range: ClosedRange<Int>  // column range within the line
    var role: Role
}

// On TextEditor:
var highlights: [Int: [TextHighlight]]  // line index → highlights
```

### Rendering

ViewRenderer applies highlights per-character with precedence:

1. Active search match (highest priority — distinct background)
2. User selection
3. Inactive search match (lowest priority — subtle background)

When multiple highlights overlap on a character, the highest-priority style wins.

### Style Resolution

Each role maps to a theme color:

```swift
// In KittyConfig.Theme:
var searchMatchBackground: Color       // subtle highlight for all matches
var activeSearchMatchBackground: Color  // strong highlight for current match
```

The existing `selectionStyle` continues to provide the user selection color.

### Performance

For files with many matches (thousands), per-character iteration over all highlights per line is O(matches_per_line × line_length). For the common case (<100 matches per line), this is negligible. If profiling shows issues, a sorted-range binary search can be added without API changes.

## Focus Model

### Shell-Level Focus

The existing `EditorState.Mode` (.tree, .editor) is too coarse for search. Add a `KeyContext` case:

```swift
// In KeyContext.swift, add:
case searchPanel
```

When the search panel is focused, `KeyContext.from(state:)` returns `.searchPanel`. The resolver routes keys to search-specific bindings (Tab for field navigation, Enter for result selection, Escape for closing).

### Search Panel Focus

Within the search panel, track which control is focused:

```swift
enum SearchPanelFocus {
    case findField
    case replaceField
    case resultsList
}
```

Tab cycles through controls. The focused control determines how Enter and character input behave.

### Focus Transitions

- Opening search: focus moves to findField
- Pressing Enter on a result: focus moves to editor, search panel retains state
- Escape in search panel: close search, return to previous focus (editor or tree)
- Ctrl+F / Cmd+F while in editor: open search with current selection as query

## UI Shape

### Activity Bar

Add `"search"` to `activityBar.items` config default. Uses existing `symbolTheme[.search]` glyph.

### Sidebar Panel

The search panel renders in the sidebar area (same width as tree panel):

```
┌─────────────────────┐
│ Find: [query      ] │  ← text input field
│ Replace: [repl    ] │  ← shown when replace is toggled
│ ○ Case  ○ Regex     │  ← toggle indicators
│ Scope: Workspace    │  ← target selector
│─────────────────────│
│ 42 results in 8 files│  ← summary line
│─────────────────────│
│ ▸ src/main.swift (3) │  ← collapsible file group
│   12: let foo = bar  │  ← match with context
│   45: foo.baz()      │
│ ▸ lib/utils.swift (2)│
│   8: import foo      │
└─────────────────────┘
```

### Editor Highlights

When search is active, all matches in the current file are highlighted:

- Inactive matches: subtle background tint
- Active match: strong background tint (the one the cursor jumped to)
- User selection: standard selection color (takes precedence over search highlights)

### Status Bar

The status bar shows search state when active:

- `Match 3/42` for in-file search with active match index
- No status bar clutter when search is inactive

## Config

Add a `search` section to KittyConfig:

```json
{
  "search": {
    "defaultTarget": "workspace",
    "includeHiddenByDefault": false,
    "includeGitIgnoredByDefault": false,
    "caseSensitiveByDefault": false,
    "regexByDefault": false,
    "excludeGlobs": ["**/.git/**", "**/build/**", "**/.build/**"],
    "maxResults": 5000,
    "debounceMilliseconds": 150
  }
}
```

- `debounceMilliseconds`: delay before workspace search starts after typing stops. In-file search is instant (no debounce).
- `maxResults`: cap to prevent unbounded memory use on broad queries.
- `excludeGlobs`: always-excluded paths (in addition to gitignore).

## Mode-Aware Keybindings

### Nano

| Key | Command |
|-----|---------|
| Ctrl+F | searchOpenFile |
| Ctrl+Shift+F | searchOpenWorkspace |
| Ctrl+R (in search panel) | toggleReplace |
| Enter | searchNext |
| Shift+Enter | searchPrevious |
| Escape | searchClose |

### Vim

| Key | Command |
|-----|---------|
| / | searchOpenFile |
| n | searchNext |
| N | searchPrevious |
| Escape | searchClose |
| (mapped shortcut) | searchOpenWorkspace |

### KittyCode

| Key | Command |
|-----|---------|
| Cmd+F | searchOpenFile |
| Cmd+Shift+F | searchOpenWorkspace |
| Cmd+H | toggleReplace |
| Enter | searchNext |
| Shift+Enter | searchPrevious |
| Escape | searchClose |
| Tab | searchNextField |
| Shift+Tab | searchPrevField |

All overrideable through the existing keybinding config system.

## New CommandIDs

```
searchOpenFile         — open/focus in-file search
searchOpenWorkspace    — open/focus workspace search
searchClose            — close search panel
searchNext             — jump to next match
searchPrevious         — jump to previous match
searchReplaceOne       — replace current match
searchReplaceAll       — replace all matches in scope
searchToggleReplace    — show/hide replace field
searchToggleCase       — toggle case sensitivity
searchToggleRegex      — toggle regex mode
searchNextField        — Tab between search controls
searchPrevField        — Shift+Tab between search controls
```

## Implementation Plan

### Phase 1: KittySearch Engine

Create the `KittySearch` SPM target with:

- `SearchQuery`, `SearchPattern`, `SearchMatch`, `SearchFileResult`, `SearchRunResult`
- `compilePattern()` — query compilation for literal and regex
- `findMatches(in:pattern:)` — core matching function
- Unit tests: literal search, case-insensitive, regex, multi-match per line, empty file, no matches, invalid regex

This is a pure library with no UI dependencies. Can be benchmarked independently.

### Phase 2: Editor Highlight Generalization

Replace `selectionRanges: [Int: ClosedRange<Int>]` with `highlights: [Int: [TextHighlight]]` in TextEditor. Update ViewRenderer to iterate highlights per-character with role-based precedence. Update RenderEditor to populate highlights from both selection and search matches.

Test: existing selection rendering still works identically.

### Phase 3: In-File Search

- Add `InFileSearchState` to EditorState
- Add search CommandIDs and keybindings
- Add `KeyContext.searchPanel` and search panel focus handling in EventHandling
- Implement search field input handling (typing updates query, compiles pattern, runs findMatches)
- Implement next/previous stepping with cursor and scroll updates
- Render match highlights in the editor
- Add search status to status bar ("Match 3/42")

Test: type query → matches highlight → next/previous cycles through → escape closes.

### Phase 4: Search Sidebar Panel

- Add `.search` to `SidebarPanel`
- Wire activity bar, render dispatch, and mouse input
- Render search controls (find field, toggles, scope selector)
- Render result list with file groups and context snippets
- Implement result selection (Enter opens file and jumps to match)
- Tab/Shift+Tab field navigation

Test: open search panel → type query → results appear → select result → editor jumps.

### Phase 5: Workspace Search

- Implement `enumerateSearchableFiles` with glob filtering
- Implement `searchWorkspace` with `TaskGroup`-based parallelism
- Buffer coordination (search open buffers in-memory, closed files from disk)
- Incremental result streaming to UI
- Cancellation on new keystroke
- Debounce for workspace searches

Test: workspace search finds matches across files → cancellation works → open buffers searched from memory.

### Phase 6: Replace

- In-file replace: single match and replace-all
- Workspace replace: plan generation, confirmation prompt, atomic application
- Regex capture group substitution
- Undo integration for open buffer replacements

Test: replace one → replace all → workspace replace with confirmation → undo works.

### Phase 7: Config and Polish

- Add `SearchConfig` to KittyConfig
- Wire config defaults (target, case sensitivity, excludeGlobs, etc.)
- Hot-reload support
- Edge cases: binary file detection, very large files, empty workspace

## Files Modified Per Phase

### Phase 1
| File | Change |
|------|--------|
| `Package.swift` | +KittySearch target |
| `Sources/KittySearch/SearchQuery.swift` | New |
| `Sources/KittySearch/SearchPattern.swift` | New |
| `Sources/KittySearch/SearchMatch.swift` | New |
| `Sources/KittySearch/SearchEngine.swift` | New |
| `Tests/KittySearchTests/` | New test files |

### Phase 2
| File | Change |
|------|--------|
| `Sources/KittyWidgets/TextEditor.swift` | Replace selectionRanges with highlights |
| `Sources/KittyWidgets/ViewRenderer.swift` | Multi-highlight rendering |
| `Sources/KittyCode/RenderEditor.swift` | Populate highlights from selection + search |

### Phase 3
| File | Change |
|------|--------|
| `Sources/KittyCode/EditorStateCore.swift` | +InFileSearchState |
| `Sources/KittyCode/CommandID.swift` | +search commands |
| `Sources/KittyCode/KeyContext.swift` | +searchPanel |
| `Sources/KittyCode/KeymapResolver.swift` | +search keybindings |
| `Sources/KittyCode/CommandDispatcher.swift` | +search dispatch cases |
| `Sources/KittyCode/EventHandling.swift` | +search panel input handling |
| `Sources/KittyCode/StatusBarContent.swift` | +match count display |

### Phase 4
| File | Change |
|------|--------|
| `Sources/KittyCode/EditorStateCore.swift` | +SidebarPanel.search |
| `Sources/KittyCode/RenderActivityBar.swift` | +search icon |
| `Sources/KittyCode/Render.swift` | +search panel render dispatch |
| `Sources/KittyCode/RenderSearch.swift` | New — search panel rendering |
| `Sources/KittyCode/MouseInput.swift` | +search panel click handling |

### Phase 5
| File | Change |
|------|--------|
| `Sources/KittySearch/WorkspaceSearch.swift` | New — parallel search coordinator |
| `Sources/KittySearch/FileEnumerator.swift` | New — glob-filtered file listing |
| `Sources/KittyCode/EditorStateCore.swift` | +workspace search state |

### Phase 6
| File | Change |
|------|--------|
| `Sources/KittySearch/SearchReplace.swift` | New — replace engine |
| `Sources/KittyCode/EditorStateFileSystem.swift` | +replace operations |
| `Sources/KittyCode/EditorPrompt.swift` | +replace confirmation prompt kind |

### Phase 7
| File | Change |
|------|--------|
| `Sources/KittyCode/Config.swift` | +SearchConfig |

## Risks and Open Questions

- **Highlight model migration** is the main widget-level prerequisite. Existing selection rendering must not regress.
- **Regex replacement** semantics: capture group syntax (`$1`, `$2`) needs clear documentation. Invalid group references should insert literally.
- **Dirty open buffers during workspace replace**: V1 policy is to apply replacements to the in-memory buffer (making it dirty) rather than requiring a save first. The user can undo per-buffer.
- **Binary file detection**: skip files where the first 8KB contains null bytes. Don't attempt to search or display results for binary files.
- **Very large files** (>10MB): search them but cap context snippet extraction. Don't load entire file into memory — stream line-by-line.
- **Performance target**: in-file search should feel instant (<5ms for files under 10K lines). Workspace search should complete in under 2 seconds for typical projects (<10K files).

## Why Not ripgrep

The industry trend is to use ripgrep. VS Code, Helix, and others shell out to `rg`. This is pragmatic for editors that don't own their file I/O layer.

KittyCode already owns:

- File enumeration (DirectoryScanner)
- Gitignore filtering (GitIgnoreChecker)
- Buffer management (BufferManager with dirty tracking)
- Text mutation (TextBuffer, TextOperations)
- Undo history (BufferEditHistory)

Shelling out to ripgrep would mean:

- An external dependency that users must install
- Subprocess management, JSON parsing, and error handling
- No access to open buffer content (rg searches disk, not memory)
- No integration with undo/redo for replace operations
- Two separate code paths for "search in open file" vs "search in workspace"

The in-house engine searches open buffers and closed files through a single code path. Replace operations integrate directly with the undo system. The search scope respects the exact same visibility rules as the file tree. There is one source of truth for file content.

For a single-project editor, Swift's built-in `String` search and `Regex` are fast enough. The architecture leaves room for optimization (SIMD scanning, mmap for large single files) if profiling reveals a need, without changing the public API.
