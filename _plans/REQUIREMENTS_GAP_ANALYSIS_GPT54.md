# KittyTUI Initial Requirements Drift And Gap Report

Date: 2026-03-10

## Scope

This report compares the current repository state against the original KittyTUI implementation plan.

Review lenses used:

- system architecture and layer boundaries
- Swift module/package design
- Swift 6 concurrency posture
- TDD and test coverage alignment
- Kitty protocol feature coverage

Repository evidence used:

- `Package.swift`
- `Sources/**/*`
- `Tests/**/*`
- `Demo/main.swift`
- build and test results from:
  - `swift build --scratch-path /tmp/.build-kittytui`
  - `swift test --scratch-path /tmp/.build-kittytui`

## Executive Summary

The codebase is materially ahead of the original plan in breadth: all planned library targets exist, the lower terminal/codec/parser/query stack is real, and the full test suite currently passes. However, the project still drifts from the original requirements in several important ways:

1. The architectural shape exists, but the layering is not being preserved consistently in source code. Higher layers and executables import lower layers directly, bypassing the intended convergence points.
2. The parser/highlighting stack is implemented mostly as code, but not as a shipped end-to-end language system. The repository contains `languages.json`, but no bundled `grammar.json` or `highlights.scm` assets, so the stated 165+ language goal is not actually delivered.
3. Incremental parsing, tree reuse, error recovery, widget rendering, widget event routing, `@State`, and app/view integration are still partial or skeletal relative to the plan.
4. The demo and app shell do not yet validate the intended product. The current `Demo` bypasses the widget layer and manually renders to the screen buffer instead of demonstrating the planned file browser + syntax viewer + status bar app.
5. The codebase added an extra product, `KittyCode`, which is not part of the original requirements and creates a second integration path that competes with the planned layered framework story.
6. TDD and test discipline are strongest in the lower layers. Test depth drops sharply in widgets and app integration, exactly where the project still has the most missing behavior.

In short: the foundation is real, but the project is still short of the original promised product, especially around shipped grammar assets, true incremental parsing, declarative widgets, and clean application-layer integration.

## Current State Snapshot

## Build And Test Health

- `swift build --scratch-path /tmp/.build-kittytui` succeeds.
- `swift test --scratch-path /tmp/.build-kittytui` succeeds.
- The Swift Testing run reports 135 passing tests across 43 suites.

This is a strong signal that the current code is internally coherent. It is not evidence that all planned requirements are complete.

## Actual Module Inventory

Implemented source targets present under `Sources/`:

- `KittyTerminal`
- `KittyCodecs`
- `KittyInput`
- `KittyRenderer`
- `KittyGrammar`
- `KittyParser`
- `KittyQuery`
- `KittySyntax`
- `KittyWidgets`
- `KittyApp`
- `KittyCode` (extra, not in the original plan)

Test targets present under `Tests/`:

- `KittyTerminalTests`
- `KittyCodecsTests`
- `KittyInputTests`
- `KittyRendererTests`
- `KittyGrammarTests`
- `KittyParserTests`
- `KittyQueryTests`
- `KittySyntaxTests`
- `KittyWidgetsTests`
- `KittyAppTests`
- `KittyCodeTests` (extra, not in the original plan)

This means the repository did not stall at scaffolding. The drift is not "nothing was built". The drift is "major promised behaviors are still only partially realized".

## Where The Code Still Aligns With The Plan

Several core commitments from the original requirements are already visible and credible:

- Pure Swift modular package structure exists in `Package.swift`.
- No external Swift package dependencies are declared in `Package.swift`.
- Layered targets are present and generally named as planned.
- Kitty terminal foundations exist in `Sources/KittyTerminal/`.
- Core codecs exist in `Sources/KittyCodecs/`.
- Renderer buffer/diff pipeline exists in `Sources/KittyRenderer/`.
- Grammar loader, parse-table compiler, parser, query parser/matcher, and theme/highlighter code all exist.
- `RawModeGuard` is implemented as `~Copyable` in `Sources/KittyTerminal/RawModeGuard.swift`.
- Tests use Swift Testing, not XCTest, across all test files.
- Kitty-specific protocol handling is implemented for keyboard, mouse, synchronized output, notifications, clipboard, and graphics encoding at least at API level.

So the project has real substance. The main issue is mismatch between the existing internal framework pieces and the fully integrated product promised by the initial spec.

## High-Level Drift Assessment

## Phase-By-Phase Status

| Phase | Planned Outcome | Current Status | Assessment |
| --- | --- | --- | --- |
| 1. Foundation | terminal types, connection, raw mode | implemented | largely aligned |
| 2. Codecs | SGR, keyboard, mouse, graphics, sequences | implemented | mostly aligned, some protocol/test gaps |
| 3. Input + Rendering | input stream, signals, buffers, diff, pipeline | implemented | mostly aligned |
| 4. Grammar | grammar loading and table compilation | implemented | aligned in code, not in shipped grammar assets |
| 5. Parser Engine | GLR, error recovery, incremental subtree reuse | partial | parser exists, incrementality and recovery are reduced |
| 6. Query System | parser, matcher, predicates, cursor | partial to strong | main pieces exist, but cursor/range support is narrower than planned |
| 7. Syntax Highlighting | theme, registry, registry-driven highlighting | partial | theme/highlighter exist, but no bundled grammars or query files |
| 8. Widgets | declarative view system, state, layout, event routing, widgets | partial | APIs exist, runtime behavior is mostly not there |
| 9. Application | app protocol, runtime, cleanup, demo app | partial | runtime exists, app/widget integration and demo scope drifted |

## Most Important Persistent Drift

### 1. The source code no longer respects the clean layer convergence promised in the plan

The plan said the two stacks would converge at Layer 4 (`KittyWidgets`) and then Layer 5 (`KittyApp`). The manifest mostly models that intention, but the source code bypasses it.

Examples:

- `Sources/KittyApp/ApplicationRuntime.swift` imports `KittyTerminal`, `KittyCodecs`, `KittyInput`, `KittyRenderer`, and `KittyWidgets` directly.
- `Sources/KittyApp/App.swift` imports lower layers directly as well.
- `Sources/KittySyntax/Highlighter.swift` imports `KittyGrammar`, `KittyParser`, and `KittyQuery` directly instead of acting as a narrow integration facade.
- `Demo/main.swift` imports `KittyWidgets`, `KittyCodecs`, `KittyInput`, `KittyRenderer`, and `KittyTerminal` directly, even though the executable target is declared as depending on `KittyApp`.
- `Sources/KittyCode/` imports and uses lower layers directly across many files.

Impact:

- The manifest presents a cleaner dependency graph than the code actually enforces.
- App-level code can couple itself to low-level implementation details.
- The framework is harder to evolve behind stable module boundaries.
- The original "two stacks converge at widgets" design is no longer the dominant integration model.

### 2. The project has code for syntax highlighting, but not a shipped grammar ecosystem

This is one of the largest gaps versus the original requirements.

Planned:

- tree-sitter-compatible `grammar.json`
- bundled `highlights.scm`
- runtime grammar registry
- 165+ language compatibility by copying grammar assets

Actual evidence:

- `Sources/KittySyntax/Grammars/languages.json` exists.
- No bundled `Sources/KittySyntax/Grammars/<language>/grammar.json` files exist.
- No bundled `highlights.scm` files exist.
- `GrammarRegistry` in `Sources/KittySyntax/GrammarRegistry.swift` can load a manifest and build a path to `grammar.json`, but there are no bundled grammar payloads to satisfy that contract.
- `Highlighter` in `Sources/KittySyntax/Highlighter.swift` requires the caller to provide a pre-built `SyntaxTree` and `Query`; it does not yet deliver the planned end-to-end registry + parser + query pipeline.

Impact:

- The repository currently demonstrates parser/highlighter mechanics, not actual 165+ language support.
- Syntax highlighting is not shippable as described because the required language assets are absent.
- The headline extensibility story is currently aspirational, not implemented.

### 3. Incremental parsing is still mostly a placeholder

The original plan made incremental subtree reuse one of the project's core architectural bets.

Actual evidence in `Sources/KittyParser/IncrementalParser.swift`:

- `parse(_:oldTree:edit:)` currently delegates to a full parse.
- The file explicitly states: "For now, delegate to full parse. Incremental optimization can be added later".
- Tree edit range shifting exists as `SyntaxTree.applying(edit:)`, but subtree reuse is not actually wired into parse execution.

Impact:

- The project does not yet meet the requirement for near-zero reparse cost on small edits.
- The parser layer is present, but one of its most important promised product qualities is still missing.

### 4. Error recovery is present only in reduced inline form, not as the planned subsystem

Planned:

- dedicated `ErrorRecovery.swift`
- insert `ERROR` nodes
- skip to valid tokens
- resume parse for editor-like broken code scenarios

Actual:

- There is no `Sources/KittyParser/ErrorRecovery.swift`.
- In `Sources/KittyParser/GLRParser.swift`, unexpected tokens are handled inline by pushing `ERROR` nodes and continuing.

This is better than having no recovery, but it is materially simpler than the planned recovery subsystem.

Impact:

- Broken-code editor scenarios are likely less robust than intended.
- The recovery behavior is not independently testable or architecturally isolated the way the plan described.

### 5. The widget system is mostly a type-level facade, not the planned rendering/event/state framework

This is the biggest gap in the top half of the stack.

Evidence:

- `Sources/KittyWidgets/View.swift` defines `View`, `Text`, `EmptyView`, and `StyledTextView`, but leaf `body` implementations are `fatalError()` placeholders.
- `Sources/KittyWidgets/Layout.swift` defines `VStack`, `HStack`, and `ZStack`, but all `body` implementations are `fatalError()` placeholders.
- `Sources/KittyWidgets/TextEditor.swift`, `Sources/KittyWidgets/TreeView.swift`, and `Sources/KittyWidgets/StatusBar.swift` all expose data structures and helpers but still use `fatalError()` for `body`.
- `Sources/KittyWidgets/ViewBuilder.swift` and `Sources/KittyWidgets/ViewModifier.swift` provide builder/modifier scaffolding, but there is no actual widget render pipeline behind them.
- No `Sources/**/*State.swift` exists.
- No `onKeyPress`, `onMouse`, or `.border()` APIs are present in `Sources/KittyWidgets/` despite being called out in the plan.

Impact:

- The declarative widget system is not yet an actual UI runtime.
- The plan's Layer 4 convergence point is present as API shape, but not as full behavior.
- The current application code cannot really rely on the widget layer to render the planned interface.

### 6. The `App` abstraction is not driving UI composition the way the plan described

Planned:

- `App` protocol with root view body
- application runtime orchestrates lifecycle around the widget tree

Actual evidence:

- `Sources/KittyApp/App.swift` defines the `App` protocol.
- `Sources/KittyApp/ApplicationRuntime.swift` provides callback-based rendering and event handling.
- `run<A: App>(_:)` in `ApplicationRuntime` simply instantiates `A()` and then calls `run(render: { _ in }, onEvent: ...)`.
- The app body is not rendered into a widget tree.

Impact:

- The declarative app model exists in API form only.
- The current runtime is really a lower-level callback shell, not the planned app/widget integration layer.

### 7. The demo does not validate the intended product

Planned demo:

- file browser on the left
- syntax viewer on the right
- status bar
- demonstration of tree view + syntax highlighting

Actual `Demo/main.swift`:

- manually writes directly into `RenderPipeline.buffer`
- imports low-level modules directly
- shows feature bullets and simple mouse/key telemetry
- does not use `TreeView`, `TextEditor`, or `StatusBar`
- does not load grammar/query assets or demonstrate a syntax viewer

Impact:

- The demo proves the terminal stack works.
- It does not prove the planned toolkit product exists.

### 8. A second product, `KittyCode`, has appeared and changes the center of gravity of the repo

The original plan defined the package as a toolkit plus a demo executable. The repository now also contains:

- product `KittyCode` in `Package.swift`
- source tree `Sources/KittyCode/` with 20 files
- test target `Tests/KittyCodeTests/`

This is not inherently bad, but it is drift.

Why it matters:

- It introduces a new product not mentioned in the original requirements.
- It creates pressure to solve app/editor needs directly in `KittyCode` instead of completing the framework abstractions first.
- It increases the chance that lower-level rendering/input gets used directly instead of through `KittyWidgets` and `KittyApp`.

## Missing Planned Components

The following planned items are missing entirely or only exist in reduced form.

## Missing Files Or Missing Dedicated Modules

| Planned Item | Current State | Notes |
| --- | --- | --- |
| `Sources/KittyWidgets/State.swift` | missing | no `@State` system or TaskLocal render context found |
| `Sources/KittyParser/ErrorRecovery.swift` | missing | reduced inline logic exists in `GLRParser.swift` |
| `Sources/KittyParser/ParseStack.swift` | missing as standalone file | `ParseStack` is nested inside `GLRParser.swift` |
| `Sources/KittyParser/TreeEdit.swift` | missing as standalone file | text edit support is embedded in `IncrementalParser.swift` extension |
| `Sources/KittySyntax/StyledTextProducer.swift` | missing | only `StyledSpan` and `Highlighter` exist |
| `Sources/KittyApp/SignalCleanup.swift` | missing | cleanup relies on runtime `defer`, not a dedicated component |

These are not just naming differences. In several cases, the missing file corresponds to missing or reduced behavior.

## Missing Behavioral Requirements

### Widget state and hydration

Missing evidence for:

- `@State`
- TaskLocal render context
- hydration/reconciliation model

### Event routing model

The plan described:

- hot keys
- focused widget
- cold keys
- bubbling via `EventResult`

Actual state:

- `EventResult` exists in `Sources/KittyWidgets/View.swift`
- no routing engine that connects it to widgets was found
- no `.onKeyPress()` or `.onMouse()` modifier APIs were found

### Real widget rendering/layout engine

Missing evidence for:

- rendering `View` trees into `ScreenBuffer`
- layout resolution from `ProposedSize` to actual placement
- widget focus model
- mouse hit-testing and dispatch into widgets

### End-to-end syntax highlighting workflow

Missing evidence for:

- grammar discovery from bundled resources
- highlight query loading from `.scm`
- file-extension driven parse + query + theme integration
- actual language asset population

### Demo acceptance criteria

Missing evidence for:

- file browser widget on left
- syntax viewer widget on right
- status bar driven through widget abstraction

## Kitty Protocol Coverage Drift

## What Is Implemented

In `Sources/KittyCodecs/KittySequences.swift` and related codec files, the repo has support for:

- synchronized output (`?2026`)
- keyboard protocol (`CSI u`)
- SGR mouse (`1006`)
- pixel mouse enable/disable sequences (`1016`)
- clipboard write/request
- notifications (`OSC 99`)
- alternate screen, cursor hide/show, bracketed paste, focus events

## Gaps And Drift In Protocol Coverage

### 1. Clipboard protocol mismatch

The original requirements listed clipboard as `OSC 5522`. The implementation in `Sources/KittyCodecs/KittySequences.swift` uses `OSC 52`.

This may be an intentional standardization choice, but it is still drift from the explicit initial requirement text and should be reconciled.

### 2. Mouse pixel mode is implemented at codec level but not used as an app capability

- `KittySequences.enableMousePixel` exists.
- `MouseDecoder` documents 1006 and 1016 handling.
- `ApplicationRuntime` enables `KittySequences.enableMouseSGR`, not pixel mode.

This means pixel-mode support exists as low-level capability, but not as an integrated runtime feature.

### 3. Pointer shapes support is missing

The requirements listed `OSC 22` mouse pointer shapes as nice-to-have.

No implementation or test evidence for pointer-shape support was found.

### 4. Graphics support exists, but validation is weak

`Sources/KittyCodecs/GraphicsEncoder.swift` exists, but no direct tests for `GraphicsEncoder` were found in `Tests/KittyCodecsTests/CodecsTests.swift`.

That does not mean it is broken, but it does mean a stated must-have protocol is currently less verified than keyboard/mouse/SGR behavior.

### 5. Clipboard and notifications are present but not visibly exercised

No direct tests were found for:

- `setClipboard`
- `requestClipboard`
- `notify`

Again, the APIs exist, but the verification story is thinner than the plan implied.

## Swift 6 Concurrency Alignment

## What Aligns

- The package uses `// swift-tools-version: 6.0`.
- `Sendable`, `AsyncStream`, `Task`, and `@MainActor` are used throughout the codebase.
- `ApplicationRuntime` is marked `@MainActor`.
- The code mostly prefers value types for domain models.

## What Still Gaps Or Drifts

### 1. No explicit strict-concurrency package settings were found

`Package.swift` contains no `swiftSettings`, no strict concurrency flags, and no explicit default actor isolation settings.

Implication:

- The project targets Swift 6 syntax/tooling, but does not visibly codify the strict concurrency posture promised by the plan.

### 2. Several core runtime classes rely on `@unchecked Sendable`

Found in:

- `Sources/KittyRenderer/RenderPipeline.swift`
- `Sources/KittyTerminal/POSIXTerminalConnection.swift`
- `Sources/KittyTerminal/MockTerminalConnection.swift`
- `Sources/KittySyntax/GrammarRegistry.swift`

This is not automatically wrong, but it is a sign that the current concurrency design still depends on trust boundaries rather than fully proven isolation.

### 3. Some classes are declared `Sendable` with mutable internals and no explicit actor isolation

Examples:

- `InputSource`
- `SignalHandler`
- `GLRParser`
- `IncrementalParser`

This may still be safe based on usage, but the package is not yet making its isolation strategy as explicit as the original "Swift 6 strict concurrency" requirement suggested.

### 4. Crash/signal cleanup is not as explicit as planned

The plan called out a dedicated cleanup component. The runtime has a `defer` block and a signal handler, which covers normal shutdown reasonably well, but there is no dedicated `SignalCleanup.swift` or explicit crash-hardening story beyond best-effort cleanup.

## TDD And Test Strategy Assessment

## Where The Project Is Strong

The lower layers are genuinely well covered for a greenfield framework:

- `KittyCodecsTests` are relatively deep and include parameterized edge-case coverage.
- `KittyGrammarTests` cover grammar loading and parse-table concerns with good algorithmic focus.
- `KittyParserTests` cover syntax tree basics, lexer behavior, GLR conflict handling, and edit shifting.
- `KittyQueryTests` and `KittySyntaxTests` cover matcher/highlighter mechanics.
- All tests use Swift Testing.

This is a credible TDD-shaped repository, especially in layers 0 through 3.

## Where The Test Story Still Falls Short Of The Plan

### 1. Widget tests are shallow relative to missing behavior

`Tests/KittyWidgetsTests/WidgetsTests.swift` mainly verifies:

- construction
- simple helper behavior
- visible row flattening
- fixed-width status bar text

It does not verify:

- rendering view trees into buffers
- real layout placement
- focus management
- event dispatch and bubbling
- `@State` behavior
- mouse/keyboard modifiers on widgets

This matches the implementation gap.

### 2. App tests validate setup, not the intended app model

`Tests/KittyAppTests/AppTests.swift` verifies app creation and setup sequence presence, but not:

- view-tree rendering from `App.body`
- widget integration
- teardown correctness under multiple shutdown scenarios
- signal cleanup robustness

### 3. Syntax tests are synthetic, not asset-driven

`Tests/KittySyntaxTests/SyntaxTests.swift` validates themes and highlighter behavior using hand-built trees and queries.

It does not validate:

- bundled grammar loading
- bundled query loading
- file-extension registry flow
- end-to-end highlighting from source file to styled spans using repository assets

### 4. Incremental parser tests do not prove subtree reuse

`Tests/KittyParserTests/ParserTests.swift` confirms that `IncrementalParser` produces a tree, but it does not prove incremental reuse, which makes sense because the implementation does not yet perform reuse.

### 5. Graphics and nice-to-have protocol features are under-tested

No direct tests were found for:

- graphics encoding
- clipboard helpers
- notification helpers
- pointer-shape support (also missing in implementation)

## Requirement-By-Requirement Gap Matrix

## Package And Product Shape

| Requirement | Status | Notes |
| --- | --- | --- |
| from-scratch Swift toolkit | met | code is custom and modular |
| zero external dependencies | met | no package deps declared |
| demo executable | partial | executable exists, but not the planned demo |
| only planned products | drifted | extra `KittyCode` product added |

## Layering And Architecture

| Requirement | Status | Notes |
| --- | --- | --- |
| clean layer graph | partial | manifest matches plan better than source imports do |
| terminal and parser stacks independent until widgets | partial | conceptually true in target graph, bypassed in source code |
| widgets as convergence point | partial | APIs exist, but current integration often skips them |

## Parser / Query / Syntax

| Requirement | Status | Notes |
| --- | --- | --- |
| grammar.json loader/compiler | met | present |
| GLR parser | met/partial | parser exists, but some planned modularity reduced |
| incremental subtree reuse | missing/partial | currently full parse fallback |
| query parser/matcher | met | present |
| grammar registry with bundled assets | partial | registry exists, assets absent |
| 165+ language support | missing | no bundled grammar/query assets |

## Widgets / App / Demo

| Requirement | Status | Notes |
| --- | --- | --- |
| declarative view system | partial | type-level API exists |
| layout engine | partial | container types exist, no full render/layout runtime |
| `@State` support | missing | no evidence found |
| key and mouse modifiers on views | missing | no APIs found |
| tree view widget | partial | data/model helper exists |
| text editor widget | partial | model/helper exists |
| status bar widget | partial | string renderer exists |
| app lifecycle shell | partial | callback runtime exists, app-body rendering absent |
| file browser + syntax viewer demo | missing | current demo is a feature showcase, not the planned app |

## Specific Gaps By Planned Layer

## Layer 0 - KittyTerminal

Status: largely aligned

What is good:

- `TerminalConnection` exists.
- `POSIXTerminalConnection` exists.
- `RawModeGuard` exists and uses `~Copyable`.
- terminal size querying via manual Darwin constant is implemented.

Remaining gaps:

- No dedicated terminal cleanup component at app layer.
- Linux intent exists via `#if canImport(Glibc)`, but Linux build/test verification is not present in repo automation.

## Layer 1 - KittyCodecs

Status: mostly aligned

What is good:

- `SGREncoder`, `KeyboardDecoder`, `MouseDecoder`, `GraphicsEncoder`, and `KittySequences` all exist.
- keyboard and mouse edge cases are well tested.

Remaining gaps:

- clipboard protocol implementation differs from the requirement text.
- graphics/clipboard/notification coverage is thinner.
- pointer-shape support is absent.

## Layer 2a - KittyInput

Status: mostly aligned

What is good:

- `SequenceRouter`, `InputSource`, `SignalHandler`, and `InputEvent` exist.
- async event stream architecture is present.

Remaining gaps:

- no evidence that input routing is connected into widget-level event bubbling.

## Layer 2b - KittyRenderer

Status: aligned to partial

What is good:

- `Cell`, `ScreenBuffer`, `DirtyTracker`, `DiffRenderer`, `RenderPipeline` exist.
- diff and pipeline tests are present.

Remaining gaps:

- renderer is being used directly by demo/app code instead of sitting behind a completed widget render system.

## Layer 3a - KittyGrammar

Status: aligned in code, incomplete in deliverable value

What is good:

- grammar definitions, loading, item sets, parse tables, lex tables, keyword extraction all exist.

Remaining gaps:

- no bundled grammar assets to validate real language loading at scale.

## Layer 3b - KittyParser

Status: partial

What is good:

- syntax tree/node types exist.
- lexer and GLR parser exist.
- basic conflict handling exists.

Remaining gaps:

- standalone error recovery subsystem missing.
- standalone parse stack module missing.
- incremental subtree reuse not implemented.

## Layer 3c - KittyQuery

Status: partial to strong

What is good:

- parser, patterns, matcher, predicates, cursor exist.

Remaining gaps:

- `QueryCursor` supports byte range only, not the planned byte/point range story.
- no real bundled `.scm` files are present to prove compatibility on actual languages.

## Layer 3d - KittySyntax

Status: partial

What is good:

- theme model exists.
- grammar registry exists.
- highlighter exists.

Remaining gaps:

- no bundled grammars or highlight queries.
- no `StyledTextProducer.swift`.
- `Highlighter` is lower-level than planned and does not yet own the full workflow.

## Layer 4 - KittyWidgets

Status: materially incomplete

What is good:

- API vocabulary exists.
- view builder and some helper logic exist.

Remaining gaps:

- rendering runtime
- state system
- event routing
- focus system
- actual widget-body execution model

## Layer 5 - KittyApp

Status: partial

What is good:

- terminal lifecycle callback runtime exists.
- raw mode, alternate screen, and cleanup are handled on normal execution paths.

Remaining gaps:

- app body does not drive render output.
- widget integration is not complete.
- dedicated signal cleanup component missing.

## Workflow And Delivery Process Gaps

The original requirements included a fairly detailed multi-branch delegation workflow and validation discipline.

Repository evidence today:

- no `TASK.md` files are present
- no `.github/` automation was found
- no CI workflows were found
- no in-repo artifacts enforce branch-per-module workflow

This does not prove the workflow was ignored outside the repo, but it does mean the collaboration plan is not institutionalized in the codebase itself.

Practical gap:

- there is no automated guarantee that Linux builds, module-specific tests, or merge-order discipline are being enforced.

## What Is Missing Most Critically

If the question is "what is still missing to honestly claim the original project goals are met?", the answer is:

1. Real bundled language assets: actual `grammar.json` and `highlights.scm` resources, not just `languages.json`.
2. True incremental parsing with subtree reuse.
3. A completed widget runtime: layout, rendering, focus, event dispatch, and state.
4. Real `App` to widget-tree integration.
5. A demo that uses `TreeView`, `TextEditor`, and `StatusBar` to show the intended file browser + syntax viewer product.
6. Cleanup of layer-boundary drift so the package architecture matches how the code is actually used.
7. Stronger verification around graphics, clipboard, notifications, and end-to-end syntax loading.

Without those, the repository is a strong foundation and a promising prototype framework, but not yet the full toolkit described in the initial plan.

## Recommended Remediation Order

### Priority 1 - Finish the missing value path, not just the missing files

Complete the end-to-end path:

- bundle at least one real grammar and highlight query pair
- make `GrammarRegistry` load from bundled resources
- make `Highlighter` own parse + query + theme flow for a real file
- prove it in tests and in the demo

This closes the largest gap between the current code and the promised product story.

### Priority 2 - Implement real incremental parsing

`IncrementalParser` is currently the clearest example of a major promised capability that still falls back to a simplified implementation. This should be made real before calling the parser stack complete.

### Priority 3 - Turn `KittyWidgets` from API facade into runtime

Implement:

- render tree traversal
- layout resolution
- focus and event routing
- state storage / hydration
- widget-to-buffer rendering

Until this exists, the framework's top-level design is still mostly declarative surface area without an engine behind it.

### Priority 4 - Reconnect `KittyApp` to the widget model

Make `App.body` actually render, and make the runtime operate on widget trees rather than ad hoc callback rendering.

### Priority 5 - Bring the demo back in line with the original acceptance target

Replace the current low-level showcase with:

- file tree pane
- syntax-highlighted viewer pane
- status bar
- real widget usage

### Priority 6 - Clean up architecture drift and product scope drift

- reduce direct lower-layer imports from `Demo`, `KittyApp`, and `KittyCode`
- decide whether `KittyCode` is part of the product vision or an out-of-scope experiment
- if it stays, clearly define whether it is a consumer of the toolkit or a parallel codepath

### Priority 7 - Codify delivery and verification

- add CI
- run full build/test automatically
- add Linux verification if Linux support is still a requirement
- add resource-based syntax tests and runtime integration tests

## Bottom Line

The repository has a solid lower-level implementation and passes its current tests. It is not empty, and it is not just scaffolding. But the project still materially drifts from the original requirements in the exact areas that define the user-visible product:

- shipped multi-language syntax support
- true incremental parsing
- a functioning declarative widget system
- app/widget integration
- the intended demo experience

Today, the codebase is best described as:

- a strong modular foundation for Kitty terminal I/O, codecs, rendering, grammar loading, parsing, and query matching
- a partial syntax framework without bundled language assets
- a partial widget/app layer with incomplete runtime behavior
- an expanded repo scope due to `KittyCode`

It is not yet accurate to say the full original KittyTUI plan has been delivered.
