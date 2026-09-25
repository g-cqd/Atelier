# Roadmap: diagnostics + hover, follow-on work

Insights gathered while landing the diagnostics/hover feature, ordered by intended execution.
See `multi-language-hover-design.md` for the full multi-language design.

## Order of work (09-25, book D37)
Core shared code and GitDiffViewer come first; work that only improves KittyCode is deferred. The work queue's values
follow this order.

- **Running:**
  - PERF-11 steps 1 to 3 (`docs/design/highlighting-tiers.md`): swift-syntax color after the lexer's first paint, the
    core tier job, and one Swift parse per side for color, intraline and hover;
  - 4A: the grammar corpus and its loading in the core;
  - GIT-06: commits as sections in the flat sidebar (`commit-grouping-design.md`);
  - CARD-12: a card's scroll step and a reveal's re-render;
  - the parser's recursion risks, node storage and hot paths.
- **Next:**
  - PERF-11 step 4, the grammar tier in the core (after 4A and step 2), then step 5, grammar color for GitDiffViewer's
    other languages;
  - the parser follow-ups: hidden helper nodes, query anchors, the grammar tables' cache format and compile cost
    (queue item 8);
  - HOVER-16, hover for other languages (phases M1 to M3 below), after 4A;
  - P1a to P1c, then P2: the text-first pipeline in GitDiffViewer (PERF-09);
  - PERF-11 steps 7 and 8 for GitDiffViewer: semantic tokens in AtelierLSP, then the semantic tier.
- **Then:** DIFF-01, DIFF-03 and DIFF-04 (below), the renderer seam (3L) and the time-boxed M1 renderer, 4B to 4F,
  TAB-09's panes, and synced split panes by row.
- **Deferred (KittyCode only):** PERF-11 step 6 and P3 (KittyCode on the tier job), the chunked highlight pass (queue
  item 4), the viewport query, the reparse left pending on a tab switch, and the grammar breaker's retry.

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

## Diff interaction refinements (user-requested 09-23)
Requested on 09-23; not scheduled yet. Xcode is the reference for items 2 and 3. The user's screenshots, and what
they show, are in `xcode-reference.md`.

1. **Resizable panes.** In split and stacked diffs, a divider between the old and new panes can be dragged to change
   their width (split) or height (stacked). The ratio persists per window, double-clicking the divider restores
   50/50, and the divider stays hittable without adding visible chrome.
2. **Gap-expansion drag fixes (investigate, then fix).**
   - *Direction bug:* dragging a gap handle back towards lines already shown, or past the context limit set in
     Settings, still discloses lines. While dragging, the handle may only reveal more lines or return towards its
     starting state; a negative drag never discloses anything.
   - *Edge auto-scroll:* holding a handle at the edge of the viewport or its container keeps disclosing lines in the
     drag direction, at a bounded rate that is not too fast, like autoscroll during a text selection.
   - *Two handles per gap:* a hidden run between two changes can grow from either side, so it shows two handles:
     one extending the change above downwards, one extending the change below upwards. Each gets its own hover
     state.
3. **Gutter scope ribbon.** Scope indicators and fold controls in the gutter, in the spirit of Xcode's code folding
   ribbon: highlight the enclosing block on hover, and disclose or collapse a block. It takes little or no extra
   width: the gutter's spacing is reworked into layers, with line numbers, diagnostics tint, change markers and scope
   controls on separate sides and z levels. Scope comes from the syntax model (SwiftSyntax for Swift, the lexer's
   brackets elsewhere).
4. **Compact inline view (a setting).** An inline mode that shows only the newest file's final content. The gutter,
   in the same visual language as the scope ribbon, marks each place with a change: an addition, a removal or a
   modification. Clicking a marker discloses that change in place, above the resulting lines. Compatible with the
   isolated-changes mode: gaps collapse the same way and the markers survive around them.
5. **First change on open, placed right and optional (user-requested 09-24, book DIFF-08).** Opening a file scrolls
   to its first change three rows below the top of the visible area, clear of the toolbar and the tab bar (today it
   lands offset). A setting, on by default, turns the scroll off so files open at their top; a tab that comes back to
   where it was left keeps that position either way.
6. **Scroll range and scrolling settings (user-requested 09-24, book CARD-19 and SET-09).** A pane's scroll range
   ends with its last line at the bottom (today TextKit's estimates and the scroll-past-end space leave a lot of empty
   room below the file). A scrolling settings group holds "Bounce at the edges" (off, as now), "Scroll past the last
   line" (off) and "Scroll to the first change when a file opens" (on).
