# KittyCode Performance Optimization Plan

## Overview

All previously-claimed optimizations (Phases A-D from prior sessions) are **missing from the codebase**. This plan restores and implements them, plus additional improvements discovered through research.

## Phase A: Zero-Allocation Rendering (Critical Path)

The rendering pipeline (DirtyTracker -> DiffRenderer -> SGREncoder -> RenderPipeline -> write) runs every frame. Eliminating allocations here has the highest impact.

### A1. ContiguousArray for hot-path storage
- `DirtyTracker.bits`: `[UInt64]` -> `ContiguousArray<UInt64>` (no bridging overhead)
- `ScreenBuffer.cells`: `[Cell]` -> `ContiguousArray<Cell>` (O(1) guaranteed COW)
- `DiffRenderer.render` / `renderFull`: `[UInt8]` output -> `inout ContiguousArray<UInt8>`
- `SGREncoder.encode` / `encodeDiff`: return via `inout ContiguousArray<UInt8>` overloads

### A2. Persistent output buffer in RenderPipeline
- Add `private var outputBuffer = ContiguousArray<UInt8>()` to `RenderPipeline`
- Reuse across frames: `outputBuffer.removeAll(keepingCapacity: true)` instead of allocating new `[UInt8]`

### A3. Lookup table for decimal encoding
- `SGREncoder.appendDecimal` and `KittySequences.appendDecimal`: replace division chains with a 256-entry `decimalTable: ContiguousArray<(UInt8, UInt8, UInt8, UInt8)>` for O(1) digit lookup

### A4. UTF-8 append optimization in DiffRenderer
- `appendUTF8`: avoid `String(char)` allocation; use `char.utf8` directly on Character (Swift 5.x+ supports direct UTF8View iteration on Character)

## Phase B: Ancillary Optimizations

### B1. Binary search in UnicodeWidth
- Replace 13 sequential `.contains()` range checks with a sorted array + binary search for `isCJKOrWide`
- Add ASCII fast path: `scalar.value < 0x1100` -> return false immediately (covers ~99% of typical source code)

### B2. Word-level CTZ scanning in DirtyTracker.dirtyRanges
- Current: per-cell `isDirty()` calls (bit extract per cell)
- Optimized: iterate words, use `trailingZeroBitCount` to find dirty spans in O(words) not O(cells)

### B3. Dictionary lookup in GLRParser
- `parseTable.terminals.firstIndex(of:)` is O(n) linear scan per token
- Build `terminalIndex: [String: Int]` dictionary at init time for O(1) lookup

### B4. Binary search in Lexer transitions
- `lexTable.states[state].transitions` iterated linearly per character
- Sort transitions by range start; use binary search for the matching range

### B5. Regex cache in Predicates
- `NSRegularExpression(pattern:)` compiled on every predicate evaluation
- Cache compiled regexes in a static dictionary keyed by pattern string

## Phase C: Data Structures

### C1. GapBuffer for TextBuffer
- Replace `[String]` lines array with a gap buffer for O(1) amortized insert/delete at cursor
- Maintain line index for O(log n) line lookup

### C2. Batch cache invalidation in Highlighter
- Track edit ranges; only rebuild `byteStyles` for affected byte ranges instead of full source

## Phase D: SIMD & Parallelism

### D1. SIMD dirty tracking
- `DirtyTracker.clear()`: use `memset` or SIMD zero-fill for large buffers
- `DirtyTracker.isEmpty`: use SIMD OR-reduction across words

### D2. TaskGroup in DirectoryScanner
- Parallelize subdirectory scanning with `withTaskGroup` for multi-core utilization
- Maintain entry count limit with atomic counter

### D3. writev(2) scatter-gather I/O
- Add `TerminalConnection.write(contiguous:)` method taking `ContiguousArray<UInt8>`
- `POSIXTerminalConnection`: use `withUnsafeBufferPointer` for zero-copy write
- Future: `writev(2)` for multi-segment writes without concatenation

## Implementation Priority

1. Phase A (A1-A4) - Highest impact, touches every frame
2. Phase B1, B2 - Common operations, easy wins
3. Phase C1 - Fundamental data structure improvement
4. Phase B3-B5 - Parser/query path, lower frequency
5. Phase D1-D3 - Advanced optimizations

## Constraints

- Swift 6 strict concurrency
- macOS 14+ / Swift 5.9+ (no InlineArray yet, requires Swift 6.2)
- All changes must preserve existing test behavior
- No new dependencies
