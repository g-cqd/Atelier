## Critical (must fix)

- **GLR state stack bookkeeping is incorrect for multi-token parses, which can drive wrong GOTO transitions and invalid parse trees.**
  - Evidence: `Sources/KittyParser/GLRParser.swift:58-65` shifts by calling `pushNode` then mutating `state`; `Sources/KittyParser/GLRParser.swift:223-225` pushes the *current* state, not the shifted state; reductions then use `Sources/KittyParser/GLRParser.swift:176-177` (`stateBeforeTop`) for GOTO.
  - Impact: reductions after >1 shift can use the wrong predecessor state.

- **Global parser stack IDs are generated through an unsafe shared mutable static, introducing Swift 6 data races.**
  - Evidence: `Sources/KittyParser/GLRParser.swift:202`, `Sources/KittyParser/GLRParser.swift:215-216`.
  - Impact: concurrent parses can race on `nextID`, and `applyReduces` relies on IDs for stack filtering (`Sources/KittyParser/GLRParser.swift:144`).

- **`DiffRenderer` can write out of bounds for valid Swift `Character` values whose UTF-8 encoding exceeds 4 bytes.**
  - Evidence: `Sources/KittyRenderer/DiffRenderer.swift:38-40`, `Sources/KittyRenderer/DiffRenderer.swift:82-87` preallocate 4 bytes and then write without bounds checks.
  - Impact: potential crash when rendering grapheme clusters / multi-scalar characters.

- **Decoder numeric accumulation can overflow and trap on malformed/unbounded input.**
  - Evidence: `Sources/KittyCodecs/KeyboardDecoder.swift:75`, `Sources/KittyCodecs/KeyboardDecoder.swift:99`, `Sources/KittyCodecs/KeyboardDecoder.swift:128`, `Sources/KittyCodecs/KeyboardDecoder.swift:152`, `Sources/KittyCodecs/KeyboardDecoder.swift:171`; `Sources/KittyCodecs/MouseDecoder.swift:70`, `Sources/KittyCodecs/MouseDecoder.swift:83`, `Sources/KittyCodecs/MouseDecoder.swift:96`.
  - Impact: a hostile or corrupted terminal stream can crash the process.

- **Bracketed paste is enabled at runtime but never actually decoded into `.paste` events.**
  - Evidence: runtime enables mode at `Sources/KittyApp/ApplicationRuntime.swift:48`; router has a `.paste` state (`Sources/KittyInput/SequenceRouter.swift:19`, `Sources/KittyInput/SequenceRouter.swift:144-156`) but no transition into it from CSI handling (`Sources/KittyInput/SequenceRouter.swift:63-83`).
  - Impact: bracketed paste payloads are misrouted/unknown, despite API exposing `InputEvent.paste`.

- **Query parser does not support standard parenthesized predicate forms (`(#eq? ...)`) used by tree-sitter queries.**
  - Evidence: `Sources/KittyQuery/QueryParser.swift:35-47` sends `(` into `parseNodePattern`; `Sources/KittyQuery/QueryParser.swift:98-100` requires an identifier immediately after `(`; predicate parser expects direct `#` at `Sources/KittyQuery/QueryParser.swift:174-177`.
  - Impact: common query files fail to parse, blocking realistic highlighting rules.

- **Grammar rule ordering is destroyed during JSON load, so start-rule selection can be wrong.**
  - Evidence: `Sources/KittyGrammar/GrammarLoader.swift:42-48` sorts `rules` keys alphabetically; parser generation uses first rule as start symbol at `Sources/KittyGrammar/ParseTableCompiler.swift:69-70`.
  - Impact: grammars with non-alphabetical start rule can compile into incorrect parsers.

- **`repeat` / `repeat1` grammar expansion is semantically incorrect in parser generation.**
  - Evidence: `Sources/KittyGrammar/ParseTableCompiler.swift:107-115` turns `repeat` into only `{0,1}` and `repeat1` into exactly `{1}`.
  - Impact: parsers reject valid repeated constructs and do not match grammar intent.

## Important (should fix)

- **Underline color cannot be reset to default in style diffs.**
  - Evidence: `Sources/KittyCodecs/SGREncoder.swift:105-107` calls `appendUnderlineColor` on changes, but `appendUnderlineColor` bails out for `.default` at `Sources/KittyCodecs/SGREncoder.swift:167`.
  - Impact: stale underline color can leak across subsequent text.

- **Cursor encoding API can trap or emit invalid numeric output for edge values.**
  - Evidence: `Sources/KittyCodecs/KittySequences.swift:70-73` force-converts `Int` to `UInt16`; decimal formatter only handles up to 4 digits cleanly (`Sources/KittyCodecs/KittySequences.swift:161-176`, especially `:164-166`).
  - Impact: negative/large coordinates can crash or produce malformed escape sequences.

- **Public buffer/tracker APIs have unchecked indexing and can crash on invalid coordinates.**
  - Evidence: `Sources/KittyRenderer/ScreenBuffer.swift:17-21`, `Sources/KittyRenderer/ScreenBuffer.swift:29-34`, `Sources/KittyRenderer/ScreenBuffer.swift:49-52`; `Sources/KittyRenderer/DirtyTracker.swift:12-21`.
  - Impact: invalid row/col/index input causes out-of-bounds traps.

- **View modifiers drop wrapped content entirely, breaking compositional semantics.**
  - Evidence: `Sources/KittyWidgets/ViewModifier.swift:26` passes `AnyViewContent()` instead of the actual `content`.
  - Impact: modifier chains do not preserve the original view tree.

- **Highlighter overlap resolution contradicts its own comment and can lose higher-priority captures.**
  - Evidence: comment says “later captures override earlier” at `Sources/KittySyntax/Highlighter.swift:35`, but sort/order+`pos` advancement (`Sources/KittySyntax/Highlighter.swift:36`, `Sources/KittySyntax/Highlighter.swift:67`) makes earlier wide spans swallow later nested spans.

- **Field-based query matching is effectively unsupported end-to-end.**
  - Evidence: field metadata is discarded in grammar expansion (`Sources/KittyGrammar/ParseTableCompiler.swift:121-122`), parse nodes are constructed without field population (`Sources/KittyParser/GLRParser.swift:165-171`), yet matcher expects fields (`Sources/KittyQuery/QueryMatcher.swift:60-63`, `Sources/KittyQuery/QueryMatcher.swift:112-114`).
  - Impact: many realistic tree-sitter queries using `field:` constraints won’t match.

- **Several `@unchecked Sendable` classes expose mutable state without synchronization or isolation boundaries.**
  - Evidence: `Sources/KittyRenderer/RenderPipeline.swift:5` (+ mutable buffers at `:7-8`), `Sources/KittySyntax/GrammarRegistry.swift:6` (+ mutating dictionaries at `:25-28`, `:65-73`), `Sources/KittyTerminal/POSIXTerminalConnection.swift:7` (+ mutable `originalTermios` at `:9`, `:55-56`, `:62`, `:84`).
  - Impact: easy to introduce data races when these are used from multiple tasks.

- **`SyntaxNode.text(from:)` can trap if `byteRange.lowerBound` exceeds source length.**
  - Evidence: `Sources/KittyParser/SyntaxNode.swift:54-56` clamps upper bound but not lower bound.

- **Reducer conflict handling returns early after first conflict and skips full reduction pass for remaining stacks.**
  - Evidence: early return at `Sources/KittyParser/GLRParser.swift:132-145`.
  - Impact: nondeterministic/incomplete GLR behavior under conflicts.

- **Test coverage gaps on critical paths**
  - `Tests/KittyCodecsTests/CodecsTests.swift:91-223` covers happy-path decoding only; no malformed/overflow sequences.
  - `Tests/KittyInputTests/InputTests.swift:20-53` has no bracketed paste start/end coverage.
  - `Tests/KittyRendererTests/RendererTests.swift:91-100` does not cover multi-byte grapheme rendering.
  - `Tests/KittyGrammarTests/GrammarTests.swift:124-170` does not validate start-rule order preservation or `repeat`/`repeat1` semantics.
  - `Tests/KittyQueryTests/QueryTests.swift:5-60` lacks parenthesized predicate syntax cases (`(#eq? ...)`) and field-constrained matching.

## Minor (nice to fix)

- **`GrammarDefinition` equality compares only `name`, ignoring rule/content differences.**
  - Evidence: `Sources/KittyGrammar/GrammarDefinition.swift:38-40`.

- **Unused route state indicates dead/unfinished routing path.**
  - Evidence: `Sources/KittyInput/SequenceRouter.swift:20` (`focusEvent`) has no active handling beyond empty `break` at `Sources/KittyInput/SequenceRouter.swift:158-159`.

- **`QueryParser` collects predicates in wildcard branch but never applies them.**
  - Evidence: `Sources/KittyQuery/QueryParser.swift:85-89` (collected), then returns `.wildcard` directly at `Sources/KittyQuery/QueryParser.swift:94`.

- **`StatusBar.render(width:)` has no guard for negative widths.**
  - Evidence: `Sources/KittyWidgets/StatusBar.swift:25-31`.

## Positive observations

- Layering and package decomposition are clear and readable (`Package.swift:24-72`), which makes reasoning about responsibilities straightforward.
- Typed error modeling is consistent across modules (`TerminalError`, `GrammarError`, `ParseError`, `QueryError`, `AppError`) and improves call-site clarity.
- The API surface uses mostly value types and explicit `Sendable` annotations, which is a good baseline for Swift 6 hardening.
- Test suite breadth across all modules is a strong foundation; although key edge cases are missing, basic behavior coverage exists in every package.
