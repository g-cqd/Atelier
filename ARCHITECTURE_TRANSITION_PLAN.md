# Architecture Transition Plan

## Status

- Date: 2026-03-11
- Scope: migrate `KittyCode` from a mixed executable-plus-domain target to a thin application shell backed by reusable domain modules
- Context: brownfield refactor with migration characteristics
- Tailoring:
  - uncertainty: medium
  - dependency density: high
  - regulatory burden: none
  - work arrival mode: batched, with interrupt-driven bug fixes allowed only for active blockers
- Planning stance: phased migration with rolling-wave detail, WIP-limited execution, and per-phase go/no-go gates

## Objective

Move component, logic, and utilities that do not belong in the `KittyCode` executable target into narrower domain modules so the package follows SOLID, DRY, KISS, and the Law of Demeter more consistently.

The end state is:

1. `KittyCode` owns application composition, layout decisions, terminal-specific interaction wiring, and editor-specific UX policy.
2. Domain targets own reusable state, services, and primitives.
3. New work such as large-file mode, alternate editor shells, or additional TUI apps can build on extracted modules without depending on `KittyCode`.

## Why This Plan

- Reduce WIP and keep one major extraction stream active at a time for predictability. [Strong][E-01]
- Migrate in small vertical slices rather than big-bang moves to reduce integration risk. [Strong][E-04][E-06]
- Introduce stable boundaries before moving code to reduce coordination and coupling cost. [Moderate-Strong][E-17][E-18]
- Use rolling-wave planning because the target architecture is clear, but hidden coupling is still being discovered. [Strong][E-27]
- Treat every phase exit as a quality gate, not just a code motion checkpoint. [Strong-Moderate][E-05]

## Current State Summary

`KittyCode` currently owns too many responsibilities:

1. Editor and workspace state:
   - `Sources/KittyCode/EditorStateCore.swift`
   - `Sources/KittyCode/BufferManager.swift`
   - `Sources/KittyCode/DocumentBuffer.swift`
2. File lifecycle and synchronization:
   - `Sources/KittyCode/EditorStateFileSystem.swift`
   - `Sources/KittyCode/FileWatcher.swift`
   - `Sources/KittyCode/FileWatcherIntegration.swift`
   - `Sources/KittyCode/AutoSaveManager.swift`
3. Git orchestration:
   - `Sources/KittyCode/GitDecorationManager.swift`
   - `Sources/KittyCode/GitRefreshManager.swift`
4. Reusable rendering and widget-like primitives:
   - `Sources/KittyCode/RenderOverlay.swift`
   - `Sources/KittyCode/StatusBarContent.swift`
5. Generic runtime invalidation:
   - `Sources/KittyCode/RenderRefreshSource.swift`

This is the main structural problem, not a lack of existing targets. `Package.swift` already contains most of the destination modules.

## Target Architecture

### 1. `KittyCode`

Keep only application-shell concerns:

- `AppMain.swift`
- high-level rendering composition such as `Render.swift`, `RenderEditor.swift`, `RenderTree.swift`, `RenderOpenFiles.swift`, `RenderActivityBar.swift`
- input routing such as `EventHandling.swift`, `EditorInput.swift`, `TreeInput.swift`, `MouseInput.swift`
- editor-specific UX policy such as which prompt opens when, which status text is shown, and which panel is visible
- shell-only layout such as `LayoutMetrics.swift`

`KittyCode` should not own durable document state, file synchronization services, git refresh loops, or reusable widget primitives.

### 2. `KittyWorkspace` (new target)

Create a new domain target for editor/workspace state and services:

- workspace session state
- document/tab management
- file open/save/reload orchestration
- auto-save orchestration
- file watcher integration
- syntax highlight post-load orchestration
- git decoration refresh coordination
- tree selection and open-document coordination where it is not UI-specific

Recommended anchor types:

- `WorkspaceSession`
- `WorkspaceDocument`
- `WorkspaceBufferStore`
- `WorkspaceFileService`
- `WorkspaceGitService`
- `WorkspaceTreeState`

### 3. `KittyFileTree`

Own generic filesystem primitives:

- `DirectoryScanner`
- `SecurePath`
- `FileWatcher` after extraction

The watcher should be reusable by any consumer, not just `KittyCode`.

### 4. `KittyGit`

Own repository-facing primitives and calculations:

- `GitStatusProvider`
- `GitLineDecorations`
- any generic diff/decor computation that does not need editor session knowledge

Session-specific orchestration may live in `KittyWorkspace`, but `KittyCode` should stop owning it.

### 5. `KittyWidgets`

Own reusable view primitives and layout models:

- overlay box layout and drawing
- generic prompt and menu overlay rendering primitives
- structured status-bar segments and separator policy
- existing list, tree, tab, and editor widgets

### 6. `KittyApp`

Own application-runtime utilities that are not editor-specific:

- `RenderRefreshSource`
- any future generic app invalidation or render scheduling utility

### 7. `KittyText`

Remain the home for text primitives and large-file abstractions:

- `TextBuffer`
- `TextCursor`
- `TextDocument`
- `DocumentSource`

`KittyText` should not inherit workspace policy, but it should become the foundation for the later paged/windowed document work.

## Split Proposal

This is the recommended target-level split for `Package.swift`.

### Proposed products

Add:

1. `library(name: "KittyWorkspace", targets: ["KittyWorkspace"])`

Keep existing products:

1. `KittyApp`
2. `KittyWidgets`
3. `KittyText`
4. `KittyFileTree`
5. `KittyGit`
6. `KittySyntax`
7. `KittyInput`
8. `KittyRenderer`
9. `KittySymbols`
10. `KittyCode`

### Proposed targets

Add:

1. `.target(name: "KittyWorkspace", dependencies: ["KittyText", "KittySyntax", "KittyFileTree", "KittyGit", "KittySync"], swiftSettings: defaultSwiftSettings)`

Adjust:

1. `KittyApp`
   - current intent: runtime and lifecycle
   - proposed dependencies: `["KittyWidgets", "KittyInput", "KittySync"]`
   - reason: this becomes the owner of `RenderRefreshSource`
2. `KittyFileTree`
   - keep `["KittySync"]`
   - reason: it becomes the owner of generic file watching in addition to scanning and path safety
3. `KittyCode`
   - proposed dependencies: `["KittyApp", "KittyWorkspace", "KittyInput", "KittyText", "KittyFileTree", "KittySyntax", "KittySymbols", "KittyGit"]`
   - reason: it remains the composition root while gradually reducing direct use of lower-level services

### Proposed layer order

1. Layer 0:
   - `KittySync`
2. Layer 1:
   - `KittyTerminal`
   - `KittyCodecs`
3. Layer 2:
   - `KittyInput`
   - `KittyRenderer`
   - `KittyText`
   - `KittyFileTree`
   - `KittySymbols`
   - `KittyGit`
4. Layer 3:
   - `KittyGrammar`
   - `KittyParser`
   - `KittyQuery`
   - `KittySyntax`
5. Layer 4:
   - `KittyWorkspace`
   - `KittyWidgets`
6. Layer 5:
   - `KittyApp`
7. Layer 6:
   - `KittyCode`
   - `Demo`
   - `KittySymbolsCLI`

### Proposed responsibility split by file

Move whole files:

1. `Sources/KittyCode/BufferManager.swift` -> `Sources/KittyWorkspace/BufferManager.swift`
2. `Sources/KittyCode/DocumentBuffer.swift` -> `Sources/KittyWorkspace/DocumentBuffer.swift`
3. `Sources/KittyCode/AutoSaveManager.swift` -> `Sources/KittyWorkspace/AutoSaveManager.swift`
4. `Sources/KittyCode/FileWatcher.swift` -> `Sources/KittyFileTree/FileWatcher.swift`
5. `Sources/KittyCode/FileWatcherIntegration.swift` -> `Sources/KittyWorkspace/FileWatcherIntegration.swift`
6. `Sources/KittyCode/GitDecorationManager.swift` -> `Sources/KittyWorkspace/GitDecorationManager.swift`
7. `Sources/KittyCode/GitRefreshManager.swift` -> `Sources/KittyWorkspace/GitRefreshManager.swift`
8. `Sources/KittyCode/RenderRefreshSource.swift` -> `Sources/KittyApp/RenderRefreshSource.swift`

Split files:

1. `Sources/KittyCode/EditorStateCore.swift`
   - `Sources/KittyWorkspace/WorkspaceSession.swift`
   - `Sources/KittyWorkspace/WorkspaceTreeState.swift`
   - `Sources/KittyCode/EditorShellState.swift`
2. `Sources/KittyCode/EditorStateFileSystem.swift`
   - `Sources/KittyWorkspace/WorkspaceFileService.swift`
   - `Sources/KittyWorkspace/WorkspaceFileLoading.swift`
   - `Sources/KittyWorkspace/WorkspaceFileSaving.swift`
   - shell-facing commands remain in `KittyCode`
3. `Sources/KittyCode/RenderOverlay.swift`
   - `Sources/KittyWidgets/OverlayBox.swift`
   - `Sources/KittyWidgets/MenuOverlay.swift`
   - `Sources/KittyWidgets/PromptOverlay.swift`
   - shell-specific prompt/menu composition remains in `KittyCode`
4. `Sources/KittyCode/StatusBarContent.swift`
   - `Sources/KittyWidgets/StatusBarSegment.swift`
   - `Sources/KittyWidgets/StatusBarLayout.swift` if needed
   - app-specific content assembly remains in `KittyCode`
5. `Sources/KittyCode/Config.swift`
   - defer the split until core module moves have settled

### Intentionally deferred split

Do not create a new theme or config target in the first migration pass. The first goal is to remove executable-owned domain logic, not to maximize target count.

## Explicit Dependency Rules

These rules define the optimal end state.

1. `KittyCode` may depend on `KittyApp`, `KittyWorkspace`, `KittyWidgets`, `KittyInput`, `KittyRenderer`, `KittyText`, `KittySyntax`, `KittySymbols`, `KittyFileTree`, and `KittyGit`.
2. `KittyWorkspace` may depend on `KittyText`, `KittySyntax`, `KittyFileTree`, `KittyGit`, and `KittySync`.
3. `KittyWidgets` must not depend on `KittyCode` or `KittyWorkspace`.
4. `KittyApp` must not depend on `KittyCode`.
5. `KittyFileTree` must not depend on `KittyCode`.
6. `KittyGit` must not depend on `KittyCode`.
7. No reusable target may import app-shell types like `EditorState`, `LayoutMetrics`, or app-specific prompt/menu models.
8. No service layer may mutate the render pipeline directly. Services signal state change; the shell decides when to render.

## Extraction Map

### Definite moves

1. Move `Sources/KittyCode/BufferManager.swift` to `KittyWorkspace`.
2. Move `Sources/KittyCode/DocumentBuffer.swift` to `KittyWorkspace`.
3. Split `Sources/KittyCode/EditorStateCore.swift` into:
   - `WorkspaceSession` and related domain state in `KittyWorkspace`
   - shell-only UI state in `KittyCode`
4. Split `Sources/KittyCode/EditorStateFileSystem.swift` into:
   - reusable workspace file services in `KittyWorkspace`
   - shell-only commands and UX policy in `KittyCode`
5. Move `Sources/KittyCode/FileWatcher.swift` to `KittyFileTree`.
6. Move `Sources/KittyCode/FileWatcherIntegration.swift` to `KittyWorkspace`.
7. Move `Sources/KittyCode/AutoSaveManager.swift` to `KittyWorkspace`.
8. Move `Sources/KittyCode/GitDecorationManager.swift` to `KittyWorkspace`.
9. Move `Sources/KittyCode/GitRefreshManager.swift` to `KittyWorkspace`.
10. Move `Sources/KittyCode/RenderRefreshSource.swift` to `KittyApp`.
11. Split `Sources/KittyCode/RenderOverlay.swift` into:
    - generic overlay primitives in `KittyWidgets`
    - app-specific prompt and menu assembly in `KittyCode`
12. Split `Sources/KittyCode/StatusBarContent.swift` into:
    - generic segment and separator layout in `KittyWidgets`
    - app-specific content providers in `KittyCode`

### Probable later moves

1. Split `Sources/KittyCode/Config.swift` into module-owned config domains after the new boundaries are stable.
2. Move `Sources/KittyCode/ColorOverlayConfig.swift` with the eventual theme or widget styling model rather than leaving it in the executable target.
3. Revisit whether some tree state should move from `KittyCode` into `KittyWorkspace` once the workspace model is in place.

### Keep in `KittyCode`

1. `AppMain.swift`
2. `Render.swift` and panel renderers
3. input dispatch and shell navigation
4. shell-specific prompt actions
5. editor-specific context menu choices
6. terminal-layout policy

## Transition Strategy

This refactor should be run as a strangler migration, not a rewrite.

Rules for every phase:

1. Create the receiving abstraction before moving the implementation.
2. Keep the build green after every extraction slice.
3. Preserve behavior first; improve design second.
4. Introduce compatibility shims only when needed, and delete them within one or two phases.
5. Do not combine module extraction with unrelated feature work.
6. Expand tests before moving high-coupling code.
7. Merge in small batches at least daily. [Strong-Moderate][E-04]
8. Limit active extraction work to one primary stream plus one stabilization task. [Strong][E-01][E-02]

## Phased Migration Order

This is the concrete migration sequence recommended for execution.

### Wave A: low-risk infrastructure extractions

1. Move `RenderRefreshSource` from `KittyCode` to `KittyApp`.
2. Move `FileWatcher` from `KittyCode` to `KittyFileTree`.
3. Update the package graph and tests so these moves land before the workspace split.

Purpose:

1. Validate the new dependency directions with minimal behavioral risk.
2. Reduce clutter in `KittyCode` before the higher-risk state split begins.

### Wave B: introduce `KittyWorkspace` and move document/tab primitives

1. Add the new `KittyWorkspace` target.
2. Move `BufferManager` and `DocumentBuffer`.
3. Introduce `WorkspaceSession` as the future owner of workspace state.
4. Keep `EditorState` as a compatibility facade during the first part of this wave.

Purpose:

1. Establish the new domain target before touching the highest-coupling workflows.
2. Move the simplest durable workspace types first.

### Wave C: split the current god object

1. Extract workspace-owned fields and behavior from `EditorStateCore.swift`.
2. Leave shell-only UI state in `KittyCode`.
3. Update render and input code to read narrower state surfaces.

Purpose:

1. Remove the current shared mutable center of gravity.
2. Make later service moves attach to `KittyWorkspace`, not to `EditorState`.

### Wave D: move file lifecycle services

1. Split `EditorStateFileSystem.swift` into workspace services and shell commands.
2. Move `FileWatcherIntegration`.
3. Move `AutoSaveManager`.
4. Keep behavior stable through compatibility calls until the full wave lands.

Purpose:

1. Remove persistence, reload, and watcher orchestration from the executable target.
2. Give the workspace a complete file lifecycle boundary.

### Wave E: move git workspace orchestration

1. Move `GitDecorationManager`.
2. Move `GitRefreshManager`.
3. Keep repository primitives in `KittyGit`.
4. Keep only git provider construction and presentation mapping in `KittyCode`.

Purpose:

1. Separate repository access from session coordination.
2. Make line decorations reusable for future shells.

### Wave F: move widget-like primitives

1. Split `RenderOverlay.swift`.
2. Split `StatusBarContent.swift`.
3. Add missing widget tests around layout, clipping, hit testing, and separators.

Purpose:

1. Make overlays and status-bar behavior reusable.
2. Stop using the executable target as a home for generic geometry and view logic.

### Wave G: narrow shell interfaces and normalize config ownership

1. Replace direct deep state access with read models and command surfaces.
2. Split config only after the service and state moves are stable.
3. Remove old compatibility seams.

Purpose:

1. Finish the Law-of-Demeter cleanup.
2. Prevent the new module graph from being undermined by legacy shell access patterns.

### Wave H: enable large-file architecture

1. Finish the `DocumentSource` integration on top of the new workspace boundary.
2. Add the first paged or windowed document path without reopening the executable split.

Purpose:

1. Use the new architecture for the next major capability.
2. Avoid mixing large-file architecture with early module extraction.

## Phase Plan

## Phase 0: Baseline, Safety Net, and Rules

- Goal: make refactoring safe before any boundary moves.
- Estimated solo duration: 2 to 3 days.

Work items:

1. Record the current target dependency graph and intended future graph in a short architecture note.
2. Expand focused regression coverage around tabs, overlays, status bar, tree/editor transitions, file reload, and git decorations.
3. Add a lightweight module-boundary checklist to PR/review practice.
4. Define naming conventions for extracted types so the move does not produce churn later.
5. Decide the new target name now. Recommendation: `KittyWorkspace`.

Exit criteria:

1. The intended module graph is documented.
2. Focused regression targets pass reliably.
3. The extraction naming scheme is fixed.
4. The receiving target name is fixed and will not change mid-migration.

Main risks:

1. Starting extraction before tests are deep enough.
2. Renaming types multiple times across phases.

## Phase 1: Introduce the Workspace Boundary

- Goal: add the new module and the first stable interfaces without moving most behavior yet.
- Estimated solo duration: 2 to 4 days.

Work items:

1. Add a new `KittyWorkspace` target to `Package.swift`.
2. Define the first public domain interfaces:
   - `WorkspaceSessionProtocol` or concrete `WorkspaceSession`
   - `WorkspaceDocument`
   - `WorkspaceBufferStore`
   - `WorkspaceFileService`
   - `WorkspaceGitService`
3. Move only type definitions and thin adapters first if that reduces churn.
4. Keep `EditorState` as a compatibility facade during this phase rather than deleting it immediately.
5. Make `KittyCode` talk to the new abstractions at the edges even if implementations still forward to old code.

Exit criteria:

1. `KittyWorkspace` exists and builds.
2. `KittyCode` depends on at least one workspace abstraction instead of reaching directly into all old state.
3. No reverse dependency from reusable targets back to `KittyCode`.

Main risks:

1. Creating thin wrappers that never get completed.
2. Copying the current god object into a new module without real responsibility split.

## Phase 2: Extract Document and Tab Core

- Goal: move durable document and tab state into `KittyWorkspace`.
- Estimated solo duration: 4 to 6 days.

Work items:

1. Move `BufferManager` and `DocumentBuffer` into `KittyWorkspace`.
2. Replace direct shell ownership of document snapshots with `WorkspaceDocument` ownership.
3. Split `EditorStateCore` into:
   - workspace domain state
   - shell state
4. Make renderers and input handlers consume smaller read-only views of workspace state rather than the whole session object.
5. Collapse duplicate caching behavior so `TextDocument` remains the source of truth for document snapshots where possible.

Exit criteria:

1. `KittyCode` no longer owns buffer/tab state.
2. The active document can be switched, edited, and restored through workspace APIs.
3. Focused editor and tab tests pass unchanged.

Main risks:

1. Hidden synchronization bugs between shell state and moved workspace state.
2. Accidentally keeping both `EditorState` and `WorkspaceSession` as peer sources of truth.

## Phase 3: Extract File Lifecycle and File Synchronization

- Goal: move open/save/reload/auto-save/watch behavior into domain services.
- Estimated solo duration: 4 to 5 days.

Work items:

1. Move `FileWatcher` into `KittyFileTree`.
2. Move `FileWatcherIntegration` and `AutoSaveManager` into `KittyWorkspace`.
3. Split file orchestration out of `EditorStateFileSystem.swift` into:
   - file loading
   - file saving
   - reload handling
   - syntax prewarm scheduling
4. Define service contracts:
   - `WorkspaceFileLoader`
   - `WorkspaceFileSaver`
   - `WorkspaceFileWatcherBridge`
5. Make the shell react to service outputs rather than own the workflow directly.

Exit criteria:

1. `KittyCode` no longer owns raw file watcher or auto-save logic.
2. Open/save/reload still behaves the same from the shell.
3. File watching is reusable from outside `KittyCode`.

Main risks:

1. Race conditions around watcher notifications and writes.
2. Regressions in prompt-based save flows.

## Phase 4: Extract Git-Oriented Workspace Services

- Goal: remove git refresh and decoration orchestration from the executable target.
- Estimated solo duration: 3 to 4 days.

Work items:

1. Move `GitDecorationManager` and `GitRefreshManager` into `KittyWorkspace`.
2. Define a clear workspace-facing git service boundary over `KittyGit` providers.
3. Keep repository access in `KittyGit`; keep session coordination in `KittyWorkspace`.
4. Make `KittyCode` consume decoration results and status summaries only.

Exit criteria:

1. `KittyCode` no longer owns polling or active-buffer git refresh workflows.
2. Git status and line decorations render exactly as before.
3. Git coordination is reusable for another editor shell.

Main risks:

1. Putting too much session behavior into `KittyGit` and polluting the repository layer.
2. Refresh loops becoming detached from render invalidation timing.

## Phase 5: Extract Reusable Overlay and Status-Bar Primitives

- Goal: move generic widget behavior into `KittyWidgets`.
- Estimated solo duration: 4 to 6 days.

Work items:

1. Move generic overlay box layout and drawing out of `RenderOverlay.swift`.
2. Introduce widget-level models for prompt and menu rendering that do not reference `EditorState`.
3. Move structured status-bar segment and separator logic into `KittyWidgets`.
4. Keep app-specific content assembly in `KittyCode`.
5. Add widget tests for overlay geometry, hit-testing, clipping, and separator rendering.

Exit criteria:

1. `KittyWidgets` owns overlay primitives and status-bar segment layout.
2. `KittyCode` provides data and actions, not geometry algorithms.
3. Overlay and status-bar regressions remain covered.

Main risks:

1. Accidentally moving app-specific behavior into reusable widgets.
2. Under-designing the widget API and recreating tight coupling under a new name.

## Phase 6: Narrow the Shell Surface

- Goal: make the executable target read from narrow interfaces instead of giant mutable state.
- Estimated solo duration: 3 to 5 days.

Work items:

1. Define small read models for renderers:
   - active document view
   - tab ribbon view
   - tree panel view
   - status bar view
2. Define command surfaces for input handlers:
   - editor commands
   - tree commands
   - workspace commands
3. Remove direct field-level access where render/input code reaches deep into session internals.
4. Replace Law-of-Demeter violations with targeted methods or value snapshots.

Exit criteria:

1. High-level shell code depends on narrow interfaces, not on broad mutable state bags.
2. Renderers and input handlers are easier to test in isolation.
3. Most code outside the shell no longer mentions `EditorState`.

Main risks:

1. Designing abstractions that are too generic and hurt readability.
2. Leaving enough escape hatches that old direct access patterns remain.

## Phase 7: Normalize Configuration Ownership

- Goal: align config types with the modules they configure.
- Estimated solo duration: 2 to 3 days.

Work items:

1. Split `Config.swift` into module-owned config domains only after runtime boundaries are stable.
2. Keep one top-level app config loader in `KittyCode`.
3. Move styling-only config types to the rendering or widget side when the final owner is clear.
4. Avoid creating a new config target unless the split clearly justifies it.

Exit criteria:

1. Each reusable module owns the config structs that define its behavior.
2. `KittyCode` remains the composition root for loading and wiring config.

Main risks:

1. Splitting config too early and multiplying churn.
2. Introducing a needless config module that increases indirection.

## Phase 8: Enable Large-File Architecture

- Goal: use the new boundaries to make `DocumentSource` and windowed document work practical.
- Estimated solo duration: 5 to 8 days for the first architectural slice.

Work items:

1. Finalize `DocumentSource` ownership in `KittyText`.
2. Add a workspace abstraction over eager and paged document backends.
3. Keep the current eager path for normal files.
4. Add a reduced-feature large-file path behind a threshold.
5. Scope syntax behavior for large files explicitly so highlighting does not block the migration.

Exit criteria:

1. Large-file work no longer requires touching `KittyCode` internals.
2. `KittyWorkspace` can work with both eager and paged document sources.

Main risks:

1. Starting large-file work before the workspace split is complete.
2. Reintroducing executable-level coupling to work around document abstractions.

## Phase 9: Cleanup, Enforcement, and Hardening

- Goal: remove temporary seams and make the new architecture self-reinforcing.
- Estimated solo duration: 2 to 3 days.

Work items:

1. Delete compatibility shims and dead forwarding code.
2. Tighten access control across modules.
3. Add architecture checks or review rules for disallowed imports and dependency directions.
4. Update developer documentation and module ownership notes.
5. Run full package verification and targeted performance checks.

Exit criteria:

1. Temporary shims are gone.
2. The module graph matches the target architecture.
3. The codebase documents how new code should be placed.

Main risks:

1. Leaving temporary compatibility seams in place permanently.
2. Finishing the move without enforcing the new rules.

## Recommended Execution Order

1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Phase 4
6. Phase 5
7. Phase 6
8. Phase 7
9. Phase 8
10. Phase 9

Parallelism should stay intentionally limited.

Allowed overlap after Phase 2:

1. Phase 3 and Phase 5 can overlap in small slices if tests are strong and no shared files are being moved simultaneously.
2. Phase 4 can overlap only after the workspace session boundary is stable.
3. Phase 7 must wait until Phases 3 through 6 have mostly settled.
4. Phase 8 must wait until the workspace boundary is genuinely in place.

## Acceptance Gates

Every phase should pass the same gate template.

1. Build gate:
   - `swift build` succeeds.
2. Regression gate:
   - focused target suites for touched areas pass.
3. Architecture gate:
   - moved code now lives in the intended target.
   - no new reverse dependencies are introduced.
4. API gate:
   - shell code depends on narrower interfaces than before.
5. Cleanup gate:
   - no unexplained duplicate implementations remain.
6. Documentation gate:
   - the architecture note and plan are updated if the move changed the intended end state.

## Success Metrics

### Structural metrics

1. `KittyCode` owns no document persistence, watcher, auto-save, or git refresh service types.
2. `KittyFileTree` owns file watching.
3. `KittyApp` owns refresh invalidation.
4. `KittyWidgets` owns overlay and status-bar primitives.
5. `KittyWorkspace` owns document and workspace session behavior.

### Coupling metrics

1. No reusable target imports `KittyCode`.
2. Shell render and input code depend on narrow views or commands rather than on a god object.
3. `EditorState` is either deleted or reduced to shell-only UI state.

### Quality metrics

1. No regression in existing focused tests.
2. Full package suite passes before Phase 9 closes.
3. No change-failure cluster appears around file open/save, tabs, overlays, or git status after extractions. [Strong][E-30]

### Extensibility metrics

1. Large-file work can proceed without reopening the module split.
2. Another TUI app could reuse file watching, workspace orchestration, and widget primitives without importing `KittyCode`.

## Risk Register

1. Big-bang rewrite risk:
   - mitigation: phase-based migration, no all-at-once state deletion, daily integration. [Strong][E-04]
2. Hidden coupling risk:
   - mitigation: impact mapping before each phase, compatibility seams, focused regression suites. [Moderate-Strong][E-17]
3. Scope creep risk:
   - mitigation: no unrelated feature work inside extraction phases, explicit non-goals. [Moderate][E-28]
4. Architecture drift risk:
   - mitigation: written dependency rules, end-of-phase architecture gate, post-migration enforcement.
5. Test gap risk:
   - mitigation: treat tests as prerequisite work, not follow-up work. [Strong-Moderate][E-05]
6. Performance regression risk:
   - mitigation: measure open, reload, highlight, and render flows before and after the largest moves.

## Non-Goals

1. Rewriting the editor from scratch.
2. Changing user-facing behavior unless needed to preserve correctness during extraction.
3. Introducing a large new framework or service container.
4. Splitting configuration into many targets before core boundaries are stable.
5. Shipping large-file mode before the workspace boundary exists.

## Working Agreements

1. Prefer concrete boundaries over abstract frameworks.
2. Prefer adapter-based extraction over rename-heavy churn.
3. Keep batches small enough that every phase can be reverted cleanly.
4. Treat temporary shims as debt with explicit removal dates.
5. Update this plan when new coupling is discovered; do not pretend the first draft is final. [Strong][E-27]

## Evidence References

- [E-01] Reduce WIP to improve flow and predictability.
- [E-04] Shorten the integration interval.
- [E-05] Quality is a Definition of Done, not a phase.
- [E-06] Small batches reduce risk.
- [E-17] Coupling drives coordination cost.
- [E-18] Reduce dependencies before tracking them.
- [E-27] Rolling-wave planning handles uncertainty.
- [E-28] Requirements volatility has measurable cost.
- [E-30] DORA metrics are the delivery baseline.

## Recommended Next Planning Artifact

Once implementation starts, create a phase-level execution backlog from this document with atomic tasks and explicit blockers for the first two phases only. Do not fully decompose all later phases until the workspace boundary work begins to land.
