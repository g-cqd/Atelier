# Future ADR: Terminal UI Framework Evolution

Status: Proposed
Date: 2026-03-12

## Goal

Engineer a more composable, SwiftUI-paradigm-like terminal UI framework with:

- better developer experience
- richer composition primitives
- clearer event and focus routing
- stronger layout capabilities

while preserving the current performance advantages of:

- direct `ScreenBuffer` rendering
- specialized leaf widgets
- explicit control over redraw

The target is not to imitate SwiftUI internally at all costs. The target is to adopt the best compositional properties of SwiftUI without sacrificing terminal rendering performance.

## Current Codebase Findings

### A SwiftUI-shaped core already exists

`Sources/KittyWidgets/View.swift` already defines:

- `View`
- `@ViewBuilder`
- `Body`
- `ProposedSize`
- `Size`
- `handleEvent(_:)`

`Sources/KittyWidgets/Layout.swift` already provides:

- `VStack`
- `HStack`
- `ZStack`

`Sources/KittyWidgets/ViewModifier.swift` already provides:

- modifiers
- modifier composition
- `RenderContext` propagation

So the project already has the beginnings of a declarative UI framework.

### The actual app does not rely on that framework deeply

`Sources/KittyCode/AppMain.swift` runs KittyCode through:

- imperative `renderFrame(...)`
- imperative `handleEvent(...)`

The editor shell does not render from a root declarative view tree. It uses custom render functions and shell-owned state transitions.

### The generic App runtime is underused by the main product

`Sources/KittyApp/App.swift` and `Sources/KittyApp/ApplicationRuntime.swift` already support a root `App` and root `View` event dispatch.

That path exists, but KittyCode largely bypasses it in favor of custom render and event closures.

This is another already-developed but underused part of the framework story.

### Layout measurement exists in API shape but is not actually used

`View.size(proposed:)` and `ProposedSize` exist in `Sources/KittyWidgets/View.swift`.

`rg` shows there is no real layout system consuming that measurement API in the current widget stack.

This means the project has layout vocabulary, but not a functioning measurement-and-placement engine.

### Event handling exists in API shape but is weakly integrated

`View.handleEvent(_:)` exists.

`Sources/KittyWidgets/KeyMap.swift` also exists as a composable keybinding map.

`rg` shows `KeyMap` is not used by KittyCode runtime.

So event routing primitives exist, but they are not the actual framework path for the main app.

### Focus support exists but is not shell-integrated

`Sources/KittyWidgets/FocusEngine.swift` exists and is tested.

`rg` shows it is not used by KittyCode runtime.

This matches the broader pattern: framework seeds exist, but the shell still uses custom focus logic and ad hoc routing.

### Rendering is still driven by runtime type switching

`Sources/KittyWidgets/ViewRenderer.swift` dispatches rendering by a large runtime switch:

- concrete leaf type checks
- protocol downcasts
- generic fallback into `body`

This is workable, but it is not a real view graph or layout engine.

### Tuple flattening still uses reflection

`ViewRenderer` uses `Mirror` to extract children from `TupleView`.

That is acceptable as a bootstrap technique, but it is not ideal in a framework that aims to be both highly composable and performance-sensitive.

### Current stack layout is simplistic

`renderStack(...)` divides the available length equally across children.

There is no support for:

- intrinsic sizing
- flexible versus fixed children
- alignment
- padding primitives
- frame constraints
- spacer-driven distribution

This is the biggest composability limit in the current framework surface.

### Some widgets bypass the `View` model entirely

`Sources/KittyWidgets/ActivityBar.swift` is a renderable struct, but not a `View`.

This is a useful signal: some UI pieces are designed as direct rendering helpers rather than as first-class composable views.

### Performance is currently protected by specialization

The current system gets good performance characteristics from:

- direct rendering into `ScreenBuffer`
- specialized leaf renderers like `TextEditor`
- explicit app-level redraw control
- no general retained view graph diff engine in the hot path

This is worth preserving.

## Gaps and Missing Features

### 1. No real measurement-and-placement layout engine

The current framework cannot support richer composition predictably because measurement is mostly nominal.

### 2. No unified focus and event-routing model

The framework has event and focus primitives, but KittyCode does not use them as the main control path.

### 3. No stable identity model

There is no concept of:

- stable view identity
- reusable subtree caching
- keyed collections
- invalidation scoping by subtree

### 4. No environment model beyond style context

`RenderContext` is useful for style overrides, but it is not a general environment system for:

- commands
- focus
- theme lookups
- feature flags
- bindings

### 5. No composable shell primitives

The main shell still uses custom functions for:

- layout
- overlay handling
- sidebar selection
- status bar assembly

That means the framework is not yet the natural way to build the app.

### 6. No high-level collection or pane abstractions

There is no framework-native abstraction for:

- panes
- toolbars
- segment bars
- reusable shell layouts
- keyed dynamic lists

### 7. Reflection and existential dispatch are still in the hot path

This is not automatically catastrophic, but it is not the right long-term architecture if the framework becomes more central.

## Already Developed But Unwired or Underused

- `App` runtime exists but KittyCode largely bypasses it.
- `ProposedSize` and `size(proposed:)` exist but are not part of a real layout engine.
- `View.handleEvent(_:)` exists but is not the main shell event route.
- `KeyMap` exists but is unused by KittyCode runtime.
- `FocusEngine` exists but is unused by KittyCode runtime.
- Modifier and builder infrastructure already exists and can be evolved rather than replaced.

## Decision

### 1. Evolve the current framework instead of replacing the renderer

Keep:

- `ScreenBuffer`
- leaf-widget specialization
- explicit redraw control

Do not replace them with a generic immediate-mode framework.

### 2. Build a real framework around a lowered view graph

The missing middle layer is:

- view description
- view graph lowering
- layout and placement
- render command generation

This should sit above leaf widgets and below the app shell.

### 3. Make layout first-class

The existing measurement API should become real through a layout protocol and explicit placement phase.

### 4. Make focus, commands, and event routing part of the framework

The framework should not only draw views. It should also provide:

- focus scopes
- command routing
- keymap scoping
- mouse hit regions

### 5. Preserve performance through specialization and caching

The framework should not rely on generic diffing of everything on every frame.

Performance should come from:

- specialized leaf nodes
- stable identities
- cached layout for stable subtrees
- explicit invalidation boundaries

## Proposed Architecture

### Option A: Evolve `KittyWidgets` in place

This is the lower-risk approach.

Add clearer internal layers inside `KittyWidgets`:

- declarative surface
- layout engine
- event and focus system
- leaf widget adapters

### Option B: Split core UI from leaf widgets

Longer-term, consider splitting into:

- `KittyUI`
  - declarative view system, layout, environment, focus, commands
- `KittyWidgetKit`
  - `TextEditor`, `ListView`, `TreeView`, `StatusBar`, `ActivityBar`

This is cleaner architecturally, but not required for the first migration.

### Core types

Suggested new framework types:

- `ViewIdentity`
- `ViewGraph`
- `ViewGraphNode`
- `LayoutNode`
- `LayoutCache`
- `LayoutProtocol`
- `LayoutSubview`
- `Placement`
- `EnvironmentValues`
- `CommandContext`
- `FocusScope`
- `EventRouter`
- `InvalidationSet`

### Layout system

Make `ProposedSize` real by introducing:

- measure phase
- place phase
- cached layout keyed by identity and proposal

Add primitives such as:

- `Spacer`
- `Padding`
- `Frame`
- `Overlay`
- `Background`
- `Divider`
- alignment options

This is the minimum required for the framework to feel meaningfully more SwiftUI-like.

### Environment model

Generalize beyond `RenderContext`.

Suggested environment responsibilities:

- theme
- commands
- focus context
- keybinding resolver
- feature flags
- shell services

Keep `RenderContext` as a low-level style overlay layer if useful, but do not treat it as the whole environment system.

### Event and command routing

Promote `handleEvent(_:)`, `KeyMap`, and `FocusEngine` into real framework infrastructure.

Suggested event flow:

1. event enters root view graph
2. focus scope resolves target subtree
3. local keymap and command handlers run
4. unhandled events bubble upward
5. shell-level fallback runs last

This gives the framework enough structure for panes, forms, search UI, and future extensibility.

### Identity and keyed collections

Add stable identity for subtree caching and dynamic collections.

Suggested abstractions:

- `ForEach`
- keyed list rows
- identity-aware subtree reuse

This is necessary for better developer experience and for performance-preserving recomposition.

### Rendering path

Keep leaf renderers specialized.

The framework should lower high-level views into render nodes that can call specialized renderers for:

- `TextEditor`
- `ListView`
- `TreeView`
- `StatusBar`
- `ActivityBar`

Do not force these through generic cell-by-cell composition when they already have optimized drawing paths.

### Hot-path cleanup

Reduce generic runtime cost by:

- removing `Mirror` from tuple child extraction in the hot path
- minimizing existential boxing during render traversal
- caching lowered child arrays for stable nodes

### Shell adoption strategy

The first consumers should be shell surfaces that benefit from composition but are less performance-critical than the text editor core:

- status bar
- activity bar
- sidebar panes
- overlays

The editor itself can remain a specialized leaf widget while the surrounding shell becomes more declarative.

## Recommended Phasing

### Phase 1: Make existing framework pieces real

- Introduce real layout and placement.
- Integrate focus and keymap primitives.
- Add environment and command plumbing.
- Keep KittyCode shell mostly unchanged.

### Phase 2: Rebuild shell chrome on top of the framework

- Activity bar
- status bar
- sidebar panes
- overlays

This validates the framework where composition value is high and latency sensitivity is moderate.

### Phase 3: Add identity-aware collections and richer containers

- `ForEach`
- list and pane abstractions
- better stack behavior
- frame and padding primitives

### Phase 4: Tighten performance paths

- remove reflection from hot paths
- add layout caching
- add subtree invalidation
- benchmark render and input latency before and after migration

## Testing Recommendations

- Add layout measurement and placement tests.
- Add focus and key-routing tests.
- Add command bubbling tests.
- Add identity and keyed collection tests.
- Add performance benchmarks for frame render time and input latency.
- Add regression tests proving specialized widgets still render through optimized paths.

## Recommendation Summary

KittyCode does not need a different renderer. It needs a real framework layer above the existing renderer.

The current codebase already contains the seed crystals of that framework:

- `View`
- `ViewBuilder`
- stacks
- modifiers
- `App`
- `KeyMap`
- `FocusEngine`

But most of them are either shallow, bypassed, or not yet integrated into the main app architecture.

The right direction is to make layout, environment, focus, and commands real, then migrate shell surfaces onto that framework while preserving specialized leaf widgets and direct `ScreenBuffer` rendering.

## Deep Technical Analysis

### Codebase Impact Assessment

#### Mirror Reflection Hot Path

The most immediate performance concern is in `ViewRenderer.swift` where `TupleView` child extraction uses `Mirror` reflection (ViewRenderer.swift:1272-1285):

```swift
extension TupleView: _TupleViewProtocol {
    fileprivate var childViews: [any View] {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .tuple {
            return mirror.children.compactMap { $0.value as? any View }
        }
        if let view = value as? any View {
            return [view]
        }
        return []
    }
}
```

`Mirror` performs runtime type introspection, allocates metadata objects, and boxes values as `Any`. In a render loop running at 60fps on terminal resize, this occurs for every `TupleView` in the view tree.

Replacement strategy using Swift's parameter pack support (Swift 5.9+):

```swift
extension TupleView: _TupleViewProtocol where T == (repeat each C) {
    fileprivate var childViews: [any View] {
        var result: [any View] = []
        // Use parameter pack iteration when available
        repeat result.append(each value)
        return result
    }
}
```

If parameter pack iteration on stored properties isn't viable yet, the alternative is to generate overloaded `childViews` for TupleView2, TupleView3, ..., TupleView10 (matching `ViewBuilder.buildBlock` overloads). This is what SwiftUI does internally — each arity has a concrete type with direct property access.

#### Layout Engine Architecture

The current layout is trivially simple: `renderStack()` in ViewRenderer.swift divides available space equally among children. `ProposedSize` and `View.size(proposed:)` exist as API surface but are never called in the render pipeline.

A real layout engine needs three phases:

**Phase 1 — Measure**: Each view is asked "given this proposed size, what size do you need?" Views return their ideal size. Leaf views (Text, StatusBar) measure their content. Container views (VStack, HStack) query children and aggregate.

**Phase 2 — Place**: Given the measured sizes and the available space, the parent assigns each child a concrete `Rect`. For stacks, this involves distributing remaining space among flexible children (Spacer, views that accept less than their ideal).

**Phase 3 — Render**: Each view renders into its assigned `Rect`. This is the only phase that touches `ScreenBuffer`.

The key types:

```swift
protocol LayoutProtocol {
    associatedtype Cache
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Cache) -> Size
    func placeSubviews(in bounds: Rect, proposal: ProposedSize, subviews: Subviews, cache: inout Cache)
}

struct LayoutSubview {
    func sizeThatFits(_ proposal: ProposedSize) -> Size
    func place(at position: Point, proposal: ProposedSize)
}
```

This mirrors SwiftUI's `Layout` protocol introduced in iOS 16/macOS 13. The terminal constraint is that all dimensions are integer character cells, not floating-point points.

Stack layout algorithm (simplified):
1. Query each child's ideal size with the stack's full cross-axis dimension and `nil` on the main axis
2. Separate fixed-size children (returned a concrete size) from flexible children (Spacer, or views that returned the full proposed size)
3. Distribute remaining space among flexible children proportionally
4. Place children sequentially along the main axis with spacing

#### View Identity and Invalidation

The current renderer has no concept of view identity. Every render traverses the full view tree and writes every cell. For the shell chrome (status bar, activity bar, sidebar headers), this is acceptable — these are small. For the text editor, this is avoided because `TextEditor` has a specialized renderer.

As the framework takes on more rendering responsibility, identity becomes important:

1. **Stable identity**: Views in a `ForEach` need stable keys so the framework can match old and new children. Without identity, reordering a list causes unnecessary redraws of unchanged items.

2. **Invalidation scoping**: When state changes, only the subtree that depends on the changed state should re-render. Without invalidation boundaries, every state change causes a full-tree traversal.

3. **Recommended approach**: Start with explicit identity (`ForEach(items, id: \.id)`) and per-frame full traversal. Add invalidation scoping only when profiling shows it's necessary. Terminal UIs are small enough that full traversal is often fast enough.

#### Environment Model Beyond RenderContext

`RenderContext` (ViewModifier.swift) carries style information (foreground, background, bold, italic) through the view tree. This is adequate for styling but insufficient for:

- **Command routing**: Views need access to the command dispatcher to handle actions
- **Focus state**: Views need to know if they are in the focused scope
- **Theme lookup**: Views need access to the full theme for semantic color resolution
- **Configuration**: Views need access to relevant config for behavior decisions

SwiftUI solves this with `EnvironmentValues` — a dictionary-like container propagated down the view tree, with typed keys:

```swift
struct EnvironmentValues {
    var theme: Theme
    var commandDispatcher: CommandDispatcher
    var focusedScope: FocusScope?
    var isEnabled: Bool
    // ...
}
```

For KittyCode's framework, extending `RenderContext` with additional fields is simpler than building a full `EnvironmentValues` system. Add fields as needed rather than engineering a generic key-value container upfront.

#### ApplicationRuntime Integration Gap

`ApplicationRuntime.run(_:App.Type)` (ApplicationRuntime.swift:146-168) exists and supports a declarative app model where a root `View`'s `body` is rendered and events are dispatched through `handleEvent()`. But KittyCode bypasses this entirely, using custom `renderFrame()` and `handleEvent()` closures in `AppMain.swift`.

Bridging strategy:

1. **Don't force migration**: The custom render/event path works and is optimized. Forcing KittyCode through `ApplicationRuntime.run(_:App.Type)` would require making `EditorState` work within the declarative view tree, which is a massive refactor with high risk.

2. **Use the framework for sub-trees**: Instead of making the entire app declarative, use the framework for composable sub-regions: status bar, activity bar, sidebar panes, overlays. These regions get their own `render(to:in:context:)` calls within the imperative `renderFrame()`.

3. **Gradual adoption**: As shell chrome migrates to framework views (Phase 2 of the ADR), the imperative render function shrinks. Eventually it becomes thin enough that lifting to `ApplicationRuntime` is a small step rather than a big bang.

### State of the Art: Terminal UI Frameworks

#### Ratatui (Rust)

Ratatui is the dominant terminal UI framework in the Rust ecosystem:
- **Immediate mode**: No retained state. The application renders the entire UI every frame by calling `terminal.draw(|frame| { ... })`.
- **Layout system**: `Layout::default().direction(Direction::Vertical).constraints([Constraint::Length(3), Constraint::Min(0)]).split(area)` — constraints-based layout with Length, Min, Max, Percentage, and Ratio.
- **Widgets**: Stateless rendering functions. `Paragraph`, `List`, `Table`, `Tabs`, `Block`, `Gauge`. Each implements `Widget` trait with `fn render(self, area: Rect, buf: &mut Buffer)`.
- **No view tree**: Ratatui is purely imperative. No composition, no modifiers, no environment. Layout is computed per-frame.
- **Performance**: Very fast due to minimal abstraction. The buffer diff is computed after rendering and only changed cells are written to the terminal.
- **Double buffering**: Maintains previous and current `Buffer`. Computes diff and only emits escape sequences for changed cells.

**Relevance to KittyCode**: Ratatui's constraint-based layout is more flexible than KittyCode's equal-division stacks. The `Constraint` enum (Length/Min/Max/Percentage/Ratio) is a good model for terminal layout primitives. However, Ratatui's lack of composition means every screen requires manual layout orchestration — the opposite of KittyCode's declarative ambition.

#### Ink (React for terminals, JavaScript)

Ink brings React's component model to terminal UIs:
- **JSX components**: `<Box flexDirection="column"><Text>Hello</Text></Box>`
- **Flexbox layout**: Full Yoga-based flexbox with `flexDirection`, `flexGrow`, `flexShrink`, `flexBasis`, `alignItems`, `justifyContent`, `padding`, `margin`.
- **Reconciler**: React's fiber reconciler adapted for terminal output. Component identity, key-based diffing, and incremental updates.
- **Hooks**: `useState`, `useEffect`, `useInput` for keyboard handling.
- **Performance tradeoff**: JavaScript + React reconciler is significantly slower than native terminal rendering. Acceptable for CLIs, not for high-performance editors.

**Relevance to KittyCode**: Ink proves that flexbox layout works well for terminal UIs. The subset of flexbox relevant to terminal layout (direction, grow, fixed sizes) maps cleanly to KittyCode's stack model with flexible children.

#### Bubbletea (Go)

Bubbletea is the standard terminal UI framework in Go:
- **Elm Architecture**: Model → Update → View. The `Model` interface has `Init()`, `Update(msg)`, and `View() string` methods.
- **No layout engine**: `View()` returns a plain string. Layout is done via `lipgloss` (a styling library) with `JoinHorizontal()`, `JoinVertical()`, `Place()`.
- **Message passing**: All state changes go through `Update(msg)`. Messages are typed values. No direct mutation.
- **Composition via embedding**: Larger models embed smaller models and delegate messages. No view tree or component lifecycle.

**Relevance to KittyCode**: Bubbletea's Elm Architecture is clean for simple TUIs but doesn't scale to complex editors. The message-passing model is too indirect for KittyCode's needs. However, the principle of "view is a pure function of state" aligns with KittyCode's declarative direction.

#### FTXUI (C++)

FTXUI is a modern C++ terminal UI library:
- **DOM-like elements**: `vbox({text("Hello"), separator(), text("World")})` creates a vertical layout.
- **Flexbox layout**: Elements support `flex`, `size(WIDTH, EQUAL, 20)`, and constraint-based sizing.
- **Components**: Stateful interactive elements with `Render()` and `OnEvent()`. Components compose via `Container::Vertical/Horizontal/Tab`.
- **Decorator pattern**: `text("Hello") | bold | color(Color::Red) | border` — modifiers applied via pipe operator.
- **Canvas rendering**: Supports sub-character rendering using Braille characters for charts and graphics.

**Relevance to KittyCode**: FTXUI's decorator pattern is similar to KittyCode's view modifier system. Its constraint-based sizing is more practical than equal-division stacks.

### Recommended Technical Approach for KittyCode

#### Framework: SOTA Terminal UI Engine

1. **Constraint-based layout solver (Cassowary)**: Implement a Cassowary-style linear constraint solver for layout, replacing the current equal-division VStack/HStack model. Views declare constraints as linear equations and inequalities: `.width == parent.width`, `.height >= 3`, `.top == sibling.bottom + 1`, `.width == parent.width * 0.3 | priority: .high`. The solver (Kiwi algorithm — a production-optimized Cassowary implementation) resolves all constraints simultaneously into exact integer positions. Constraints support priorities (required, strong, medium, weak) for graceful degradation when constraints conflict. Built-in constraint sugar: `.fixed(n)` (required equality), `.min(n)` (inequality), `.max(n)` (inequality), `.flexible(priority:)` (weak equality to fill available space), `.ratio(n, d)` (proportional to parent). The solver runs incrementally: on terminal resize, only the changed root constraint is updated, and the solver propagates changes in O(constraints-affected) time rather than re-solving from scratch. This gives KittyCode layout power equivalent to Auto Layout / CSS Flexbox in a terminal context.

2. **Full EnvironmentValues propagation with type-safe keys**: Implement a type-safe environment system modeled on SwiftUI's `EnvironmentValues`. Define `EnvironmentKey` protocol with `associatedtype Value` and `static var defaultValue: Value`. Access via `@Environment(\.theme) var theme` (property wrapper that reads from the nearest ancestor's environment). Environment values flow down the view tree automatically — any ancestor can inject overrides via `.environment(\.theme, darkTheme)`. Built-in environment keys: `theme` (full color/style scheme), `colorScheme` (light/dark), `isEnabled` (interactive or disabled), `focusState` (focused scope ID), `locale` (for future i18n), `layoutDirection` (LTR/RTL), `commandDispatcher` (for triggering commands), `diagnosticSeverityFilter` (for filtering visible diagnostics). The environment container uses copy-on-write semantics so overrides at any tree level do not allocate unless values actually differ from the parent.

3. **Animation primitives with frame-rate-limited rendering**: Terminal animations via a declarative API: `withAnimation(.linear(duration: 0.3)) { state.sidebarWidth = 40 }`. Animate any numeric property: position, size, opacity (via terminal color blending between foreground and background), scroll offset. The animation system maintains a priority queue of active animations, each with a start time, duration, easing curve (linear, easeIn, easeOut, easeInOut, spring), and interpolation closure. A dedicated animation render loop ticks at 30fps (capped to avoid terminal throughput saturation) during active animations, producing intermediate frames via the standard `RenderPipeline`. When no animations are active, the render loop returns to event-driven (zero CPU usage). Practical uses: smooth sidebar resize (width interpolation over 200ms), tab slide-in (horizontal offset animation), cursor blink (opacity oscillation), notification toast fade-in/fade-out, smooth scroll (scroll offset interpolation over 100ms). No terminal UI framework currently supports declarative animations — this is a differentiator.

4. **Accessibility layer with semantic annotations**: Views declare semantic annotations: `accessibilityLabel("File explorer")`, `accessibilityRole(.list)`, `accessibilityValue("3 items")`, `accessibilityHint("Press enter to open")`. These annotations are stored in the view tree alongside layout and rendering data. For terminals that support it, emit OSC sequences for screen reader compatibility (VoiceOver on macOS recognizes certain terminal semantics). Ensure focus order matches reading order by deriving it from the view tree traversal. All interactive elements must have text labels. The annotation API exists from day one even if terminal screen reader support is limited — it ensures the architecture is ready when terminal accessibility improves, and it provides introspection for automated testing.

5. **Concrete TupleView codegen to eliminate Mirror reflection**: Replace the `Mirror`-based reflection in `ViewRenderer` (lines 1272-1285, the current bottleneck) with compile-time generated concrete types: `TupleView2<A, B>`, `TupleView3<A, B, C>`, through `TupleView10<A, B, C, D, E, F, G, H, I, J>`. Each type has direct stored properties (`let v0: A; let v1: B; ...`) and a `var childViews: [AnyView]` computed property that returns them without any runtime introspection. The `@resultBuilder` `ViewBuilder` provides overloads for `buildBlock(_ v0: V0, _ v1: V1) -> TupleView2<V0, V1>` through arity 10. For bodies exceeding 10 children, nest: `TupleView10<..., TupleView5<...>>`. This eliminates all `Mirror` usage from the hot render path entirely. Expected improvement: 10-50x faster child extraction per TupleView node, which compounds across the entire view tree every frame.

6. **Retained-mode virtual view tree with structural diffing**: Build a virtual view tree each frame (lightweight value-type node descriptors), diff it against the previous frame's tree, and emit only the changed subtrees to the `RenderPipeline`. Use view identity for stable diffing: explicit identity via `.id("sidebar")` modifier, or implicit structural identity based on position in the parent's child list (SwiftUI's default). The diff algorithm walks both trees in parallel: same identity + same type = diff children recursively; same identity + different type = destroy old subtree, create new; missing identity = removal; new identity = insertion. Only subtrees where at least one property changed are re-measured, re-laid-out, and re-rendered. This is the core of React/SwiftUI's rendering model adapted for terminal cells, and it composes with the existing cell-level diff in `RenderPipeline` for a two-tier optimization: structural diff (skip unchanged subtrees) then cell diff (skip unchanged characters).

7. **Focus management system promoting FocusEngine to core**: Promote the existing but unused `FocusEngine` to a core framework primitive. Implement a hierarchical focus scope tree that mirrors the view tree. Each focusable view registers in a `FocusScope`. Tab/Shift+Tab cycles focus within the current scope. Escape moves focus to the parent scope. Focus scopes create isolated focus rings: the sidebar has its own ring (file tree items), the editor area has its own ring (tabs, editor), the command palette captures focus exclusively. `@FocusState` property wrapper binds a boolean or enum to focus state, enabling views to react to focus changes: `@FocusState var isFocused: Bool` or `@FocusState var focus: PanelFocus?`. Focus-dependent styling: focused views receive a distinct border style, background tint, or cursor indicator, all driven by the environment (`\.focusState`). This replaces the ad-hoc focus routing in EventHandling.swift with a fully declarative, extensible system.

8. **Modifier chain architecture (SwiftUI model for terminals)**: View modifiers like `.padding(1)`, `.border(.single)`, `.foregroundColor(.red)`, `.frame(width: 40, height: 10)`, `.background(.color(.blue))` wrap views in modifier containers that participate in the layout and rendering pipeline. Each modifier is a `ViewModifier` that adjusts the proposed size (padding reduces available space, frame overrides it), decorates the rendered output (border draws around the child, foregroundColor sets the style), or injects environment values. Modifiers compose naturally: `.padding(1).border(.single).padding(1)` creates padding inside the border and outside it. The modifier chain is resolved during layout: the outermost modifier receives the proposed size from the parent, adjusts it, passes it inward, receives the child's size, adjusts it, and returns it outward. This is the terminal equivalent of SwiftUI's modifier system, enabling expressive, composable view styling without subclassing.

## SOTA Review and Accuracy Assessment

This section evaluates the ADR's technical claims and recommendations against verified state-of-the-art knowledge as of March 2026.

### Verified Accurate

1. **Ratatui's constraint-based layout** — verified. Ratatui uses Cassowary via the `kasuari` crate (Rust port of the C++ Kiwi library). Supports `Length`, `Percentage`, `Ratio`, `Min`, `Max`, `Fill` constraints with priority-based conflict resolution.

2. **Ink's Flexbox via Yoga** — verified. Full Yoga-based flexbox with `flexDirection`, `justifyContent`, `alignItems`, padding, margin. Used by GitHub Copilot CLI, Gatsby, Prisma.

3. **FTXUI's decorator pattern** — verified. `element | bold | border | color(Color::Blue)` reads naturally. Three-layer architecture (screen, DOM, component).

4. **Bubbletea's Elm Architecture** — verified. Model → Update → View with message passing. No built-in layout engine; layout via Lipgloss string composition.

5. **SwiftUI's Layout protocol** — verified. Two-phase measure-place (`sizeThatFits` + `placeSubviews`) introduced in iOS 16/WWDC22. This maps directly to terminal UI layout where all dimensions are integer character cells.

6. **The ADR's decision to evolve the current framework rather than replace the renderer** is well-reasoned. The existing `ScreenBuffer` + specialized leaf renderers pattern provides good performance.

7. **The recommendation to migrate shell chrome first** (status bar, activity bar, sidebar panes, overlays) before the editor core is the standard adoption strategy.

### Requires Qualification

1. **"Constraint-based layout solver (Cassowary)"** (point 1) — **Likely over-engineered for a terminal editor**. Cassowary solves simultaneous linear constraints, which is powerful but complex to debug. SwiftUI's simpler measure-place protocol is sufficient for most terminal layouts and easier to reason about. Ratatui uses Cassowary successfully, but terminal UIs rarely have the kind of mutual constraint dependencies that justify a full solver. The simpler approach: measure-place with explicit constraint types (`fixed`, `min`, `max`, `flexible`, `ratio`) handled by container-specific logic rather than a general solver. Reserve Cassowary for cases where the simpler approach proves insufficient.

2. **"Animation primitives with frame-rate-limited rendering"** (point 3) — **Genuine differentiator but needs careful scope**. No terminal UI framework currently supports declarative animations. The claim is accurate as a differentiator. However, terminal animation is constrained by terminal emulator throughput (not all terminals handle 30fps well). The animation loop should be adaptive: detect terminal capabilities and reduce frame rate for slower terminals. Also, most of the listed use cases (smooth sidebar resize, tab slide-in, cursor blink, smooth scroll) provide marginal UX benefit in a terminal context vs. the implementation cost.

3. **"Accessibility layer with semantic annotations"** (point 4) — **Forward-looking but currently limited in practice**. VoiceOver on macOS can interact with terminal text, but terminal accessibility is fundamentally constrained by the character grid model. The recommendation to annotate views from day one is architecturally sound (ensures the structure is ready), but the practical benefit is limited until terminal emulators advance their accessibility support. The ADR should note this honestly.

4. **"Concrete TupleView codegen to eliminate Mirror reflection"** (point 5) — **Correct diagnosis and solution**. Swift parameter packs (SE-0393, SE-0398, Swift 5.9+) provide a cleaner solution than generating TupleView2..TupleView10 manually. The ADR mentions parameter pack iteration as an alternative. As of Swift 5.9/6.0, `repeat each` syntax can iterate parameter packs, potentially avoiding the need for arity-specific overloads. However, parameter pack support for stored properties has limitations — the codegen approach may still be needed as a fallback.

5. **"Retained-mode virtual view tree with structural diffing"** (point 6) — **Significant complexity increase over the current approach**. The ADR correctly notes that terminal UIs are small enough that full traversal is often fast enough (in the "View Identity and Invalidation" section). The retained-mode diffing recommendation in the SOTA section contradicts this pragmatic observation. For a terminal editor, immediate-mode rendering with cell-level diffing (which KittyCode already has via `RenderPipeline`) is likely sufficient. The structural diffing layer should be added only if profiling shows the full traversal is a bottleneck — not as a default architectural choice.

6. **"Full EnvironmentValues propagation with type-safe keys"** (point 2) — **Sound but note the simpler alternative the ADR itself proposes**. The codebase impact section wisely suggests "extending `RenderContext` with additional fields is simpler than building a full `EnvironmentValues` system." The SOTA section then recommends the full system. The pragmatic path is to start with extended `RenderContext` and only introduce a generic key-value environment if the field count exceeds maintainability (>15-20 fields).

### References

- Ratatui layout concepts: https://ratatui.rs/concepts/layout/
- Kasuari (Cassowary for Rust): https://github.com/ratatui/kasuari
- Cassowary algorithm paper (Badros, Borning, Stuckey, 2001): https://constraints.cs.washington.edu/solvers/cassowary-tochi.pdf
- Kiwi C++ implementation: https://github.com/nucleic/kiwi
- Ink repository: https://github.com/vadimdemedes/ink
- FTXUI repository: https://github.com/ArthurSonzogni/FTXUI
- Bubbletea repository: https://github.com/charmbracelet/bubbletea
- SwiftUI Layout protocol: https://developer.apple.com/videos/play/wwdc2022/10056/
- Swift parameter packs (SE-0393): https://github.com/swiftlang/swift-evolution/blob/main/proposals/0393-parameter-packs.md
