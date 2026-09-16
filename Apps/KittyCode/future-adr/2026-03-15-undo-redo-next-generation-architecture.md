# Future ADR: Undo/Redo Next-Generation Architecture

Status: Proposed
Date: 2026-03-15
Supersedes: Phases 1-4 of `2026-03-12-undo-redo-history-assessment.md` (all completed)

## Context

The phased roadmap from the original undo/redo assessment is complete:

- Phase 1: `hasUndo`/`hasRedo` surfaced into status bar and context menus
- Phase 2: `HistoryCoordinator` introduced, dispatch moved out of mode switch
- Phase 3: Tree operation records enriched with selective invalidation
- Phase 4: Config-wired budgets, redo/undo stack pruning, snapshot guardrails

The current system is solid for its scope: per-buffer snapshot-based undo with coalescing, per-tree-operation undo with filesystem snapshots, bounded stacks, and coordinated availability reporting.

This ADR captures the longer-horizon architectural investments that would take the history system from "good enough" to "best-in-class terminal editor."

## Current Limitations

### 1. Full-snapshot storage is O(document_size x undo_depth)

Each `BufferEditSnapshot` stores a complete `TextBuffer` (array of line strings), `TextCursor`, and `LineEnding`. Each `Transition` stores both `before` and `after` snapshots.

Concrete cost:
- 10,000-line file, 40 chars/line average = ~400KB per snapshot
- Two snapshots per transition = ~800KB per undo step
- At `maxUndoSteps = 200`: ~160MB for a single buffer

Coalescing reduces step count but does not reduce per-step size.

### 2. Undo stack, not undo tree

After undoing and making a new edit, the redo branch is permanently discarded (`redoStack.removeAll` in `recordChange`). There is no way to recover previous redo branches or navigate alternate timelines.

### 3. No persistence across sessions

Closing a buffer or quitting the editor loses all undo history. There is no serialization format or sidecar file mechanism.

### 4. No transaction grouping

Format-on-save, multi-cursor edits, search-and-replace-all, and snippet expansion each produce multiple `recordChange` calls. They cannot be grouped into a single undoable unit.

### 5. Fingerprint computation is O(document_size)

`contentFingerprint` iterates all lines through `Hasher` on every `recordChange()`, `undo()`, and `redo()`. For large files this is measurable overhead on every keystroke.

### 6. Tree snapshots are in-memory only

`captureFileSystemSnapshot` stores file `Data` in the undo stack. For directories near the guardrail threshold (500 files / 10MB), this memory stays allocated until the history entry is pruned.

## Proposed Investments

### A. Piece Table Text Storage

Replace `TextBuffer` (array of line strings) with a piece table. The piece table maintains two backing buffers: the original file content (immutable) and an append-only add buffer for all inserted text. The document is described by an ordered sequence of piece descriptors `(buffer: .original | .add, offset: Int, length: Int)` stored in a balanced tree for O(log n) insert, delete, and positional lookup.

**Impact on undo**: Edits become piece descriptor splits and inserts. Undo snapshots store descriptor sequences rather than full text copies. Memory drops from O(document_size x undo_depth) to O(edit_size x undo_depth).

**Scope**: This is a `KittyText` rewrite. `TextBuffer`, line indexing, and all consumers (`DocumentBuffer`, `WorkspaceSession`, rendering) are affected.

**Prerequisite for**: Undo tree, persistent undo, large-file editing.

**Complexity**: High. This is the single largest item and the foundation for everything else.

### B. Undo Tree with Branch Preservation

Replace the linear undo/redo stacks with a rooted tree of edit nodes. When the user undoes and makes a new edit, the old redo branch is preserved as a sibling rather than discarded.

Navigation model (following Neovim semantics):
- Undo: move to parent node
- Redo: move to newest child on current branch
- "Earlier": move to globally previous edit by timestamp, regardless of branch
- "Later": inverse of "earlier"

Data structure per node:
```
UndoNode {
    parent: UndoNode?
    children: [UndoNode]
    timestamp: Date
    editDelta: EditDelta
    cursorPosition: TextCursor
}
```

Optional future UI: `:undotree` command rendering a tree visualization in a sidebar panel.

**Depends on**: Piece table (storing full snapshots per tree node is prohibitively expensive; delta-based nodes require compact edit representation).

### C. Persistent Undo Across Sessions

Serialize the undo tree (or stack, if tree is not yet implemented) to a sidecar file at `.kittycode/undo/<content-hash>.undo` on save and exit. On open, if the sidecar exists and the file's current content hash matches the header, restore the history.

Binary format sketch:
- 16-byte header: magic, version, content SHA-256, node count
- Depth-first serialized nodes with delta-encoded edit operations (varint offsets/lengths, raw bytes for inserted text)

If the file has been externally modified (hash mismatch), discard the sidecar and start fresh.

**Can be implemented independently** of piece table or undo tree — even serializing the current snapshot-based stack would be valuable, though storage-heavy.

**Lighter alternative**: Serialize only the last N undo steps (e.g., 20) to bound sidecar file size while still covering the most common "I just reopened the file and want to undo" scenario.

### D. Transaction-Based Grouping

Expose `beginTransaction() -> TransactionID` and `commitTransaction(TransactionID)` on `BufferEditHistory` (or the coordinator). All edits recorded between begin/commit are undone as one step.

Use cases:
- Format-on-save: formatter produces N edits, one undo step
- Multi-cursor edit: N insertions, one undo step
- Snippet expansion: placeholder insertion + cursor positioning
- Search-and-replace-all: M replacements, one undo step

Transactions nest: an outer transaction can contain inner transactions.

**Independent of piece table.** Can be implemented on the current snapshot model by grouping transitions.

### E. Incremental Fingerprinting

Replace the O(document_size) `contentFingerprint` with an incrementally maintained hash. Options:

1. **Rolling hash on piece table**: The piece table naturally tracks which pieces changed. Recompute the hash contribution of only the affected pieces.
2. **Line-level Merkle tree**: Maintain a balanced tree of per-line hashes. Update only the path from the edited line to the root. O(log n) per edit.
3. **Version counter**: For undo/redo validation, a monotonic version counter may suffice instead of content hashing. External refresh is the only case requiring true content comparison.

**Depends on**: Piece table (option 1) or is independent (options 2-3).

### F. Disk-Backed Tree Snapshots

Instead of holding file `Data` in memory for tree operation undo, write snapshot data to a temporary directory on disk. The undo stack holds paths to the temporary copies.

Trade-off: I/O on undo execution vs. reduced memory pressure during normal editing.

**Independent of all other items.** Can be implemented as a standalone improvement.

### G. Async Tree Snapshot Capture

For large directories that pass the guardrail threshold, run `captureFileSystemSnapshot` on a background task with cancellation support and progress indication, rather than blocking the main actor.

The current synchronous capture is acceptable because the guardrails prevent the expensive cases from reaching it. This becomes relevant if guardrail thresholds are raised or if users request undo support for larger directories.

**Independent.** Low priority unless guardrail thresholds change.

## Recommended Sequencing

### Near-term (independent of piece table)

These can be done on the current snapshot-based architecture:

1. **Transaction grouping (D)** — Unblocks format-on-save and search-and-replace-all as single undo steps. Medium complexity.
2. **Disk-backed tree snapshots (F)** — Reduces memory pressure. Low complexity.
3. **Persistent undo, light version (C)** — Serialize last N steps. Medium complexity, high user value.

### Medium-term (piece table foundation)

4. **Piece table text storage (A)** — Large effort, but prerequisite for efficient undo tree and large-file editing.
5. **Incremental fingerprinting (E)** — Natural follow-on to piece table.

### Long-term (requires piece table)

6. **Undo tree (B)** — Requires compact delta representation from piece table to be practical.
7. **Full persistent undo (C, full version)** — Undo tree serialization with branch preservation.
8. **Async tree capture (G)** — Only if guardrail thresholds are raised.

## Design Constraints

- **No CRDT/OT complexity yet.** The original assessment explored `retain/insert/delete` OT-compatible primitives. This is preparation for real-time collaboration and should be deferred until collaboration is actually on the roadmap. The additional complexity is not justified for single-user editing.
- **Piece table must preserve `TextBuffer` API surface.** The migration should be internal to `KittyText`. Consumers should see the same `lines`, `line(at:)`, `text`, `lineCount` interface, backed by different storage.
- **Persistent undo must handle content hash mismatches gracefully.** Never apply stale undo data to a modified file. Silent discard is the correct behavior.

## References

- VS Code Text Buffer Reimplementation (2018): piece table architecture and performance analysis
- Neovim undo tree: `u_header_T` linked structure, `:earlier`/`:later` time navigation, persistent undo file format
- Crowley, "Data Structures for Text Sequences" (1998): foundational comparison including piece tables
- Zed transaction model: per-user selective undo via operation-ID-keyed undo maps
- Xi editor CRDT: revision-based undo with rewind-and-replay
