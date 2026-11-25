# Design: multi-language on-hover documentation

Status: investigated, not yet scheduled. Builds on the Swift hover feature (AtelierLSP,
AtelierDocIndex, DiffTextKit hover UI).

## Summary

`SourceKitLSPService` is already ~95% language-agnostic: its configuration, didOpen cache, idle
shutdown, restart budget and timeout race contain nothing Swift-specific; the only hardcoding is
the literal `"swift"` languageID in `LSPHoverProvider`. Generalizing is therefore mostly a data
problem, not an architecture problem.

## Architecture

- **`LanguageServerDescriptor`** (AtelierLSP, pure data): executable names (ordered), args,
  `Set<Language>` served, root markers (tsconfig.json, Cargo.toml, go.mod, …),
  `initializationOptions: JSONValue?`, env override variable, extra search directories
  (npm-global bin, `~/.cargo/bin`, `~/go/bin`), and `SessionTuning` — which splits
  `initializeTimeout` from `requestTimeout` (mandatory for JVM servers).
- **`LanguageServerSession`**: rename of `SourceKitLSPService` (mechanical; behavior lands as
  data). Add `initializationOptions` + `workspaceFolders` to `InitializeParams`.
- **`LanguageServerRegistry`** actor keyed by `(rootURL, serverID)` — not by language, so one
  session can later serve both hover and semantic tokens (KittyCode's unused
  `SemanticProviderDescriptor.lsp` case binds here). Root found by walking up from the document
  matching the descriptor's root markers.
- **Discovery**: reuse the ToolDiscovery precedence via a small `ExecutableLocating` protocol;
  move ToolDiscovery(+ToolLocation/Origin/Status) into a shared target (or AtelierProcess) so
  AtelierLSP does not import AtelierDiagnostics. Add `additionalDirectories` to the walk.
- **Language detection** in the provider, not the query: `HoverQuery.documentURI` always carries
  the path; add `Language.lspLanguageID` (name matches LSP spec strings except shell →
  "shellscript", plain → "plaintext"). UI layer needs zero changes.

## Server table (v1 verdicts)

| Server | Root markers | Notes | v1? |
|---|---|---|---|
| sourcekit-lsp | Package.swift, *.xcodeproj | exists today | yes |
| typescript-language-server | tsconfig/jsconfig/package.json | `--stdio`; npm-global discovery; init 10 s | **yes** |
| gopls | go.work, go.mod | `~/go/bin`; fastest win, validates the abstraction | **yes** |
| clangd | compile_commands.json, .clangd | xcrun-discoverable; degraded without compile DB; `.h` → ObjC ambiguity | next |
| rust-analyzer | Cargo.toml | `~/.cargo/bin` | later |
| pyright/basedpyright | pyrightconfig/pyproject | prefer basedpyright (self-contained) | later |
| kotlin-language-server | build.gradle(.kts) | JVM boot 10–60 s; init 60 s, idle 600 s; doc-comment tier carries Kotlin meanwhile | last |

Bundle **no** server binaries in v1 (the bundled-directory discovery rung already exists for
later; only clangd/rust-analyzer/gopls are realistic candidates).

## No-server fallback: generic doc comments via the tree-sitter stack — feasible

- 20 `grammar.json` grammars already ship in KittyCode (`Grammars/`, ~3 MB); `GLRParser`
  produces typed trees; `QueryMatcher.execute(query:tree:pointRange:)` answers
  identifier-at-position directly. Move the grammar corpus to a shared resource target both
  apps consume.
- New target `AtelierDocComment`: `DocCommentConvention` per language (JSDoc/KDoc/Doxygen/
  rustdoc/godoc/docstring marker stripping + tag → markdown rules), `GenericDocCommentIndex`
  (mirrors DocCommentIndex: content-hash incremental), `GenericIdentifierLocator`, provider.
  Parse cache by content hash is required (GLR parse per hover is too slow).
- Caveats: external-scanner-dependent grammars (python indent, yaml, ruby heredocs) parse
  degraded, but comments + declaration heads survive GLR error forests.

## Tiering

`TieredHoverProvider` stays a dumb sequential composer: language server → generic doc-comment
tier (Swift keeps its swift-syntax doc-index tier). Optional additive `HoverContent.Source
.docComment` case for a provenance badge.

## Settings

Per-server (not per-language) `ToolLocation` records (`isEnabled` + `customPath`), same Tools-tab
row style, `--version` probing works for all six.

## Non-goals

No LSP completion/diagnostics/definition; no offline docsets (Dash/DevDocs) — they answer
stdlib questions and need real symbol resolution, string matching would produce confidently
wrong popovers; no node/JVM runtime management; no `didChange` incrementality; no per-project
LSP config passthrough.

## Phases

1. Genericize (rename session, timeout split, InitializeParams additions, lspLanguageID).
2. Descriptor table + registry + discovery extraction + `LanguageServerHoverProvider`.
3. Wire GitDiffViewer: ts-ls + gopls, per-server settings.
4. Grammar corpus move + `AtelierDocComment` tier (Go, TS/JS, Kotlin, Java, C/C++, Rust, Ruby).
5. clangd/rust-analyzer/pyright, `.h` disambiguation, KittyCode semantic-token reuse.

## Phase 4 assessment: the doc-comment tier without a server (09-25)

HOVER-16 criterion 2: without a language server, hover answers from the source's own doc comments. This section
measures the bundled grammars, compares the design's grammar path with a lexer path, and recommends one per language.

### Grammar check

`BundledGrammarMeasurements` (KittySyntaxTests, `GDV_BENCH`), one grammar per process, at `work` weight 2, on the
debug build. CPU time is the thread's own (`CLOCK_THREAD_CPUTIME_ID`); the machine ran at load 15–45 on 8 cores, so
the wall clock is up to 2.5× the CPU time. One realistic file per language, 39–66 KB, from upstream releases: Go
1.27.1 `net/http/request.go`, KaTeX `src/Parser.ts`, npm's `@npmcli/arborist/lib/node.js`, OpenJDK 27
`java/util/ArrayList.java`, Kotlin 2.1.0 `kotlin/text/Strings.kt`, Lua 5.4.6 `lvm.c`, jsoncpp 1.9.5
`json_reader.cpp`, Rust 1.98.1 `core/src/iter/range.rs`, Ruby 3.3.0 `lib/optparse.rb`. The 50 KB column scales the
file's parse time linearly.

| Grammar | Compiles | Compile CPU (peak rise, states) | Parse CPU (file) | Per 50 KB | ERROR bytes | Highlighter keeps it |
|---|---|---|---|---|---|---|
| TypeScript | yes | 29.3 s (+277 MiB, 8,876) | 0.22 s (39 KB) | 0.29 s | 0.0 % | yes |
| JavaScript | yes | 6.2 s (+50 MiB, 2,136) | 1.17 s (51 KB) | 1.16 s | 0.0 % | yes |
| Go | yes | 3.5 s (+18 MiB, 1,032) | **35.4 s** (52 KB) | 34.3 s | 2.0 % | **no** |
| Java | yes | 5.9 s (+49 MiB, 1,919) | **45.1 s** (66 KB) | 34.1 s | 0.03 % | yes |
| Kotlin | yes | 9.2 s (+120 MiB, 3,230) | 0.93 s (64 KB) | 0.72 s | **61.8 %** | no |
| C | yes | 2.9 s (+60 MiB, 1,988) | 4.85 s (59 KB) | 4.1 s | 0.2 % | yes |
| C++ | yes | 35.3 s (+211 MiB, 4,133) | 0.26 s (58 KB) | 0.23 s | 0.0 % | yes |
| Rust | yes | 13.3 s (+172 MiB, 7,058) | 0.31 s (53 KB) | 0.29 s | **32.8 %** | no |
| Ruby | yes | 4.6 s (+40 MiB, 1,345) | 0.67 s (63 KB) | 0.53 s | 0.0 % | yes |

- The 09-23 state-limit and empty-token failures are gone: all nine compile.
- The design's grammar deadline is 250 ms. **Only C++ meets it**; TypeScript is just over.
- **Go and Java parse for 34 s of CPU per 50 KB**, which rules them out whatever the budget. Go's parse also leaves
  the highlighter on the lexer, although its 2.0 % error share passes the 5 % gate; the cause is not yet known.
- **Kotlin and Rust fail the gate:** Rust's sample is macro-heavy (`macro_rules!`), and Kotlin misreads most of
  `Strings.kt`.
- JavaScript, C and Ruby read correctly but take 0.5–4 s per 50 KB. A background indexer could take that; a
  per-hover parse could not.
- **One file per language is a thin sample.** A grammar that fails here is out. One that passes needs the corpus
  runs step 4 plans before it ships.

### Two paths for TypeScript, JavaScript and Go

**(a) The design's path.** PERF-11 step 4 puts the grammar tier in the core (`docs/design/highlighting-tiers.md`
§7, size L, not started). A doc-comment tier then reads grammar definitions from the facts store (§3.4). Beyond step
4, it needs:
- each grammar's upstream `tags.scm`, which the corpus does not bundle;
- support in `QueryParser` for its `#select-adjacent!` and `#strip!` predicates, or the same adjacency rule in
  Swift;
- a declaration pass that publishes `SyntaxDeclaration`s, and a lookup that reads them.

For v1 it answers TypeScript, answers JavaScript at a 1.2 s parse per 50 KB, and answers nothing for Go until the
GLR hot paths (queue item `glr-hot-paths`) cut Go's parse by two orders of magnitude.
- **Size:** L (step 4) plus M (tags queries, declaration pass, tier). Blocked on step 4, and for Go on a parser
  fix.
- **Shared with GitDiffViewer's grammar colour (step 5):** everything. Warming the tables, the parse, the gate and
  the facts store are step 5's own, so the doc tier costs one query per parse.

**(b) A lexer path.**
- Comments are already lexical tokens: `CodeScanner` knows each language's line and block comments, strings and
  template literals.
- A per-language table recognises the declaration head that follows a doc comment:
  - TypeScript and JavaScript: `function name`, `class Name`, `interface Name`, `type Name =`, `enum Name`,
    `const|let|var name =`, `name(` inside a class body, and `export` / `default` / `async` / `abstract` prefixes;
  - Go: `func name(`, `func (recv) name(`, `type Name`, and `const` / `var` names, grouped ones included.
- A doc comment is the run of comments that ends on the line just above the head:
  - JSDoc `/** */` with its `@param` and `@returns` tags turned into markdown;
  - godoc `//` lines.
- The identifier under the pointer comes from the lexer's identifier token at the position.
- Matching is by name, as the Swift doc index already does, so a name declared in several files lists each
  declaration.
- **Known misses:** JavaScript regular-expression literals, which the lexer does not know; declarations that no head
  pattern names, such as object-literal methods and computed names; and anything a macro or code generator writes.
- **Size:** M, about 600–900 lines with tests, and nothing to wait for:
  - a new core target, with no swift-syntax: comment conventions, head tables, identifier lookup;
  - the extractor seam `DocCommentIndex` already has, taught per language;
  - the app feeding TypeScript, JavaScript and Go files and their corpus to the index;
  - the index as the tier behind the language server for those languages.
- **Shared with step 5:** the lexical tier's comment and identifier tokens, which colour already produces for every
  side, and the output type (`SyntaxDeclaration`) and index. Grammar facts could replace the extractor per language
  later without touching the index, the provider or the app.

### Recommendation

A mix per language, built on one interface:
- **Now: path (b) for TypeScript, JavaScript and Go.** It closes criterion 2 for v1 without waiting for step 4. Go
  cannot take path (a) at today's parse speed.
- **Later, per language, path (a):** a language moves to grammar declarations when its grammar clears the gate and
  a background budget (proposed: 2 s CPU per 50 KB) on its corpus. Today that is TypeScript, C++ and Ruby, and
  JavaScript at the budget's edge. The move is data: a change in the extractor table, nothing more.
- Kotlin, Java, C, Rust and Go keep the lexer path until their grammar or the parser improves; Kotlin, Java, C and
  Rust also need their head tables when phase 5 adds their servers.

### API sketch

```swift
// AtelierSyntaxModel (exists): SyntaxDeclaration, SyntaxFacts, SyntaxFactsStore.

// New target AtelierDocComment: AtelierSyntaxModel and AtelierLexers, no swift-syntax.
public protocol DeclarationExtracting: Sendable {
    /// The documented declarations of `text`, in source order.
    func declarations(in text: String, language: Language) -> [SyntaxDeclaration]
}

/// Path (b): comment tokens from the lexical scanner, declaration heads from a per-language table.
public struct LexicalDeclarationExtractor: DeclarationExtracting {
    public static func supports(_ language: Language) -> Bool  // TypeScript, JavaScript and Go at first
}

/// How a language writes doc comments, and how to turn one into markdown.
public enum DocCommentConvention: Sendable {
    case jsDoc, goDoc  // later: kDoc, javadoc, doxygen, rustdoc, yard
    public static func convention(for language: Language) -> DocCommentConvention?
    public func markdown(fromComment text: Substring) -> String?  // nil for a plain comment
}

/// The identifier token under a position, from the lexer.
public enum LexicalIdentifierLocator {
    public static func identifier(in text: String, language: Language, line: Int, utf16Column: Int) -> String?
}

// AtelierDocIndex: DocCommentIndex routes each file to an extractor by language. Swift keeps swift-syntax; a later
// GrammarDeclarationExtractor reads SyntaxFactsStore.declarations and fits the same seam.
public init(extractors: [Language: any DeclarationExtracting], store: SyntaxFactsStore? = nil)

// The hover tier: DocIndexHoverProvider takes an identifier locator, so the same provider serves Swift
// (IdentifierLocator) and the other languages (LexicalIdentifierLocator).
```

In GitDiffViewer, a TypeScript, JavaScript or Go hover then asks for `[language server, doc-comment index]`, and
Swift keeps `[language server, doc index, SDK]`.
