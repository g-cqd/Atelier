# KittyCode Performance and Reuse Plan

Updated: 2026-03-10

## Baseline

- Platform floor: macOS 26
- Toolchain: Swift 6.2
- Scope: Apple-only terminal editor and supporting libraries
- Goal: move reusable logic out of `KittyCode` into lower modules, then spend optimization effort only where it changes measured hot paths

## Already In Place

- `ContiguousArray` is already used on core hot paths in `KittyRenderer`, `KittyCodecs`, and `KittyText`.
- Render output is already reused across frames through a persistent `ContiguousArray<UInt8>` in `RenderPipeline`.
- Terminal writes already support a zero-copy contiguous path through `TerminalConnection.writeContiguous(_:)`.
- Dirty tracking already uses a bitset plus word-level scanning.
- Parser terminal and non-terminal lookup tables are already cached as dictionaries.
- Lexer and syntax-node extraction already try contiguous UTF-8 storage before copying.
- Directory scanning already uses structured concurrency for parallel subdirectory traversal.

## Landed In This Pass

- Raised the package baseline to Swift tools 6.2 and macOS 26.
- Simplified `KittySync.StateLock` to a single `Synchronization.Mutex` implementation.
- Replaced the remaining `NSLock`-backed syntax artifacts cache with shared `StateLock`.
- Moved text display metrics out of `KittyCode` into reusable `KittyText` APIs.
- Added `KittyWidgets.TextEditorLayout` so cursor-placement math lives with the widget instead of the app target.
- Refactored `KittyCode` to consume the shared text metrics and text-editor layout helpers.
- Refactored `KittyCode` title and footer rendering to use the reusable `StatusBar` widget.
- Added reusable `KittyText.TextMutation` edit deltas and routed editor edits through them.
- Reused syntax highlighting sessions and scratch buffers instead of rebuilding them for each refresh.
- Added incremental fallback highlighting updates so single-line edits and line merges/splits patch only the affected range.
- Added background syntax-artifact prewarming for visible file types using structured concurrency.
- Added reusable text-editor hit testing in `KittyWidgets.TextEditorLayout` and switched KittyCode mouse handling to it.

## Opportunity Map

### SIMD

Status:
- Limited upside today because the hottest paths are branchy text/layout code, not large numeric kernels.

Best candidates:
- `DirtyTracker.isEmpty` and `DirtyTracker.clear()` for large buffers.
- `ScreenBuffer.fill` if profiling shows row fills dominating render time.

Action:
- Only pursue after Instruments shows buffer scans or fills as a top CPU consumer.

### Arena Allocation

Status:
- Not yet used explicitly.

Best candidates:
- `Highlighter.buildSpans` scratch arrays (`rawSpans`, `byteStyles`, output spans).
- `LanguageHighlighter.splitDocumentSpans`.
- Parser temporary node/capture collections during repeated edits.

Action:
- Introduce a reusable scratch-buffer or arena-style allocator in a lower module only after measuring highlight churn on large files.

### Zero Copy

Status:
- Good coverage already exists in input routing, renderer output, terminal writes, lexer tokenization, and syntax-node text extraction.

Largest remaining gap:
- `EditorState.refreshHighlights()` rebuilds `textBuffer.text` and re-highlights the entire document on every edit.

Action:
- Build an incremental highlighting pipeline around edit ranges and reusable scratch storage.
- Keep full-document highlighting as fallback for correctness.

### Atomics and Mutexes

Status:
- `Synchronization.Mutex` is now the shared locking primitive through `StateLock`.

Best next candidates:
- Replace lock-based counters with atomics only where the state is truly scalar, such as bounded traversal counters.

Action:
- Consider `swift-atomics` only if contention shows up in profiling.
- Do not replace general-purpose protected state with atomics where a mutex is clearer and safer.

### Swift Async Algorithms

Status:
- Not used yet.

Best candidates:
- Merge terminal input, resize, and shutdown streams in `ApplicationRuntime`.
- Debounce bursts of `SIGWINCH` resize events.

Action:
- Add only if the event pipeline grows more complex or resize storms become observable.

### Swift Algorithms

Status:
- Not used yet.

Best candidates:
- Tree flattening and presentation helpers.
- Query and highlight post-processing where chunking or stable partitioning improves clarity.

Action:
- Treat as a readability library first, not a performance library.

### Synchronization Framework

Status:
- Now part of the core synchronization story through `StateLock`.

Action:
- Keep all shared mutable caches and test doubles on the same primitive unless a stronger reason exists.

### InlineArray, ContiguousArray, Span

Status:
- `ContiguousArray` is already widely and correctly used.
- `InlineArray` and `Span` are available under the current toolchain but not yet adopted.

Best candidates:
- `Span`: borrowed contiguous views in parser and renderer helper loops where APIs currently bounce through buffer-pointer closures.
- `InlineArray`: only for tiny fixed-size hot data where profiler evidence justifies it.

Action:
- Prefer `Span` over bespoke unsafe-pointer helpers when a borrowed contiguous view improves both clarity and performance.
- Avoid forced `InlineArray` adoption without measurements.

### Metal and Shaders

Status:
- No meaningful fit today.

Reason:
- This renderer emits terminal escape bytes, not pixels. The dominant work is text layout, diffing, encoding, and I/O, which does not map naturally to Metal.

Action:
- Do not add Metal to the current terminal rendering pipeline.
- Revisit only if the project grows a pixel-based preview, minimap, image-processing feature, or offscreen raster stage.

### Aggressive Parallelism

Status:
- Present in directory scanning, but not elsewhere.

Best candidates:
- Background syntax-artifact loading.
- Background highlighting for large-file open.
- Parallel preprocessing of syntax/highlight data, but only after incremental highlighting reduces work size.

Action:
- Use structured concurrency and `@concurrent` only for CPU-bound, side-effect-free work.
- Avoid parallelizing per-keystroke paths until data movement and full-document work are reduced first.

## Ordered Execution Plan

### Phase 1

- Done: platform and synchronization simplification.
- Done: extract shared text metrics and text-editor layout helpers.
- Done: make KittyCode use shared widgets for bars instead of manual line assembly.
- Done: move text-editor hit testing out of KittyCode so widget coordinate mapping is shared with rendering.

### Phase 2

- Done for fallback languages: incremental highlight invalidation keyed by edit ranges.
- Done for highlighting internals: reusable scratch storage for highlight/span splitting.
- In progress: move grammar-backed highlighting and artifact work further off the foreground path where it preserves UI responsiveness.
- Next extraction target: tree-view hit testing and scroll-visibility math so tree interaction uses shared widget logic too.

### Phase 3

- Measure render-time row fills and screen clearing.
- Optimize `ScreenBuffer.fill` and related row operations if they show up in Instruments.
- Re-evaluate SIMD or span-based implementations only against measured bottlenecks.

### Phase 4

- Modernize the application event pipeline if needed with `swift-async-algorithms`.
- Debounce resize storms and simplify stream fan-in.

### Phase 5

- Reassess external package additions:
  - `swift-atomics` for scalar counters under contention
  - `swift-algorithms` for clarity-heavy transforms
  - `swift-async-algorithms` for stream composition

## What Not To Do

- Do not add Metal to the terminal renderer.
- Do not force `InlineArray` into non-hot code.
- Do not replace every mutex with atomics.
- Do not add aggressive parallelism to per-keystroke paths before incremental work reduction is in place.
