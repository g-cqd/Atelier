# Future ADR: Search, Replace, and Search Focus Architecture

Status: Proposed
Date: 2026-03-12

## Goal

Add first-class search and replace to KittyCode with:

- current-file search
- workspace-wide search
- bulk replace for both
- next/previous occurrence stepping
- result counts and result lists
- a dedicated search pane in the sidebar activity bar
- case-sensitive and regex options

This revision also adds four explicit product decisions:

- the engine should be in-house, parallel, and optimized for low-latency interactive use
- scope customization should include hidden and ignored files, and support broader scope controls
- defaults should be configurable in `~/.kittycode.json`
- bindings and interaction should respect `nano`, `vim`, and a new `kittycode` mode

## Refined Product Scope

### V1 surface

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
  - selectable results list with snippets
- Replace:
  - replace current match
  - replace all in current file
  - replace selected file/group in workspace
  - replace all in workspace with confirmation

### V1 boundaries

- Plain text and regex search only.
- No external `rg` dependency.
- No tree-sitter structural search in this feature.
- No quick-open palette in this ADR.
- No whole-word, exclude UI editor, or saved search history in the first slice.

## Current Codebase Findings

- The sidebar is currently limited to `.explorer` and `.openDocuments` in `Sources/KittyCode/EditorStateCore.swift`, `Sources/KittyCode/Render.swift`, `Sources/KittyCode/RenderActivityBar.swift`, and `Sources/KittyCode/MouseInput.swift`.
- Input focus is ad hoc. The shell only models `.tree` and `.editor`, while prompts and context menus short-circuit input in `Sources/KittyCode/EventHandling.swift`.
- `KittyWidgets.FocusEngine` already exists in `Sources/KittyWidgets/FocusEngine.swift` but is not wired into KittyCode.
- `TextEditor` only supports one highlighted range per line through `selectionRanges: [Int: ClosedRange<Int>]` in `Sources/KittyWidgets/TextEditor.swift` and `Sources/KittyWidgets/ViewRenderer.swift`. Search needs multi-match highlight support.
- `KittyQuery` is a structural query engine, not a text search engine. It should stay out of V1 search.
- Async file traversal and file loading already exist:
  - `Sources/KittyFileTree/DirectoryScanner.swift`
  - `Sources/KittyWorkspace/WorkspaceFileLoading.swift`
  - `Sources/KittyWorkspace/WorkspaceSession.swift`
- Active-buffer writes exist in `Sources/KittyCode/EditorStateFileSystem.swift`, but workspace replace needs a planner that handles both open buffers and closed files consistently.
- The search glyph already exists in `Sources/KittySymbols/TerminalSymbolTheme.swift`.
- Config hot reload already exists through `KittyConfig.load(...)`, `AppMain`, and `EditorState.applyConfig(...)`.

## Decision

### 1. Build an in-house search engine

KittyCode should not shell out to `rg` for the core feature. The editor should own:

- candidate file enumeration
- query compilation
- parallel execution
- result aggregation
- replace planning
- cancellation and incremental refresh

This keeps behavior deterministic, config-driven, and tightly integrated with open buffers, tree visibility, and mode-aware UI.

### 2. Build a related search focus engine

Search is not just a matcher. It needs a keyboard-first focus model for:

- editor
- sidebar panel
- search controls
- result list
- overlay prompts

The existing `KittyWidgets.FocusEngine` should be promoted from an unused widget helper into a shell-level building block, then extended with stable control ids inside KittyCode.

### 3. Support customizable scope

Scope should be modeled as two dimensions:

- target:
  - current file
  - open buffers
  - workspace
- filters:
  - include hidden
  - include gitignored
  - include globs
  - exclude globs
  - optional root override in later slices

This gives users both a simple path and a scalable path.

### 4. Make search configurable

Search defaults should be defined in config and hot-reload with the rest of the app.

### 5. Make search mode-aware

Search commands should resolve through the same command system as the rest of the app and expose different defaults for:

- `nano`
- `vim`
- `kittycode`

The new `kittycode` mode is the GUI-like preset for the app.

## Proposed Architecture

### New target

Add a new SwiftPM target:

- `Sources/KittySearch`

Suggested dependencies:

- `KittyFileTree`
- `KittyText`
- `KittySync`

Keep rendering and keybinding concerns in `KittyCode`. Keep pure search logic in `KittySearch`.

### Core types

- `SearchQuery`
- `SearchTarget`
- `SearchScopeOptions`
- `SearchPattern`
- `SearchMatch`
- `SearchFileResult`
- `SearchRunResult`
- `SearchReplaceEdit`
- `SearchReplacePlan`
- `SearchExecutionStats`

### Engine layout

- `SearchFileEnumerator`
  - creates a stable candidate snapshot
  - respects hidden and ignored settings
  - applies include and exclude globs
- `SearchCompiler`
  - compiles literal and regex queries once
  - precomputes case-folding strategy
- `LiteralSearchKernel`
  - custom UTF-8 scanning path
  - optimized for interactive literal search
  - supports fast ASCII case-insensitive fallback
- `RegexSearchKernel`
  - uses precompiled regex objects behind the same engine boundary
  - runs in parallel worker tasks
- `SearchWorkerPool`
  - bounded `TaskGroup` execution
  - adaptive worker count based on CPU count and query kind
- `SearchResultAggregator`
  - streams grouped results
  - computes total counts
  - extracts snippets
  - supports cancellation and result caps
- `SearchReplacePlanner`
  - converts matches into file edits
  - handles capture-group replacement for regex
  - produces an auditable dry-run plan before mutation
- `SearchBufferCoordinator`
  - reconciles disk files with open buffers
  - decides how dirty buffers participate in search and replace

### Performance strategy

- Prefer memory-mapped reads for closed files when safe.
- Avoid loading file content twice for snippet extraction.
- Use a literal fast path for the common case.
- Keep regex on a separate compiled path.
- Bound concurrency to avoid saturating the system during live search.
- Debounce interactive workspace searches.
- Carry file-level cancellation checks through every worker.
- Add benchmarks before tuning API details.

## Focus and Navigation Model

### Shell-level focus

Introduce a focus model above `EditorState.Mode`, for example:

- `tree`
- `editor`
- `sidebar(panel: SidebarPanel)`
- `overlay`

Keep `Mode` for editing semantics if needed, but stop using it as the entire focus model.

### Search panel focus

Within the search panel, use a panel-local focus enum:

- `findField`
- `replaceField`
- `targetSelector`
- `optionsRow`
- `resultsList`

Back this with an extended `FocusEngine`.

### Editor match navigation

Search navigation should update:

- active match index
- editor cursor
- editor scroll position
- active highlight style

This is the "focusing engine for the editor" part of the feature, not just sidebar focus.

## UI Shape

### Activity bar

Add `search` to `activityBar.items`.

### Sidebar panel

Add `.search` to `EditorState.SidebarPanel`.

The search panel should render:

- query controls at the top
- counts and stepper below the controls
- result list below the summary

### Result list behavior

- Enter opens the file and jumps to the match.
- Repeated next/previous stays in the editor but keeps the search panel state.
- Selecting a file group can enable scoped replace for that file.

## Rendering Changes

`TextEditor` should support more than one highlighted range per line. Proposed evolution:

- replace `selectionRanges: [Int: ClosedRange<Int>]`
- with a generalized highlight model such as `highlightRanges: [Int: [TextHighlightRange]]`

Each highlight should carry a role:

- user selection
- search match
- active search match

This avoids abusing the selection renderer for search results.

## Config Additions

Suggested config extension:

```json
{
  "keybindingMode": "kittycode",
  "search": {
    "defaultTarget": "workspace",
    "includeHiddenByDefault": false,
    "includeGitIgnoredByDefault": false,
    "caseSensitiveByDefault": false,
    "regexByDefault": false,
    "includeGlobs": [],
    "excludeGlobs": ["**/.git/**", "**/build/**"],
    "parallelism": 0,
    "maxResults": 5000,
    "debounceMilliseconds": 75,
    "previewContextLines": 1
  }
}
```

Notes:

- `parallelism: 0` means auto-tune.
- Keybindings for search commands should live in the command-based keybinding system from the keybinding ADR.

## Mode-Aware Defaults

### Nano

- `Ctrl+F`: open current-file search
- `Ctrl+Shift+F` or a terminal-safe fallback: workspace search
- `Ctrl+R`: toggle replace
- `Enter` / `Shift+Enter`: next / previous match

### Vim

- `/`: open current-file search
- `n` / `N`: next / previous match
- a command or mapped shortcut opens workspace search
- search panel still supports universal `Enter` and `Esc`

### KittyCode

- `Cmd+F`: current-file search
- `Cmd+Shift+F`: workspace search
- `Cmd+Shift+H` or similar: show replace
- `Enter` / `Shift+Enter`: next / previous match
- `Tab` / `Shift+Tab`: search control focus

All of these should be overrideable.

## Implementation Plan

1. Create `KittySearch` and benchmark a literal-search spike against representative repositories.
2. Introduce generalized editor highlight ranges so search can render multi-match and active-match overlays.
3. Add shell-level focus state and panel-local focus handling based on `FocusEngine`.
4. Add search state to `EditorState` and wire a new `.search` sidebar panel into activity bar, render, and mouse input.
5. Implement current-file search first, including live counts, next/previous stepping, and replace-one / replace-all.
6. Implement workspace search with bounded parallelism, grouped results, snippets, and cancellation.
7. Implement workspace replace planning and confirmation, then apply mutations safely across closed files and eligible open buffers.
8. Wire search commands into the command-based keybinding system and config defaults.
9. Add regression tests, rendering tests, and engine benchmarks.

## Risks and Open Questions

- Multi-highlight rendering is the main widget-level prerequisite.
- Regex replacement semantics need a clearly documented capture-group policy.
- Dirty open buffers need explicit behavior during workspace replace:
  - skip
  - require save
  - or operate on buffer state and persist it
- Very large files may need caps or progressive result streaming.
- If the app must support non-kitty terminals gracefully, GUI-like shortcuts need terminal-safe fallback bindings.

## Recommendation

Proceed in this order:

1. command and focus architecture
2. editor highlight generalization
3. in-file search
4. workspace search
5. workspace replace

This keeps the first shipping slice useful while preserving the path to a fast in-house engine.
