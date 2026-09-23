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

## UI wave (queued behind hover/toolbar debugging)
- Findings navigator: toolbar item → scrollable list of all analyzer warnings/errors, grouped
  by file, row click jumps to the line.
- Diagnostic markers without layout shift: drop the +14pt gutter column; line-number
  decoration blending with gutter/line + trailing-edge overlay chip; both clickable; popover
  anchors on the LINE (NSPopover from the owning view with a positioning rect — fixes the
  top-of-container anchoring bug).
- Unified hover: diagnostics for the hovered squiggle join documentation in one sectioned
  surface; context menu (Show Documentation / Show Issue) as the explicit path.
- Rich popover (investigation running): custom anchored panel (Xcode Quick Help style),
  syntax-colored code via AtelierLexers+AtelierTheme, sectioned content, provenance footer,
  apple-docs corpus as the system-API tier.
- Cards list: sticky file headers — each file's collapsible title bar pins to the top of the
  scroll view while its file is partially scrolled, so collapse stays reachable; preserve the
  card rounding/clipping, shadow, and negative space against the toolbar and surroundings
  (pinned header keeps the card's visual language, likely LazyVStack pinnedViews + custom
  clipping so the floating header carries the card's top rounding + shadow).

## Reload continuity wave (user-requested)
- Differential re-comparison: on reload/auto-refresh, diff incoming FilePairs against current
  by (path, oldBlobID, newBlobID); unchanged pairs keep their RenderedText/cards untouched
  (DiffPreparer already caches by blob keys — the gap is pipeline-level set-diff + selective
  publish instead of clear-and-republish).
- No viewer collapse on reload: card fold state and scroll position survive both file reloads
  and full re-comparisons; explicitly preserved for the files that do re-render.
- Native tabs: investigate NSWindow tabbing (tabbingMode/tabbingIdentifier bridged from the
  SwiftUI WindowGroup) so comparisons can live as native macOS window tabs.

## In-app tab bar styling (user-requested; shipped)
The request targets the app's own `TabBarView` (file tabs opened from card headers), not native
NSWindow tabs. Shipped: one `TabBarLayout.gap` (6 pt) drives the inter-tab gap and the bar's inset;
tabs are Liquid Glass inside a single `GlassEffectContainer`, with a light shadow and no bar material;
the diff badge is the leading visual, and the close button takes its place on hover with an animated
swap (`TabSlotContent`); tabs are neutral, with no accent tint.

## Accent-color adaptation (research)
Adapting app accent colors throughout the UI to the selected syntax theme (beyond light/dark
matching, which is implemented as `matchesThemeAppearance`): needs a palette-extraction design
(dominant hue from theme keywords/accents), contrast guarantees, and a decision on scope
(controls? selection? badges?). Research before committing.

## Badge state fidelity (follow-up)
Per-file staged/unstaged/untracked badge states need AtelierGit to stop collapsing porcelain
v2's index (X) and worktree (Y) columns into one FileStatus, plus a path from GitStatusEntry
into SourceEntry/the comparison model. v1 approximates by side kind (working tree = unstaged
style). Cross-consumer enum change — sequence with the FileStatusProvider/GitStatusProvider
modularization move.
