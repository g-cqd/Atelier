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
