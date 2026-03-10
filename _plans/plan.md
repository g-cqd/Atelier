# KittyCode SOTA Completion & Modular Extraction Plan

## Context

Seven independent codebase reviews (Gemini, GLM-4.7, GPT-5.4, Grok, Opus 4.6) and two requirements gap analyses (Gemini 3.1 Pro, GLM-4.7) were consolidated against a validated exploration of the current codebase. KittyCode is a pure-Swift 6 terminal UI framework (zero dependencies) with a layered architecture across 10 library modules, 2 executables, 68 source files, ~9,500 LOC, and 135 passing tests.

**The core structural problem:** The library modules (KittyWidgets, KittySyntax) define data structures and protocols but lack rendering integration, while KittyCode bypasses them entirely — directly manipulating `RenderPipeline.buffer` with free functions and a monolithic `EditorState`. The View protocol has no `render(to:at:)`, ViewModifiers are no-ops, there is no `@State`, and the syntax pipeline (Highlighter + Query + Grammar) sits completely unused.

**Goal:** Make KittyCode and all sub-modules SOTA, feature-complete, and maximally composable. Extract reusable features into independent SPM modules. Ship KittyCode as a flagship app built entirely on the composable library stack.

**Sources:** 5 codebase reviews (Gemini, GLM-4.7, GPT-5.4, Grok, Opus 4.6) + 3 gap analyses (Gemini 3.1 Pro, GLM-4.7, GPT-5.4)

---

## Phase 1: Security & Correctness Hardening (P0)

**Goal:** Eliminate all critical safety issues without changing public API shapes.

### 1A: Fix @unchecked Sendable violations

| File | Issue | Fix |
|------|-------|-----|
| `Sources/KittyRenderer/RenderPipeline.swift:5` | Mutable front/back buffers, no sync | Add `@MainActor` isolation (already used on @MainActor everywhere), remove `@unchecked Sendable` |
| `Sources/KittySyntax/GrammarRegistry.swift:6` | Mutable dictionaries, no sync | Convert to `actor GrammarRegistry` — make `register`, `loadManifest`, `grammar(for:)` async |
| `Sources/KittyTerminal/POSIXTerminalConnection.swift:7` | Mutable `originalTermios`, no sync | Add `OSAllocatedUnfairLock` around `originalTermios` mutations, document safety invariant |
| `Sources/KittyTerminal/MockTerminalConnection.swift:3` | Uses NSLock correctly | Add `// SAFETY:` invariant comment documenting NSLock contract (already safe) |

**Tests to add:** Concurrency stress tests for GrammarRegistry (concurrent register + lookup).

### 1B: Add resource limits

| File | Issue | Fix |
|------|-------|-----|
| `Sources/KittyCode/EditorStateFileSystem.swift:80` | Unbounded file read | Add 50MB file size check via `FileManager.attributesOfItem` before `contents(atPath:)` |
| `Sources/KittyCode/EditorStateFileSystem.swift:4` | Unbounded directory scan | Add `maxEntries: Int = 10_000` parameter, bail when exceeded |
| `Sources/KittyGrammar/GrammarLoader.swift:11` | Unbounded grammar load | Add 10MB size cap on `Data(contentsOf:)` |
| `Sources/KittyInput/SequenceRouter.swift:184,194` | Unbounded OSC/paste buffers | Add 1MB buffer cap, discard and emit error event on overflow |
| `Sources/KittyParser/GLRParser.swift:31` | Unbounded parse stack growth | Add `maxStacks: Int = 256` limit, prune lowest-priority stacks |
| `Sources/KittyQuery/QueryParser.swift:12` | Unbounded query depth | Add recursion depth limit (128) |

**Tests to add:** Resource limit rejection tests for each boundary.

### 1C: Fix path traversal & file security

| File | Issue | Fix |
|------|-------|-----|
| `Sources/KittyCode/EditorStateFileSystem.swift` | No path validation | Add `SecurePath.validate(_:root:)` — canonicalize with `URL.standardized.resolvingSymlinks`, verify `hasPrefix(root)` |
| `Sources/KittyCode/EditorStateFileSystem.swift:76,101` | Open/save without validation | Gate all file ops through SecurePath validator |
| `Sources/KittyCode/Config.swift:95` | Silent config failure | Log warning on parse failure instead of silent fallback |

### 1D: Fix error handling

| File | Issue | Fix |
|------|-------|-----|
| `Sources/KittyApp/ApplicationRuntime.swift:89,108,119` | `catch {}` on flush/redraw | Add `import os; private let logger = Logger(subsystem: "kittycode", category: "runtime")` — log errors |
| `Sources/KittyApp/ApplicationRuntime.swift:37-38` | `try?` on cleanup | Log cleanup failures |
| `Sources/KittyApp/ApplicationRuntime.swift:77` | `try?` on resize | Log resize failure |
| `Sources/KittyCode/AppMain.swift:13` | `/tmp` crash log with `try?` | Use `FileManager.default.temporaryDirectory` with unique name, log to stderr as fallback |

### 1E: Remove force unwraps

| File | Issue | Fix |
|------|-------|-----|
| `Sources/KittyCode/EditorInput.swift:13-124` | 10x `Character("X").asciiValue!` | Extract `private enum AsciiKey { static let a: UInt8 = 0x61 ... }` named constants |
| `Sources/KittyCode/EventHandling.swift:14,18` | 2x same pattern | Use AsciiKey constants |
| `Sources/KittyGrammar/ParseTableCompiler.swift:262-275` | 4x dictionary force unwrap | Replace with `guard let` + throw `GrammarError` |

### 1F: Add strict concurrency settings to Package.swift

Add to Package.swift:
```swift
let defaultSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]
```
Apply to all targets. Fix any new warnings this surfaces.

### 1G: Extract ParseStack to standalone file + isolate ErrorRecovery

| File | Change |
|------|--------|
| `Sources/KittyParser/GLRParser.swift` | Extract `ParseStack` struct to new `Sources/KittyParser/ParseStack.swift` |
| `Sources/KittyParser/GLRParser.swift` | Extract error recovery logic (ERROR node insertion, token skipping) to new `Sources/KittyParser/ErrorRecovery.swift` with `ErrorRecoveryStrategy` protocol |
| `Sources/KittyParser/GLRParser.swift:2` | Remove unused `import os` |

### 1H: Fix untested codec features + protocol mismatch

| File | Change |
|------|--------|
| `Sources/KittyCodecs/GraphicsEncoder.swift` | Add tests for chunk encoding, payload building |
| `Sources/KittyCodecs/KittySequences.swift` | Reconcile clipboard: original spec says OSC 5522, impl uses OSC 52 — document intentional choice or fix |
| `Tests/KittyCodecsTests/CodecsTests.swift` | Add test suites for GraphicsEncoder, clipboard (setClipboard/requestClipboard), notification (notify) |

**Verification:** `swift build && swift test` — all 135+ tests pass, plus new tests.

---

## Phase 2: New Module Extraction — KittyText & KittyFileTree

**Goal:** Extract reusable features from KittyCode into independent library modules.

### 2A: Create `KittyText` module (text buffer primitives)

**New target in Package.swift:** `KittyText` (depends on `KittyCodecs` only)

Extract and generalize from KittyCode:
- **Rope/PieceTable data structure** — New. Replace `[String]` file content with efficient text buffer supporting O(log n) insert/delete. Start with PieceTable (simpler, sufficient for v1).
- **Cursor model** — Extract from `EditorStateCore.swift` (cursorRow, cursorCol, scrollOffset, hScrollOffset) into `TextCursor` struct
- **Navigation logic** — Extract from `EditorNavigation.swift` (`jumpWordForward`, `jumpWordBackward`, `ensureEditorVisible`) into `TextNavigator`
- **Editing primitives** — Extract from `EditorEditing.swift` (`insertText`) into `TextEditor` operations on PieceTable
- **Selection model** — New. `TextSelection` with anchor/head, multi-cursor support foundation
- **UnicodeWidth** — New. Calculate terminal display width of `Character` (handle CJK, emoji, zero-width joiners)

**Files to create:**
```
Sources/KittyText/
├── PieceTable.swift          # O(log n) text buffer
├── TextCursor.swift          # Position, scroll state
├── TextNavigator.swift       # Word jump, page up/down, ensure visible
├── TextOperations.swift      # Insert, delete, undo/redo stack
├── TextSelection.swift       # Anchor/head selection model
└── UnicodeWidth.swift        # Terminal column width calculation
Tests/KittyTextTests/
└── TextTests.swift           # PieceTable ops, cursor math, word boundaries
```

### 2B: Create `KittyFileTree` module (file system browsing)

**New target in Package.swift:** `KittyFileTree` (depends on nothing — pure Foundation)

Extract and generalize from KittyCode:
- **FileEntry model** — Extract from `FileTree.swift` into public `FileNode` struct
- **Directory scanner** — Extract from `EditorStateFileSystem.swift:4-40` (`scanDirectory`) with security hardening (path validation, symlink checks, resource limits)
- **Tree flattening** — Extract from `EditorStateFileSystem.swift:43-58` (`flatten`)
- **Tree navigation** — Extract from `TreeInput.swift` (expand/collapse, cursor movement)

**Files to create:**
```
Sources/KittyFileTree/
├── FileNode.swift            # Public model (name, path, isDirectory, children, isExpanded)
├── DirectoryScanner.swift    # Secure scanning with limits, symlink handling
├── FileTreeNavigator.swift   # Expand/collapse, flatten for display
└── SecurePath.swift          # Path validation, canonicalization, root boundary
Tests/KittyFileTreeTests/
└── FileTreeTests.swift       # Scanner tests, path validation, tree operations
```

### 2C: Update dependency graph

```
Package.swift additions:
  .target(name: "KittyText", dependencies: ["KittyCodecs"]),
  .target(name: "KittyFileTree"),
  .testTarget(name: "KittyTextTests", dependencies: ["KittyText"]),
  .testTarget(name: "KittyFileTreeTests", dependencies: ["KittyFileTree"]),

Update KittyWidgets to depend on KittyText:
  .target(name: "KittyWidgets", dependencies: ["KittySyntax", "KittyInput", "KittyText"]),

Update KittyCode to depend on both:
  .executableTarget(name: "KittyCode", dependencies: ["KittyApp", "KittyFileTree"]),
```

**Verification:** `swift build && swift test` — all tests pass + new module tests.

---

## Phase 3: Widget System Completion

**Goal:** Make the View protocol actually render, handle events, and manage state.

### 3-pre: Fix QueryCursor range support

| File | Change |
|------|--------|
| `Sources/KittyQuery/QueryCursor.swift` | Extend to support both byte range AND point range (row/col) filtering, not just byte range |

### 3A: View rendering integration

| File | Change |
|------|--------|
| `Sources/KittyWidgets/View.swift` | Add `func render(to buffer: inout ScreenBuffer, in rect: Rect)` to View protocol with default implementation that calls `body.render(to:in:)` |
| `Sources/KittyWidgets/View.swift` | Add `struct Rect: Sendable { var x, y, width, height: Int }` |
| `Sources/KittyWidgets/Layout.swift` | Implement `render(to:in:)` on VStack (vertical subdivision), HStack (horizontal subdivision), ZStack (overlay) |
| `Sources/KittyWidgets/TextEditor.swift` | Implement `render(to:in:)` using KittyText buffer + syntax spans |
| `Sources/KittyWidgets/TreeView.swift` | Implement `render(to:in:)` using KittyFileTree flattened nodes |
| `Sources/KittyWidgets/StatusBar.swift` | Implement `render(to:in:)` writing styled spans into buffer row |

### 3B: State management

**New file:** `Sources/KittyWidgets/State.swift`

```swift
@propertyWrapper
public struct State<Value: Sendable>: Sendable {
    // TaskLocal-based render context for hydration
    // Mutation triggers invalidation flag on owning view
}
```

- Implement invalidation tracking: when `wrappedValue` mutates, flag dirty
- Add `@Binding` for parent-child state sharing
- Wire into `ApplicationRuntime` event loop: after event handling, if any state dirty, re-render

### 3C: Event handling on Views

| File | Change |
|------|--------|
| `Sources/KittyWidgets/View.swift` | Add `func handleEvent(_ event: InputEvent) -> EventResult` with default `.ignored` |
| `Sources/KittyWidgets/ViewModifier.swift` | Add `.onKeyPress(_:)` and `.onMouse(_:)` modifiers that wrap handler closures |
| `Sources/KittyWidgets/ViewModifier.swift` | Fix all existing modifiers (ForegroundModifier, etc.) to actually apply styles during render |
| New: `Sources/KittyWidgets/FocusEngine.swift` | Focus tree manager: Tab/Shift-Tab navigation, focused view receives events first |

### 3D: Fix ViewModifier no-ops

Current state: All modifiers return `content` unchanged. Fix by:
1. Add `RenderContext` that carries accumulated styles down the view tree
2. During `render(to:in:)`, pass context through modifiers
3. Leaf views (Text, StyledTextView) apply context styles when writing to buffer

**Tests to add:** Widget rendering tests (render to mock buffer, verify cell contents), state mutation + re-render tests, event dispatch tests.

**Verification:** `swift build && swift test` — widget tests actually verify rendered output.

---

## Phase 4: Syntax Pipeline Completion

**Goal:** Wire the real grammar-based highlighting pipeline and ship grammar files.

### 4A: Grammar file generation strategy

**Approach:** Use tree-sitter CLI to convert `grammar.js` → `grammar.json` for each language. Write `highlights.scm` query files (these are the standard tree-sitter highlight queries, widely available in tree-sitter repos).

**Priority languages (Phase 4A):** JSON, Swift, Python, JavaScript, TypeScript, Rust, Go, C
**Extended languages (Phase 4B):** HTML, CSS, Bash, Ruby, Java, Kotlin, Lua, TOML, YAML, Markdown, C++

**Files to create:**
```
Sources/KittySyntax/Grammars/
├── languages.json           # Update with paths
├── json/
│   ├── grammar.json         # From tree-sitter-json
│   └── highlights.scm       # Standard query
├── swift/
│   ├── grammar.json         # From tree-sitter-swift
│   └── highlights.scm
├── python/
│   ├── grammar.json
│   └── highlights.scm
└── ... (8 languages initially, 20 total)
```

**Build tooling:** Add `Scripts/generate-grammars.sh` that clones tree-sitter repos and extracts grammar.json + highlights.scm.

### 4B: Wire KittyCode to KittySyntax pipeline

| File | Change |
|------|--------|
| `Sources/KittyCode/Highlight.swift` | Replace `highlightSwift()` with call to `KittySyntax.Highlighter.highlight()` using parsed tree + query |
| `Sources/KittyCode/EditorStateCore.swift` | Add `var syntaxTree: SyntaxTree?` and `var grammarRegistry: GrammarRegistry` |
| `Sources/KittyCode/EditorStateFileSystem.swift` | On file open, detect language from extension via registry, parse file, store tree |
| `Sources/KittyCode/EditorStateCore.swift` | On edit, use `IncrementalParser` to update tree |

**Keep `highlightSwift()` as fallback** for when no grammar is available for a language.

### 4C: Complete IncrementalParser

| File | Change |
|------|--------|
| `Sources/KittyParser/IncrementalParser.swift` | Implement actual incremental behavior: apply TreeEdit to shift positions, identify reusable subtrees by comparing edit region against node ranges, re-parse only changed region |

**Tests to add:** Grammar loading integration tests, highlight output tests for each language, incremental re-parse correctness tests.

**Verification:** `swift build && swift test` — open a .swift file in KittyCode, see grammar-based highlighting.

---

## Phase 5: KittyCode Rewrite on Library Stack

**Goal:** Rewire KittyCode to use KittyWidgets View system + KittyText + KittyFileTree instead of direct RenderPipeline manipulation.

### 5-pre: Fix layer boundary drift (GPT-5.4 finding)

Higher layers bypass the intended convergence points. Fix direct lower-layer imports:

| File | Issue | Fix |
|------|-------|-----|
| `Sources/KittyApp/ApplicationRuntime.swift` | Imports KittyTerminal, KittyCodecs, KittyInput, KittyRenderer directly | Expose needed APIs through KittyWidgets re-exports; runtime should primarily interact through widget layer |
| `Sources/KittyApp/App.swift` | `run<A: App>(_:)` ignores `A.body` entirely — just calls `run(render: { _ in }, onEvent: ...)` | Wire `App.body` into widget render tree: instantiate body, call `render(to:in:)` on root view, dispatch events through view hierarchy |
| `Demo/main.swift` | Imports 5 lower layers directly | Rewrite to use View system exclusively (deferred to Phase 7C) |
| `Sources/KittyCode/*.swift` | 20 files import lower layers directly | Migrate to use KittyWidgets/KittyText/KittyFileTree abstractions |

### 5A: Define KittyCode as a View hierarchy

Replace the current free-function rendering with a View-based architecture:

```swift
struct EditorApp: View {
    @State var editorState: EditorModel

    var body: some View {
        HStack {
            TreeView(nodes: editorState.fileTree)
                .onKeyPress { handleTreeKey($0) }
            VStack {
                TextEditorView(buffer: editorState.textBuffer, highlights: editorState.highlights)
                    .onKeyPress { handleEditorKey($0) }
                StatusBar(message: editorState.statusMessage)
            }
        }
    }
}
```

### 5B: Refactor EditorState

| Current (monolithic) | New (composed) |
|----------------------|----------------|
| `EditorState.fileContent: [String]` | `KittyText.PieceTable` |
| `EditorState.cursorRow/Col` | `KittyText.TextCursor` |
| `EditorState.fileTree` | `KittyFileTree.FileNode` tree |
| `EditorState.colorScheme` | `KittySyntax.Theme` |
| `EditorState.scrollOffset` | Managed by `TextEditorView` widget |
| `highlightSwift()` | `KittySyntax.Highlighter` |

### 5C: Refactor event handling

Replace hardcoded keybindings in `EditorInput.swift` with a composable `KeyMap` system:

```swift
// New: Sources/KittyWidgets/KeyMap.swift
public struct KeyMap: Sendable {
    public var bindings: [(KeyEvent) -> EventResult?]
    public func handle(_ event: KeyEvent) -> EventResult { ... }
}
```

Extract Vim mode as a separate `KeyMap` configuration rather than inline switch statements.

### 5D: Cleanup

- Remove direct `pipeline.buffer[row, col] = Cell(...)` calls from KittyCode render files
- Delete `Render.swift`, `RenderEditor.swift`, `RenderTree.swift`, `RenderEmptyEditor.swift`, `RenderScrollableEditor.swift`, `RenderWrappedEditor.swift` — replaced by View `render(to:in:)` implementations
- Simplify `EventHandling.swift` to delegate to View event system
- Keep `Config.swift` but migrate to typed theme loading via KittySyntax

**Verification:** `swift build && swift test` — KittyCode runs identically through View system.

---

## Phase 6: Platform, Logging & CI

**Goal:** Production readiness.

### 6A: Linux support

| File | Change |
|------|--------|
| `Package.swift:7-9` | Remove platform restriction (SPM on Linux ignores `platforms:`) or add conditional |
| `Sources/KittyTerminal/POSIXTerminalConnection.swift` | Already has `#if canImport(Darwin/Glibc)` — verify all paths compile on Linux |
| `Sources/KittyApp/ApplicationRuntime.swift` | Replace any `import os` (Darwin-only Logger) with cross-platform logging abstraction |

**New:** `Sources/KittyTerminal/KittyLogger.swift` — cross-platform structured logging that uses `os.Logger` on Darwin and `stderr` on Linux.

### 6B: Structured logging

Replace all `print()`, `try?` silent failures, and `catch {}` with `KittyLogger` calls:
- `KittyLogger.error("Flush failed", error)`
- `KittyLogger.warning("Config parse failed, using defaults")`
- `KittyLogger.debug("Resize: \(newSize)")`

### 6C: Nice-to-have Kitty protocols

| Protocol | File | Implementation |
|----------|------|---------------|
| OSC 52 (Clipboard) | `Sources/KittyCodecs/ClipboardCodec.swift` | Encode/decode base64 clipboard operations |
| OSC 99 (Notifications) | `Sources/KittyCodecs/NotificationEncoder.swift` | Terminal notification builder |
| OSC 22 (Pointer Shapes) | `Sources/KittyCodecs/PointerShapeEncoder.swift` | Cursor shape escape sequences |

### 6D: CI/CD

**New:** `.github/workflows/ci.yml`
- Matrix: macOS-latest + ubuntu-latest
- Steps: `swift build`, `swift test`, `swift build -c release`

**Verification:** CI green on both platforms.

---

## Phase 7: Test Coverage & Documentation

**Goal:** Bring test coverage and docs to SOTA level.

### 7A: Test coverage expansion

**Priority targets (weakest coverage):**

| Module | Current | Target | Key additions |
|--------|---------|--------|---------------|
| KittyCode | 8 tests | 40+ | Editor workflows, file I/O errors, save/open, mouse, tree interaction |
| KittyApp | 2 tests | 15+ | Runtime lifecycle, error paths, quit, resize, signal handling |
| KittyWidgets | 10 tests | 30+ | View rendering, @State mutation, event dispatch, focus, layout math |
| KittySyntax | 9 tests | 20+ | Grammar resource loading, manifest errors, highlight output |
| KittyText (new) | 0 | 30+ | PieceTable CRUD, cursor math, word boundaries, selection |
| KittyFileTree (new) | 0 | 20+ | Scanner security, path validation, tree flatten, expand/collapse |

**Test quality improvements:**
- Adopt `makeSUT()` factory pattern across all suites
- Use parameterized tests (`@Test(arguments:)`) for boundary conditions
- Reduce `@testable import` — test public API surface where possible
- Add integration tests: file open → parse → highlight → render cycle

### 7B: Documentation

- Add `///` DocC comments to all public protocols, structs, enums, and error types
- Create `README.md` with architecture diagram, module descriptions, quick start
- Standardize naming: `bg` → `backgroundColor`, `treeBg` → `treeBackgroundColor` in Config
- Remove unused `import os` from `Sources/KittyParser/GLRParser.swift:2`

### 7C: Demo cleanup

- `Demo/main.swift`: Deduplicate rendering logic (lines 32-148 vs 151+)
- Rewrite Demo to use View system instead of direct RenderPipeline

**Verification:** `swift test` — 300+ tests passing. `swift build` clean with no warnings.

---

## Phase 8: Performance & Polish

**Goal:** SOTA performance characteristics.

### 8A: Performance optimizations

- **Viewport culling** in TextEditor: only render visible lines, skip off-screen content
- **Lazy grammar loading**: load grammar.json only when file of that language is first opened
- **Parse table caching**: serialize compiled ParseTable to disk, skip recompilation
- **Object pooling**: reuse Cell arrays in ScreenBuffer resize instead of reallocating
- **Wide character handling**: use UnicodeWidth in ScreenBuffer for proper 2-cell character rendering

### 8B: Final polish

- Complete IncrementalParser with real subtree reuse
- Add `ImageWidget` using GraphicsEncoder for inline images
- Add `OverlayWindow`/`Portal` for command palette, context menus
- Remove all TODO/FIXME comments or convert to tracked issues

---

## Evolved Module Dependency Graph

```
Layer 0:  KittyTerminal (POSIX, logging)
Layer 1:  KittyCodecs (SGR, keyboard, mouse, graphics, clipboard, notifications)
            ↓
Layer 2a: KittyInput (async events, signals)
Layer 2b: KittyRenderer (buffer, dirty, diff, pipeline)
            ↓
Layer 2c: KittyText (PieceTable, cursor, navigation, editing, unicode width)  [NEW]
            ↓
Layer 3a: KittyGrammar (grammar loader, LR tables)
Layer 3b: KittyParser (GLR, incremental, lexer)
Layer 3c: KittyQuery (query parser, matcher)
Layer 3d: KittySyntax (theme, registry, highlighter)
            ↓
Layer F:  KittyFileTree (scanner, navigator, secure path)  [NEW]
            ↓
Layer 4:  KittyWidgets (View, @State, ViewBuilder, layout, focus, keymap, event handling)
Layer 5:  KittyApp (App protocol, runtime, logger)
            ↓
          KittyCode (flagship editor)
          Demo (showcase)
```

## Verification Strategy

Each phase ends with:
1. `swift build` — clean compile, zero warnings
2. `swift test` — all tests pass (cumulative count grows per phase)
3. Manual smoke test — run KittyCode, open a file, navigate, verify no regressions

## Critical Files Reference

**Most-modified files across all phases:**
- `Package.swift` (Phases 2, 6)
- `Sources/KittyWidgets/View.swift` (Phase 3)
- `Sources/KittyWidgets/ViewModifier.swift` (Phase 3)
- `Sources/KittyApp/ApplicationRuntime.swift` (Phases 1, 6)
- `Sources/KittyCode/EditorStateCore.swift` (Phases 4, 5)
- `Sources/KittyCode/EditorStateFileSystem.swift` (Phases 1, 2)
- `Sources/KittyCode/Highlight.swift` (Phase 4)
- `Sources/KittyRenderer/RenderPipeline.swift` (Phase 1)
- `Sources/KittySyntax/GrammarRegistry.swift` (Phase 1)
