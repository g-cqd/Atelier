## Critical (must fix)

- `Sources/KittyGrammar/GrammarLoader.swift:42-48` sorts rule names alphabetically even though the comment says rule order matters, and `Sources/KittyGrammar/ParseTableCompiler.swift:68-70` then uses `grammar.rules.first` as the start symbol. Any grammar whose entry rule is not alphabetically first will compile with the wrong start production.

- `Sources/KittyGrammar/ParseTableCompiler.swift:89-113` lowers every `PATTERN` to the same `_pattern` terminal and collapses `REPEAT` / `REPEAT1` to at most one occurrence, while `Sources/KittyParser/Lexer.swift:38-83` only lexes keywords, whitespace, or single raw bytes. In practice identifiers, numbers, regex tokens, and repeated constructs from real tree-sitter grammars cannot parse, so the current pipeline is not actually `grammar.json` compatible.

- `Sources/KittyApp/ApplicationRuntime.swift:42-49` enables bracketed paste, but `Sources/KittyInput/SequenceRouter.swift:18-20`, `Sources/KittyInput/SequenceRouter.swift:63-83`, and `Sources/KittyInput/SequenceRouter.swift:144-156` never recognize the `ESC [ 200 ~` start marker. The runtime turns the mode on, but pasted text will never surface as `.paste`.

- `Sources/KittyRenderer/DiffRenderer.swift:38-40`, `Sources/KittyRenderer/DiffRenderer.swift:69-70`, and `Sources/KittyRenderer/DiffRenderer.swift:82-87` assume every `Character` fits in 4 UTF-8 bytes. That is false for multi-scalar grapheme clusters, so rendering emoji, ZWJ sequences, or combining characters can write past `charBuf` and crash. `Sources/KittyRenderer/ScreenBuffer.swift:29-35` makes this reachable from normal `write` calls.

- `Sources/KittyParser/GLRParser.swift:202-216` uses `nonisolated(unsafe)` global mutable state for `ParseStack.nextID`. `GLRParser` and `IncrementalParser` are both `Sendable`, so concurrent parses race on this counter immediately under Swift 6.

## Important (should fix)

- `Sources/KittyCodecs/MouseDecoder.swift:113-131` masks button bits with `0x03`, which drops the high-button extension bit. `MouseButton.button4` / `.button5` in `Sources/KittyCodecs/Types.swift:120-121` are therefore unreachable, and extra mouse buttons decode as primary buttons instead.

- `Sources/KittyInput/SequenceRouter.swift:46-51` routes `ESC O` (SS3) sequences into `KeyboardDecoder`, but `Sources/KittyCodecs/KeyboardDecoder.swift:47-55` interprets `ESC` + non-`[` as Alt+character. Function-key style SS3 sequences therefore decode incorrectly.

- `Sources/KittyParser/GLRParser.swift:132-145` returns out of `applyReduces` as soon as the first stack hits a conflict. Any later stacks in the array are returned unreduced for that token, which breaks GLR behavior once there is more than one active parse stack.

- `Sources/KittySyntax/Highlighter.swift:35-37` and `Sources/KittySyntax/Highlighter.swift:47-67` flatten captures purely by start offset. A broad earlier capture consumes the full region before a later nested capture is processed, so more specific captures never override outer ones.

- `Sources/KittyQuery/QueryMatcher.swift:57-82` matches each child pattern against “any child” and does not track order or reuse. The same child can satisfy multiple positions, and query semantics drift far from tree-sitter’s ordered sibling matching.

- `Sources/KittyTerminal/POSIXTerminalConnection.swift:11-13` stores a caller-supplied file descriptor, but `Sources/KittyTerminal/POSIXTerminalConnection.swift:35-42` always writes to `STDOUT_FILENO`. A custom tty/pty connection will read one fd and write another.

- `Sources/KittyRenderer/RenderPipeline.swift:5-8`, `Sources/KittySyntax/GrammarRegistry.swift:6-8`, and `Sources/KittyTerminal/POSIXTerminalConnection.swift:7-10` are `@unchecked Sendable` with mutable state and no explicit isolation boundary. `Sources/KittyApp/ApplicationRuntime.swift:69-85` already shares the terminal connection across the main actor, an input task, and signal callbacks, so the concurrency story is currently “trust me” rather than enforced.

- `Sources/KittyRenderer/ScreenBuffer.swift:17-18`, `Sources/KittyRenderer/ScreenBuffer.swift:29-35`, `Sources/KittyRenderer/ScreenBuffer.swift:49-53`, `Sources/KittyRenderer/DirtyTracker.swift:12-21`, `Sources/KittyCodecs/KittySequences.swift:67-73`, and `Sources/KittyWidgets/StatusBar.swift:25-38` all rely on unchecked indices/counts. Negative or out-of-range coordinates and widths currently trap instead of failing gracefully.

- `Package.swift:46-49`, `Sources/KittySyntax/Grammars/languages.json:2-20`, and `Sources/KittySyntax/GrammarRegistry.swift:70-72` advertise bundled grammars for many languages, but the package only ships `languages.json` and no matching `grammar.json` directories. Out-of-the-box grammar loading cannot succeed for any listed language.

- Test coverage is heavily happy-path. `Tests/KittyInputTests/InputTests.swift:8-73` never covers paste, SS3/function keys, or malformed/overflowing escape sequences; `Tests/KittyRendererTests/RendererTests.swift:53-114` never covers non-ASCII / wide graphemes; `Tests/KittyGrammarTests/GrammarTests.swift:20-199` and `Tests/KittyParserTests/ParserTests.swift:101-152` only exercise tiny literal grammars, not start-rule ordering, patterns, repetition, or GLR conflicts; `Tests/KittySyntaxTests/SyntaxTests.swift:48-66` never exercises overlapping captures.

## Minor (nice to fix)

- `Sources/KittyWidgets/ViewModifier.swift:21-27` builds modifier bodies with a fresh `AnyViewContent()` instead of the wrapped `content`, so modifier composition is structurally a no-op today.

- `Sources/KittyGrammar/GrammarDefinition.swift:38-40` defines equality by `name` only. Two different grammars with the same name compare equal, which is surprising for a value type and can poison caches or tests.

- `Sources/KittyParser/IncrementalParser.swift:44-65` only shifts `byteRange` during edits. `pointRange` and `fields` are left stale, so cursor- and diagnostic-oriented consumers will get inconsistent locations after `applying(edit:)`.

- `Sources/KittyWidgets/TextEditor.swift:32-39` hard-caps `lineNumberWidth` at 5, so files with 100,000+ lines render the wrong gutter width.

## Positive observations

- `Package.swift:23-72` has a clear layered module graph. Low-level terminal/codecs, parser/query/syntax, widgets, and app runtime are separated cleanly, which makes the defects above localized rather than tangled.

- The byte-level protocol code is easy to audit because most encoders/decoders use explicit state machines and concrete byte builders, especially in `Sources/KittyCodecs/KeyboardDecoder.swift:6-242`, `Sources/KittyCodecs/MouseDecoder.swift:5-168`, `Sources/KittyCodecs/KittySequences.swift:2-182`, and `Sources/KittyCodecs/SGREncoder.swift:3-208`.

- Core model types are mostly value types with `Sendable` / `Equatable` conformance, for example `Sources/KittyCodecs/Types.swift:3-223`, `Sources/KittyParser/SyntaxNode.swift:22-68`, and `Sources/KittyRenderer/Cell.swift:4-15`. That is a good foundation once the `@unchecked Sendable` reference types are tightened up.

- Every target has at least some tests (`Tests/`), which is a strong starting point for a from-scratch package. The biggest gap is edge-case realism rather than total absence of test scaffolding.
