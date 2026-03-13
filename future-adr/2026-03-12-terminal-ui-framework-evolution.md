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
