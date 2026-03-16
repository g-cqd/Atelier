# Future ADR: Split Screen Architecture and Layout Stability

Status: Proposed
Date: 2026-03-13

## Goal

Enable split screen editing (vertical and horizontal) with independent editor panes, each with its own tab ribbon, and fix layout instability caused by conditional tab ribbon rendering.

Split screen is a foundational code editor capability. Without it, users must switch tabs to compare files, reference API signatures, or work on related code side by side. The current architecture assumes a single editor region with a single active buffer, making this impossible.

The layout stability fix addresses a visible UI jump that occurs when the first buffer is opened or the last buffer is closed. This is a one-line fix that should ship immediately, independent of the split screen work.

## Scope

This ADR covers:

- split pane model and data structures
- per-pane tab ribbons and buffer management
- layout computation for split configurations
- pane focus management and routing
- separator rendering and resize interaction
- layout stability fix for tab ribbon conditional rendering
- SOTA comparison with other editors

This ADR does not cover:

- floating or detached panes
- multi-window support
- minimap rendering (deferred to a future ADR)
- diff view integration (builds on splits but is a separate feature)
- session persistence format (referenced but not fully specified)

## Current Codebase Findings

### EditorState is a singleton god object with one active buffer

`Sources/KittyCode/EditorStateCore.swift` is the central state object for the entire application. It owns:

- `bufferManager: BufferManager` with a single `activeIndex` (EditorStateCore.swift:197)
- `textBuffer`, `textCursor`, `scrollOffset`, `hScrollOffset`, `selection` forwarded from `WorkspaceSession`
- `wrapCache`, `highlightedLines`, `highlightSession` as single-buffer concerns
- `mode: Mode` as a flat `.tree`/`.editor` enum (EditorStateCore.swift:114-117)
- `tabScrollOffset` as a single global tab ribbon scroll state (EditorStateCore.swift:187)

This is the fundamental blocker for split screen. Every piece of per-editor state is singular and global.

### BufferManager assumes one active view

`Sources/KittyWorkspace/BufferManager.swift` maintains a flat `buffers: [DocumentBuffer]` array with a single `activeIndex: Int` (BufferManager.swift:11). Methods like `nextTab()`, `prevTab()`, and `switchTo(index:)` all operate on this single index.

The buffer manager can hold multiple open buffers, but only one can be "active" at a time. There is no concept of multiple simultaneous active views into different (or the same) buffers.

### LayoutMetrics computes a single editor region

`Sources/KittyCode/LayoutMetrics.swift` computes layout for exactly one editor area:

- `editorStart`: the column where the single editor begins
- `editorWidth`: the width of the single editor
- `contentStartRow`: the row where content begins (after tab ribbon)
- `contentRows`: the number of rows for the single editor

There is no concept of dividing the editor region into sub-regions.

### Render.swift renders exactly one editor area

`Sources/KittyCode/Render.swift` orchestrates rendering as a fixed pipeline:

1. Tab ribbon (lines 27-52) renders one `TabRibbon` for the global `bufferManager`
2. Activity bar (lines 54-62) renders once
3. Sidebar panel (lines 64-93) renders once
4. Editor (lines 95-104) calls `renderEditorPanel()` once
5. Status bar (lines 106-115) renders once
6. Overlay (lines 117-123) renders once

The tab ribbon uses `state.bufferManager.activeIndex` and `state.tabScrollOffset` as globals. There is no loop over panes or recursive layout.

### RenderEditor.swift renders one TextEditor

`Sources/KittyCode/RenderEditor.swift` constructs a single `TextEditor` widget (lines 45-73) from the global `state.textBuffer`, `state.scrollOffset`, `state.cursorRow`, `state.cursorCol`, and `state.selection`. It renders into a single `Rect`.

### Tab ribbon state and selection are global, not per-pane

`EditorState.tabScrollOffset` (EditorStateCore.swift:187) is a single integer. `tabRibbonTabs()` (EditorStateCore.swift:648-662) builds tabs from `bufferManager.buffers`, which is a single flat list. The tab ribbon active index comes from `bufferManager.activeIndex`.

In a split screen model, each pane needs its own tab list, active tab, and scroll offset.

### The layout jump bug in LayoutMetrics.swift

The `showTabRibbon` computation at LayoutMetrics.swift:31-32:

```swift
self.showTabRibbon =
    state.config.tabRibbon.position == .top && state.bufferManager.count > 0
```

This condition means:

- When `bufferManager.count` transitions from 0 to 1 (first buffer opened), `showTabRibbon` flips from `false` to `true`, causing `contentStartRow` to shift from 0 to 1 and `contentRows` to shrink by 1. The editor content visibly jumps down.
- When `bufferManager.count` transitions from 1 to 0 (last buffer closed), the reverse happens. The welcome screen or empty editor jumps up.

This is a visible layout instability that occurs during normal editor usage.

## Gaps and Missing Features

### 1. No concept of editor groups or panes

There is no data structure representing a pane, an editor group, or any unit of editing context smaller than the entire `EditorState`. Every piece of editor view state (cursor, scroll, selection, wrap cache, highlights) is singular.

### 2. No split layout tree

There is no recursive or hierarchical layout structure. `LayoutMetrics` computes a fixed three-column layout (activity bar + sidebar + editor) with no ability to subdivide the editor region.

### 3. No per-pane focus tracking

`EditorState.Mode` is `.tree` or `.editor` with no granularity. There is no way to express "the left pane has focus" or "the right pane's tab ribbon has focus." The keybinding ADR's focus context proposal addresses this at the command level, but pane-level focus is an additional dimension.

### 4. No separator or divider widget

There is no widget for rendering an interactive divider between panes. The current sidebar separator (Render.swift:87-93) is a hardcoded vertical line drawn with a loop, not a reusable, interactive component.

### 5. No resize interaction model

There is no mouse interaction for dragging a split boundary. The sidebar width (`treePanelWidth`) is config-driven, not drag-adjustable. Split pane ratios need both config defaults and runtime drag interaction.

### 6. Layout instability on tab ribbon show/hide

As described in the findings, the conditional tab ribbon rendering creates a visible content shift. This affects both the current single-pane editor and any future split screen implementation.

## Already Developed But Unwired

### FocusEngine could serve as per-pane focus tracking

`Sources/KittyWidgets/FocusEngine.swift` is a minimal index-based ring buffer (FocusEngine.swift:5-28) with `focusNext()`, `focusPrevious()`, and `isFocused(_:)`. It tracks a single `focusedIndex` within `focusableCount`. While it needs significant extension (typed identifiers, hierarchical scoping), it is a starting point for pane focus cycling.

### TextEditor is already a self-contained widget

`Sources/KittyWidgets/TextEditor.swift` is a fully self-contained rendering widget. It takes all its state as constructor parameters: `buffer`, `scrollOffset`, `cursorRow`, `cursorCol`, `selectionRanges`, etc. It renders into an arbitrary `Rect`. This means it can already be instantiated multiple times with different state, rendering into different screen regions. The widget itself is not the blocker -- the blocker is the state management above it.

### TabRibbon widget is already a standalone component

`Sources/KittyWidgets/TabRibbon.swift` is a standalone rendering component with no global dependencies. It takes `tabs: [Tab]`, `activeIndex: Int`, `scrollOffset: Int`, and a style, then renders into an arbitrary `Rect`. It also provides `tabIndex(atColumn:ribbonX:ribbonWidth:)` for hit testing. This widget is ready for per-pane instantiation.

### ProposedSize/View.size(proposed:) layout protocol exists

`Sources/KittyWidgets/View.swift` defines `ProposedSize` (View.swift:21-29) and `View.size(proposed:)` (View.swift:48-50). While the measurement API is nominal (returning the proposed size as-is), the vocabulary exists. A real constraint-based layout engine can build on these types as described in the terminal UI framework ADR.

### RenderPipeline supports double-buffered diff rendering

`Sources/KittyRenderer/RenderPipeline.swift` implements double-buffered rendering with cell-level diffing. This means multiple panes rendering into different screen regions will naturally benefit from diff-based output -- only changed cells are emitted. No architectural change to the renderer is needed for split support.

## Decision

### 1. Introduce a SplitNode recursive enum for layout structure

The split layout should be modeled as a recursive binary tree:

```swift
enum SplitNode {
    case leaf(EditorGroup)
    case horizontal(left: SplitNode, right: SplitNode, ratio: Double)
    case vertical(top: SplitNode, bottom: SplitNode, ratio: Double)
}
```

This is the same model used by VS Code, tmux, WezTerm, and every major editor or terminal multiplexer that supports splits. A binary tree is simpler than an N-way grid and composes naturally. Any grid layout can be expressed as nested binary splits.

The `ratio` (0.0 to 1.0) determines how space is divided between the two children. A ratio of 0.5 means equal division. The ratio is the drag target for resize interaction.

### 2. Introduce an EditorGroup as the per-pane state container

Each leaf in the split tree owns an `EditorGroup`:

```swift
struct EditorGroup {
    let id: EditorGroupID
    var bufferRefs: [BufferRef]
    var activeBufferIndex: Int?
    var scrollState: ScrollState
    var cursorState: CursorState
    var selectionState: SelectionState
    var tabScrollOffset: Int
    var wrapCache: EditorState.WrapCache
    var highlightedLines: [[StyledSpan]]
    var highlightSession: LanguageHighlighter.Session?
}
```

Each `EditorGroup` owns its own:

- tab list (`bufferRefs`) -- which buffers are open in this pane
- active tab selection (`activeBufferIndex`)
- scroll position (`scrollState`)
- cursor position (`cursorState`)
- selection state (`selectionState`)
- tab ribbon scroll offset (`tabScrollOffset`)
- line wrap cache (`wrapCache`)
- syntax highlighting state (`highlightedLines`, `highlightSession`)

### 3. Share buffer content, isolate view state

`TextBuffer` content is shared across panes. If two panes show the same file, they share the same `DocumentBuffer` and `TextBuffer`. But each pane has its own cursor, scroll position, selection, and wrap cache.

This is the standard model used by VS Code, Zed, and Neovim. Edits in one pane appear immediately in all panes showing the same buffer, but scroll position and cursor are independent.

`BufferRef` is a lightweight reference to a `DocumentBuffer` in the shared `BufferManager`:

```swift
struct BufferRef: Identifiable {
    let id: UUID
    let bufferPath: String
}
```

The actual `DocumentBuffer` lives in the shared `BufferManager`, which becomes a content store rather than a view model.

### 4. Fix layout stability immediately

Change LayoutMetrics.swift:31-32 from:

```swift
self.showTabRibbon =
    state.config.tabRibbon.position == .top && state.bufferManager.count > 0
```

to:

```swift
self.showTabRibbon =
    state.config.tabRibbon.position == .top
```

This always reserves the tab ribbon row when the user has configured it for the top position. When no buffers are open, an empty tab ribbon row is rendered instead of collapsing the space. The tab ribbon widget's `render()` already handles empty tabs gracefully (the `guard !tabs.isEmpty` at TabRibbon.swift:68 skips tab rendering but the background fill still applies).

This is a one-line fix with zero risk that eliminates a visible layout jump.

## Proposed Architecture

### SplitNode tree with recursive layout computation

The split layout tree is the core data structure:

```swift
typealias EditorGroupID = UUID

enum SplitNode {
    case leaf(EditorGroup)
    case horizontal(left: SplitNode, right: SplitNode, ratio: Double)
    case vertical(top: SplitNode, bottom: SplitNode, ratio: Double)
}
```

Layout computation is recursive. Given an available `Rect`, each node:

- **leaf**: the entire rect is assigned to the `EditorGroup`
- **horizontal**: split the rect into left and right by `ratio * rect.width`, with a 1-column separator between them
- **vertical**: split the rect into top and bottom by `ratio * rect.height`, with a 1-row separator between them

```swift
struct PaneLayout {
    let groupID: EditorGroupID
    let editorRect: Rect
    let tabRibbonRect: Rect?
}

func computeLayouts(node: SplitNode, available: Rect, showTabRibbon: Bool) -> [PaneLayout] {
    switch node {
    case .leaf(let group):
        let tabRows = showTabRibbon ? 1 : 0
        let tabRect = showTabRibbon
            ? Rect(x: available.x, y: available.y, width: available.width, height: 1)
            : nil
        let editorRect = Rect(
            x: available.x,
            y: available.y + tabRows,
            width: available.width,
            height: max(0, available.height - tabRows)
        )
        return [PaneLayout(groupID: group.id, editorRect: editorRect, tabRibbonRect: tabRect)]

    case .horizontal(let left, let right, let ratio):
        let leftWidth = max(1, Int(Double(available.width - 1) * ratio))
        let rightWidth = max(1, available.width - 1 - leftWidth)
        let leftRect = Rect(x: available.x, y: available.y,
                           width: leftWidth, height: available.height)
        let rightRect = Rect(x: available.x + leftWidth + 1, y: available.y,
                            width: rightWidth, height: available.height)
        return computeLayouts(node: left, available: leftRect, showTabRibbon: showTabRibbon)
             + computeLayouts(node: right, available: rightRect, showTabRibbon: showTabRibbon)

    case .vertical(let top, let bottom, let ratio):
        let topHeight = max(1, Int(Double(available.height - 1) * ratio))
        let bottomHeight = max(1, available.height - 1 - topHeight)
        let topRect = Rect(x: available.x, y: available.y,
                          width: available.width, height: topHeight)
        let bottomRect = Rect(x: available.x, y: available.y + topHeight + 1,
                             width: available.width, height: bottomHeight)
        return computeLayouts(node: top, available: topRect, showTabRibbon: showTabRibbon)
             + computeLayouts(node: bottom, available: bottomRect, showTabRibbon: showTabRibbon)
    }
}
```

### EditorGroup with independent state

Each `EditorGroup` is a complete editing context:

```swift
struct EditorGroupID: Hashable, Sendable {
    let uuid: UUID
    init() { self.uuid = UUID() }
}

struct ScrollState: Sendable {
    var scrollRow: Int = 0
    var scrollCol: Int = 0
    var wrapRowOffset: Int = 0
}

struct CursorState: Sendable {
    var row: Int = 0
    var col: Int = 0
}

struct SelectionState: Sendable {
    var selection: TextSelection?
}

struct EditorGroup: Identifiable {
    let id: EditorGroupID
    var bufferRefs: [BufferRef]
    var activeBufferIndex: Int?
    var scrollState: ScrollState
    var cursorState: CursorState
    var selectionState: SelectionState
    var tabScrollOffset: Int = 0
    var wrapCache: EditorState.WrapCache = .init()
    var highlightedLines: [[StyledSpan]] = []
    var highlightSession: LanguageHighlighter.Session?

    var activeBufferRef: BufferRef? {
        guard let index = activeBufferIndex,
              index >= 0, index < bufferRefs.count
        else { return nil }
        return bufferRefs[index]
    }

    var isEmpty: Bool { bufferRefs.isEmpty }
}
```

### PaneLayout computation from SplitNode tree

The `LayoutMetrics` struct should evolve to support splits:

```swift
struct SplitLayoutMetrics {
    let activityBarWidth: Int
    let sidebarWidth: Int
    let totalSidebarWidth: Int
    let editorRegion: Rect
    let paneLayouts: [PaneLayout]
    let separators: [SeparatorLayout]
    let showTabRibbons: Bool

    struct SeparatorLayout {
        let rect: Rect
        let orientation: SplitOrientation
        let parentNode: SplitNodePath
    }
}
```

The existing `LayoutMetrics` computation for activity bar and sidebar remains unchanged. The editor region (`editorStart`, `editorWidth`, `contentStartRow`, `contentRows`) becomes the input `Rect` for the recursive `computeLayouts()` call.

### FocusEngine promotion for pane focus routing

The current `FocusEngine` needs extension to support pane-level focus:

```swift
enum PaneFocus {
    case tree
    case sidebarPanel(SidebarPanel)
    case editorGroup(EditorGroupID)
    case overlay
}
```

Pane focus determines:

- which pane's cursor is visible
- which pane receives keyboard input
- which pane's tab ribbon shows active styling
- which pane's status is shown in the status bar

Focus cycling between panes should use directional navigation:

- `Ctrl+W h/j/k/l` or `Cmd+Alt+Arrow` to move focus between panes
- `Ctrl+W w` or `Cmd+Alt+W` to cycle focus to the next pane

This aligns with Neovim's `<C-w>` window navigation.

### Separator widget with drag-to-resize

A new `SplitSeparator` widget:

```swift
struct SplitSeparator {
    let orientation: SplitOrientation
    let style: Style

    func render(to buffer: inout ScreenBuffer, in rect: Rect) {
        switch orientation {
        case .horizontal:
            for row in 0..<rect.height {
                buffer[rect.y + row, rect.x] = Cell(
                    character: "\u{2502}", style: style)
            }
        case .vertical:
            for col in 0..<rect.width {
                buffer[rect.y, rect.x + col] = Cell(
                    character: "\u{2500}", style: style)
            }
        }
    }
}
```

Mouse interaction for drag-to-resize:

1. On mouse down within a separator's `Rect`, enter resize drag mode.
2. Track mouse movement and update the corresponding `SplitNode`'s `ratio`.
3. Enforce minimum pane dimensions (e.g., 10 columns wide, 3 rows tall) to prevent degenerate layouts.
4. On mouse up, finalize the ratio and re-render.

### Per-pane tab ribbon rendering

The render loop changes from rendering one tab ribbon to rendering one per pane:

```swift
for layout in paneLayouts {
    if let tabRect = layout.tabRibbonRect {
        let group = splitTree.group(for: layout.groupID)
        let tabs = group.tabRibbonTabs(bufferManager: bufferManager, config: config)
        let ribbon = TabRibbon(
            tabs: tabs,
            activeIndex: group.activeBufferIndex ?? -1,
            scrollOffset: group.tabScrollOffset,
            style: tabStyle
        )
        ribbon.render(to: &pipeline.buffer, in: tabRect)
    }
}
```

Each pane's tab ribbon shows only the buffers open in that pane, with its own scroll offset and active selection.

### Buffer sharing model

`BufferManager` remains the canonical store for all open `DocumentBuffer` objects. It continues to manage file I/O, dirty state, preview buffers, and edit history.

`EditorGroup.bufferRefs` holds lightweight references to buffers in the manager. Multiple groups can reference the same buffer path. The buffer manager should evolve to support reference counting:

```swift
extension BufferManager {
    func retainCount(forPath path: String) -> Int {
        // Count how many EditorGroups reference this buffer
    }

    func closeIfUnreferenced(path: String) {
        // Only remove from buffers array if no EditorGroup references it
    }
}
```

When a buffer is modified in one pane:

1. The `DocumentBuffer.textBuffer` is updated in place.
2. An invalidation notification is broadcast to all `EditorGroup` instances referencing that buffer.
3. Each group invalidates its `wrapCache` and `highlightedLines`.
4. The render loop re-renders all visible panes.

### Command routing to focused pane

With the command-based keybinding system proposed in the keybinding ADR, split commands integrate naturally:

- `split.verticalNew`: split the focused pane vertically
- `split.horizontalNew`: split the focused pane horizontally
- `split.close`: close the focused pane (merge its space into the sibling)
- `split.focusLeft`, `split.focusRight`, `split.focusUp`, `split.focusDown`: directional focus navigation
- `split.moveLeft`, `split.moveRight`, `split.moveUp`, `split.moveDown`: move the focused pane
- `split.resizeGrow`, `split.resizeShrink`: adjust the split ratio

All editing commands (save, undo, redo, cursor movement, selection, clipboard) are routed to the focused `EditorGroup`. The command dispatcher determines the focused pane from `PaneFocus` and forwards to the appropriate group's state.

## Layout Stability Fix

### The specific one-line fix

In `Sources/KittyCode/LayoutMetrics.swift`, line 31-32, change:

```swift
self.showTabRibbon =
    state.config.tabRibbon.position == .top && state.bufferManager.count > 0
```

to:

```swift
self.showTabRibbon =
    state.config.tabRibbon.position == .top
```

### Why this works

- The `TabRibbon.render()` method at TabRibbon.swift:68 already has a `guard !tabs.isEmpty` that skips tab content rendering when there are no tabs. The background fill still applies, producing a clean empty row.
- Render.swift:27 checks `if showTabRibbon` before rendering. With this fix, the tab ribbon row is always present when configured, so the background fill runs even with zero buffers. The `TabRibbon` widget handles the empty state gracefully.
- `contentStartRow` and `contentRows` remain stable regardless of buffer count changes, eliminating the layout jump.

### Why this is safe

- When `tabRibbon.position != .top`, the behavior is unchanged (showTabRibbon is false).
- When `tabRibbon.position == .top` and buffers are open, the behavior is unchanged.
- The only change is when `tabRibbon.position == .top` and zero buffers are open: the tab ribbon row is now shown as an empty styled row instead of being hidden. This is visually correct -- VS Code, Zed, and other editors always show the tab bar even when empty.

### This fix should ship immediately

This is a Phase 0 fix that is independent of the split screen architecture. It can be shipped as a single-commit bugfix.

## SOTA Comparison

### VS Code: EditorGroup model with grid layout

VS Code pioneered the `EditorGroup` model for split panes in terminal-era editors:

- **EditorGroup**: Each group has its own tab list, active editor, and scroll position. Groups are arranged in a grid layout that supports both horizontal and vertical splits.
- **Grid layout**: VS Code uses a 2D grid system, not a binary tree. Groups can be resized by dragging borders. The grid supports complex layouts like 2x2 or L-shaped arrangements.
- **Side-by-side diff**: Built on the split model. Diff view opens two synchronized editors in a horizontal split.
- **Minimap per pane**: Each editor pane has its own minimap showing the full document structure.
- **EditorService**: A central service manages which group is active and routes commands. Groups can be created by drag-and-drop, keyboard shortcuts, or the command palette.
- **Tab overflow**: Tabs wrap or scroll per group, not globally.
- **Lock groups**: Groups can be locked to prevent tabs from being opened or moved.

VS Code's grid model is more flexible than a binary tree but also more complex. For KittyCode, a binary tree is sufficient for v1 and can be extended to a grid later if needed.

### Neovim: Window splits with window-local options

Neovim's split model is deeply integrated into its architecture:

- **Windows**: Neovim has buffers, windows, and tabs as distinct concepts. A window is a view into a buffer. Multiple windows can show the same buffer with independent cursor/scroll.
- **`vsplit`/`hsplit`**: Vim commands `<C-w>v` and `<C-w>s` create vertical and horizontal splits. `<C-w>` prefix keys provide comprehensive window management.
- **Window-local options**: Options like `scrolloff`, `wrap`, `number`, `signcolumn` can be set per-window. This is exactly the per-pane state isolation KittyCode needs.
- **Floating windows**: Neovim supports floating windows with z-ordering, used for completion popups, hover documentation, and UI plugins.
- **`wincmd`**: A rich command vocabulary for window management: resize, rotate, equalize, close, move to tab, exchange.
- **Autocmds**: `WinEnter`, `WinLeave`, `BufWinEnter`, `BufWinLeave` events let plugins react to window focus changes.

Neovim's window model is the most mature among terminal editors. The binary tree layout and `<C-w>` navigation should be KittyCode's primary reference.

### Helix: No splits by design

Helix deliberately omits splits:

- **Picker-based navigation**: Instead of splits, Helix uses fuzzy pickers for file switching, symbol navigation, and buffer management. The design philosophy is that splits add complexity without proportional benefit in a terminal context.
- **Multiple buffers, one view**: Helix supports multiple open buffers but always shows one at a time. Buffer switching is via picker or `:bn`/`:bp`.
- **Trade-off**: This is simpler but prevents side-by-side comparison, which is a common workflow for code review, API reference, and test-implementation pairing.

KittyCode should support splits. The Helix approach is valid for a different product philosophy, but KittyCode aims to be a VS Code-class editor in the terminal.

### Zed: Splits with shared and independent scroll

Zed's split model is modern and opinionated:

- **Split or no split**: Zed supports horizontal and vertical splits but keeps the model simple. No complex grid layouts.
- **Shared buffer, independent views**: Like VS Code, edits propagate across splits showing the same file, but cursor and scroll are per-split.
- **Synchronized scrolling**: Zed supports synchronized scroll for diff views where two panes scroll in lockstep.
- **Multi-buffer views**: Zed has a unique "multibuffer" view that shows excerpts from multiple files in a single scrollable pane. Search results, diagnostics, and references use this view.
- **GPU rendering**: Zed's splits benefit from GPU-accelerated rendering where each pane can render independently without blocking others.

The synchronized scrolling and multi-buffer view are future features for KittyCode, but the basic split model aligns closely.

### tmux and WezTerm: Terminal multiplexer split model

Terminal multiplexers use recursive binary splits:

- **tmux**: Panes are arranged in a binary tree within a window. `split-window -h` and `split-window -v` create horizontal and vertical splits. Pane borders are rendered as box-drawing characters. Panes can be resized, swapped, and zoomed (temporarily full-screen). tmux's pane model is the direct ancestor of most terminal split implementations.
- **WezTerm**: Uses a similar binary tree model with configurable split ratios. Supports both fixed-pixel and proportional sizing. WezTerm renders pane borders with configurable styles and colors.
- **Relevance**: These are the closest analogs to KittyCode's rendering context. Box-drawing character separators, character-cell-aligned boundaries, and proportional ratios are the standard for terminal splits.

## Recommended Technical Approach

### 1. Recursive constraint-based layout for split trees

Implement layout as a recursive descent over the `SplitNode` tree. Each node receives an available `Rect` and distributes space to its children. The layout algorithm should:

- Enforce minimum pane dimensions (configurable, default 10 columns x 3 rows) to prevent degenerate splits.
- Account for separator overhead (1 character) in space distribution.
- Round pixel allocation deterministically (left/top child gets the extra character on odd divisions) to avoid 1-character jitter on resize.
- Cache layout results keyed by `(node structure hash, available rect)` to skip recomputation when only pane content changes.

### 2. Independent pane rendering into screen buffer regions

Each pane should render independently into its assigned screen buffer region. This is naturally supported by the existing `TextEditor.render(to:in:)` and `TabRibbon.render(to:in:)` APIs, which already take arbitrary `Rect` parameters.

The render loop becomes:

```swift
for layout in paneLayouts {
    renderTabRibbon(for: layout, pipeline: pipeline, state: state)
    renderEditor(for: layout, pipeline: pipeline, state: state)
}
renderSeparators(separators: separators, pipeline: pipeline, state: state)
```

Because `RenderPipeline` uses double-buffered diff rendering, only changed cells are emitted. A keystroke in one pane does not cause the other pane's cells to be re-emitted. This gives near-zero overhead for inactive panes.

### 3. Shared buffer with copy-on-write view state

`DocumentBuffer` holds the shared content: `textBuffer`, `editHistory`, `isDirty`, `filePath`. View state (`ScrollState`, `CursorState`, `SelectionState`, `WrapCache`, `highlightedLines`) is per-`EditorGroup`.

When a buffer is modified:

1. The `DocumentBuffer.textBuffer` is mutated.
2. An invalidation notification is broadcast to all `EditorGroup` instances referencing that buffer.
3. Each group invalidates its `wrapCache` and `highlightedLines`.
4. The render loop re-renders all affected panes.

Swift's value semantics and copy-on-write for `TextBuffer` (array of strings) make this safe. The actual string data is shared until mutation occurs.

### 4. Synchronized scrolling mode for diff views

As a future extension, two panes showing related files (or the same file) can be linked for synchronized scrolling:

```swift
struct ScrollLink {
    let paneA: EditorGroupID
    let paneB: EditorGroupID
    let mode: ScrollLinkMode  // .lockstep, .proportional
}
```

In lockstep mode, scrolling pane A scrolls pane B by the same number of lines. In proportional mode, scrolling pane A scrolls pane B proportionally (useful for files of different lengths in diff view).

This requires the scroll handler to check for active scroll links and propagate scroll changes. It builds naturally on the per-pane scroll state model.

### 5. Floating and detached panes for future

The `SplitNode` tree can be extended with a `.floating(EditorGroup, frame: Rect)` case for overlay panes:

```swift
enum SplitNode {
    case leaf(EditorGroup)
    case horizontal(left: SplitNode, right: SplitNode, ratio: Double)
    case vertical(top: SplitNode, bottom: SplitNode, ratio: Double)
    case floating(EditorGroup, frame: Rect)  // future
}
```

Floating panes render with z-ordering above the split tree, similar to the current overlay system. This supports future features like floating terminals, documentation popups, or detached editor views.

### 6. Split persistence in session state

The split tree structure and pane contents should be serializable for session persistence:

```swift
struct SplitSessionState: Codable {
    enum NodeState: Codable {
        case leaf(EditorGroupState)
        case horizontal(left: NodeState, right: NodeState, ratio: Double)
        case vertical(top: NodeState, bottom: NodeState, ratio: Double)
    }

    struct EditorGroupState: Codable {
        let bufferPaths: [String]
        let activeBufferIndex: Int?
        let scrollRow: Int
        let cursorRow: Int
        let cursorCol: Int
    }

    let rootNode: NodeState
    let focusedGroupID: String
}
```

This integrates with the broader session persistence story. On editor restart, the split layout and open files can be restored.

## Implementation Plan

### Phase 0: Layout stability fix (immediate)

- Change `state.config.tabRibbon.position == .top && state.bufferManager.count > 0` to `state.config.tabRibbon.position == .top` in LayoutMetrics.swift.
- Update Render.swift to render the tab ribbon background even when no tabs exist (the TabRibbon widget already handles this).
- Add a test verifying `contentStartRow` and `contentRows` are stable when `tabRibbon.position == .top` regardless of buffer count.

This is a one-commit fix.

### Phase 1: EditorGroup and SplitNode data model

- Define `EditorGroupID`, `BufferRef`, `EditorGroup`, `SplitNode`.
- Extract per-editor view state from `EditorState` into `EditorGroup`: scroll, cursor, selection, wrap cache, highlights.
- Create a `SplitTreeManager` that owns the root `SplitNode` and provides methods for traversal, group lookup, and mutation.
- Wire `EditorState` to use a single-leaf `SplitNode` by default, maintaining backward compatibility.
- Ensure all existing tests pass with the new data model.

### Phase 2: Layout computation for splits

- Implement recursive `computeLayouts()` from `SplitNode` and available `Rect`.
- Extend `LayoutMetrics` (or introduce `SplitLayoutMetrics`) to support per-pane rects.
- Implement separator layout computation.
- Add unit tests for layout computation with various split configurations.

### Phase 3: Per-pane rendering

- Modify `render()` in Render.swift to iterate over `paneLayouts` instead of rendering a single editor.
- Render per-pane tab ribbons using each pane's `EditorGroup` state.
- Render per-pane editors using each pane's cursor, scroll, and selection.
- Render separators between panes.
- Add the focused-pane indicator (e.g., tab ribbon highlight or border color).

### Phase 4: Pane focus and input routing

- Introduce `PaneFocus` to track which pane has focus.
- Route keyboard input to the focused pane's `EditorGroup`.
- Implement directional focus navigation between panes.
- Update status bar to show the focused pane's context.
- Wire mouse clicks within a pane's rect to set pane focus.

### Phase 5: Split commands and interaction

- Add split/close/resize commands to the command system.
- Implement mouse drag-to-resize for separators.
- Implement keyboard resize (grow/shrink focused pane).
- Add keybinding defaults for nano, vim, and kittycode modes.
- Handle edge cases: closing the last pane in a split, closing all panes, opening a file in a specific pane.

### Phase 6: Buffer sharing and cross-pane updates

- Implement buffer change notification across panes.
- Handle cursor/selection invalidation when a shared buffer is modified from another pane.
- Implement "open in split" from the file tree and tab ribbon.
- Handle buffer close with reference counting (only remove from `BufferManager` when no pane references it).

### Phase 7: Polish and edge cases

- Handle terminal resize with split layouts (proportional re-layout).
- Handle minimum pane dimension enforcement during resize.
- Add split layout to session persistence.
- Add drag-and-drop for moving tabs between panes.
- Performance optimization: skip rendering for panes that have not changed.

## Testing Recommendations

### Unit tests

- `SplitNode` layout computation with known inputs and expected `Rect` outputs.
- `EditorGroup` state isolation: modifying one group does not affect another.
- Buffer sharing: two groups referencing the same buffer see the same content.
- `SplitTreeManager` operations: split, close, find group, traverse.
- Separator layout computation.
- Minimum dimension enforcement during split and resize.
- Tab ribbon per-pane: each group shows only its own tabs.
- Layout stability: `contentStartRow` is stable regardless of buffer count when tab ribbon is configured.

### Integration tests

- Split a pane, open a file in each, verify independent scroll and cursor.
- Edit a shared buffer in one pane, verify the other pane reflects the change.
- Close a pane, verify the sibling expands to fill the space.
- Terminal resize with active splits, verify proportional re-layout.
- Focus navigation with directional commands, verify correct pane receives input.
- Tab operations (open, close, switch) within a pane do not affect other panes.

### Rendering tests

- Verify separator characters are rendered at correct positions.
- Verify per-pane tab ribbons render in their assigned rects.
- Verify the focused pane indicator is visible.
- Verify the empty tab ribbon row renders correctly (layout stability fix).

### Performance tests

- Measure render time with 2, 3, and 4 panes vs. a single pane.
- Measure input latency with multiple panes.
- Verify that editing in one pane does not cause full re-render of other panes (diff rendering should skip unchanged cells).

## Risks and Open Questions

### How does the god object migration interact with splits?

The `ARCHITECTURE_TRANSITION_PLAN.md` defines a 9-phase migration to extract `EditorState` into focused components. The split screen work extracts per-editor view state into `EditorGroup`, which is the same direction as the architecture migration. However, the split work should not depend on the full migration completing first. The approach of creating `EditorGroup` as a new type that wraps extracted state can proceed independently and will accelerate the migration rather than conflict with it.

### How do vim motions work across panes?

Vim motions operate within the focused pane. `<C-w>` prefix switches to window management mode. This is standard Neovim behavior. The question is whether operator-pending motions (e.g., `d` followed by a motion) should be scoped to the focused pane. The answer is yes -- operators never cross pane boundaries in any vim implementation.

### What happens to global state that assumes a single editor?

Several pieces of state are currently global and will need refactoring:

- `EditorState.textBuffer`, `textCursor`, `scrollOffset` -- these must be looked up from the focused `EditorGroup`.
- `EditorState.selection` -- must be per-group.
- `EditorState.wrapCache` -- must be per-group.
- `EditorState.highlightedLines` -- must be per-group.
- `renderRefreshSource?.invalidate()` -- must be pane-aware or remain global (invalidating all panes is safe, just potentially wasteful).

### How does search interact with splits?

The search ADR proposes workspace-wide and per-file search. With splits:

- "Search in current file" operates on the focused pane's active buffer.
- Navigating search results opens the target file in the focused pane.
- "Search in all open files" should search across all panes' open buffers.
- Search highlighting should appear in all panes showing a buffer with matches.

### What is the maximum useful number of splits in a terminal?

Terminal dimensions are limited. A typical terminal is 200x50 characters. With a sidebar, the editor region might be 160x49. Each split adds a 1-character separator. With minimum pane dimensions of 10x3, the theoretical maximum is roughly 16 horizontal splits or 16 vertical splits. In practice, 2-4 panes is the typical usage.

The implementation should not impose an artificial limit but should warn or prevent splits that would result in panes smaller than the minimum dimensions.

### Should panes support different sidebar visibility?

No. The sidebar is global, not per-pane. This matches VS Code's model. The activity bar and sidebar are outside the editor region and are shared across all panes.

### How does tab drag-and-drop between panes work?

Tab drag-and-drop is a Phase 7 polish feature. The interaction model:

1. Mouse down on a tab in pane A.
2. Mouse drag crosses into pane B's rect.
3. A visual indicator shows the drop target.
4. Mouse up moves the `BufferRef` from pane A's `bufferRefs` to pane B's `bufferRefs`.
5. If pane A has no remaining buffers, it shows the empty state (or is closed, depending on config).

## Recommendation Summary

Ship the layout stability fix immediately as a one-line change in `LayoutMetrics.swift`. This eliminates a visible UI jump with zero risk.

For split screen, proceed in phases starting with the data model (`EditorGroup`, `SplitNode`) and working outward through layout, rendering, focus, and interaction. The key architectural insight is that `TextEditor` and `TabRibbon` are already self-contained widgets that can be instantiated multiple times -- the work is in the state management and routing layers above them, not in the rendering widgets themselves.

The split screen feature should align with but not depend on:

- the keybinding ADR (for command-based split management)
- the terminal UI framework ADR (for constraint-based layout primitives)
- the architecture transition plan (for extracting state from the god object)

The recommended order is:

1. Layout stability fix (Phase 0, immediate)
2. Data model and state extraction (Phase 1)
3. Layout computation (Phase 2)
4. Rendering (Phase 3)
5. Focus and input routing (Phase 4)
6. Commands and interaction (Phase 5)
7. Buffer sharing and cross-pane updates (Phase 6)
8. Polish (Phase 7)

## Deep Technical Analysis

### Codebase Impact Assessment

#### EditorState God Object Decomposition for Splits

The most impactful change is decomposing `EditorState` to separate per-pane state from global state. The current `EditorState` (EditorStateCore.swift) intermixes both categories:

**Global state** (stays on EditorState):
- `workspace: WorkspaceSession` (EditorStateCore.swift:172)
- `config: KittyConfig` (EditorStateCore.swift:176)
- `bufferManager: BufferManager` (EditorStateCore.swift:197) -- content store
- `treeState: WorkspaceTreeState` (EditorStateCore.swift:268)
- `mode: Mode`, `vimMode: VimMode` (EditorStateCore.swift:671-672)
- `colorScheme: ColorScheme` (EditorStateCore.swift:182-186)
- `symbolTheme`, `statusMessage`, `prompt`, `contextMenu`
- `sidebarCollapsed`, `activeSidebarPanel`, `treePanelWidth`

**Per-pane state** (must move to EditorGroup):
- `textBuffer`, `textCursor` (EditorStateCore.swift:198-206) -- view into the active buffer
- `scrollOffset`, `hScrollOffset`, `wrapRowOffset` (EditorStateCore.swift:556-569)
- `selection` (EditorStateCore.swift:692-695)
- `wrapCache` (EditorStateCore.swift:691)
- `highlightedLines`, `highlightSession` (EditorStateCore.swift:218-226)
- `tabScrollOffset` (EditorStateCore.swift:187)
- `cachedMaxLineWidth` (EditorStateCore.swift:251-254)

**Forwarding properties** (EditorStateCore.swift:189-264) currently delegate to `WorkspaceSession`. These must instead delegate to the focused `EditorGroup`. The transition requires a `focusedGroup` accessor:

```swift
var focusedGroup: EditorGroup {
    splitTreeManager.group(for: paneFocus.focusedGroupID)
}
```

All per-pane property accessors on `EditorState` become forwarding to `focusedGroup`:

```swift
var textBuffer: TextBuffer {
    get { focusedGroup.resolvedTextBuffer(from: bufferManager) }
    set { focusedGroup.setTextBuffer(newValue, in: bufferManager) }
}
```

This is a large refactor but can be done incrementally by replacing one forwarding property at a time.

#### Render.swift Pipeline Extension

The current render pipeline (Render.swift:6-135) has a fixed structure. The split screen extension modifies the middle section:

```
[unchanged]  Layout calculations
[unchanged]  Activity bar
[unchanged]  Sidebar panel + separator
[CHANGED]    Tab ribbon  ->  Per-pane tab ribbons
[CHANGED]    Editor      ->  Per-pane editors + separators
[unchanged]  Status bar
[unchanged]  Overlay
```

The tab ribbon section (Render.swift:27-52) currently renders one ribbon at row 0. With splits, it must iterate over `paneLayouts` and render each pane's ribbon in its assigned `tabRibbonRect`.

The editor section (Render.swift:96-104) currently calls `renderEditorPanel()` once. With splits, it must iterate over `paneLayouts` and call a per-pane version of `renderEditorPanel()` with each group's state and rect.

The cursor position computation (Render.swift:125-134) must select the cursor from the focused pane only. Non-focused panes should not contribute a cursor position to the terminal.

#### BufferManager Evolution

`BufferManager` (BufferManager.swift:4-140) must evolve from being a view model (with `activeIndex` determining what is shown) to being a content store (with `EditorGroup` instances determining what is shown where).

The `activeIndex` concept becomes per-`EditorGroup`. The `BufferManager.activeIndex` can remain as a convenience for the focused group but should not be the source of truth for rendering.

Methods that need rethinking:
- `open()` (BufferManager.swift:25-47): Currently sets `activeIndex`. Should return the buffer index without side effects. The caller (EditorGroup) decides which group to add it to.
- `close()` (BufferManager.swift:49-63): Currently adjusts `activeIndex`. Should only remove the buffer if no group references it. Each group independently adjusts its own `activeBufferIndex`.
- `switchTo()`, `nextTab()`, `prevTab()` (BufferManager.swift:77-90): These are per-group operations, not global operations.

#### MouseInput.swift Hit Testing

The current mouse input handling uses the global `LayoutMetrics` to determine click targets: activity bar, sidebar, editor, tab ribbon, scroll bars. With splits, clicks in the editor region must additionally determine which pane was clicked.

The hit test logic becomes:

1. Is the click in the activity bar region? (unchanged)
2. Is the click in the sidebar region? (unchanged)
3. Is the click in the editor region? If so:
   a. Check each `PaneLayout` for containment.
   b. If the click is in a separator, enter resize drag mode.
   c. If the click is in a pane's tab ribbon rect, delegate to that pane's tab hit testing.
   d. If the click is in a pane's editor rect, delegate to that pane's editor input handling and set pane focus.

### State of the Art: Split Implementation Patterns

#### VS Code EditorGroupService (TypeScript)

VS Code's split implementation is the most feature-complete:

- **EditorGroupService**: Central service managing an `EditorGroupView` tree. Each node is either a leaf (editor group) or a branch (grid node with children and sizes).
- **SplitSizing**: Groups track their `minimumSize`, `maximumSize`, and `orthogonalSize`. The layout uses a constraint solver to distribute space respecting all constraints.
- **DragOverlay**: When dragging a tab, a translucent overlay appears showing where the tab will land. Drop targets include: center (open in this group), top/bottom/left/right edges (create new split).
- **Grid widget**: A reusable `Grid` widget handles the recursive layout, separator rendering, and drag-to-resize. This widget is used both for editor splits and for the panel layout (terminal, output, problems).
- **EditorGroupModel**: Each group tracks: `editors` (ordered list), `activeEditor`, `previewEditor`, `sticky` editors, `locked` state. State changes emit events that the view layer observes.

#### Neovim Window Layout (C)

Neovim's window implementation is performance-focused:

- **Frame tree**: Windows are arranged in a tree of frames. Each frame is either a leaf (window) or a row/column container.
- **win_split()**: Core split function that creates a new window by dividing the current window's frame. Handles all the edge cases: minimum dimensions, status bar lines, sign columns.
- **win_close()**: Merges the closing window's space into a sibling. Handles the tree restructuring.
- **Window-local variables**: `w:` variables, local options, local mappings. Each window can have completely different display settings.
- **winlayout()**: Returns a nested list describing the window tree, useful for session saving and plugins.
- **Performance**: Windows share the same buffer content via a B-tree rope. Display is computed per-window with a display line cache. Only the visible portion of each window is rendered.

#### Zed Workspace Splits (Rust)

Zed takes a simpler approach:

- **Axis-based splits**: Only horizontal or vertical, not grid. Splits are created via commands or drag-and-drop.
- **PaneGroup**: A recursive enum similar to the proposed `SplitNode`, with `Pane` leaves and `PaneAxis` branches.
- **Flex sizing**: Children within a `PaneAxis` have flex ratios. Resizing adjusts flex values.
- **Item trait**: Each item in a pane implements an `Item` trait with methods for rendering, saving, and event handling. This means panes can contain non-editor items (terminals, preview, settings).
- **Focus model**: A single `focused_pane` ID determines which pane receives input. Focus transfers on click or keyboard navigation.

### Recommended Technical Approach for KittyCode

#### 1. Binary tree with ratio-based sizing

Use the `SplitNode` enum as specified in the Decision section. Ratio-based sizing is simpler than constraint-based sizing and sufficient for a binary tree. Each split stores a `Double` ratio (0.0 to 1.0) that determines how the available space is divided.

Minimum pane dimensions should be enforced as hard constraints:

```swift
struct SplitConstraints {
    static let minPaneWidth = 10
    static let minPaneHeight = 3
    static let separatorSize = 1
}
```

Before creating a split, check that both resulting panes would meet minimum dimensions. If not, refuse the split with a status message.

#### 2. SplitTreeManager for tree operations

```swift
@MainActor
final class SplitTreeManager {
    var root: SplitNode
    var focusedGroupID: EditorGroupID

    func group(for id: EditorGroupID) -> EditorGroup?
    func split(_ groupID: EditorGroupID, direction: SplitDirection, ratio: Double)
    func close(_ groupID: EditorGroupID)
    func resize(_ path: SplitNodePath, delta: Double)
    func allGroups() -> [EditorGroup]
    func adjacentGroup(from: EditorGroupID, direction: Direction) -> EditorGroupID?
    func computeLayouts(available: Rect, showTabRibbon: Bool) -> [PaneLayout]
}
```

The `SplitTreeManager` encapsulates all tree mutation logic. It is the single place where the split tree is modified, ensuring structural invariants (e.g., no empty branches, minimum dimensions).

#### 3. EditorGroup state extraction strategy

Rather than extracting all per-pane state at once, do it incrementally:

1. **First**: Extract `tabScrollOffset` and `activeBufferIndex` per group. These are the simplest and most isolated.
2. **Second**: Extract `scrollState` and `cursorState`. These require updating all cursor/scroll code to go through the focused group.
3. **Third**: Extract `selectionState`. This touches selection rendering and clipboard.
4. **Fourth**: Extract `wrapCache` and `highlightedLines`. These are the most complex because they interact with syntax highlighting and the wrap computation.

Each extraction step should be a separate commit with passing tests.

#### 4. Backward-compatible single-pane default

The default state should be a single-leaf `SplitNode`:

```swift
let defaultGroup = EditorGroup(id: EditorGroupID())
let defaultTree = SplitNode.leaf(defaultGroup)
```

All existing behavior should work unchanged with this default. The split screen feature is purely additive -- users who never split see no difference.

#### 5. Per-pane rendering with early-exit optimization

The render loop should skip re-rendering panes whose content has not changed:

```swift
struct PaneRenderState {
    var lastBufferVersion: Int
    var lastScrollRow: Int
    var lastCursorRow: Int
    var lastCursorCol: Int
    var lastWidth: Int
    var lastHeight: Int
}
```

Compare the current pane state against the cached render state. If nothing changed, skip the render call for that pane. The `RenderPipeline` diff rendering already handles cell-level deduplication, but skipping the entire render call avoids the cost of constructing `TextEditor` widgets and computing gutter decorations for unchanged panes.

#### 6. Keyboard shortcuts for split management

Default keybindings by mode:

**vim mode** (aligned with Neovim):
- `<C-w>v`: vertical split
- `<C-w>s`: horizontal split
- `<C-w>c` or `<C-w>q`: close pane
- `<C-w>h/j/k/l`: focus left/down/up/right
- `<C-w>=`: equalize pane sizes
- `<C-w>>/<C-w><`: resize wider/narrower
- `<C-w>+/<C-w>-`: resize taller/shorter

**kittycode mode**:
- `Cmd+\`: vertical split
- `Cmd+Shift+\`: horizontal split
- `Cmd+W`: close pane (when no tabs remain)
- `Cmd+Alt+Arrow`: focus directional
- `Cmd+Alt+=`: equalize

**nano mode**:
- `Ctrl+\`: vertical split
- `Ctrl+Shift+\`: horizontal split
- `Ctrl+W` then `s`: close pane (when no tabs remain)
- `Ctrl+W` then arrow: focus directional

#### 7. Pane zoom (temporary maximize)

Add a zoom command that temporarily maximizes the focused pane to fill the entire editor region, hiding all other panes and separators. Zooming again or pressing Escape restores the split layout. This matches tmux's `<C-b>z` and Neovim's `<C-w>o`.

```swift
var isZoomed: Bool = false
var zoomedGroupID: EditorGroupID?
```

When zoomed, the layout computation returns a single `PaneLayout` for the zoomed group using the full editor region. The split tree structure is preserved but not rendered.

#### 8. Split-aware status bar

The status bar should show information about the focused pane:

- File name and path from the focused group's active buffer
- Cursor position from the focused group's cursor state
- Language mode from the focused group's active buffer
- A pane indicator (e.g., "Pane 1 of 3" or a visual position indicator) when splits are active

This requires the status bar renderer to accept the focused `EditorGroup` rather than reading from global `EditorState` properties.

---

### SOTA Review and Accuracy Assessment

This section evaluates the technical claims and architectural decisions in this ADR against current state-of-the-art knowledge from established editor implementations and relevant literature.

#### 1. VS Code EditorGroup Model: K-ary Grid vs Binary Tree

**Claim in ADR:** The ADR proposes a binary tree model for split management.

**Accuracy:** VS Code's internal model uses a **k-ary grid** (`EditorGridWidget`), not a binary tree. Each grid node can contain multiple children in a single row or column, allowing three-way splits without extra nesting levels. Neovim's internal model uses a **frame tree** that is also not strictly binary — a frame can have multiple children in a single split direction.

**Assessment:** The binary tree model proposed here is **simpler and entirely adequate for v1**. It naturally supports horizontal and vertical splits, and most real-world split configurations (2-4 panes) are representable without pathological depth. The k-ary model becomes valuable only when users frequently create 3+ panes in a single direction and want uniform sizing control. This is a reasonable simplification for a terminal editor's first split implementation. The ADR should acknowledge this as a deliberate simplification, noting that migration to k-ary is additive (a binary tree is a special case of a k-ary tree).

#### 2. Neovim Window Model Accuracy

**Claim in ADR:** References to Neovim's window management model.

**Accuracy:** Neovim's window model internally uses a `frame_T` structure organized as a tree where each frame node has a `fr_layout` field indicating `FR_LEAF` (a single window), `FR_ROW` (children arranged horizontally), or `FR_COL` (children arranged vertically). This is a **frame tree**, not a flat list or a binary tree. The `:split` and `:vsplit` commands create new leaf nodes within the appropriate frame node, and Neovim's equalization algorithm (`win_equal()`) walks this tree recursively to distribute space.

**Assessment:** The ADR's approach of a `SplitNode` enum with `.leaf` and `.split` variants is structurally similar to Neovim's frame tree but constrained to binary branching. This is accurate modeling for the described use cases. The `equalizeSizes()` function described in the ADR correctly mirrors the recursive equalization approach used by Neovim.

#### 3. tmux Pane Model

**Claim in ADR:** References to tmux for zoom behavior (`<C-b>z`).

**Accuracy:** tmux's pane zoom temporarily maximizes a pane to fill the window, preserving the layout tree. The zoom state is a boolean flag on the window structure; the pane tree is not modified. The ADR's proposed `isZoomed` / `zoomedGroupID` approach correctly mirrors this pattern.

**Assessment:** Accurate. The proposed zoom implementation is a clean match for tmux's well-established behavior.

#### 4. Layout Stability and Resize Algorithms

**Claim in ADR:** Proportional resize algorithm that preserves pane ratios when the terminal window resizes.

**Accuracy:** This is the standard approach used by all major editors and terminal multiplexers. VS Code, Neovim, and tmux all use proportional distribution on resize. The key subtlety the ADR correctly identifies is **minimum size constraints** — when proportional allocation would shrink a pane below its minimum, the excess must be redistributed to other panes. Neovim handles this with a two-pass algorithm: first allocate proportionally, then enforce minimums and redistribute the deficit.

**Assessment:** The ADR's approach is sound. One detail worth noting: when multiple panes simultaneously hit their minimum constraints, the redistribution algorithm must handle cascading constraints (pane A's surplus goes to pane B, which then also hits its minimum). The ADR's recursive layout computation handles this implicitly through the tree structure, which is correct.

#### 5. Synchronized Scrolling

**Claim in ADR:** References synchronized scrolling for diff views.

**Accuracy:** Synchronized scrolling in diff contexts requires **line-level alignment**, not just pixel-offset synchronization. VS Code's diff editor uses a computed alignment map that accounts for inserted/deleted lines, ensuring that corresponding lines in both panes remain visually aligned even when the documents have different line counts. Neovim's `scrollbind` option provides simpler offset-based synchronization that doesn't account for diff alignment.

**Assessment:** For a first implementation, simple offset-based scroll synchronization (Neovim-style `scrollbind`) is sufficient. Line-level diff alignment is a feature of the diff viewer, not the split system itself. The ADR correctly scopes this as a future enhancement rather than a v1 requirement.

#### 6. Mouse Hit Testing

**Claim in ADR:** Describes mouse click handling for focus switching between panes.

**Accuracy:** Terminal mouse events report cell coordinates (row, column). Hit testing against the pane layout tree is a simple point-in-rectangle test. This is straightforward in terminal contexts because coordinates are integer cell positions, not sub-pixel floating-point values as in GUI editors.

**Assessment:** The approach is correct and simpler than GUI editor hit testing. The ADR appropriately handles separator dragging (resize by mouse) by detecting clicks on separator positions.

#### 7. Render Pipeline Optimization

**Claim in ADR:** Per-pane render skipping using cached render state comparison.

**Accuracy:** This is a sound optimization. VS Code uses a similar approach — each editor widget independently tracks its dirty state and skips rendering when unchanged. Neovim uses a `must_redraw` flag system at multiple granularities (cell, line, window, screen). The `PaneRenderCache` struct proposed in the ADR captures the essential state for dirty checking.

**Assessment:** Correct approach. The ADR should note that cursor blink events should NOT trigger a full pane render — only the cursor cell needs updating. This is a common performance pitfall in terminal editor implementations where cursor blink invalidates the entire pane cache.

#### 8. Keyboard Shortcut Design

**Claim in ADR:** Vim-mode shortcuts aligned with Neovim (`<C-w>` prefix).

**Accuracy:** The proposed vim-mode keybindings (`<C-w>v`, `<C-w>s`, `<C-w>h/j/k/l`, etc.) are **exactly correct** — they match Neovim's default window management bindings. The kittycode-mode bindings (`Cmd+\`, `Cmd+Shift+\`, `Cmd+Alt+Arrow`) follow macOS GUI conventions. The nano-mode bindings are reasonable inventions as nano has no native split support.

**Assessment:** Well-designed. One addition worth considering: `<C-w>T` (move pane to new tab) and `<C-w>r`/`<C-w>R` (rotate panes) are commonly used Neovim window commands that could be added in a later phase.

#### Overall Assessment

**Accuracy: HIGH.** The ADR makes no significant factual errors. The binary tree model is a reasonable simplification clearly adequate for v1. The layout algorithms, resize behavior, zoom implementation, and keybinding design all align well with established patterns from VS Code, Neovim, and tmux.

**Risk areas:**
- **Binary tree to k-ary migration:** If users request three-way splits frequently, the binary tree will produce unnecessarily deep nesting. Plan the data model with migration in mind (the current `SplitNode` enum could be extended to hold `[SplitChild]` instead of a fixed pair).
- **Focus management across splits:** The ADR describes directional focus movement (`<C-w>h/j/k/l`) but doesn't detail the algorithm for resolving ambiguous cases (e.g., when moving left and two panes are stacked vertically to the left). Neovim uses a "closest center point" heuristic — the pane whose center is closest to the current cursor position wins. This should be specified.
- **Render cache invalidation:** Scroll events, diagnostic updates, and git gutter changes must all invalidate the pane render cache. The cache check should include a content version counter on the buffer, not just cursor position and dimensions.
