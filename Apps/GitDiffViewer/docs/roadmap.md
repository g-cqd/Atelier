# Roadmap: diagnostics + hover, follow-on work

Insights gathered while landing the diagnostics/hover feature, ordered by intended execution.
See `multi-language-hover-design.md` for the full multi-language design.

## In flight (current feature)
- Track A chrome/glue: status-bar counts, toolbar readout, card badges, overlay pipeline.
- Track B: LSPConnection + SourceKitLSPService; then TieredHoverProvider, app wiring, polish.
- AemiJSON vs Foundation benchmark (SARIF MB-scale decode; per-hover LSP messages; the
  envelope double-pass decode is the suspected win) — adoption verdicts pending numbers.

## Phase M1 — LSP genericization (after the Swift hover lands)
- Rename `SourceKitLSPService` → `LanguageServerSession`; Swift becomes descriptor data.
- Split `initializeTimeout` from `requestTimeout` in the session tuning (JVM servers need it).
- `InitializeParams` gains `initializationOptions: JSONValue?` (+ workspaceFolders).
- `Language.lspLanguageID` on AtelierSyntaxModel (spec strings; shell → "shellscript").
- `ToolStatus` gains a generic-executable identity (server rows currently borrow a placeholder
  `DiagnosticTool` — noted smell from the Tools tab work).

## Phase M2 — descriptor registry
- `LanguageServerDescriptor` table (sourcekit-lsp, typescript-language-server, gopls first;
  clangd/rust-analyzer/pyright next; kotlin-language-server last — JVM boot economics).
- `LanguageServerRegistry` keyed by (rootURL, serverID); root-marker walk (tsconfig, go.mod,
  Cargo.toml, …). Discovery via a shared `ExecutableLocating` seam (move ToolDiscovery out of
  AtelierDiagnostics so AtelierLSP doesn't import SARIF machinery); add npm-global,
  ~/.cargo/bin, ~/go/bin rungs.
- `LanguageServerHoverProvider` replaces the hardcoded-"swift" provider.
- Settings: per-server rows already exist (`lspServerLocations`); add ts-ls + gopls entries.

## Phase M3 — language-generic doc-comment tier
- Move the 20-grammar tree-sitter corpus (KittyCode `Grammars/`, ~3 MB) to a shared resource
  target both apps consume.
- New `AtelierDocComment` target: per-language `DocCommentConvention` (JSDoc/KDoc/Doxygen/
  rustdoc/godoc/docstrings → markdown), `GenericDocCommentIndex`, point-range identifier
  lookup via `QueryMatcher`, content-hash parse cache (required — GLR parse per hover is too
  slow). Slots as tier 2 behind any language server.

## Phase M4 — JSON performance (gated on benchmark verdicts)
- Apply the AemiJSON adopt/keep verdict per call site: SARIF decode (MB-scale, background),
  LSP envelope decode+classify (latency path; kill the JSONValue re-encode double-pass),
  settings blobs (expected: leave Foundation).

## Later / opportunistic
- arcleak `--baseline` from the left ref → "introduced findings only" mode; old-side rows.
- Left-side blob didOpen for LSP hover (degraded fidelity, synthetic paths) — v2 of hover.
- Semantic tokens through the same registry sessions into KittyCode's highlighter.
- Bundling clangd/rust-analyzer/gopls behind the existing bundled-directory rung (optional).
- Dissolve the `DiffCore`/`DiffGit` re-export shims (cosmetic debt).

## Non-goals (decided)
- No offline docsets tier (Dash/DevDocs) — needs real symbol resolution to avoid confidently
  wrong popovers. No LSP completion/diagnostics/definition. No node/JVM runtime management.
