# Syntax color in tiers (PERF-11): design

- **Status:** proposal, 2026-09-25. Nothing in the product changes with this document.
- **Code:** `main` at `0948ee1`. Paths follow the fix plan's convention: `Atelier*` targets live in
  `Packages/AtelierCore/Sources/`, `Kitty*` targets in `Apps/KittyCode/Sources/`, and `DiffComparison`,
  `DiffRendering`, `DiffTextKit` and `GitDiffViewer` in `Apps/GitDiffViewer/Sources/`.
- **Request:** book PERF-11 (R121): "imo, the highlighting should be a tiered job, lexer and grammar started in
  parallel, swift syntax and sourcekit when enabled, used to also enrich the color syntaxing ideally and provide more
  information at that moment as well". Related: PERF-09, MOD-01, MOD-02, HOVER-16, HOVER-19, LANG-01.
- **Machine:** Apple M3, 8 cores, 16 GB, macOS 26, Swift 6.4.0 release toolchain, release builds. Other agents'
  jobs shared the machine (load average 14 to 19 during the runs quoted here, higher earlier).
- **Lab:** `/tmp/tiers-lab` (a scratch package over this worktree's `AtelierCore` and `KittyCode`, and the inputs)
  and `/tmp/tiers-lsp` (a sourcekit-lsp probe). The appendix shows how to rerun them.

## Summary

**The tier model.** One job per file revision runs up to four tiers at once, off the main thread. Each tier paints
over the ones below it as soon as it lands, and each keeps what it learned in a per-file facts store.

| Tier | Runs | Layer | Typical cost, measured | Beyond color, it learns |
|---|---|---|---|---|
| 0. Lexer (`AtelierLexers`) | always | `lexical` | 0.02–0.22 ms per Swift file of 5–71 KB | line entry states, comment and string ranges |
| 1. Grammar (GLR, `AtelierParser`) | languages whose grammar qualifies | `structural` | JSON 65 ms at 198 KB; Python 18 ms at 8 KB; Swift 74 ms to 1.5 s | the tree, definitions, error share |
| 2. swift-syntax (`AtelierSwiftSyntax`) | Swift, when enabled | `syntactic` (new) | 1–14 ms per Swift file of 5–71 KB | declarations, doc comments, token boundaries |
| 3. Semantic tokens (sourcekit-lsp) | Swift on disk, when enabled | `semantic` | 4–11 ms warm; first tokens 0.2–1.2 s after opening | symbol kinds and modifiers |

**What the measurements change.**
- **For Swift, swift-syntax beats the grammar on every count.** Parsing and classifying a Swift file takes
  1–14 ms with swift-syntax. The GLR grammar takes 54 ms to 1.4 s to parse the same files. Two of the five real
  files then fail the 5 % quality gate (6.2 % and 28.2 % of their bytes lie under ERROR nodes), so 1.1–1.4 s of
  work is thrown away. Loading Swift's cached tables costs 2.1 s of CPU, more than the 1.7 s a cold compile takes.
  The recommendation is that swift-syntax be Swift's structural tier whenever it is enabled, with the GLR Swift
  grammar only a fallback (question Q1).
- **The GLR grammar pays off for other languages**, JSON and Python among those measured.
- **sourcekit-lsp returns no semantic tokens for a diff side that is not on disk.** A side read from git history gets
  a synthetic `atelier-blob://` URI, and after 20 s it still had none. The tier can serve only the working-tree side
  and KittyCode (Q3).

**Two findings about the code today** (section 1):
- KittyCode's editor highlights with the lexer. Grammar color appears only from the pass that runs after a file
  opens, and the next full refresh replaces it.
- The merged-highlighting API and `semanticProvider` in `LanguageHighlighter` have no caller (review Kitty S17).

**Build order** (section 7). The first step stands alone: swift-syntax color on the Swift sides of GitDiffViewer,
over the lexer's first paint, as an attribute-only update. Grammar color for GitDiffViewer's other languages comes
once 4A moves the grammar stack into the core.

## 1. What exists today

Each line below was read in the code at `0948ee1`.

| Area | What the code does | Where |
|---|---|---|
| GitDiffViewer color | The lexer scans each whole side while a diff is prepared, off the main actor. The tokens become `LineTokens` in UTF-16 offsets. `DiffRenderer.attributed` writes them into the storage as `.foregroundColor` before the first paint, so color is baked into the text. | `DiffRendering/RenderedDiff.swift` (`PreparedDiff.init`), `DiffRendering/DiffRenderer.swift` (`tokensByLine`, `attributed`) |
| GitDiffViewer intraline | For Swift, `SwiftSyntaxTokenRanges` parses a whole side on `SwiftSyntaxStack`, lazily and only when paired lines need the syntax granularity (3I). Other languages use `CodeTokenRanges`. | `AtelierSwiftSyntax/SwiftSyntaxTokenRanges.swift`, `AtelierDiff/DiffModel.swift` |
| Hover | Tiered hover providers, with sourcekit-lsp first. `DocCommentIndex` runs its own swift-syntax parse of every Swift file in the changeset and the corpus. So a Swift side is parsed twice, once for intraline and once for hover. | `AtelierLSP/TieredHoverProviders.swift`, `AtelierDocIndex/DocCommentIndex.swift` |
| KittyCode grammar | `LanguageHighlighter.Session` parses with the GLR grammar, queries `highlights.scm` with capture roles resolved once, and falls back to the lexer below the 5 % gate (`maxErrorBytePercent`). It reuses the last tree when the source hash matches. | `KittySyntax/LanguageHighlighter.swift` |
| KittyCode editor | `refreshHighlights()` lexes the viewport on the main actor, and the full pass runs on a detached task. Both use sessions made with `preferGrammar: false`, so they use the lexer only. The grammar colors a file only in the pass that runs after it opens (`LanguageHighlighter.highlightDocument` after `ensureArtifacts`), and the next full refresh replaces those colors with the lexer's. | `KittyEditor/EditorStateCore.swift` (`currentHighlightSession`, `computeFullHighlight`), `KittyEditor/EditorStateFileSystem.swift` |
| Merging | Tokens carry a `HighlightLayer`, one of `lexical`, `structural` or `semantic`, with no layer for swift-syntax. `HighlightMerger` (3G) paints by layer, then width, then priority, into one per-byte array over the whole document. `LineTokens` is the flat per-line buffer. | `AtelierSyntaxModel/HighlightToken.swift`, `HighlightMerger.swift`, `LineTokens.swift` |
| Semantic tokens | `LSPSemanticTokenDecoder` decodes data and deltas and is tested, but nothing calls it. AtelierLSP's client capabilities cover hover only, and no `semanticTokens` request exists. `Session.semanticProvider`, `highlightDocumentMerged` and `highlightViewportMerged` have no caller either (review Kitty S17). Worse, `highlightDocumentMerged` waits for the provider before it returns any color. | `AtelierSyntaxModel/LSPSemanticTokenDecoder.swift`, `AtelierLSP/LSPTypes.swift` |
| Edits | `GrammarParser` reparses the whole source every time ("no previous tree is reused"). `SyntaxTree.applying(edit:)` shifts node ranges and reparses nothing. No incremental reparse exists. | `AtelierParser/GrammarParser.swift` |
| Grammar tables | Compiled tables are cached on disk under the temporary directory, in `kittycode-cache`, keyed by grammar hash and format version (v18). Swift's table file is 112 MB. | `KittySyntax/CompiledTableCache.swift`, `GrammarRegistry.swift` |
| The pipeline | P1a, P1b, P1c, P2, P3 and 4A are queued, and none of their types exist yet (`LexState` as the lexer's state, `LineLexer`, `DecorationStore`, `renderingAttributesValidator`, `HighlightCoordinator`). | `docs/reviews/2026-09-23-fix-plan.md` ("Then: the text-first progressive pipeline"), review §7.4 |

The task brief says KittyCode colors with the grammar. The code only half agrees: the highlighter can, but the
editor keeps grammar color only until its first full refresh. So "KittyCode keeps grammar color through scrolls and
edits" is a new behavior, delivered in step 6.

## 2. Measurements

All figures are medians of thread CPU time, in release builds, over files of this repository. Thread time does
not grow when the machine is busy, but wall time does: under the heavier load earlier in the day, wall times were 2
to 7 times these (the Swift table took 5.9 s to load and 11.8 s to compile). The deadlines in section 4.7 are wall
times, so they carry a margin.

**Per file** (`tierbench` and `grammarsplit`; 31 runs for the lexer, 5 for the grammar, 9 for swift-syntax):

| File | Size | Lexer | Grammar: parse / query / whole tier | Error bytes (gate) | swift-syntax: parse / parse + classify |
|---|---|---|---|---|---|
| `HighlightTokenTests.swift` | 4.7 KB | 0.015 ms | 54 / 8.7 / 74 ms | 4.8 % (passes) | 0.48 / 1.0 ms |
| `Lexer.swift` | 10.8 KB | 0.034 ms | 174 / 17 / 215 ms | 0 % | 1.1 / 2.9 ms |
| `Rope.swift` | 29 KB | 0.087 ms | 632 / 46 / 783 ms | 0 % | 2.9 / 7.1 ms |
| `ViewRenderer.swift` | 61 KB | 0.22 ms | 1,393 / 59 / 1,509 ms | 28.2 % (fails) | 5.5 / 13.9 ms |
| `EditorStateCore.swift` | 71 KB | 0.15 ms | 1,126 / 83 / 1,159 ms | 6.2 % (fails) | 6.0 / 13.4 ms |
| `languages.json` | 1.4 KB | 0.007 ms | 0.6 / 0.5 / 1.2 ms | 0 % | – |
| JSON grammar's `grammar.json` | 12.9 KB | 0.051 ms | 2.3 / 1.8 / 4.8 ms | 0 % | – |
| Go grammar's `grammar.json` | 198 KB | 0.88 ms | 30 / 23 / 65 ms | 0 % | – |
| `main_actor_budget.py` | 8.3 KB | 0.025 ms | 8.6 / 8.2 / 18 ms | 0 % | – |

- The whole tier is `Session.highlightDocumentTokens`: parse, query and token building. The query comes from the
  split tool.
- Swift's grammar costs about 11–23 ms per KB. JSON's costs 0.33 ms per KB, and Python's about 2 ms per KB, from its
  single sample.
- `SwiftSyntaxTokenRanges`, today's intraline parse, costs 1.1, 2.6, 6.4, 12.9 and 13.9 ms on the five Swift files.
  That is about what a swift-syntax color tier would cost, so one shared parse could give color, token boundaries and
  declarations for the price of today's intraline parse alone.

**Grammar tables:**

| Grammar | Cold compile | Load from the disk cache | States |
|---|---|---|---|
| JSON | 3 ms | 3 ms | 44 |
| Python | 774 ms | 400 ms | 1,522 |
| Swift | 1,660 ms | 2,093 ms (112 MB file) | 2,898 |

- The process that loaded Swift's cached tables peaked at 509 MB resident. The one that compiled them and parsed the
  five files peaked at 148 MB of footprint.
- Queue item 8 still says a first compile costs 28–47 s and 0.6–1.2 GB. The compile has since become much cheaper,
  and the cache now costs Swift more than it saves.

**Other paths:**
- A 60-line viewport queried from a parsed tree through `highlightViewport` takes 0.4–4.7 ms. Most of that is
  KittyCode's scan of the whole source for line starts, and its copy of that source.
- The per-byte `HighlightMerger.merge` over lexical and structural tokens takes 0.09 ms at 4.7 KB, 0.7 ms at 29 KB and
  5.1 ms at 198 KB.

**sourcekit-lsp semantic tokens** (the `/tmp/tiers-lsp` probe):
- **Setup:** the probe runs sourcekit-lsp 6.4 over a one-target package holding a copy of `AtelierText`, with a
  full-document request.
- **Startup:** `initialize` takes 0.84–1.45 s.
- **First tokens:** the first file (29 KB) gets tokens 1,217 ms after `didOpen`, and a second file (9 KB) 235 ms
  after. Before that the server answers with no tokens.
- **Warm requests:** 9.9–10.7 ms for 29 KB (1,425 tokens) and 4.1–4.9 ms for 9 KB (303 tokens).
- **What the tokens cover:** only identifier kinds: class, enum, enumMember, function, interface, method, property,
  struct, typeParameter and variable. No keywords, comments or literals.
- **Synthetic URIs:** the same text opened under an `atelier-blob://` URI gets no tokens after 20 s, nor in an
  earlier run that waited 90 s.
- **A lower bound:** in this repository's packages, whose build settings take longer to load, the first tokens will
  come later.

**Measured by the reviews and still valid:**
- Setting rendering attributes for one screen costs 0.84 ms, and for every token of an L file 34 ms. Setting colors
  through storage edits costs 743–1,911 ms of relayout (perf-gui, review §7.2).
- KittyCode's 60-line viewport lex costs 71–119 µs (3B, queue item 2).

## 3. The tier model

### 3.1 Shared vocabulary (AtelierSyntaxModel)

These are UI-free types, so both apps and every tier share them (MOD-01, MOD-02):

- **`SourceSnapshot`**: a document ID, a `SourceRevision`, a `Language` and the UTF-8 bytes. The bytes are a
  side's string in GitDiffViewer and a rope snapshot in KittyCode, so a snapshot copies nothing.
- **`SourceRevision`**: the freshness key. It holds the document ID, the language (LANG-01: choosing another language
  makes a new revision) and either a **content key** or a **version**.
  - GitDiffViewer uses the content key, which is the blob ID. Blob IDs are content hashes on every kind of source
    (`DiffPreparer`), so a result stays valid for as long as it is cached.
  - KittyCode uses the version, `documentVersion`. It can compute a content key off the main actor as well, so that
    an undo back to text it has seen reuses the results.
- **`TierUpdate`**: what a tier emits. It carries the tier, the revision it read, the lines it covers, their tokens
  as `LineTokens`, its coverage (below) and optional facts. A tier emits several: the visible lines first, then the
  rest.
- **`HighlightLayer`** gains `syntactic` between `structural` and `semantic`: `lexical` 0, `structural` 1,
  `syntactic` 2, `semantic` 3. swift-syntax is the compiler's own parser, so it outranks a tree-sitter grammar, and
  the language server's identifier kinds refine both.
- **Coverage.** A tier is either complete or sparse over the lines it covers:
  - A **complete** tier accounts for every byte of those lines: the grammar once its parse passes the gate, and
    swift-syntax. Where it leaves a byte without a token, the byte is plain text on purpose.
  - A **sparse** tier (semantic tokens) speaks only about the bytes it covers.

  The rule matters because no role means "plain". The lexer colors `set` in `let set = [1]` as a keyword. swift-syntax
  knows it is a name and emits no token for it. Merged by layer alone, the lexer's keyword color would show through.

### 3.2 Merging

The merge extends 3G's order. For each line:

1. Take the highest complete tier that has landed for the line's current revision. Drop every tier below it.
2. Add each sparse tier above it.
3. Paint by layer, then width, then priority, as `HighlightMerger` documents.

In practice:
- Semantic tokens over swift-syntax recolor names only, and keywords, comments and literals keep swift-syntax's
  colors.
- Before any complete tier lands, the lexer is the baseline.

The merge runs per line, for visible lines first, in P1c's per-line merge: the per-byte, whole-document merge
costs 5 ms at 198 KB and needs a whole-document array.

### 3.3 The tiers

| | 0. Lexer | 1. Grammar | 2. swift-syntax | 3. Semantic tokens |
|---|---|---|---|---|
| **Input** | Snapshot bytes; with P1a, a line source and the stored `LexState` checkpoints | Snapshot bytes and the grammar's artifacts: tables, query, capture roles, scanner | Snapshot bytes, Swift only (HOVER-19) | The document on disk, opened or changed in sourcekit-lsp, with the version sent |
| **Output** | `lexical` tokens, complete for the language's token kinds; line entry states | `structural` tokens from `highlights.scm`, complete once gated; the tree; the error-byte share | `syntactic` tokens from swift-syntax's classification, with declaration names marked `.declaration`; complete | `semantic` tokens with modifiers, sparse; the result ID for deltas |
| **Runs on** | Pool thread, at user-initiated QoS for the visible lines, utility for the rest. KittyCode's edited line is re-lexed on the main actor in the text path (1–2.5 µs, perf-tui) | Pool thread, utility QoS, at most `max(1, cores / 4)` parses at once per app | `SwiftSyntaxStack`'s 64 MiB thread (async `run`), utility QoS | The server process, with the reply decoded on a pool thread |
| **Freshness** | Revision; KittyCode re-lexes from the edit until a line starts in its old state | Revision. The last tree is reused by content hash, and its tokens are carried across an edit (section 4.5) | Revision, one parse per (document, content key) | Document version: a reply for an older version is dropped |
| **Cancellation** | Checks every 256 lines (P1a's `ProgressiveHighlighting`) | `GLRParser` checks every 256 tokens; a deadline cancels the child task | Between the parse and the classification, and per chunk of classified lines | Cancels the LSP request (`$/cancelRequest`) |
| **Failure** | Cannot fail: a language without a scanner stays plain | Tables missing or failed to compile, parse throws (`tooManyTokens`, `tooDeep`), deadline, or the gate fails. Recorded against the grammar hash and content key; the lines keep the lexer | Deadline (200 ms), or more than 5 % of bytes in unexpected nodes (the same gate). The lines keep what is below | No server, repository not trusted (1A), document not on disk, error, or a 2 s timeout. The lines keep what is below |
| **Learns** | Entry state per line (resumable lexing); comment and string ranges | The tree (a viewport re-query costs 0.4–4.7 ms); definitions (captures with `.definition`); error share; parse throughput per grammar | Declarations (name, kind, name range, whole range, doc comment, signature); token boundaries per line; fold ranges | Symbol kind and modifiers per identifier (deprecated, static, readonly, declaration) |
| **Consumers of what it learns** | KittyCode's keystroke re-lex; intraline boundaries for languages without a better tier | Viewport re-query and carrying across edits; HOVER-16's doc-comment tier for other languages; a declaration outline; skipping grammars that cannot meet the budget | Intraline boundaries (replacing `SwiftSyntaxTokenRanges`' own parse); hover's doc-comment tier (replacing `DocCommentIndex`'s own parse); naming a hunk's enclosing declaration | Hover asks sourcekit-lsp only over an identifier, not over a keyword, literal or comment; navigation tells a type from a value; deprecated names can show it |

### 3.4 The syntax facts store

`SyntaxFactsStore` is an actor in the core, keyed by `SourceRevision`, and bounded in bytes with least-recently-used
eviction (PERF-08's third criterion). Each entry holds what the tiers above published, each part stamped with its
tier:
- `tokenBoundaries`: UTF-16 ranges per line.
- `declarations`: `[Declaration]`.
- `symbolKinds`: a sorted array of ranges and kinds.
- `quality`: the error share and the outcome of each tier: finished, failed with a reason, skipped with a reason, or
  timed out.

Readers get a snapshot of the entry at one revision. The store never holds a grammar tree:
- KittyCode's buffer holds its own tree for re-queries and edits.
- GitDiffViewer is read-only and has every line's tokens once the query is done, so it drops the tree then.

The store answers the "provide more information at that moment" half of R121:
- **Hover:** the swift-syntax parse that colors a side also feeds hover. `DocCommentIndex` then indexes
  changeset files from the facts instead of parsing them again.
- **Intraline:** `SelectedSyntaxTokenRanging` reads the token boundaries, so the syntax granularity costs no parse
  of its own.
- **Navigation:** the declarations give an outline and the declaration that encloses each change.
- **HOVER-16:** grammar definitions give the doc-comment tier for other languages.

### 3.5 Where the code lives (MOD-01, MOD-02)

- **Shared types** (`SourceSnapshot`, `SourceRevision`, `TierUpdate`, the coverage rule, the per-line merge, the
  facts types and store, and the `HighlightTier` protocol) go in `AtelierSyntaxModel`.
- **The tier job** is a new `AtelierHighlighting` target that depends on `AtelierSyntaxModel` and `AemiRuntime`
  only.
- **Each tier lives with its engine:** `LexicalTier` in `AtelierLexers`, `GrammarTier` in the grammar stack (4A
  brings the corpus and the artifact loading into the core), `SwiftSyntaxTier` in `AtelierSwiftSyntax`, and
  `SemanticTokenTier` in `AtelierLSP`.
- **Each app composes its tiers** in its composition root. So highlighting pulls in no language server, and only
  GitDiffViewer's and KittyCode's roots decide which tiers run.

```swift
public protocol HighlightTier: Sendable {
    var layer: HighlightLayer { get }
    var coverage: TierCoverage { get }
    func supports(_ language: Language) -> Bool
    /// Emits the visible lines first, then the rest; throws `CancellationError` or a `TierFailure`.
    func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws
}
```

The job is caller-driven, as the core tier requires. `HighlightTiers.run(_:tiers:visibleLines:clock:)` is an async
function that runs one child task per supported tier in a task group and returns each `TierUpdate` through an
`AsyncStream` that the app consumes. It starts no unstructured task and takes no `TaskProvider`.

## 4. Scheduling

### 4.1 One job per revision, all tiers at once

- Every supported tier starts together (PERF-11's first criterion). None waits for another, so a slow or failing tier
  never delays the ones below it (its second and third criteria).
- **The grammar and swift-syntax tiers of one Swift file.** Under Q1's recommendation, swift-syntax replaces the
  grammar for Swift when it is enabled, so the lexer and swift-syntax start in parallel. With swift-syntax off, the
  lexer and the GLR grammar do.
- **Cancellation.** A new revision cancels the job of the old one, except for the carry rule in KittyCode (4.5).
  Closing a file cancels its job. So does leaving it: switching files in GitDiffViewer, or switching buffers in
  KittyCode.
- **Deadlines.** Each child races its deadline against the injected clock, so tests drive them with `TestClock`.

### 4.2 Warming grammar tables ahead

- A table load costs 3 ms for JSON, 0.4 s for Python and 2.1 s for Swift, and never runs on the path to the first
  text.
- **GitDiffViewer** warms the grammars of the changeset's languages when a comparison opens: one at a time (5b found
  that warming several at once went over 1 GB), at utility QoS, in the order of the languages' first files in the
  list.
- **KittyCode** keeps its prewarm of the visible tree's languages, made serial. Its `Task(priority:)` moves onto
  the task provider (review Kitty S18).
- **A file whose grammar is not warm yet** shows the lexer's color. Its grammar tier waits for the warm to finish and
  runs only if the file is still shown.

The disk cache itself needs a look: Swift loads slower than it compiles. That is queue item 8's work, and section 8
lists it as a risk.

### 4.3 Visible lines first

- **Lexer:** P1a's `ProgressiveHighlighting` lexes the viewport, then chunks outward.
- **Grammar:** the parse has to cover the whole file, but the query can run on the visible range first (0.4–4.7 ms
  from the tree), emit, and then cover the rest.
- **swift-syntax:** the tier classifies the visible range first (`classifications(in:)` in SwiftIDEUtils), then the
  rest.
- **Semantic tokens:** the tier asks `semanticTokens/range` for the visible lines when the server offers it, then
  `full`.

When the viewport moves, the app tells the job. Each tier's next chunk then starts at the new viewport: the lexer's
chunks and the grammar's and swift-syntax's classification of lines not yet emitted. No tier restarts.

### 4.4 GitDiffViewer: both sides, cards, prefetch

- **Each side is its own snapshot**, and the old and new sides run in parallel. When both sides have the same blob
  (an unchanged file shown whole), the facts store holds one entry, and both use it.
- **Only displayed files run the upper tiers:** the file shown, and the mounted cards of a folder comparison.
  `DiffPreparer.prefetch` keeps doing the lexer only, as it does today.
- **The job is a child of the render task**, as review §7.4 requires of decoration tasks. Its updates carry the
  pipeline generation and the rendered text's ID. An update for a text that is no longer published is dropped.
- **Results are cached by blob ID** in the facts store and a token cache beside it. Going back to a file already
  refined shows the refined color one frame after its text, with no parse.

### 4.5 KittyCode: edits

**A keystroke** (text path, perf-tui §3, P3):
1. The edit goes into the rope, `documentVersion` goes up, the dirty rows are drawn, and the frame is flushed.
2. The lexer re-lexes the edited line from its stored entry state until a line starts in its old state, usually one
   line, at 1–2.5 µs, on the main actor. This is the one piece of tier work on the main thread. Section 9, Q6, asks
   to keep it there.

**Carry across the edit.** The upper tiers' tokens of the previous revision stay on screen for lines the edit did
not touch:
- Lines below the edit move by the change in the line count.
- A token's offsets are relative to its line, so they stay valid.
- The edited lines show the lexer's color until the tiers land again.

A carried token is marked stale. It is replaced when the new revision's tier lands, or dropped back to the lexer if
that tier fails.

**Reparse after a pause:**
- The job for the new revision starts 150 ms after the last keystroke, the same debounce the gutter uses. A newer
  keystroke cancels it.
- The grammar reparses the whole file. `SyntaxTree.applying(edit:)` shifts the old tree's ranges so that a viewport
  re-query of untouched lines stays right while the reparse runs, but it reuses nothing.
- True incremental GLR reparsing, which would reuse unchanged subtrees, does not exist (Q5).
- For Swift, swift-syntax reparses in 1–14 ms. It has incremental parsing (`IncrementalParseTransition`), which is
  worth taking only if a full parse ever misses its budget.

**Semantic tokens on edits.** The tier sends `didChange` with the full text after the same debounce, then asks for
a delta against the last result ID. `LSPSemanticTokenDecoder.applyDelta` and `SemanticTokensState` already exist.

### 4.6 Concurrency and memory

- **Grammar parses:** at most `max(1, cores / 4)` at once per app. Two on this machine, so a folder comparison with
  many Swift cards cannot take every core.
- **swift-syntax threads:** each parse gets its own 64 MiB-stack thread. Stack memory is reserved, and only as much
  as the parse touches is committed. The job limits them to `cores / 2`.
- **Language server:** one request in flight per document.
- **Memory:** the facts store and the token cache share one byte budget. Step 3 sets the number from a measurement;
  64 MB is a starting point. A GitDiffViewer tree lives only until its query is done. KittyCode keeps one tree per
  open buffer.

### 4.7 Budgets

The budgets are set from the measurements in section 2: thread CPU time, with a margin for a loaded machine. Each
step that adds a tier adds a benchmark gated by `GDV_BENCH` that guards its budget (PERF-09's fifth criterion).

| Stage | Budget | Measured |
|---|---|---|
| Lexer, visible lines of one side | ≤ 1 ms | 71–119 µs for 60 lines (KittyCode) |
| Lexer, whole side | ≤ 2 ms per 100 KB | 0.22 ms at 61 KB, 0.88 ms at 198 KB |
| swift-syntax, one side up to 100 KB, parse and classify | ≤ 50 ms; the deadline is 200 ms | 1.0–13.9 ms at 5–71 KB |
| Grammar, one pass: parse and query, per side or per edit | 250 ms deadline (review §7.4) | JSON 65 ms at 198 KB, Python 18 ms at 8 KB, Swift 74–783 ms at 5–29 KB |
| Grammar, whether to start at all | Start only when the predicted time (bytes × this grammar's last observed ms per KB) is under the deadline. The first file of a language always starts. | Swift 11–23 ms/KB, so about 12 KB; JSON 0.33 ms/KB; Python about 2 ms/KB |
| Grammar table warm | Off the path to the first text; one grammar at a time | JSON 3 ms, Python 0.4 s, Swift 2.1 s |
| Semantic tokens, per request | 2 s timeout; no deadline on display, since it is the last refinement | 4–11 ms warm; first tokens 0.2–1.2 s after `didOpen` |
| Applying one tier's update, main thread, GitDiffViewer | ≤ 1 ms per screen | 0.84 ms per screen of rendering attributes (perf-gui) |
| Applying one tier's update, main actor, KittyCode | ≤ 1 ms for the visible rows | to be measured in step 6 |

A grammar that times out, or fails its gate, three times in a row on files of one language stops starting for that
language until its grammar hash changes. That is review §7.4's per-language breaker. The count lives with the
throughput figure in the grammar's capability record.

## 5. Painting

Each tier after the first paint changes colors only. It never changes text, fonts or line heights, so nothing lays
out again.

### 5.1 GitDiffViewer, TextKit 2

**Today.** Color is written into the storage before the first paint (`DiffRenderer.attributed`). A later tier cannot
recolor through the storage: editing it relayouts, which costs 743–1,911 ms for an L or XL file.

**The design.** It uses P2's approach, with P2's `DecorationStore` taking the tiers:

1. **The first paint is unchanged.** Until P2 lands, the lexer's colors stay in the storage. After P2, `RenderedText`
   is plain, and the lexer's colors arrive like any other tier's.
2. **A per-pane store holds each tier's `LineTokens` per side:** `RefinedColors` at first, P2's `DecorationStore`
   later. It maps a row to its side and source line through `RowMeta.oldNumber` and `newNumber`, and a line to its
   UTF-16 start through `RenderedText.lineStarts`. Bidi placeholders keep the source's offsets, so the tokens need
   no remapping (`tokensByLine`' contract).
3. **The validator.** Each pane's `NSTextLayoutManager.renderingAttributesValidator` fills the attributes of the
   fragment being displayed: for each row in the fragment, the merged tokens (3.2) as `.foregroundColor` rendering
   attributes. These draw over the storage's color, and they affect neither layout nor size.
4. **When a tier lands,** the store installs the update on the main actor, if the text ID and generation still
   match. It then calls `invalidateRenderingAttributes(for:)` on the range of the displayed fragments whose rows the
   update covers. TextKit runs the validator for those fragments only. Rows off screen are colored by the validator
   when they scroll into view.
5. **The layout fragment.** `DiffLayoutFragment` keeps drawing row backgrounds, emphasis and squiggles. When
   swift-syntax's token boundaries change the emphasis ranges (the syntax granularity), P2's emphasis side table takes
   them, and the fragment gets `setNeedsDisplay` without new layout.
6. **Both kinds of pane.** The scrolling pane (`DiffTextView`) and the card pane (`EmbeddedDiffTextView`, whose
   content storage `StaticTextLayout` lends) each install the validator on their own layout manager.
7. **The renderer seam (3L, M1).** The store is backend-neutral. A CoreText renderer reads the same merged tokens per
   visible row when it draws, so a tier that lands invalidates the visible tiles.

Theme roles map to colors only. GitDiffViewer's palette already uses no font traits, so no tier can change glyph
widths.

### 5.2 KittyCode, the terminal

- **The buffer.** After P3, `LineHighlights` holds `LineTokens` per tier, or their per-line merge, in place of
  `[[StyledSpan]]`.
- **When a tier lands** on the main actor, the coordinator does four things:
  1. It applies the update only if its revision is the current `documentVersion` (P3's gate G2), or if it is a
     carried update (4.5).
  2. It merges the visible lines it covers.
  3. It resolves their styles and compares each line's spans with those it replaces.
  4. It marks dirty only the rows whose spans changed.
- **The frame** then rewrites only those rows' cells (P3's dirty rows, R7, over the cell `DirtyTracker`).
- **Lines off screen** are merged lazily, when they scroll in.
- **Wrapping.** A cell's width does not depend on its style, so the wrap cache, which is keyed by
  `documentVersion`, stays valid. The terminal may use bold and italic.

### 5.3 Rules common to both

- A tier never blanks a line. Where it has nothing, the line keeps what is below it, down to plain text.
- Applying the same update twice changes nothing. The validator and the terminal rebuild their colors from the store
  every time, so an update has no effect that could be lost.
- An update applies only to the revision it read, and so never to text that has changed. KittyCode's line-shifted
  carry (4.5) is the one exception, and it is marked stale.

## 6. Fitting PERF-11 into the plan

| Item | Before PERF-11 | Change |
|---|---|---|
| P1a (text and lexer APIs) | `LineSource`, `LexState`, `LineLexer`, `ProgressiveHighlighting`, `lexAll` | `ProgressiveHighlighting` emits `TierUpdate`s stamped with the revision, so the lexer is tier 0 of the job. Nothing else changes. |
| P1b (phased diff) | `DiffStructure`, `IntralineEmphasis`, `MovedBlocks` | `IntralineEmphasis` takes Swift's token boundaries from the facts store (step 3) rather than from `SwiftSyntaxTokenRanges`' own parse. The provider protocol stays. |
| P1c (tokens and merging) | `LineTokens`' final layout; per-line layer merging for visible lines | Step 2 lands the per-line merge, with four layers and the coverage rule. P1c keeps the layout, and PERF-11 settles review §7.5's open choice in favor of 12 bytes: semantic tokens need modifiers, which the 8-byte form lacks. |
| P2 (GitDiffViewer adoption) | Stage 0 to 3, `DecorationStore`, colors through `renderingAttributesValidator`, `.decorated(textID, layer)` | Step 1 takes the validator slice early, as `RefinedColors`, and P2's `DecorationStore` absorbs it. `.decorated` is sent once per tier update. Stage 1 becomes "every tier's colors". |
| P3 (KittyCode adoption) | `LineHighlights` with the G1–G3 gates, `HighlightCoordinator`, dirty rows | The coordinator drives the core tier job for 4 tiers (step 6), with the carry rule across edits and grammar color that survives scrolls and edits. G1–G3 apply per tier. |
| 4A (grammar corpus in the core) | The grammar folders move to a core resource target; decode and cache fixes | It also moves the artifact loading into the core (`SyntaxArtifactsCache`, `GrammarRegistry`, `CompiledTableCache`) and adds `GrammarTier`, with the warm-ahead, the deadline, the gate, the failure record and the throughput predictor (step 4). Without this, GitDiffViewer cannot get grammar color, because an app does not import another app's module. |
| B11 (semantic tokens into `LanguageHighlighter.semanticProvider`) | A KittyCode-only, pull-based provider, waited for inside the merge | Retargeted to a core `SemanticTokenTier` in AtelierLSP (steps 7 and 8). The unused `semanticProvider`, `documentURI`, `highlightDocumentMerged` and `highlightViewportMerged` are deleted (Kitty S17). |
| Queue item 8 (grammar compile cost) | "28–47 s and 0.6–1.2 GB" | Measured now: a 1.7 s compile, and a 2.1 s load of a 112 MB cached table. The item should compare loading with compiling, and change the cache format or drop the cache for grammars that compile faster than they load. |
| HOVER-16 | Language servers per language, a doc-comment tier without one | Its doc-comment tier for other languages reads grammar definitions from the facts store (section 3.4). |
| HOVER-19, LANG-01 | Swift-only tiers; a language chooser planned | swift-syntax and semantic tokens run for `.swift` only. The language is part of `SourceRevision`, so choosing another language restarts every tier. |

The new steps are 1, 2, 3, 5 and 8. Steps 4, 6 and 7 extend 4A, P3 and B11.

## 7. Build order

Each step is one reviewable change: one track, with its tests and, for a tier, its gated benchmark. Refactors land in
commits apart from behavior changes.

**Step 1. GitDiffViewer: swift-syntax color on Swift sides, after the lexer's** (size M; depends on nothing
queued).
- **Change:**
  - add `HighlightLayer.syntactic`;
  - add a swift-syntax classifier that makes `syntactic` tokens with complete coverage, run on `SwiftSyntaxStack`;
  - add a per-pane `RefinedColors` store and the rendering-attributes validator on both kinds of pane;
  - `RenderPipeline` starts the tier per displayed Swift side after `.published`, as a child of the render task,
    stamped with the generation, the text ID and the blob;
  - a setting, "Refine Swift color with swift-syntax", on by default.
- **Files:**
  - `AtelierSyntaxModel/HighlightToken.swift`;
  - `Packages/AtelierCore/Package.swift` (AtelierSwiftSyntax gains `SwiftIDEUtils`);
  - new `AtelierSwiftSyntax/SwiftSyntaxHighlights.swift`;
  - new `DiffTextKit/RefinedColors.swift`;
  - `DiffTextKit/DiffTextView.swift`, `EmbeddedDiffTextView.swift`;
  - `DiffComparison/RenderPipeline.swift` and a new `RenderPipeline+Refinement.swift`;
  - `DiffComparison/ViewerSettings.swift`, `GitDiffViewer/Views/SettingsView.swift`.
- **Acceptance:**
  1. The first paint is byte-identical to today's (a pixel comparison).
  2. In `let set = [1]`, `set` is drawn in the keyword color at first and in the plain text color once the tier
     lands.
  3. The tier's landing invalidates no layout fragment (a layout-count spy).
  4. An update for a superseded render is dropped.
  5. A non-Swift file never reaches swift-syntax.
  6. With the setting off, no parse runs.
  7. A gated benchmark keeps the tier at 50 ms or less per side at 71 KB, and the application at 1 ms or less per
     screen.
  8. `main-actor-budget.sh` passes.

**Step 2. The core tier job and the per-line merge** (size M; a refactor, no behavior change).
- **Change:**
  - `HighlightTier`, `TierUpdate`, `SourceRevision` and `TierCoverage`;
  - `LayeredLineTokens` with the coverage rule (P1c's per-line merge);
  - `HighlightTiers.run` in a new `AtelierHighlighting` target;
  - `LexicalTier` and `SwiftSyntaxTier`;
  - step 1's wiring moves onto the job.
- **Files:**
  - new `AtelierSyntaxModel/TierUpdate.swift`, `LayeredLineTokens.swift`;
  - new `AtelierHighlighting/HighlightTier.swift`, `HighlightTiers.swift`;
  - new `AtelierLexers/LexicalTier.swift`, `AtelierSwiftSyntax/SwiftSyntaxTier.swift`;
  - `Packages/AtelierCore/Package.swift`;
  - `DiffComparison/RenderPipeline+Refinement.swift`.
- **Acceptance:**
  1. With fake tiers on a `TestClock`, a tier that throws or passes its deadline leaves the other tiers' updates.
  2. A slow tier does not delay a fast one (`AsyncProbe` order).
  3. Visible lines come first.
  4. Cancelling the job stops every tier.
  5. The coverage rule: a complete tier hides lower layers on its lines, and a sparse one does not.
  6. A lexical-only merge equals `HighlightMerger`'s.
  7. GitDiffViewer's pixels are unchanged from step 1.

**Step 3. Swift syntax facts: one parse per side** (size M).
- **Change:** the facts types and the byte-bounded `SyntaxFactsStore`. `SwiftSyntaxTier` publishes declarations and
  token boundaries. `SwiftSyntaxTokenRanges` and `DocCommentIndex` read from the store for changeset files.
- **Files:**
  - new `AtelierSyntaxModel/SyntaxFacts.swift`, `SyntaxFactsStore.swift`;
  - `AtelierSwiftSyntax/SwiftSyntaxTier.swift`, `SwiftSyntaxTokenRanges.swift`;
  - `AtelierDocIndex/DocCommentIndex.swift`;
  - `DiffComparison/HoverDocumentation.swift`.
- **Acceptance:**
  1. A parse counter shows one swift-syntax parse per blob and side for color, intraline and hover together.
  2. The intraline emphasis and the hover documentation are identical to today's.
  3. The store evicts past its bound.
  4. The bound is set from a measured memory figure.

**Step 4. The grammar tier in the core** (size L; extends 4A, which it absorbs or follows).
- **Change:**
  - the corpus and the artifact loading move into the core;
  - add `GrammarTier`: tables warmed one grammar at a time, the deadline, the gate, the failure record keyed by
    grammar hash and content key, the throughput predictor and the breaker;
  - `KittySyntax.LanguageHighlighter` wraps it.
- **Files:** 4A's list (`KittySyntax/Grammars/`, `GrammarRegistry.swift`, `LanguageHighlighter.swift`,
  `GrammarHighlightEngine.swift`, `CompiledTableCache.swift`, `AtelierGrammar/GrammarLoader.swift`, both manifests),
  plus a new `GrammarTier.swift` in the core.
- **Acceptance:**
  1. Every bundled grammar loads from the core.
  2. A deadline cancels a parse (`TestClock`).
  3. A gate failure is recorded, and the same content is not parsed again.
  4. A file predicted over the budget starts no parse (a spy).
  5. Three failures stop the grammar for its language until its hash changes.
  6. KittyCode's suites pass.

**Step 5. GitDiffViewer: grammar color for its other languages** (size M; depends on steps 2 and 4).
- **Change:** the changeset's grammars are warmed when a comparison opens, and the grammar tier runs per displayed
  side through the same store. Swift runs the GLR grammar only when swift-syntax is off (Q1).
- **Files:** `DiffComparison/RenderPipeline+Refinement.swift`, `DiffComparison/DiffViewerModel+Loading.swift`,
  `DiffComparison/ViewerSettings.swift`.
- **Acceptance:**
  1. A JSON and a Python side refine to grammar color after the lexer's.
  2. A grammar that is not warm leaves the lexer's color, then refines if the file is still shown.
  3. A failed gate keeps the lexer's color.
  4. A gated benchmark guards the 250 ms deadline on the JSON and Python samples.

**Step 6. KittyCode on the tier job** (size L; P3's coordinator; depends on steps 2 and 4, and on P1a for the
keystroke re-lex).
- **Change:** the `HighlightCoordinator` drives the job, carries colors across edits, reparses after the debounce,
  and marks only changed rows dirty. The unused merged-highlighting API goes.
- **Files:** P3's list (`KittyEditor/EditorStateCore.swift`, a new `KittyEditor/HighlightCoordinator.swift`,
  `KittyWorkspace/DocumentBuffer.swift`, `KittyWidgets/TextEditor.swift`, `KittySyntax/LanguageHighlighter.swift`,
  `KittySyntax/LineHighlights.swift`).
- **Acceptance:**
  1. Grammar color on a JSON file survives a scroll, a full refresh and an edit elsewhere in the file. Today the
     lexer's color replaces it.
  2. The edited lines show the lexer's color until the reparse lands.
  3. An update for an older version is dropped (G2).
  4. A keystroke stays within review §7.4's budget (1 ms median, 8 ms at p99).
  5. Applying a tier costs 1 ms or less of main-actor time for the visible rows (a gated benchmark).

**Step 7. Semantic tokens in AtelierLSP** (size M; B11 retargeted).
- **Change:**
  - the client capabilities advertise semantic tokens, with refresh support;
  - `SourceKitLSPService` gains `semanticTokens(full:)`, `delta` and `didChange`, and keeps the legend;
  - the reply is decoded with `LSPSemanticTokenDecoder`;
  - add `SemanticTokenTier`.
- **Files:** `AtelierLSP/LSPTypes.swift`, `SourceKitLSPService.swift`, a new `AtelierLSP/SemanticTokenTier.swift`,
  `AtelierSyntaxModel/LSPSemanticTokenDecoder.swift`.
- **Acceptance**, over a scripted transport:
  1. The request has the right shape.
  2. A delta is applied against the last result ID.
  3. A reply for an older version is dropped.
  4. A 2 s timeout ends as a `TierFailure`.
  5. A synthetic URI is never sent.

**Step 8. The semantic tier in both apps, behind a setting** (size M; depends on steps 2, 6 and 7).
- **Change:**
  - "Semantic color from sourcekit-lsp", off by default and subject to the trust gate (1A);
  - GitDiffViewer asks only for sides on disk, and KittyCode for its files;
  - symbol kinds go to the facts store, and hover reads them to skip asking the server over a keyword, literal or
    comment.
- **Files:** `DiffComparison/ViewerSettings.swift`, `RenderPipeline+Refinement.swift`, `HoverDocumentation.swift`,
  `KittyEditor/HighlightCoordinator.swift`, KittyCode's configuration.
- **Acceptance:**
  1. With the setting off, no request is made (a spy).
  2. A history side never asks.
  3. With it on, identifiers refine and keywords keep swift-syntax's colors.
  4. A server that does not answer leaves the lower tiers' colors.

**Later, once the steps above land:**
- HOVER-16's doc-comment tier and an outline for other languages, from grammar facts;
- the declaration that encloses each change, named in the change navigator.

## 8. Risks

- **The disk cache can make Swift slower.** Loading Swift's 112 MB table costs more than compiling it. With
  swift-syntax enabled (Q1), Swift never loads it. If the GLR Swift grammar is kept, queue item 8 must fix the cache
  first.
- **The quality gate throws work away late.** Two of the five Swift files failed only after 1.1–1.4 s of parsing.
  The predictor and the breaker bound the loss for any language; only a faster parser removes it (queue item
  `glr-hot-paths`).
- **Rendering attributes can disappear.** TextKit drops them when a fragment is laid out again (a resize, or a gap
  reveal), so the validator must rebuild them from the store every time. Setting them once without a validator would
  lose colors on the next layout.
- **Colors can visibly change more than once.** Moving from the lexer to a complete tier changes many colors at
  once, which is the point of the refinement. A carried color that is dropped after a failed reparse changes back,
  and only KittyCode's carry rule can cause that.
- **Contention.** A folder comparison of many Swift cards runs two tiers per side per card. The per-app limits
  (4.6), and running the tiers only for mounted cards, bound it. The first measurement in step 5 checks it.
- **Memory.** Every open KittyCode buffer holds its grammar tree, and the facts store is bounded. The swift-syntax
  threads reserve 64 MiB of stack each, which costs address space rather than memory.
- **The semantic numbers are a lower bound.** The first tokens took 0.2–1.2 s from a small package. The real
  packages load their build settings more slowly.

## 9. Open questions

Each question has a recommendation. None blocks step 1, which assumes Q1's recommendation and Q7's default.

- **Q1. Should swift-syntax replace the GLR grammar for Swift?**
  - Measured: the GLR Swift parse takes 54 ms to 1.4 s, 2 of 5 real files fail the gate, and the tables cost 2.1 s to
    load. swift-syntax takes 1–14 ms and reads Swift as the compiler does.
  - **Recommendation:** yes, whenever swift-syntax is enabled. The GLR Swift grammar then runs only with swift-syntax
    off, and only on files the predictor lets through. For Swift, "the lexer and the grammar start in parallel"
    becomes "the lexer and swift-syntax start in parallel".
- **Q2. Should grammar color be opt-in per language?**
  - **Recommendation:** no global opt-in. A grammar colors by default once its language qualifies: its corpus match
    rate, its samples passing the gate, and its throughput within the budget, all recorded with the grammar. Today
    that is JSON and Python. Each other language joins as the compiler gaps in fix plan §5b close. A per-language
    setting can turn a grammar off.
- **Q3. Are sourcekit-lsp's semantic tokens worth their latency, per diff side?**
  - The server's first answer takes 0.2–1.2 s after opening a file, on top of its startup. Then they cost 4–11 ms,
    and they recolor identifiers only. A side read from git history gets none.
  - **Recommendation:**
    - off by default in both apps;
    - with the setting on, GitDiffViewer asks only for working-tree sides, and KittyCode for its files;
    - never for history sides;
    - always subject to the trust gate.
  - Their clearest value is the symbol kinds for hover and navigation, more than the color.
- **Q4. After an edit in KittyCode, should the upper tiers' colors be carried on untouched lines until the reparse
  lands?**
  - **Recommendation:** yes. Otherwise a keystroke drops a whole screen of grammar color back to the lexer's for
    100–1,000 ms. The edited lines take the lexer's color at once.
- **Q5. Should the GLR parser get incremental reparsing, reusing unchanged subtrees?**
  - **Recommendation:** not now. Reparse whole files after a 150 ms pause, within the 250 ms deadline. Revisit if a
    language that qualifies misses the deadline on files of common size. swift-syntax's incremental parsing is
    available if its full parse ever misses its own budget.
- **Q6. Is the one exception to "off the main thread" acceptable?** The exception is KittyCode's re-lex of the edited
  line on the main actor, in the text path, at 1–2.5 µs.
  - **Recommendation:** yes. Moving it off the main actor would show the edited line uncolored for a frame, and
    saves nothing.
- **Q7. Should each tier be a setting of its own?**
  - **Recommendation:**
    - swift-syntax: on by default;
    - semantic tokens: off by default;
    - grammar: per language, as in Q2;
    - the lexer: always on.
  - All of them appear under Settings > Syntax Color in GitDiffViewer and in KittyCode's configuration, with the
    same names.
- **Q8. What memory bound should the facts store have?**
  - **Recommendation:** decide from step 3's measurement; 64 MB shared with the token cache is a starting point.

## 10. Remaining P1 and P2 after PERF-11 (09-25)

PERF-11 steps 1 to 3 (`d28b7d3` to `f884256`) took part of the plan's P1 and P2 (section 6). This is what each item
still needs, read in the code at `e7509975`, and the PERF-09 step that builds it. "Step" below means a hand-back of the
PERF-09 lane, not a step of section 7.

**P1a, text and lexer APIs (AtelierText, AtelierLexers).** PERF-09 step 1.
- `LineSource`, `TextLines` and the rope's conformance: none exists. AtelierDiff has its own `DiffSource`, with
  `SubstringLines` and `ByteLines`, and the lexers read a whole side's bytes.
- `LexState`, `LineLexer` and `LexStates`: the scanners scan a whole text only and keep no state, so no line can be
  scanned alone; a viewport lexed on its own is wrong inside a block comment or a multi-line string (perf-core L7).
- `ProgressiveHighlighting` as tier 0: `LexicalTier` scans the whole side before it emits the visible lines, then emits
  the rest from the tokens it already has. It keeps no states between runs.
- `lexAll`: none exists.
- Not in P1a: `LexStates.apply(_:)`, the re-lex after an edit, serves KittyCode's keystroke path only. It goes with P3
  and section 7's step 6, which D37 defers.

**P1b, phased diff (AtelierDiff).** PERF-09 step 2.
- Landed before PERF-11: D1's discard pass (`solveMatched`), D2's cost limit and Myers' cancellation (2H), and a D
  bound on the intraline Myers (`LineDiff.diff(_:_:maximumEdits:)`).
- `DiffLimits`: none. The limits live apart: `IntralineDiff.maximumLineLength`, `maximumChangedShare` and
  `maximumRangesPerSide`, `LinePairing.maximumPairs`, and `LineDiff`'s `costLimit` parameter.
- `DiffStructure`: none. `DiffModel.init` builds everything at once: the edit script, the pairing, every paired line's
  emphasis and the moved blocks.
- `IntralineEmphasis`: none; the emphasis is computed for every paired line inside `DiffModel.init`. PERF-11 step 3
  already gives the syntax granularity Swift's token boundaries from the facts store, so the new phase takes them
  from there, and only visible changes are emphasized first.
- `MovedBlocks` as a phase: `MovedBlocks.detect(removed:added:)` exists, but `markMovedBlocks` interns every changed
  line a second time through a `[Substring: Int]` table (Core S14), runs of candidates are uncapped, and the result is
  two `Set<Int>`s. D6 (reuse the interned ids, bitmaps, a candidate cap) is open.
- D3: `DiffModel.lines(of:)` still splits with `utf8.split` and maps each line to a `Substring`; `TextLines` (step 1)
  is its memchr replacement.
- D4: `LineInterner` hashes with XXH64 into `[UInt64: Int]` plus a collision map and a byte arena; one flat seeded
  table is open.
- D5: the D bound exists; running on UTF-16 units without the token arrays, and the range-based cleanup, are open.
- D8: `HistogramSolver` is generic over `Hashable` elements; the dense arrays over interned ids are open.
- Core S13: `LinePairing` compares bigrams of every removed and added pair up to 40,000 pairs, whatever their lengths;
  the length gate is open.
- `DiffSource` becomes an alias of `LineSource`, which moves AtelierDiff onto AtelierText.

**P1c, tokens and merging (AtelierSyntaxModel).** PERF-09 step 1.
- Landed with PERF-11 step 2: the flat per-line buffer (`LineTokens`, perf-core M1, from 3G) and the per-line merge
  with the coverage rule (`LayeredLineTokens`).
- Remaining: the 12-byte token that section 6 settled. `LineTokens` holds 32-byte `HighlightToken`s, with a layer and a
  priority per token, and `LayeredLineTokens.merged(line:)` runs `HighlightMerger`'s per-byte map on each line it
  merges. With 12-byte `LineToken`s (start, length, role, modifiers), each tier resolves its own overlaps before it
  cuts its tokens into lines, and the merge lays each layer over the one below in one pass.

**P2, GitDiffViewer adoption.** PERF-09 step 3, after steps 1 and 2.
- Stage 0, plain text first: not yet. `PreparedDiff.init` lexes both whole sides, and `DiffRenderer.attributed` writes
  the lexer's colours into the storage before the first paint, so colour is on the path to the first text.
- Stage 1, colour through `renderingAttributesValidator`: in place for the tiers after the lexer (`RefinedColors`,
  PERF-11 step 1). The lexer's colour joins it once the storage is plain.
- Stage 2, emphasis and moved blocks into a side table the layout fragment draws: not yet; both are baked into the
  attributed text (`.diffEmphasis`) and the row metadata when the text is built.
- Stage 3, the diagnostics overlay: it follows the rendered text today; step 3 checks that it redraws without new
  layout once the stages split.
- `DiffStructure` and decorations in place of `PreparedDiff`: waits for step 2.
- `DecorationStore`: none; `RefinedColors` holds the tiers' colours per pane and becomes the store's colour part.
- `.decorated(textID, layer)`: none; `RenderPipeline` emits `.published` and `.finished` only.
- The viewport (`perf11-viewport`): the tier job colours about 80 lines around a side's first change first, since the
  panes do not report the rows they show.
- Budgets and guards: stage deadlines on the injected clock, and a benchmark per stage.

## Appendix: rerunning the measurements

Every run goes through `~/.agent-harness/bin/work run --agent tiers --weight 2 -- …`, with
`PATH="$HOME/.swiftly/bin:$PATH"`.

- `/tmp/tiers-lab` holds `Package.swift`, which depends on this worktree's `Apps/KittyCode` and
  `Packages/AtelierCore` by path, and on swift-syntax for `SwiftIDEUtils`. It also holds `samples/<language>/`.
  - `swift build -c release`, then `.build/release/tierbench samples swift json python` for the lexer, the grammar
    session, the viewport query, the merge and swift-syntax.
  - `.build/release/grammarsplit <KittySyntax/Grammars> samples <name>` for the cold compile and the parse and query
    timed apart.
  - The raw output is in `run-cpu.txt` and `run-split-cpu.txt`. The earlier wall-time runs under heavier load are in
    `run-cold.txt` and `run-split.txt`.
- `/tmp/tiers-lsp` holds `probe.py <package root> <sourcekit-lsp> <files…>`. It opens each file under its `file://`
  URI and under an `atelier-blob://` URI, times the first non-empty `semanticTokens/full`, then four more requests.
  `pkg/` is the one-target package it serves.
- The repository's own gated benchmarks cover parts of this: `BundledGrammarMeasurements` (a compile and large
  samples per grammar), `LexerThroughputBenchmark`, `TokenPipelineBenchmark` and `SyntaxTierModelTests`' benchmark.
  The benchmarks each step adds guard the budgets in section 4.7.


## Decisions (09-25)

The user settled the open questions this note raised; where an answer differs from the recommendation above, the
answer wins (book D33 to D36):

- **Q1, Swift's structural tier (D33):** "merged but glr as background and not prioritized". swift-syntax is the Swift
  structural tier and paints first; the GLR Swift grammar still runs for Swift, in the background at the lowest
  priority, never ahead of any other tier's work, and its layer merges under swift-syntax's when it lands.
- **Q2, grammar color per language (D34):** on by default once a language qualifies; a setting per language turns it off.
- **Q3, semantic tokens (D35):** on by default where possible: used automatically for every working-tree side and
  KittyCode file once the language server is trusted. History-only sides still get none, since sourcekit-lsp returns
  nothing for them.
- **KittyCode's grammar color (D36):** fixed ahead of the tier work, so a qualifying language keeps its grammar color
  across refreshes and edits.
- **Order of work (D37):** core and GitDiffViewer first. Steps 1 to 5 and 7 go ahead; step 6, KittyCode on the tier
  job, is deferred with the other KittyCode-only work. Step 8 lands GitDiffViewer's half first, which needs steps 2
  and 7 only; KittyCode's half waits for step 6.
