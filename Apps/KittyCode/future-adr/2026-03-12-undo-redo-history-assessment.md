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

## Deep Technical Analysis

### Codebase Impact Assessment

#### BufferEditHistory Snapshot Cost Analysis

The current `BufferEditSnapshot` (BufferHistory.swift:4-28) stores a full copy of `TextBuffer`, `TextCursor`, and `TextDocument.LineEnding` per transition. The `Transition` struct (lines 37-41) stores both `before` and `after` snapshots, meaning each undo step stores two complete document copies.

Concrete cost model:
- A 10,000-line file with an average of 40 characters per line = ~400KB per snapshot
- Two snapshots per transition = ~800KB per undo step
- 100 undo steps = ~80MB for a single buffer
- With coalescing (default window), rapid typing merges into fewer transitions, but each merged transition still stores full before/after snapshots

The `contentFingerprint` (lines 19-27) iterates all lines through `Hasher`, combining line ending, line count, and every line string. This is O(document_size) per fingerprint computation, called on every `recordChange()`, `undo()`, and `redo()`.

Mitigation strategies (ordered by implementation complexity):

1. **Bounded depth** (simplest): Add `maxUndoSteps: Int` to `BufferEditHistory`. On `recordChange()`, if `undoStack.count > maxUndoSteps`, drop the oldest transition. A default of 200 steps covers typical editing sessions while capping memory at ~160MB worst case for large files.

2. **Bounded memory**: Track cumulative snapshot byte count. Estimate per-snapshot bytes as `textBuffer.lines.reduce(0) { $0 + $1.utf8.count }`. Evict oldest transitions when the total exceeds a configurable budget (e.g., 50MB per buffer).

3. **Structural sharing**: Instead of copying `TextBuffer` entirely, use a persistent data structure (e.g., a rope or piece table with structural sharing). Transitions that modify a few lines share most of the backing storage. This is a major refactor of `KittyText` and should wait for the large-file architecture work.

4. **Delta encoding** (medium-term): Store the first snapshot as a full checkpoint, then subsequent transitions as edit operations (insert/delete ranges with content). Reconstruct snapshots by replaying deltas from the nearest checkpoint. Checkpoint every N steps (e.g., every 50 operations) to bound replay cost.

#### Fingerprint-Based Invalidation Brittleness

Both `BufferEditHistory.reconcileWithRefresh()` (lines 128-139) and `FileTreeOperationHistory.validateRefresh()` (FileTreeOperationHistory.swift:44-56) use content fingerprinting to detect external changes. When the fingerprint differs from the stored value, the entire undo/redo stack is discarded.

Problems with the current approach:

1. **Hash collisions**: `Hasher` uses random seeding per process. While collisions are rare, a collision between the refreshed content and the stored fingerprint would silently accept divergent state — the system would believe nothing changed when the file was actually modified externally.

2. **All-or-nothing invalidation**: Any single-character external change to a file invalidates the entire history. The system cannot distinguish "a formatter added a trailing newline" from "the file was completely rewritten."

3. **Tree history is even more aggressive**: `FileTreeOperationHistory` fingerprints the entire tree structure (FileTreeOperationHistory.swift:113-127) by hashing every node's path, `isDirectory` flag, and child count recursively. Creating an unrelated file anywhere in the workspace clears the tree undo stack.

Improvements:

1. **Per-operation path tracking for tree history**: Store the set of paths affected by each tree operation. On refresh, only invalidate operations whose affected paths intersect with the changed paths. Operations affecting untouched subtrees can survive.

2. **Content-aware buffer invalidation**: Instead of fingerprinting the entire buffer, compare the refreshed content against `undoStack.last?.after.textBuffer`. If the refresh matches the expected post-edit state, the history is still valid. Only invalidate if the refresh produces content that doesn't match any known state in the stack.

3. **Partial invalidation**: Allow truncating the stack from the point where the external change occurred rather than clearing everything. If the bottom 5 transitions are still valid (their expected states match), keep them and only discard the top of the stack.

#### FileTreeOperationHistory Recursive Snapshot Cost

`captureFileSystemSnapshot(at:)` (EditorTreeFileOperations.swift:306-322) recursively reads all file data into memory for delete and duplicate operations. For a directory with 1000 files totaling 50MB, this captures 50MB of `Data` into the undo stack.

Current safety valve: `hasOpenBufferConflict(at:)` (lines 260-263) prevents operations on paths with open buffers, avoiding the hardest coordination cases. But it doesn't prevent expensive snapshots of large directories.

Improvements:

1. **Size threshold**: Before capturing, estimate the total size with a quick `FileManager` enumeration. If the total exceeds a threshold (e.g., 10MB), warn the user and offer to proceed without undo support for that operation.

2. **Lazy snapshot restoration**: Instead of holding all file data in memory permanently, write snapshot data to a temporary directory on disk. The undo stack holds paths to the temporary copies rather than raw `Data`. This trades I/O on undo for reduced memory pressure during normal editing.

3. **Async capture with progress**: For large directories, run `captureFileSystemSnapshot()` on a background task with cancellation support. Show a progress indicator. The current synchronous inline capture blocks the main actor during the filesystem traversal.

#### Undo/Redo Command Routing

The current routing in EventHandling.swift dispatches undo/redo based on `EditorState.Mode` — `.editor` routes to buffer history, `.tree` routes to tree history. This is a direct mode check, not a command resolution.

Migration to command-based routing:

1. Define `CommandID.global.undo` and `CommandID.global.redo`.
2. The `CommandDispatcher` determines the active history domain from the current `KeyContext` (editor focus → buffer history, tree focus → tree history, search panel focus → no-op or search-specific undo if supported).
3. The dispatcher calls the `HistoryCoordinator` which asks the appropriate domain engine for its `StepResult` and surfaces the outcome to the status bar.
4. This naturally extends to future domains: search/replace undo could become a third domain that reverses bulk replacements.

### State of the Art: Editor Undo/Redo Architectures

#### VS Code: Operation-Based Undo

VS Code uses an operation-based undo model:
- **UndoRedoService**: A central service that manages undo stacks per resource URI. Each stack entry is an `IUndoRedoElement` with `undo()` and `redo()` methods.
- **Compound edits**: Multiple operations can be grouped into a single undo unit using `pushEditOperations()`. This handles cases like format-on-save where the formatter's changes should undo as one step.
- **Workspace undo**: File create/delete/rename operations are tracked in a separate workspace undo stack. Each entry records the forward and inverse filesystem operation.
- **Memory management**: VS Code uses a piece table (derived from the Monaco editor) for text storage, giving O(1) structural sharing between undo states. Only the edit descriptors are stored, not full snapshots.

#### Neovim: Undo Tree

Neovim's undo model is the most sophisticated among terminal editors:
- **Undo tree, not stack**: Neovim stores a full tree of edit states. After undoing and making new edits, the old redo branch is preserved as a sibling rather than discarded. Users can navigate the full history tree.
- **Persistent undo**: The undo tree can be serialized to disk (`:set undofile`), surviving across editor sessions. The file format includes checksums to detect external file modifications.
- **Change granularity**: Each undo entry records the changed region (start line, end line, replaced text) rather than a full snapshot. This makes undo storage proportional to edit size, not document size.
- **Time-based navigation**: `:earlier 5m` and `:later 5m` navigate the undo tree by wall-clock time, not by step count.

#### Zed: Transaction-Based History

Zed uses a transaction model:
- **Edit transactions**: Each logical user action opens a transaction. All buffer modifications within the transaction are grouped. Undo reverts the entire transaction.
- **Concurrent collaboration**: The undo model is CRDT-aware, designed to work with real-time collaboration. Each operation has a Lamport timestamp for causal ordering.
- **Selective undo**: The architecture supports undoing specific operations out of order (needed for collaborative editing where user A undoes their change without affecting user B's subsequent edits).

#### Xi Editor: CRDT Rope

Xi (now archived but architecturally influential):
- **CRDT-based rope**: Text is stored as a CRDT, making every edit inherently mergeable and undoable without snapshots.
- **Engine separation**: The undo engine operates on abstract edit operations, completely decoupled from the text storage representation.
- **Revision graph**: Similar to Neovim's undo tree, Xi maintains a full revision graph with branch support.

### Recommended Technical Approach for KittyCode

#### History System: SOTA Architecture

1. **Piece table text storage**: Replace the current `TextBuffer` (array of line strings, causing ~800KB full-snapshot copies per undo step for 10K-line files) with a piece table. The piece table maintains two backing buffers: the original file content (immutable, read-only) and an append-only add buffer that accumulates all inserted text. The document is described by an ordered sequence of piece descriptors `(buffer: .original | .add, offset: Int, length: Int)` stored in a balanced binary tree (red-black tree or B-tree) for O(log n) insert, delete, and positional lookup. Edits become piece splits and inserts — no text is ever copied or moved. Undo is O(1) piece descriptor manipulation: restore the previous descriptor sequence. Memory usage drops from O(file_size x undo_depth) to O(edit_size x undo_depth). This is the model used by VS Code's Monaco editor, which achieves sub-microsecond undo on files of any size. Line index metadata (byte offsets of newlines) is maintained incrementally alongside the piece table for O(log n) line-to-offset conversion.

2. **Undo tree with full branch preservation**: Implement a true undo tree, not an undo stack. The history is a rooted tree of edit nodes. When the user undoes and then makes a new edit, the old redo branch is preserved as an alternate timeline (sibling branch), never discarded. Navigation: `u` for undo (move to parent), `Ctrl+R` for redo (move to newest child on the current branch), `g-` for "earlier in time" (move to the globally previous edit regardless of branch, ordered by timestamp), `g+` for "later in time" (the inverse). These are Neovim's exact semantics. Provide an `:undotree` command that renders a tree visualization in a sidebar panel: the current node is highlighted, branches are shown with their timestamps, and the user can jump to any node by selecting it. The tree structure uses a `UndoNode` type with `parent: UndoNode?`, `children: [UndoNode]`, `timestamp: Date`, `editDelta: EditDelta`, and `cursorPosition: BufferPosition`.

3. **Persistent undo across editor restarts**: Serialize the full undo tree to a sidecar file at `.kittycode/undo/<sha256-of-file-content>.undo` on file save and editor exit. On file open, if a sidecar file exists and the file's current SHA-256 content hash matches the hash recorded in the sidecar header, restore the complete undo tree including all branches. The binary format: 16-byte header (magic, version, content hash, node count), followed by depth-first serialized tree nodes with delta-encoded edit operations (using varint encoding for offsets and lengths, and raw bytes for inserted text). If the file has been externally modified (hash mismatch), discard the sidecar and start fresh. Undo surviving editor restarts is one of Neovim's most beloved features — KittyCode should match it from day one.

4. **Transaction-based grouping for compound operations**: All edits within a single logical user action are grouped into one undo transaction. The `HistoryCoordinator` exposes `beginTransaction() -> TransactionID`, `commitTransaction(TransactionID)`, and `rollbackTransaction(TransactionID)`. Use cases: format-on-save (formatter produces N edits, all undone as one step), multi-cursor edit (N insertions across N cursor positions, one undo step), snippet expansion (placeholder insertion + cursor positioning), search-and-replace-all (M replacements, one undo step). A single `u` reverses the entire transaction. Transactions nest: an outer transaction (e.g., "rename symbol") can contain inner transactions (e.g., "edit file A" + "edit file B"), and undo at the outer level reverses everything.

5. **Operational transform compatible edit representation**: Structure all edit operations as OT-compatible primitives: `retain(n)` (skip n characters), `insert(string)` (insert text at current position), `delete(n)` (delete n characters). Every edit in the undo tree is stored in this canonical form. Composition: two sequential operations can be composed into one. Transformation: two concurrent operations can be transformed against each other to produce convergent results. This does not require collaboration today, but it makes the data model directly compatible with future real-time collaboration (OT or CRDT-based), and it provides a clean, well-studied algebra for undo/redo, conflict detection, and operational rebasing.

6. **Content-addressable checkpoints for fast reconstruction**: Every Nth edit (default: N=100), store a full content-addressable checkpoint: the complete piece table state plus a SHA-256 hash of the document content at that point. When seeking to a distant point in the undo tree (e.g., the user clicks a node 500 edits ago in the undo tree visualization), find the nearest checkpoint and replay edits forward from there, rather than replaying from the root. This bounds worst-case reconstruction time to O(N) edit replays regardless of total history depth. Checkpoints are also used to validate persistent undo file integrity on load.

7. **Edit coalescing with configurable granularity**: Consecutive character inserts coalesce into a single undo step when: (a) they occur within 500ms of each other, (b) they are at adjacent positions (sequential typing), and (c) no word boundary has been crossed. Typing "foo bar" produces 2 undo steps ("foo " and "bar") because the space is a word boundary. Typing "hello" within 500ms produces 1 undo step. The following operations always break coalescing and create a new undo step: any delete operation, any paste operation, any programmatic edit (LSP rename, formatter), any cursor movement without editing, any mode switch, and any explicit transaction boundary. Coalescing parameters (timeout, word-boundary detection) are user-configurable.

8. **Memory budget with intelligent branch eviction**: Set a per-buffer undo memory budget (default: 50MB). Track cumulative undo tree memory by summing edit delta sizes across all nodes. When the budget is exceeded, prune the oldest leaf branches of the undo tree first — branches that are furthest from the current position and oldest by timestamp. Never evict: the current branch (root to current node), any node within the last 100 edits, or any checkpoint node. Evicted branches are tombstoned (metadata preserved, delta data freed) so the tree visualization can still show "pruned branch" indicators. If persistent undo is enabled, evicted branches remain in the sidecar file and can be restored on demand.

## SOTA Review and Accuracy Assessment

This section evaluates the ADR's technical claims and recommendations against verified state-of-the-art knowledge as of March 2026.

### Verified Accurate

1. **VS Code's UndoRedoService architecture** — verified. VS Code uses a central service managing per-resource undo stacks with `IUndoRedoElement` entries. Compound edits use `pushEditOperations()` to group multiple operations into one undo step.

2. **Neovim's undo tree** — verified. Neovim implements a true undo tree via `u_header_T` structs linked through `uh_next`/`uh_prev` (branch navigation) and `uh_alt_next`/`uh_alt_prev` (sibling branches). Time-based navigation (`:earlier`/`:later`) uses `uh_time` timestamps with depth-first tree walking.

3. **Neovim's persistent undo** — verified. Serialized to a binary file with SHA-256 content hash in the header. On load, hash is compared against current file content; mismatch causes the undo file to be silently ignored. The format includes a magic header, depth-first tree serialization, and integrity checksum.

4. **Zed's transaction-based CRDT model** — verified. Zed uses immutable insertion IDs with Lamport timestamps, tombstone-based deletion, and an undo map (odd count = undone, even = active). Per-user selective undo is supported via operation-ID-keyed undo maps.

5. **The ADR's phased approach** (surface existing capabilities → add coordinator → improve workspace operations → add budgets) is well-sequenced and practical.

6. **The decision to keep buffer and workspace history as separate domains** is correct. Every editor reviewed maintains this separation.

### Requires Correction or Qualification

1. **"O(1) structural sharing between undo states"** (piece table section, point 1) — **Misleading**. Creating a modified piece table or rope after an edit is O(log n) because the path from the edited leaf to the root must be duplicated (copy-on-write). Only cloning an unmodified snapshot (e.g., Helix's ropey clone) is O(1) — it increments a reference count. The distinction matters for undo cost analysis.

2. **"Sub-microsecond undo on files of any size"** (piece table section, point 1) — **Overstated**. Piece descriptor manipulation is fast, but undo also involves line-index metadata updates and CRLF boundary checking, which add O(log n) cost. "Low microseconds" is more defensible. VS Code's blog itself notes that `getLineContent` is O(log n) vs O(1) for line arrays, "but we are talking about microseconds."

3. **Xi maintains "a full revision graph with branch support"** (SOTA section) — **Partially accurate**. Xi's revision history is a linear sequence with undo-group toggling, not an explicitly navigable tree like Neovim's. Branches are implicit (toggled undo groups creating different active/inactive sets) rather than explicit tree nodes with navigation commands.

4. **"CRDT-based rope: every edit inherently undoable without snapshots"** (Xi section) — **Imprecise**. Xi's CRDT undo uses rewind-and-replay from a base state, which is conceptually checkpoint-based. It avoids full-document snapshots but requires replaying history segments from the nearest point where toggled groups affect state.

5. **"Operational transform compatible edit representation"** (recommendation 5) — **Forward-looking architectural choice, not current best practice**. The `retain(n)/insert(s)/delete(n)` format originates from Google Wave's OT protocol and is used by ShareDB and Yjs. It is sound for future collaboration support, but most single-user editors (VS Code, Neovim, Helix, Zed in local mode) use simpler `(range, replacement_text)` pairs internally. This should be explicitly labeled as a preparation-for-collaboration choice rather than a current necessity, and the additional complexity cost should be acknowledged.

6. **Edit coalescing description** (point 7) — **Reasonable composite but no single editor uses exactly this combination**. Neovim uses mode boundaries only (entering/leaving insert mode). Apple NSTextView uses time-based coalescing. Most GUI editors use a combination of time + position continuity. The ADR's proposed model (500ms + word boundary + mode switch) is defensible but should note it is a novel composite rather than an established standard.

### Academic References

- Crowley, "Data Structures for Text Sequences" (1998) — foundational comparison of text data structures including piece tables
- Prakash & Knister, "A Framework for Undoing Actions in Collaborative Systems" (1994, TOCHI)
- Sun & Ellis, "OT in Real-time Group Editors" (1998, CSCW) — foundational OT framework
- Sun, "Undo as Concurrent Inverse in Group Editors" (2002, TOCHI 9(4)) — undo as concurrent inverse
- Cass et al., "An Empirical Evaluation of Undo Mechanisms" (2006) — users prefer cascading selective undo
- VS Code Text Buffer Reimplementation (2018): https://code.visualstudio.com/blogs/2018/03/23/text-buffer-reimplementation
- Xi editor CRDT details: https://xi-editor.io/docs/crdt-details.html
- Zed CRDT blog: https://zed.dev/blog/crdts
- Ropey crate: https://github.com/cessen/ropey
- "Text Showdown: Gap Buffers vs Ropes" (2023): https://coredumped.dev/2023/08/09/text-showdown-gap-buffers-vs-ropes/
