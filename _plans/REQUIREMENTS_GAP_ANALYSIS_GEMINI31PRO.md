# KittyTUI Architecture & Requirements Gap Analysis

## Executive Summary
The KittyTUI project plan is exceptionally well-structured, modular, and ambitious. The choice to build a pure-Swift, zero-dependency TUI framework leveraging Kitty's advanced protocols is innovative. The layer separation (Terminal -> Codecs -> Input/Renderer -> Widgets) and the parallelization strategy for the GLR Parser stack are excellent. 

However, building a from-scratch terminal toolkit and a full GLR parser involves hidden complexities. This report identifies architectural drift, missing components, and technical gaps that persist in the current requirements, specifically regarding cross-platform system calls, Unicode rendering, text editing data structures, and Swift 6 concurrency patterns.

---

## 1. Platform & POSIX Abstraction Gaps (Layer 0)

### The `TIOCGWINSZ` Portability Issue
**Gap:** The plan specifies: *"TIOCGWINSZ via manual hex constant 0x40087468 (not imported on macOS Darwin)"* and claims the package supports macOS 14+ and Linux. 
**Drift:** `0x40087468` is the `ioctl` request code for `TIOCGWINSZ` **only on macOS (Darwin)**. On Linux (x86_64, ARM64), `TIOCGWINSZ` is `0x5413`. Hardcoding the Darwin hex constant will immediately break Linux support.
**Recommendation:** Implement conditional compilation for platform-specific ioctl constants:
```swift
#if os(macOS)
let TIOCGWINSZ: UInt = 0x40087468
#elseif os(Linux)
let TIOCGWINSZ: UInt = 0x5413
#endif
```

## 2. Text, Unicode, and Rendering Over-simplifications (Layer 2b & 4)

### Grapheme Clusters vs. Terminal Cells
**Gap:** The plan defines `Cell.swift` as `Character + Style + width`. Terminals operate on a strict grid. Swift's `Character` represents an extended grapheme cluster, which can vary in display width.
**Drift:** Standard ASCII is 1 cell wide. Emojis and CJK (Chinese, Japanese, Korean) characters are 2 cells wide (East Asian Fullwidth). Some complex graphemes (like flag emojis or zero-width joiners) are rendered unpredictably. The plan is missing a robust `wcwidth` (terminal column width calculation) equivalent in pure Swift.
**Recommendation:** Add a `UnicodeWidth` module to calculate the visual cell width of Swift `Character`s. The renderer must pad 2-cell characters appropriately in the `ScreenBuffer` to prevent horizontal misalignment.

### Text Editor Data Structures
**Gap:** Layer 4 defines `TextEditor` as a "Scrollable syntax-highlighted text display" and Layer 3b discusses "Incremental parsing flow" via `tree.edit(TextEdit)`. However, there is no mention of the underlying data structure to hold the document text.
**Drift:** Relying on a standard `String` or `[String]` for a text editor will cause severe performance issues during edits (O(N) character insertions).
**Recommendation:** Introduce a proper text-buffer data structure, such as a **Rope** or a **Piece Table**, before building `TextEditor`. This is crucial for efficient O(log N) edits and seamless integration with the Incremental Parser.

## 3. UI, State, and Event Management (Layer 4 & 5)

### State Invalidation & Re-rendering
**Gap:** Layer 4 introduces `@State` with `TaskLocal` render context, and Layer 5 defines an event loop `for await event in inputSource.events`. 
**Drift:** How does a mutation in `@State` trigger a re-render? The plan lacks a clear **Invalidation Engine**. In SwiftUI, state mutations push invalidation signals to the runloop. Here, if an event mutates state, the framework needs a mechanism to dirty the view tree and schedule a layout/render pass.
**Recommendation:** Define a `ViewGraph` or `Environment` that tracks `@State` subscriptions. When state changes, flag the view as dirty. The main event loop should yield to a `RenderPipeline.flushIfDirty()` step.

### Focus Management & Overlays
**Gap:** Mentions "Three-tier dispatch: hot keys → focused widget → cold keys" but misses a structured way to navigate focus (e.g., Tab / Shift-Tab). Furthermore, there is no mention of global overlays (modals, dropdowns, tooltips).
**Drift:** `ZStack` handles local z-ordering, but a command palette or context menu needs to escape its parent's clipping/layout bounds.
**Recommendation:** 
1. Add a `FocusEngine` to manage a focus tree and handle directional/tab navigation.
2. Introduce an `OverlayWindow` or `Portal` system to render global floating elements outside the standard layout hierarchy.

## 4. Parser & Tree-sitter Complexities (Layer 3)

### Lexical Complexities & External Scanners
**Gap:** The plan aims to parse tree-sitter `grammar.json` and states: *"Zero external dependencies... 165+ existing tree-sitter grammars can be used"*.
**Drift:** Many popular tree-sitter grammars (e.g., HTML, Markdown, Python, C) rely heavily on a `scanner.c` file—a custom C implementation to handle context-sensitive tokenization (like Python's significant indentation or Markdown's complex block rules). 
**Risk:** While Layer 3b mentions an `ExternalScanner` protocol (Swift closures), you cannot automatically translate the existing C external scanners from the 165+ languages into Swift. You will only be able to automatically support languages that *do not* use an external scanner (e.g., JSON), unless you manually rewrite their custom scanners in Swift.
**Recommendation:** Explicitly document which grammars are supported out-of-the-box (those without `scanner.c`). Create a plan to manually port essential external scanners (like Swift or Python) to the `ExternalScanner` protocol.

## 5. Kitty Protocol Coverage

**Gap:** The plan mentions the Graphics Protocol (Images) as a "Must-have", but no Layer 4 widget is designed to display images.
**Drift:** Image rendering in Kitty requires chunking base64 payloads and managing image IDs to avoid redundant memory usage in the terminal. If the screen scrolls or a view is re-rendered, image placements must be meticulously re-drawn or cleared.
**Recommendation:** Introduce an `ImageWidget` in Layer 4 that integrates with Layer 1's `GraphicsEncoder`. Add an `ImageManager` in the App layer to track terminal-side image allocations and evictions.

## 6. Development Workflow Risks (Codex Delegation)

**Risk:** The plan delegates highly algorithmic tasks (Layer 3: GLR Parse Table compilation, Lexical DFA construction) to Codex (`gpt-5.4`). 
**Drift:** Building a production-grade GLR parser that perfectly matches tree-sitter's semantics (handling dynamic precedence, GLR state merging, and error recovery) from pure LLM prompting is extremely high-risk. Tree-sitter's conflict resolution logic is highly nuanced.
**Recommendation:** Assign Claude Code to heavily pair-program and verify Layers 3a-3b. Do not rely fully on automated Codex merges for the core parser engine, as hidden semantic bugs in table generation will cause cascading failures in syntax highlighting.

---

## Summary of Action Items Before Implementation
1. Add `UnicodeWidth` module to calculate grapheme cluster sizes.
2. Abstract POSIX constants (`TIOCGWINSZ`) for macOS vs. Linux.
3. Define a proper text data structure (Rope/Piece Table) for `TextEditor`.
4. Define the View Invalidation/Re-render trigger loop.
5. Add a Focus Tree manager and an Overlay rendering system.
6. Acknowledge and plan for the manual porting of C-based `external_scanners` for target languages.