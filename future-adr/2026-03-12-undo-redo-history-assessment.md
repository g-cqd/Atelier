# Future ADR: Undo/Redo and Workspace History Assessment

Status: Proposed
Date: 2026-03-12

## Goal

Assess the current undo/redo architecture for:

- individual editor buffers
- file tree and workspace manipulation

and define a coherent path toward a fuller history system with clearer availability, safer invalidation behavior, and better reuse of already-written but currently unwired capabilities.

## Scope

This ADR covers:

- text edit undo/redo inside a single buffer
- file tree create, delete, move, rename, and duplicate history
- external refresh invalidation
- command routing and availability surfacing
- already-developed but unused or partially wired features

This ADR does not propose implementation work for:

- cross-session persistence
- AST-level semantic history
- search history
- command palette history

## Current Codebase Findings

### Buffer undo/redo already exists and is functional

`Sources/KittyWorkspace/BufferHistory.swift` implements `BufferEditHistory` with:

- `undoStack` and `redoStack`
- `savedFingerprint` and `currentFingerprint`
- coalescing by elapsed time
- explicit `markSaved`, `reset`, and `reconcileWithRefresh`

`Sources/KittyCode/EditorStateCore.swift` wires it through:

- `activeBufferSnapshot()`
- `textDidChange(...)`
- `undoActiveBuffer()`
- `redoActiveBuffer()`
- `applyActiveBufferSnapshot(...)`

This is a real, working per-buffer history system, not just a stub.

### Buffer history is snapshot-based

Each transition stores a full `BufferEditSnapshot`:

- `TextBuffer`
- `TextCursor`
- `TextDocument.LineEnding`

This is simple and robust, but it means history size grows with snapshot count and document size. There is no visible cap, pruning policy, or memory budget.

### Buffer history is local to each open buffer

The model is intentionally per-buffer. `Tests/KittyCodeTests/UndoRedoTests.swift` confirms undo/redo follows the active buffer and does not cross tab boundaries.

That is the correct current behavior, but there is no higher-level history coordinator above it.

### Undo/redo routing is mode-based, not intent-based

`Sources/KittyCode/EventHandling.swift` routes the same undo shortcut to different systems depending on `EditorState.Mode`:

- `.editor` -> `undoActiveBuffer()` / `redoActiveBuffer()`
- `.tree` -> `undoFileTreeOperation()` / `redoFileTreeOperation()`

This means undo semantics depend on which pane is focused, not on a first-class command target or history capability model.

### Buffer history invalidation on external changes is implemented

`Sources/KittyWorkspace/FileWatcherIntegration.swift` reloads clean buffers from disk and calls `reconcileWithRefresh(...)`.

`Sources/KittyCode/EditorStateFileWatcherDelegate.swift` surfaces:

- "`<file>` reloaded from disk"
- "`<file>` reloaded from disk; undo history cleared"

This is the main invalidation path today.

### Buffer history has availability signals, but they are not surfaced

`BufferEditHistory` exposes:

- `hasUndo`
- `hasRedo`

`Sources/KittyCode/FileTreeOperationHistory.swift` exposes the same for tree history.

`rg` shows these are not consumed by runtime UI, menus, or status reporting.

This is one of the clearest "already developed but unwired" features in this area.

### Buffer history save-state behavior is correct but minimally surfaced

`Sources/KittyCode/EditorStateFileSystem.swift` marks the active snapshot as saved on write:

- `activeBuffer.editHistory.markSaved(currentSnapshot)`
- `activeBuffer.isDirty = activeBuffer.editHistory.isDirty(...)`

So the saved checkpoint exists logically, but there is no user-facing way to inspect save boundaries or show whether the top undo boundary crosses the last saved state.

### File tree workspace history also exists and is functional

`Sources/KittyCode/FileTreeOperationHistory.swift` implements a second history stack for:

- `create`
- `delete`
- `move`
- `duplicate`

`renameTreeItem(...)` in `Sources/KittyCode/EditorTreeFileOperations.swift` is just a thin alias for `moveTreeItem(...)`.

Undo/redo roundtrips are covered in `Tests/KittyCodeTests/TreeFileOperationTests.swift`.

### Tree history is fingerprint-invalidated on refresh

`loadInitialTree(validateHistory:)` validates the current tree fingerprint and clears tree history on divergence.

This is safe, but aggressive. Any external file-system change that alters the tree can clear the entire undo/redo stack.

### Tree history stores reversible file-system operations, but not rich transactions

The history item type is a plain enum. It does not record:

- selection restoration metadata beyond ad hoc reselection
- open-buffer side effects
- grouped multi-step operations
- explicit invalidation reasons
- progress or failure recovery metadata

### Tree history uses full subtree snapshots for delete and duplicate

`captureFileSystemSnapshot(at:)` recursively stores file data for files and directories.

That makes undoing delete or redo of duplicate possible, but it can become expensive for large trees or binary-heavy directories.

### Open buffers intentionally block some tree operations

`EditorTreeFileOperations.swift` refuses move and delete when open buffers conflict with the target path.

That is a reasonable safety rule today, but it also means file-tree history and buffer history are not coordinated. The system avoids a complex state sync by forbidding the hard cases.

### Current test coverage is useful but narrow

Current tests cover:

- per-buffer undo isolation
- buffer coalescing on and off
- invalidation after external refresh divergence
- tree create/undo/redo
- tree history invalidation on refreshed divergence
- selection editing undo in `Tests/KittyCodeTests/SelectionEditingTests.swift`

There is no broader test coverage for:

- history availability surfacing
- save-boundary semantics
- multiple sequential tree operations
- large directory snapshot cost
- mixed buffer and tree workflows

## Gaps and Missing Features

### 1. No unified history capability layer

The app has two history systems, but no coordinator that answers:

- what can currently be undone
- what can currently be redone
- which domain owns the next undo
- how that should be shown in status UI

The mode switch in `EventHandling.swift` is a shortcut, not a durable architecture.

### 2. No surfaced availability or affordance

Both history engines already expose availability, but the UI does not use it.

Missing surfaces include:

- status bar history state
- context menu enablement
- future command palette integration
- future toolbar or sidebar affordance

### 3. Invalidation reason is not durable state

After an external refresh, the watcher delegate can tell the user history was cleared. After that, the only remaining outcome may be "Nothing to undo."

That means the user-visible reason for history loss is transient and can be lost quickly.

### 4. Buffer history has no visible budget or pruning policy

The snapshot approach is acceptable for a first system, but it currently has:

- no max depth
- no byte budget
- no checkpoint compaction
- no large-file policy

### 5. No workspace transaction model

There is no way to treat a series of file operations as one undoable unit, and no way to represent compound effects across:

- filesystem changes
- open buffer state
- selection state
- current tab state

### 6. Tree history invalidates too broadly

Any tree refresh divergence clears the stack. That is safe but not nuanced.

The current model cannot distinguish:

- unrelated external changes
- changes under an untouched subtree
- changes that do not affect the reversible operation chain

### 7. Tree history is sync and potentially heavy

Recursive file snapshot capture happens inline and can become expensive for large directories. There is no background execution, progress reporting, or size threshold policy.

### 8. History semantics stop at the current two domains

There is no undo/redo support for adjacent workspace actions such as:

- tab close and reopen
- save-as path change as a reversible workspace operation
- preview to pinned transitions
- batch file operations

Not all of these belong in v1 history, but the current architecture makes them awkward to add later.

## Already Developed But Unwired or Underused

- `BufferEditHistory.hasUndo` and `hasRedo` exist but are not consumed.
- `FileTreeOperationHistory.hasUndo` and `hasRedo` exist but are not consumed.
- `config.keybindings.historyModifier` is wired in `ShortcutMatching.swift`, but undo/redo still resolve through ad hoc focus-mode checks instead of a command layer.
- Save checkpoints exist through `savedFingerprint`, but there is no surfaced notion of "saved boundary reached."
- Tree history fingerprint validation is implemented, but invalidation reasons are collapsed into one generic status string.

## Decision

### 1. Keep buffer history and workspace history as separate domains

They solve different problems:

- buffer history is high-frequency, local, and latency-sensitive
- workspace history is low-frequency, explicit, and file-system-backed

They should not be collapsed into one raw stack.

### 2. Add a shared history coordination layer above both

KittyCode should introduce a shell-level history surface that can answer:

- `canUndo`
- `canRedo`
- `undoTarget`
- `redoTarget`
- `lastInvalidationReason`

This should become the command-facing API.

### 3. Preserve the current snapshot model short term, but add budgets

The existing buffer history is good enough to keep for now. The right near-term improvement is not an immediate rewrite to deltas. The right near-term improvement is:

- bounded depth
- bounded memory policy
- optional periodic checkpointing
- large-file guardrails

### 4. Enrich workspace history before broadening it

The tree history system should first become a richer reversible operation journal before it attempts to undo more types of workspace action.

### 5. Make invalidation explicit state, not only a transient message

Both history engines should persist the last invalidation reason so the UI can explain "why undo is unavailable" instead of only "nothing to undo."

## Proposed Architecture

### Shared types

Suggested new shell-level types:

- `HistoryDomain`
- `HistoryAvailability`
- `HistoryInvalidationReason`
- `HistoryStatus`
- `UndoCommandTarget`

Example domains:

- `buffer(path: String)`
- `workspaceTree`

### Buffer history evolution

Keep `BufferEditHistory` as the engine, but add:

- `maxUndoSteps`
- `maxUndoBytes`
- `lastInvalidationReason`
- `reachedSavedBoundary`

Suggested next-step internal types:

- `BufferHistoryBudget`
- `BufferHistoryStats`
- `BufferHistoryCheckpoint`

Short term:

- keep full snapshots
- prune oldest entries when over budget
- expose availability and save-boundary status

Medium term:

- consider a hybrid journal with periodic checkpoints plus smaller edit records for large files

### Workspace history evolution

Replace the raw enum-only mental model with a richer operation record, for example:

- `WorkspaceOperationRecord`
- `WorkspaceOperationInverse`
- `WorkspaceOperationContext`

Each record should be able to carry:

- forward action
- inverse action
- affected paths
- selection restoration target
- open-buffer preconditions
- optional grouped transaction id
- failure classification

### Command routing

Undo and redo should resolve through one command path, not a direct `mode` branch.

Suggested flow:

1. Determine focused context.
2. Ask the history coordinator for the active undo target.
3. Execute the target-specific undo or redo.
4. Surface the result through a consistent status model.

This keeps tree focus and editor focus relevant, but removes hardcoded branching from the raw key handler.

### UI surfacing

At minimum, history state should be available to:

- status bar
- context menus
- future command palette
- future search/replace flows that perform bulk edits

The first UI addition does not need to be elaborate. A compact status signal is enough if it is accurate.

## Recommended Phasing

### Phase 1: Surface and stabilize current capabilities

- Wire `hasUndo` and `hasRedo` into shell state.
- Add persistent invalidation reason tracking.
- Add tests for availability after save, refresh, and tree divergence.
- Keep current behavior otherwise.

### Phase 2: Improve correctness and ergonomics

- Introduce a history coordinator.
- Move undo/redo dispatch out of the raw mode switch.
- Add save-boundary awareness.
- Add richer status text and context menu enablement.

### Phase 3: Improve workspace operation modeling

- Replace plain tree history items with richer records.
- Add grouped workspace operations.
- Make invalidation more selective where safe.

### Phase 4: Improve performance and scaling

- Add buffer history budgets.
- Add large-directory snapshot guardrails.
- Move heavy workspace snapshotting off the hot path where possible.

## Testing Recommendations

- Add buffer tests for saved-boundary transitions.
- Add buffer tests for bounded history pruning.
- Add tree tests for grouped operations.
- Add tree tests for invalidation reason persistence.
- Add integration tests for mixed editor/tree undo when focus changes.

## Recommendation Summary

The current undo/redo implementation is real and reasonably solid, but it is still two separate local systems held together by focus-mode branching. The best next step is not to replace everything. The best next step is to expose the capabilities that already exist, preserve invalidation reasons as real state, and add a coordinator above the two engines.

After that, the main deeper investments are:

- budgeted buffer history
- richer workspace operation records
- command-based undo routing
