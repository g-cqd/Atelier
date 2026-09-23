# Requirements audit

**Every `file:line` in this document refers to commit `10ae905`** (`main`, 2026-09-23 08:11 CEST). Comment-only
sweep commits will land on `main` after this audit and shift line numbers. To follow a reference, read
`git show 10ae905:<path>`.

Each requirement in `book.md` gets one verdict: Met, Partially met, Not met, Regressed, Needs visual
confirmation, or Superseded. `plan.md` orders the remaining work.

## Summary

| Area | Met | Partially met | Not met | Regressed | Needs visual confirmation | Superseded | Total |
|---|---|---|---|---|---|---|---|
| PROC | 6 | 2 | 0 | 0 | 0 | 0 | 8 |
| DIAG | 4 | 3 | 1 | 0 | 0 | 0 | 8 |
| TOOL | 1 | 1 | 0 | 1 | 0 | 1 | 4 |
| HOVER | 6 | 4 | 1 | 0 | 5 | 2 | 18 |
| DUI | 2 | 1 | 1 | 0 | 0 | 0 | 4 |
| SET | 4 | 3 | 1 | 0 | 0 | 0 | 8 |
| CARD | 3 | 2 | 3 | 0 | 3 | 0 | 11 |
| TAB | 4 | 0 | 0 | 0 | 1 | 1 | 6 |
| GIT | 1 | 2 | 1 | 0 | 0 | 0 | 4 |
| WIN | 1 | 0 | 0 | 0 | 2 | 0 | 3 |
| PERF | 2 | 5 | 0 | 0 | 1 | 0 | 8 |
| JSON | 1 | 2 | 0 | 0 | 0 | 0 | 3 |
| MOD | 0 | 2 | 1 | 0 | 0 | 0 | 3 |
| QUAL | 3 | 2 | 2 | 0 | 0 | 0 | 7 |
| **Total** | **38** | **29** | **11** | **1** | **12** | **4** | **95** |

95 entries: 91 active requirements and 4 superseded ones.

## Top 10 gaps, by user impact

1. **Reloads still collapse the viewer (GIT-03, GIT-04).** Auto-refresh after a save, the Reload button, Swap and
   a commit in a terminal all blank the card list into "Comparing…" and lose the scroll position. A two-sided
   reload clears everything when its first side lands (`DiffComparison/DiffViewerModel.swift:282-290`, GDV B2).
   A one-sided reload that changes a file unpublishes the cards before their replacement is ready
   (`DiffComparison/RenderPipeline.swift:122-124`, GDV B3).
2. **Hovering runs sourcekit-lsp inside any repository the user opens (QUAL-07).** Hover is on by default, and
   the language server starts with the repository as its workspace and working directory
   (`GitDiffViewer/App.swift:244-255`, `AtelierLSP/SourceKitLSPService.swift:225-234` and `:341-349`). A hostile
   repository's build configuration can then run code (Sec C1). git's isolation also leaves command-running keys
   unpinned (Sec C2, H1).
3. **The sticky headers keep three defects the user reported on 09-22 (CARD-03, CARD-04, CARD-06).** A pinned
   header's material is deliberately unclipped and translucent (`GitDiffViewer/Views/CombinedDiffView.swift:228-241`),
   and the header-body seam doubles at rest. The rework has only started: one untracked file, nothing wired.
4. **The system-wide lag fix is neither installed nor measured (PERF-05 to PERF-07).** `eeb7ffa` removed the
   per-header double material, but the installed build predates it, and no after-measurement of WindowServer
   exists. Every expanded card body still carries a live material, and the embedded gutter's draw cost grows with
   the square of its rows (GDV B8).
5. **The toolbar findings button and diagnostics label never appear after a run (DIAG-05, DUI-01).** They read
   only an unobserved property, so SwiftUI never refreshes them (`DiffComparison/DiagnosticsModel.swift:20-39` and
   `:51`, GDV B9).
6. **The card list, the default view, has no diagnostics (DIAG-03, DUI-03, HOVER-14).** No squiggles, no gutter
   markers, and no diagnostics in its hover panel (`DiffTextKit/EmbeddedDiffTextView.swift` has no overlay).
7. **Settings changes misbehave across windows (SET-05, SET-07, SET-03).** The badge scheme never reaches open
   windows; a base edit silently creates a project override (GDV B1); a theme change resets the single-file
   scroll; the per-project surface offers 4 of the 9 project-scoped settings.
8. **arcleak, dolly and deadwood findings never reach the UI (DIAG-01).** An absolute SARIF path is kept as is
   (`AtelierDiagnostics/SARIFDecoder.swift:80-93`), and the corpus filter drops it
   (`AtelierDiagnostics/DiagnosticsEngine.swift:271-275`), per Analyzers A-1, D-2 and W-3. None of the three
   tools is installed on this machine.
9. **System API documentation misses iOS frameworks and caches failures forever (HOVER-04).** The SDK probe runs
   against the macOS SDK while the work repositories are iOS projects, and a timeout is cached as a permanent miss
   (Core B9).
10. **Tool discovery fails under fish, and the sourcekit-lsp location is locked by default (TOOL-01, TOOL-02).**
    The user's login shell is fish, whose `echo $PATH` separates entries with spaces (Core B10). The Language
    Servers section is disabled whenever diagnostics are off, which is the default: a regression from `1c5bdec`.

## Method and limits

- **Paths.** App targets live under `Apps/GitDiffViewer/Sources/` (`DiffComparison/`, `DiffRendering/`,
  `DiffTextKit/`, `GitDiffViewer/`). Core targets live under `Packages/AtelierCore/Sources/` (`Atelier*/`). Tests
  live under `Apps/GitDiffViewer/Tests/GitDiffViewerTests/` and `Packages/AtelierCore/Tests/`.
- **Commits.** The day's range is `7853f42..10ae905`: 24 commits. I read the code, not the commit messages, to
  decide each verdict.
- **Build seen.** The installed `~/Applications/GitDiffViewer.app` was signed 2026-09-22 16:32, between `1752778`
  (16:13) and `eeb7ffa` (17:14). It was not running during the audit, and I did not launch or capture it. The one
  GitDiffViewer process that ran was the sticky-header agent's review build in `/private/tmp/gdv-cards`, built from
  `main` at 08:21, after `10ae905` landed. I did not capture it. I viewed that agent's baseline screenshot of the
  card list at rest (`base-rest.png` and its zoom `base-rest-tl4.png`, 08:22) and cite what it shows where noted.
  The user's own screenshots show builds from 09-22.
- **No build and no test run.** The user reported the machine as laggy, and other agents were building. Where I
  cite passing tests, the source is the pre-push hook, which ran both packages' suites on `eeb7ffa` (session
  transcript, 09-23 07:51). Nothing ran the suites on `10ae905` in my presence.
- **Review reports.** Six code reviews and three sweep reports are in `/tmp/reviews/`. I cite their findings as
  `GDV B2` (`gitdiffviewer.md`), `Core B9` (`ateliercore.md`), `Sec C1` (`security.md`), `JSON #16`
  (`aemi-aemijson.md`) and `Analyzers D-2` (`analyzers-hooks.md`). I confirmed each cited finding in this
  repository's code before relying on it. Where a finding rests on code outside this repository (the analyzers'
  SARIF output), I say so.

## Verdicts

### PROC: Delivery and process

#### PROC-01 · One local source of truth — **Met**
- `~/Developer/Atelier` is a full clone: `origin` is `g-cqd/Atelier`, `upstream` is `g-cqd/Atelier`, and the
  history reaches back past `7853f42`.
- `~/Developer` holds no other GitDiffViewer copy and no vendored AtelierCore. The three `Atelier-comments-*`
  directories are git worktrees of this repository, made for the comment sweep.
- `Apps/GitDiffViewer/Package.swift` resolves `../../Packages/AtelierCore` unmodified.

#### PROC-02 · Toolchain matches — **Met**
- `.swift-version` pins 6.4.0 (added in `8fdec51`). In the repository, `swift --version` (swiftly) reports
  "Apple Swift version 6.4 (swift-6.4-RELEASE)". All three manifests declare `swift-tools-version: 6.4`.
- Note: `xcrun swift` still resolves Xcode's 6.3.3, and the hooks choose swift-format by `PATH` order (Analyzers
  PH-2). The two formatters disagreed on 09-22 (session transcript, 12:44).

#### PROC-03 · Install, re-sign, relaunch — **Partially met**
- Met: the installed bundle's signature verifies (`codesign --verify --deep --strict`), with team `L2LRQKFJ3U`,
  signed 2026-09-22 16:32. Earlier batches were installed and relaunched on the two open repositories (session
  transcript, 09-21 17:04 and 17:32; 09-22 11:01, 14:10 and 16:13).
- Gap: the installed build predates `eeb7ffa` and `10ae905`, and no instance of it was running during the audit.

#### PROC-04 · g-cqd mirror — **Met**
- `origin` is `https://github.com/g-cqd/Atelier.git`, and `origin/main` equals `main` at `10ae905`.
- AemiJSON resolves from `https://github.com/g-cqd/AemiJSON.git` at a pinned revision
  (`Packages/AtelierCore/Package.swift:48-54`). A clean clone needs the `g-cqd` SSH credentials.

#### PROC-05 · Straight to main — **Met**
- All 24 commits since `7853f42` are on `main` and pushed.
- The comment sweep sits on three branches (`chore/comments-core`, 4 commits; `chore/comments-gdv`, 5;
  `chore/comments-kitty`, 4), to be replayed onto `main`. See QUAL-03.

#### PROC-06 · Roadmap kept and implemented — **Partially met**
- Met: `Apps/GitDiffViewer/docs/roadmap.md` exists and records the insights (`8fdec51`, `6472485`, `10ae905`).
- Gap: several sections contradict the code. "In flight" says AemiJSON "adoption verdicts pending numbers"
  (lines 9-10), but AemiJSON already backs SARIF and JSON-RPC. The "UI wave" still promises a "provenance footer"
  and an "apple-docs corpus as the system-API tier" (lines 63-65), both dropped. Most items the user approved on
  09-22 14:13 remain open (see `plan.md`).

#### PROC-07 · Plan first — **Met**
- A plan was written, then reviewed and revised before implementation (session transcript, 09-21 14:27 to 14:46:
  plan file, two design agents, a modernization review). Implementation started at 14:46.

#### PROC-08 · Skills and instruction files loaded — **Met**
- The sessions loaded the relevant skills and `AGENTS.md` (session transcript, 09-21 14:37-14:39 and 09-22 10:05).
- How well the code obeys them is audited under MOD-03 and QUAL-06, both Not met.

### DIAG: Diagnostics tools

#### DIAG-01 · Five analyzers run — **Partially met**
- Met: `AtelierDiagnostics/DiagnosticTool.swift:2-11` defines SwiftLint, swift-format, arcleak, dolly and
  deadwood, plus Lockwood's SwiftFormat. `AtelierDiagnostics/ToolCommand.swift:18-31` builds each command line.
  A missing tool reports `.toolMissing` without stopping the others
  (`AtelierDiagnostics/DiagnosticsEngine.swift:127-129`). SwiftLint and both formatters were checked against real
  binaries and are bundled in the installed app (`Contents/Helpers`: `swiftlint`, `swift-format`, `swiftformat`).
- Gap 1: arcleak, dolly and deadwood are not installed on this machine, so no run was ever observed.
- Gap 2: those three tools write an absolute path, not a `file://` URI, into SARIF (Analyzers A-1, D-2, W-3;
  their code, not verified here). `SARIFDecoder.relativePath` keeps such a path whole
  (`AtelierDiagnostics/SARIFDecoder.swift:80-93`, confirmed). The corpus filter then compares it with
  root-relative paths and drops every dolly and deadwood finding (`DiagnosticsEngine.swift:271-275`, confirmed).
  arcleak findings keep an absolute path that no row mapping matches (`DiffTextKit/DiagnosticOverlay.swift:91`).
- Gap 3: corpus tools run for any working-tree comparison, Swift or not (`DiagnosticsEngine.swift:113-117`).
- Tests: `SARIFDecoderTests`, `ToolCommandTests`, `DiagnosticsEngineTests`, `XcodeTextParserTests`. None feeds
  a SARIF log with a plain absolute path.
- Commits: `8fdec51`, `dc9eb77`, `7b9a7a3`.

#### DIAG-02 · Global and per-tool toggles — **Met**
- Master toggle: `GitDiffViewer/Views/ToolsSettings.swift:64`; per-tool toggle: `:167`. Only enabled tools run
  (`DiffComparison/DiagnosticsModel.swift:88`, `AtelierDiagnostics/DiagnosticsSession.swift:42`). Turning the
  master off cancels and clears (`DiagnosticsModel.swift:144-150`). Off by default
  (`DiffComparison/ViewerSettings.swift:324`).
- Tests: `DiagnosticsModelTests` "turning the master toggle off cancels the run and clears findings",
  "comparisonChanged only asks the session to run enabled tools"; `DiagnosticsSessionTests` "a disabled tool is
  never run".
- Commits: `dc9eb77`, `c6d12ea`, `1c5bdec`.

#### DIAG-03 · Findings on their lines — **Partially met**
- Met in the single-file panes: squiggles (`DiffTextKit/DiffLayoutFragment.swift:75-95`) and a tinted line number
  (`DiffTextKit/DiffGutterView.swift:250-300`), fed by `GitDiffViewer/Views/DiagnosticDiffTextView.swift:59-78`.
- Gap: the card list, the default view, draws neither. `DiffTextKit/EmbeddedDiffTextView.swift` has no overlay,
  and a card header shows only counts (`GitDiffViewer/Views/CombinedDiffView.swift:201-203`).
- Tests: `DiagnosticRowMapperTests`, `DiagnosticOverlayTests`.
- Commits: `dc9eb77`, `c10d36e`.

#### DIAG-04 · Status bar summary — **Met**
- `GitDiffViewer/Views/StatusBarView.swift:62-86` shows the warning and error counts, a spinner while running, and
  a per-tool breakdown tooltip (`DiffComparison/DiagnosticsBreakdown.swift`). It refreshes because it reads the
  observed `isRunning` (`:64`).
- Tests: `DiagnosticsBreakdownTests`, `DiagnosticsModelTests` "the summary totals errors and warnings, overall and
  per tool".
- Commit: `c6d12ea`.

#### DIAG-05 · Toolbar summary — **Not met**
- The item exists (`GitDiffViewer/Views/ToolbarItems.swift:39-65`, registered at
  `GitDiffViewer/Views/ContentView.swift:174`) but never appears after a run. Its body shows only when
  `diagnostics.summary` is non-empty (`ToolbarItems.swift:43`). `summary` derives only from `findingsByTool`
  (`DiffComparison/DiagnosticsModel.swift:20-39`), which is `@ObservationIgnored` (`:51`), so nothing the item
  reads changes when findings land. The field has been ignored since `dc9eb77`.
- Review: GDV B9, confirmed.
- Tests: `DiagnosticsModelTests` checks the value of `summary`, not that views observe it.
- Confirm by eye: enable diagnostics in a repository with lint warnings. The status bar shows counts after the
  run; the toolbar item stays hidden until an unrelated setting change redraws it.

#### DIAG-06 · Project configuration respected — **Met**
- SwiftLint runs from the root with no path arguments, so the project's `included:` and `excluded:` apply
  (`AtelierDiagnostics/ToolCommand.swift:20-21`). Lockwood's formatter lints `.` the same way (`:24-25`). A
  formatter without its configuration file is skipped (`AtelierDiagnostics/DiagnosticTool.swift:100-106`,
  `DiagnosticsEngine.swift:118-125`). Displayed findings are narrowed to the changed files
  (`DiagnosticsEngine.swift:271-275`).
- Tests: `DiagnosticsEngineRequiredConfigurationTests` (4 tests, for example "swift-format is skipped when the
  project has no swift-format configuration").
- Commit: `7b9a7a3`. The session transcript (09-21 17:32) records the runs on the two work repositories.
- Risk: path relativization matches a bare string prefix, so a root reached through a symlink loses its corpus
  findings (Core S23).

#### DIAG-07 · Lockwood's SwiftFormat — **Met**
- A separate `swiftformat` tool (`AtelierDiagnostics/DiagnosticTool.swift:5-8`, `:34`), run as `--lint .`
  (`ToolCommand.swift:24-25`), gated on `.swiftformat` (`DiagnosticTool.swift:103`). Its `(rule)` prefix becomes the
  rule ID (`AtelierDiagnostics/XcodeTextParser.swift:41-51`). It has its own discovery row and is bundled.
- Tests: `XcodeTextParserTests` "a parenthesized rule prefix, as swiftformat emits, is extracted the same way as a
  bracketed one"; `DiagnosticsEngineRequiredConfigurationTests` "swiftformat runs when the project has a
  dot-swiftformat configuration".
- Commit: `7b9a7a3`.

#### DIAG-08 · Analyzed sides — **Partially met**
- Met: the setting exists with "Newer side" as default (`DiffComparison/ViewerSettings.swift:52-63`, `:238-240`;
  `GitDiffViewer/Views/ToolsSettings.swift:66-70`).
- Gap: "Both sides" analyzes nothing more. It copies newer-side findings onto removed rows that share their line
  number (`DiffTextKit/DiagnosticOverlay.swift:86-100`), which can put a finding on unrelated old content. The
  caption says so (`ToolsSettings.swift:71-75`).
- Tests: `ViewerSettingsTests` "analyzed sides defaults to the newer side and round trips through user defaults".
- Commit: `1c5bdec`.

### TOOL: Tool discovery and user-set locations

#### TOOL-01 · Dynamic discovery — **Partially met**
- Met: six rungs in a fixed order (`AtelierDiagnostics/ToolDiscovery.swift:51-77`): environment override, custom
  path, bundle, toolchain (`xcrun --find`), well-known directories (Homebrew, `~/.swiftly/bin`, `~/.mint/bin`,
  `~/.local/bin`), then the login shell's `PATH`. Settings shows origin and version, and Refresh re-probes
  (`GitDiffViewer/Views/ToolsSettings.swift:77`, `:235-267`).
- Gap: the login-shell rung runs `$SHELL -l -c "echo $PATH"` and splits on `:` (`ToolDiscovery.swift:130-148`).
  The user's login shell is fish (`dscl` reports `/opt/homebrew/bin/fish`), which prints `$PATH` with spaces, so
  the rung yields one bogus directory. A tool reachable only through fish's `PATH` is reported missing.
- Also: relative `PATH` entries are accepted (Sec L1), and concurrent first lookups each spawn a login shell
  (Core S6).
- Review: Core B10, confirmed.
- Tests: `ToolDiscoveryTests` (13 tests, for example "the login shell PATH is the last rung"), all with
  colon-separated fake output.
- Commits: `8fdec51`, `c6d12ea`.

#### TOOL-02 · Locations settable in Settings — **Regressed**
- Met for the diagnostics tools: each row has Locate… and Reset (`GitDiffViewer/Views/ToolsSettings.swift:136-147`),
  and a custom path wins over discovery (`AtelierDiagnostics/ToolDiscovery.swift:57-59`).
- Regressed for sourcekit-lsp: the Language Servers section is disabled and dimmed whenever diagnostics are off
  (`ToolsSettings.swift:100-108`), and diagnostics are off by default while hover is on. In `c6d12ea` the section
  was always editable; `1c5bdec` (09-22 10:26) added the gate.
- Also: a custom path that is not executable falls through to discovery silently (`ToolDiscovery.swift:57`), so the
  row shows the discovered tool in green; the broken-pin state appears only when nothing else is found
  (`ToolsSettings.swift:180-185`). A new sourcekit-lsp pin applies only after a restart: the registry caches each
  root's service, `nil` included (`AtelierLSP/SourceKitLSPRegistry.swift:17-21`), and the SDK tier is resolved once
  per app (`GitDiffViewer/App.swift:209-231`). A per-project sourcekit-lsp setting is ignored, because the app reads
  only the base key (`App.swift:262-267`; Sec L2, confirmed).
- Tests: `ToolDiscoveryTests` "a custom path beats the bundled directory, which beats the toolchain". No test covers
  the settings gate.

#### TOOL-03 · Bundling optional — **Met**
- `Apps/GitDiffViewer/scripts/bundle.sh:28-79` stages each tool it finds under `Contents/Helpers`, skips a missing
  one with a warning, and signs every helper. Discovery treats the bundle as one rung among six
  (`ToolDiscovery.swift:60-63`).
- Risk: the script copies the first binary on `PATH` and signs it with the local identity (Sec M5).
- Commit: `c6d12ea`.

#### TOOL-04 · Bundle the five analyzers — **Superseded**
- Replaced by TOOL-03, TOOL-01 and TOOL-02 (09-21 15:20).

### HOVER: Hover documentation

#### HOVER-01 · Hover from sourcekit-lsp and swift-syntax, toggleable — **Met**
- sourcekit-lsp session: `AtelierLSP/SourceKitLSPService.swift:40-148`; swift-syntax doc index:
  `AtelierDocIndex/DocCommentIndex.swift:39-51`; tier order LSP, doc index, SDK
  (`DiffComparison/HoverDocumentation.swift:176-189`). Toggle: `DiffComparison/ViewerSettings.swift:222-224`, shown
  in Settings (`GitDiffViewer/Views/ToolsSettings.swift:65`) and the view options
  (`GitDiffViewer/Views/ViewOptionsMenu.swift:94-96`).
- Tests: `SourceKitLSPServiceTests` (8), `DocCommentIndexTests` (19), `DocIndexHoverProviderTests` (6),
  `HoverDocumentationTests` (14).
- Commits: `8fdec51`, `dc9eb77`, `c6d12ea`.

#### HOVER-02 · Hover works in every pane — **Met**
- The tracking area's selectors are pinned to `mouseMoved:` and friends (`DiffTextKit/DocHoverController.swift:148-162`,
  `90374b7`). The card panes attach their own controller (`DiffTextKit/EmbeddedDiffTextView.swift:87`, `:117-118`,
  `:159`) with a resolver (`GitDiffViewer/Views/CombinedDiffView.swift:360-379`, `661c8b1`).
- Evidence the panel appears in the card list: the user's images 07 and 09 (09-22 15:40, 16:20).
- Tests: `DocHoverControllerTests` (9), `HoverHitTesterTests`.

#### HOVER-03 · Project doc comments appear — **Needs visual confirmation**
- The code now covers each cause found on 09-22. A declaration-only answer no longer wins: tiers merge
  (`AtelierLSP/TieredHoverProviders.swift:22-59`, `b30579b`). Candidate prose renders
  (`DiffTextKit/HoverDocPanel.swift:418-430`, `1752778`). The doc index is fed while cards stream
  (`DiffComparison/DiffViewerModel+Diagnostics.swift:51-72`, `eeb7ffa`). The index extracts a documented computed
  property inside an extension. A missing doc reads "No documentation" (`HoverDocPanel.swift:337-341`).
- Tests: `DocCommentIndexTests` "a documented computed property inside an extension with an explicit get block is
  indexed"; `SDKDocumentationProviderTests` "declaration-only repo LSP, doc index has the doc comment -- merges with
  provenance docIndex". No test covers the streaming feed from `eeb7ffa`.
- Risk: every publish replaces the index with the changeset alone, then re-reads and re-parses up to 2,000 corpus
  files (`DiffComparison/HoverDocumentation.swift:138-159`, `AtelierDocIndex/DocCommentIndex.swift:39-51`; GDV B6,
  confirmed). A hover during that pass can miss a symbol declared outside the changeset.
- The installed build predates `eeb7ffa`.
- Confirm by eye: on a build of `10ae905`, open a comparison of 30 or more files, and hover a symbol whose `///`
  comment sits in a changed file while the list is still loading. The comment's text must appear under the
  declaration. Repeat on a documented computed property declared in an extension (image 09).

#### HOVER-04 · System APIs from on-device documentation — **Partially met**
- Met: `AtelierLSP/SDKDocumentationProvider.swift:44-143` probes the on-device toolchain through sourcekit-lsp with
  a synthetic document that mirrors the file's imports. No network, no apple-docs. The probe targets the chain's
  last segment (`:132-135`) and retries in type position (`:94-106`). Underscored attributes are dropped
  (`DiffRendering/HoverMarkdownStructurer.swift:142`).
- Gap 1: the scratch server gets no SDK or target option (`:259-272`), so it resolves against the host's macOS SDK
  and iOS-only frameworks such as UIKit cannot resolve. The two work repositories that were open are iOS projects.
- Gap 2: a timeout or a connection failure returns `nil` (`AtelierLSP/SourceKitLSPService.swift:143-147`), and the
  provider caches that `nil` for the process's lifetime (`SDKDocumentationProvider.swift:78-86`). A cold first probe
  therefore hides the symbol's documentation until the app restarts (Core B9, confirmed).
- Gap 3: prose appears only when the SDK's `.swiftdoc` carries it, and a bare member name without a receiver is
  rejected (`:219-222`).
- Tests: `SDKDocumentationProviderTests` (24), including "hovers the chain's last dot-separated segment, not its
  head" and "a nil result is also cached"; `SDKDocumentationProviderIntegrationTests` (environment-gated).
- Commits: `51503a4`, `c10d36e`.

#### HOVER-05 · Quick Help style panel — **Partially met**
- Met: a borderless, non-activating `NSPanel` child window replaces `NSPopover` (`DiffTextKit/HoverDocPanel.swift:195-219`),
  with slots for the declaration, the body, parameters, returns, candidates and diagnostics (`:248-254`). The body
  scrolls past the cap (`:24-27`).
- Gap: image 02's structure is missing. There is no symbol title row and no section header for the discussion,
  and hairlines appear only before candidates (`:399-403`). `hover-panel-design.md` still promises a "symbol header
  row".
- Tests: `HoverDocPanelTests` (4), `HoverPanelSizingTests` (8), `HoverMarkdownStructurerTests` (9).
- Commits: `27bc8c3`, `1752778`, `eeb7ffa`.

#### HOVER-06 · Colored, legible declarations — **Partially met**
- Met: the declaration uses the pane's palette (`DiffRendering/CodeAttributedBuilder.swift`) on a chip filled with
  the theme's background (`DiffRendering/HoverDocument.swift:148-152`, `1752778`).
- Gap: when the hovered row carries a finding, the single-file resolver rebuilds the document without
  `chipBackground` (`GitDiffViewer/Views/DiagnosticDiffTextView.swift:101-104`). The chip then falls back to clear
  (`DiffTextKit/HoverDocPanel.swift:305`), and image 07's washed-out colors return on exactly those rows. The GDV
  sweep report flags the same line.
- Tests: `HoverDocumentTests` "buildCarriesTheChipBackgroundFromThePalette"; `CodeAttributedBuilderTests` (5). No test
  covers the diagnostics path.

#### HOVER-07 · Panel fits its content — **Needs visual confirmation**
- The panel's height comes from the content stack's own fitting size (`DiffTextKit/HoverDocPanel.swift:299-358`),
  with a 40 pt floor for an empty document and a 420 pt cap (`:16-17`, `:24-27`). The 260 pt floor went in
  `1752778`; sizing from the laid-out height came in `eeb7ffa`.
- Tests: `HoverDocPanelTests` "aDeclarationOnlyDocumentHasNoWastedSpace",
  "aFullDocumentWithParametersAndCandidatesHasNoWastedSpace"; `HoverPanelSizingTests`.
- The installed build predates `eeb7ffa`.
- Confirm by eye: hover an undocumented symbol; the panel must be one declaration tall plus "No documentation".
  Hover a documented function with parameters; no empty band may remain below the last section.

#### HOVER-08 · Glass, clipped by rounded corners — **Needs visual confirmation**
- The panel uses an `NSVisualEffectView` with the `.popover` material, 8 pt continuous corners, and a mask image that
  clips the behind-window material to the rounded shape (`DiffTextKit/HoverDocPanel.swift:207-219`, `b30579b`).
- It does not use Liquid Glass (`NSGlassEffectView`, available since macOS 26.0 per the local Apple documentation;
  the app's floor is 26.1). See Q3.
- Confirm by eye: hover over a busy, colored area of a diff and check that no square corner of material shows past
  the rounded edge. Then decide whether the material reads as the glass you asked for.

#### HOVER-09 · Panel follows its line — **Met**
- On each scroll the controller recomputes the identifier's rectangle, moves the panel, and closes it once the
  identifier leaves the visible rect (`DiffTextKit/DocHoverController.swift:122-140`, `b30579b`).
- Tests: `DocHoverControllerTests` "scrolling while the panel is visible keeps it open, repositioned, not closed",
  "scrolling the hovered identifier entirely out of view closes the panel".

#### HOVER-10 · No flash — **Needs visual confirmation**
- A bounds notification with no real scroll is ignored, and an anchor that cannot be recomputed keeps the panel
  in place (`DiffTextKit/DocHoverController.swift:122-140`, `c10d36e`).
- Tests: `DocHoverControllerTests` "a bounds-changed notification with no actual scroll offset is a no-op".
- Confirm by eye: hover `View` in a SwiftUI file (the case reported on 09-22 14:15), in the card list and in the
  single-file view. The panel must stay until the pointer leaves the identifier and the panel.

#### HOVER-11 · No duplicates — **Met**
- `AtelierDocIndex/DocCommentIndex.swift:61-127` collapses a blob entry whose path has a `file://` twin, merges
  identical renderings, and keeps the queried revision's own entry.
- Tests: `DocCommentIndexTests` "blob and file entries with the same signature collapse to the file entry", "blob
  and file entries at the same path with different signatures keep only the file entry", "same-named declarations at
  genuinely different paths both remain candidates", "hovering the old blob side itself shows the old side's own
  documentation, not the new one's".
- Commit: `c10d36e`.

#### HOVER-12 · Typography and spacing — **Needs visual confirmation**
- Every prose run gets an explicit system font from its markdown intent, so nothing falls back to Helvetica
  (`DiffRendering/HoverDocument.swift:190-208`, `eeb7ffa`). One spacing scale drives every slot
  (`DiffTextKit/HoverDocPanel.swift:56-70`). The declaration chip is an `NSBox` with a 1 pt separator-colored stroke
  (`:473-481`).
- Tests: `HoverDocumentTests` "summaryProseAlwaysCarriesAnExplicitSystemFont".
- The installed build predates `eeb7ffa`.
- Confirm by eye: hover a documented symbol with bold, italic and inline code in its comment. All prose must be in
  the system font, and the declaration must sit in a lightly stroked box.

#### HOVER-13 · No source label — **Met**
- The panel has no footer slot (`DiffTextKit/HoverDocPanel.swift:248-254`, `eeb7ffa`).
- Tests: `HoverDocPanelTests` "provenanceStillHasNoFooterFootprint".
- Leftover: `HoverDocument.Provenance.label` (`DiffRendering/HoverDocument.swift:74-82`) is now unused.

#### HOVER-14 · Documentation and diagnostic in one hover — **Partially met**
- Met in the single-file panes: the hovered row's findings join the document (`GitDiffViewer/Views/DiagnosticDiffTextView.swift:85-107`)
  and render as tinted rows (`DiffTextKit/HoverDocPanel.swift:434-453`).
- Gap: the card list has no diagnostics in its hover (`GitDiffViewer/Views/CombinedDiffView.swift:368-379`). The
  match is by row, not by the underlined range under the pointer. There is no context menu. Rows with findings lose
  the declaration chip's background (HOVER-06).
- Commit: `c10d36e`.

#### HOVER-15 · Multi-language design — **Met**
- `Apps/GitDiffViewer/docs/multi-language-hover-design.md` covers a descriptor table per server, a registry keyed by
  root and server, discovery, a tree-sitter doc-comment fallback, tiering, non-goals and phases (`8fdec51`).

#### HOVER-16 · Hover for other languages — **Not met**
- Only `Language.lspLanguageID` exists (`AtelierSyntaxModel/Language.swift:65-71`), and nothing calls it.
  `AtelierLSP/LSPHoverProvider.swift:12-14` hard-codes `"swift"`. The language server is tried only for `.swift`
  files (`DiffComparison/HoverDocumentation.swift:191-197`), and the doc index and SDK tiers are Swift-only.
- No `LanguageServerDescriptor`, registry or `AtelierDocComment` target exists.

#### HOVER-17 · apple-docs tier — **Superseded**
- Replaced by HOVER-04 (09-22 11:24). No apple-docs code exists.

#### HOVER-18 · Provenance footer — **Superseded**
- Replaced by HOVER-13 (09-22 16:20). The footer slot was removed in `eeb7ffa`.

### DUI: Diagnostics UI

#### DUI-01 · Toolbar list of findings — **Not met**
- The list itself exists: a popover grouped by file, sorted by line (`GitDiffViewer/Views/FindingsNavigator.swift:44-83`,
  `DiffComparison/FindingsNavigatorGrouping.swift:17-29`). Choosing a finding pins its file (`FindingsNavigator.swift:68`).
- Gap: the button that opens it appears only when `diagnostics.summary` is non-empty (`FindingsNavigator.swift:14`),
  and that value is never observed (see DIAG-05; GDV B9, confirmed). After a run, the button stays hidden.
- Also: the jump stops at the file; a comment says the line scroll "is not wired yet" (`FindingsNavigator.swift:64-67`).
- Tests: `FindingsNavigatorGroupingTests` (3).
- Commit: `c10d36e`.

#### DUI-02 · No gutter layout change — **Met**
- A finding tints its line number and draws a faint underlay behind it (`DiffTextKit/DiffGutterView.swift:250-300`),
  with no column of its own: the width comes from the digits alone (`:101-107`).
- Commit: `c10d36e`.

#### DUI-03 · Open a finding from its line — **Partially met**
- Met: clicking a decorated line number opens the finding (`DiffTextKit/DiffGutterView.swift:163-182`).
- Gap: no trailing-edge overlay, no click on the line itself, and nothing in the card list, which draws no markers.

#### DUI-04 · Popover anchored on its line — **Met**
- The gutter passes the row's own rectangle and view (`DiffTextKit/DiffGutterView.swift:163-182`), and an
  `NSPopover` shows relative to it (`GitDiffViewer/Views/DiagnosticDiffTextView.swift:113-119`).
- Commit: `c10d36e`.

### SET: Settings

#### SET-01 · Research-based Settings — **Met**
- `Apps/GitDiffViewer/docs/settings-design.md` states P1 to P10 with sources and audits the old window (A1 to A5).
  The window applies R1 (one summary row per tool with disclosure, `GitDiffViewer/Views/ToolsSettings.swift:122-171`),
  R2 (four tabs by user question, `GitDiffViewer/Views/SettingsView.swift:20-33`), R3 (one label per setting,
  `DiffComparison/SettingLabels.swift`), R4 (per-tab Restore Defaults with a deviation count, `SettingsView.swift:254-291`)
  and R6 (captions and a trust note, `ToolsSettings.swift:79-85`). R5 is audited as SET-03.
- Tests: `SettingLabelTests`; `ViewerSettingsTests` "restoring general defaults resets its settings and fires
  observers" and three more restore tests.
- Commits: `1c5bdec`, `38b2e7b`.

#### SET-02 · Platform conventions — **Met**
- A fixed-size window (`GitDiffViewer/Views/SettingsView.swift:34`), tab panes with symbols (`:21-32`), and the last
  pane restored (`DiffComparison/ViewerSettings.swift:242-244`). View settings also live in the window's view options
  (`GitDiffViewer/Views/ViewOptionsMenu.swift`).
- Commit: `1c5bdec`.

#### SET-03 · Per-project settings — **Partially met**
- Met: identity is a SHA-256 of the standardized root (`DiffComparison/ProjectIdentity.swift:16-34`). Nine keys can
  be scoped per project (`DiffComparison/ViewerSettings.swift:140-143`). Each window adopts its current project
  (`GitDiffViewer/Views/ComparisonWindow.swift:72-75`). Settings lists and clears overrides
  (`GitDiffViewer/Views/SettingsView.swift:254-340`).
- Gap 1: only 4 of the 9 scoped keys have a per-window control: changed-files-only, ignored files, heuristics with
  whitespace, and tree style (`GitDiffViewer/Views/ViewOptionsMenu.swift:88-178`). Diagnostics enablement, analyzed
  sides, tool locations, server locations and context lines can be edited only in the Settings window, which writes
  the app-wide values. "tune all settings for a specific project" is not possible (see Q2).
- Gap 2: overrides appear that the user never made (GDV B1, confirmed). `store` writes the scoped key whenever a
  project is adopted, unless `isFallingBackToBase` is set (`ViewerSettings.swift:284-293`). A broadcast sets only
  `isApplyingBroadcast` (`DiffComparison/ViewerSettings+ProjectOverrides.swift:193-199`), and `adoptProject` sets
  neither (`:30-33`). So editing Context lines in Settings writes an override for every open project window, and
  switching a window to another repository copies the old values into the new project.
- Also: `settings-design.md` R5 lists granularity as overridable, but `projectScopedKeys` omits it (GDV S17).
- Tests: `ProjectSettingsTests` (10). None asserts that a broadcast or an adoption creates no override.
- Commits: `38b2e7b`, `1752778`, `c10d36e`.

#### SET-04 · Light and dark setting — **Met**
- System, Light and Dark (`GitDiffViewer/Views/SettingsView.swift:175-180`) apply app-wide through
  `NSApplication.shared.appearance` (`GitDiffViewer/App.swift:123-160`). The launch crash from the first version was
  fixed in the same commit.
- Tests: `ViewerSettingsTests` "appearance scheme defaults to system and round trips through user defaults".
- Commit: `1752778`.

#### SET-05 · Live settings, no new comparison — **Partially met**
- Met: an edit in the Settings window is broadcast to every window's settings (`DiffComparison/ViewerSettings.swift:291-292`,
  `DiffComparison/ViewerSettings+ProjectOverrides.swift:172-199`). A theme change maps to `.palette`, which recolors
  through a relayout without re-diffing (`DiffComparison/DiffViewerModel.swift:579-581`).
- Gap 1: `reload(key:)` has no case for `badgeScheme` or `matchesThemeAppearance`
  (`ViewerSettings+ProjectOverrides.swift:48-165`). Each window has its own settings instance
  (`GitDiffViewer/Views/ComparisonWindow.swift:46-48`), so a badge-scheme change never reaches an open window.
- Gap 2: a broadcast writes project overrides (GDV B1, see SET-03).
- Gap 3: the relayout runs with `keepingScroll: false` (`DiffViewerModel.swift:476`), which clears revealed lines
  (`DiffComparison/RenderPipeline.swift:151`) and sends the single-file pane back to the top. It re-renders every card
  on the main actor (GDV B7).
- Tests: `ViewerSettingsBroadcastTests` (5), including "a theme change on one instance fires the palette category on
  another, not a re-comparison category". None covers the badge scheme.
- Commit: `1752778`.

#### SET-06 · Appearance from the theme — **Met**
- `matchesThemeAppearance` (`DiffComparison/ViewerSettings.swift:255-257`) feeds a pure precedence rule: an explicit
  pin wins, and off is the default (`DiffComparison/BadgeStyle.swift:122-141`). The applier observes the app-level
  settings for appearance and palette changes (`GitDiffViewer/App.swift:123-144`).
- Tests: `AppearancePrecedenceTests` (7).
- Commit: `eeb7ffa`.

#### SET-07 · Badge color scheme — **Partially met**
- Met: Classic and Xcode schemes (`DiffComparison/BadgeStyle.swift:76-93`), chosen in Settings
  (`GitDiffViewer/Views/SettingsView.swift:209-216`) and applied to explorer rows
  (`GitDiffViewer/Views/FileExplorerView.swift:26`) and tabs (`GitDiffViewer/Views/TabBarView.swift:31`).
- Gap: card headers and the status bar always draw the classic filled badge
  (`GitDiffViewer/Views/ChangeBadge.swift:123`, `GitDiffViewer/Views/StatusBarView.swift:44`). A change in Settings
  does not reach open windows (SET-05). The baseline capture from 08:22 shows orange `M` badges on the card headers.
- Tests: `BadgeStyleResolverTests` (10), including "xcode scheme reads a modification and a rename both as blue".
- Commit: `eeb7ffa`.

#### SET-08 · Accent color research — **Not met**
- The roadmap records the question ("Accent-color adaptation (research)", `Apps/GitDiffViewer/docs/roadmap.md`), but
  no research note exists.

### CARD: The card list and file badges

#### CARD-01 · Sticky headers — **Met**
- Each card is a `Section` whose header pins in a `LazyVStack(pinnedViews: [.sectionHeaders])`
  (`GitDiffViewer/Views/CombinedDiffView.swift:45`, `:113-122`), and a click on the pinned header folds the file
  (`:219`). The user's reports from 09-22 15:39 on describe pinned headers, so pinning works.
- Commit: `c10d36e`.

#### CARD-02 · Card look when pinned — **Needs visual confirmation**
- A pinned header gets full rounding and a border (`GitDiffViewer/Views/CombinedDiffView.swift:173`, `:222`,
  `:256-260`) and rests 16 pt below the toolbar through the list's top margin (`:40`, `:56`).
- Confirm by eye: scroll a long card until its header pins. The header must sit one list-gap below the toolbar,
  with rounded corners and a single soft shadow.

#### CARD-03 · Content clipped behind a pinned header — **Not met**
- A pinned header's fill is `.regularMaterial` (`GitDiffViewer/Views/CombinedDiffView.swift:181-183`), which blurs
  the content beneath instead of hiding it. The fill is deliberately left unclipped over the header's whole
  rectangle (`:228-241`), and nothing clips the body at the header's bottom edge. Content also scrolls through the
  16 pt margin above a pinned header, faded by the soft edge effect (`:56-61`).
- The rework agent resumed at 07:43. At 09:27 it added an untracked
  `Apps/GitDiffViewer/Sources/DiffTextKit/StickyCardGeometry.swift`, a clip geometry that holds the header while the
  body scrolls beneath it. Nothing uses it yet, and nothing is committed.

#### CARD-04 · One card at rest — **Partially met**
- Met: header and body touch, since the stack has zero spacing (`GitDiffViewer/Views/CombinedDiffView.swift:45`),
  and both cast the same shadow (`:227`, `:294`).
- Gap: an expanded, unpinned header draws no border (`:222`: width 0 unless the card is folded or pinned), while the body strokes its full
  outline, top edge included (`:290`), under its own `Divider` (`:283`). The seam is therefore a double line, and the
  header's sides lack the body's border. The baseline capture from 08:22 shows both: a darker line between header
  and body, and a border that starts only at the body.

#### CARD-05 · Nothing clips shadows or the scroll bar — **Needs visual confirmation**
- The white strip is gone: the list relies on a soft scroll-edge effect that AppKit draws as window chrome
  (`GitDiffViewer/Views/CombinedDiffView.swift:57-61`), not an overlay.
- Confirm by eye: scroll the list; the top card's shadow and the scroll bar must render in full at the top edge.

#### CARD-06 · No square glass layer, no extra shadow when pinned — **Not met**
- The square material behind a pinned header is a documented choice: "deliberately left unclipped, covering the
  header's whole rectangular footprint" (`GitDiffViewer/Views/CombinedDiffView.swift:228-241`). The header's shadow
  stays on while pinned (`:227`), so a pinned header adds a shadow over the content below.

#### CARD-07 · Folding keeps the gap — **Met**
- The gap is a section footer of 16 pt that exists whether or not the body renders
  (`GitDiffViewer/Views/CombinedDiffView.swift:117-122`).
- Commit: `eeb7ffa`.

#### CARD-08 · Expand and collapse symbols — **Met**
- `rectangle.expand.vertical` and `rectangle.compress.vertical` with `.contentTransition(.symbolEffect(.replace))`
  (`GitDiffViewer/Views/CombinedDiffView.swift:189-193`). The baseline capture shows the compress symbol on the
  headers.
- Commit: `c10d36e`.

#### CARD-09 · Badge states and Xcode colors — **Partially met**
- Met: the resolver fills staged changes and strokes unstaged ones with colored text; the Xcode scheme makes
  Modified and Renamed blue (`DiffComparison/BadgeStyle.swift:76-116`). Explorer rows for the working-tree side
  draw stroked badges (`GitDiffViewer/Views/ChangeBadge.swift:230-265`), and a new file shows a stroked "A". The
  baseline capture shows stroked `A` and `M` badges in the explorer.
- Gap: card headers and the status bar keep the classic filled badge (`ChangeBadge.swift:123`). The state is not
  per file (CARD-11), and `.untracked` is never produced.
- Tests: `BadgeStyleResolverTests` (10).
- Commit: `eeb7ffa`.

#### CARD-10 · Selection and focus — **Needs visual confirmation**
- `ChangeBadgeView` inverts only when the row's `backgroundStyle` is `.emphasized`, which AppKit sets for a selected
  row in a focused list (`GitDiffViewer/Views/ChangeBadge.swift:219-236`).
- Tests: `BadgeStyleResolverTests` "selected but unfocused keeps the state's own look, not the inverted one".
- Confirm by eye: select a file in the explorer; its badge must turn white with colored text. Click the diff; the
  selection must turn gray and the badge return to normal.

#### CARD-11 · Badge state from git — **Not met**
- The state comes from the side's kind: a working tree is "unstaged", anything else "staged"
  (`DiffComparison/SideState.swift:71-73`). The roadmap's "Badge state fidelity" section records the gap.

### TAB: Window tabs and the in-app tab bar

#### TAB-01 · Native window tabs — **Met**
- Comparison windows share a tabbing identifier with `tabbingMode = .preferred`
  (`GitDiffViewer/Views/ComparisonWindow.swift:54-61`), the welcome window is `.disallowed`
  (`GitDiffViewer/App.swift:39-43`), and the + button opens the welcome window (`App.swift:323-325`).
- No test covers the tabbing bridge. See Q1 for what the request meant.
- Commit: `c1be5ac`.

#### TAB-02 · Equal gaps — **Met**
- One constant, `TabBarLayout.gap` (6 pt, `DiffComparison/TabBarLayout.swift:8-10`), sets both the spacing between
  tabs and the bar's inset (`GitDiffViewer/Views/TabBarView.swift:24-25`, `:50`).
- Tests: `TabBarLayoutTests` "the bar's gap is six, the one constant tying inter-tab spacing to the bar's own insets".
- Commit: `10ae905`.

#### TAB-03 · Glass tabs with a light shadow — **Needs visual confirmation**
- Each tab uses `.glassEffect(.regular.interactive())` inside one `GlassEffectContainer`, with a shadow of opacity
  0.12 and radius 1.5, and the bar draws no background (`GitDiffViewer/Views/TabBarView.swift:24`, `:84-89`).
- Confirm by eye: open two files as tabs; each tab must read as glass with a barely visible shadow over the window
  background.

#### TAB-04 · Close button in the badge slot — **Met**
- A fixed-size slot shows the close button on hover, the badge otherwise, and the document icon only when there is
  no badge (`GitDiffViewer/Views/TabBarView.swift:99-123`; `DiffComparison/TabBarLayout.swift:16-26`). No leading space
  is reserved.
- Tests: `TabBarLayoutTests` (6).
- Commit: `10ae905`.

#### TAB-05 · Badge instead of the icon; neutral tabs — **Met**
- The slot shows the diff badge (`GitDiffViewer/Views/TabBarView.swift:114-118`). Tabs have no accent tint: only the
  text style and the stroke opacity mark the active tab (`:80`, `:85-88`).
- Commit: `10ae905`.

#### TAB-06 · Native window-tab restyle — **Superseded**
- Replaced by TAB-02 to TAB-05. The roadmap corrected the reading in `10ae905`.

### GIT: Git features, freshness and reload continuity

#### GIT-01 · Watch and refresh — **Partially met**
- Met: one watcher per working-tree comparison routes tree edits to a reload, `.git/HEAD` to a re-comparison, and
  refs to a menu refresh, each debounced (`DiffComparison/RepositoryFreshness.swift:104-115`, `:223-259`). It is
  wired in every window (`GitDiffViewer/Views/ComparisonWindow.swift:83`) and switchable
  (`DiffComparison/ViewerSettings.swift:197`). Linked worktrees resolve their metadata paths
  (`DiffComparison/GitMetadataLocation.swift`).
- Gap 1: every comparison change tears the watcher down and attaches a new stream that starts from "now", which
  cancels pending debounces (`RepositoryFreshness.swift:165-171`, called on every reload through
  `DiffComparison/DiffViewerModel+Freshness.swift:29-36`). A save made during a reload can be lost (GDV B4,
  confirmed).
- Gap 2: in a linked worktree, the refs directory is never watched. A second `watchDirectory` returns early
  (`AtelierFileTree/AtelierFileWatcher.swift:86-87`), so `watchDirectory(paths.refs)` at
  `RepositoryFreshness.swift:195` does nothing (GDV B5, Core B7, confirmed). The per-file sources on `HEAD` and
  `packed-refs` stop after git's first lock-and-rename (Core B8).
- Also: files an IDE rewrites and git ignores, such as `xcuserdata/*.xcuserstate`, are neither hidden nor skipped,
  so they trigger reloads that hash the whole tree (`RepositoryFreshness.swift:264-281`; GDV S2).
- Tests: `RepositoryFreshnessTests` (17), `GitMetadataLocationTests` (7), `DiffViewerModelRefsChangedTests` (2),
  `FileWatcherTests` (6). The linked-worktree test checks the paths requested, not that the second stream exists.
- Commits: `ac42c63`, `e63b014`, `4452731`, `c10d36e`.

#### GIT-02 · Fetch, reusable — **Met**
- `AtelierGit/GitClient.swift:136-176` adds `branches`, `tags`, `remotes`, `aheadBehind` and `fetch` to the core
  client, which KittyCode already depends on. Fetch runs under its own `networking` isolation
  (`AtelierGit/GitIsolation.swift:90-97`). Both source menus offer it (`GitDiffViewer/Views/SourceToolbarControl.swift:204-215`);
  success refreshes both sides' menus and re-compares a remote-tracking side
  (`DiffComparison/DiffViewerModel+Freshness.swift:79-97`).
- Tests: `GitClientRunnerTests` (fetch argv, isolation, checked refs), `SideStateFetchTests` (8),
  `DiffViewerModelFetchTests`, `RepositoryFetchTests`.
- Commits: `16d22fe`, `c10d36e`.
- Security of the transport is audited under QUAL-07 (Sec H1). Fetch runs on git's width-4 pool
  (`DiffComparison/SideState.swift:58`), which `gaps-and-modularization.md` ruled out.

#### GIT-03 · A reload never collapses the viewer — **Not met**
- Two-sided reloads (Reload, Swap, a refs change while the left side is parked on `HEAD`) clear everything when the
  first side lands. `sourcesChanged` sets `comparison = .empty` and `trees = .empty` and calls `pipeline.clear()`
  while the other side still loads (`DiffComparison/DiffViewerModel.swift:282-290`). The explorers go blank, the
  detail area shows "Comparing…", and folds, scroll and reuse are lost. A commit in a terminal takes this path
  through `DiffComparison/DiffViewerModel+Freshness.swift:58-62` (GDV B2, confirmed).
- One-sided reloads that change a file unpublish first. `render` sets `file = nil` and `cards = []`
  (`DiffComparison/RenderPipeline.swift:122-124`) and republishes only after the changed pairs are prepared
  (`:448-485`). Meanwhile `detailState` returns `.loading` (`DiffViewerModel.swift:168`) and the detail view swaps in
  a `ProgressView` (`GitDiffViewer/Views/DiffDetailView.swift:23-24`), which destroys the panes and their scroll
  (GDV B3, confirmed).
- What holds: folds survive (`DiffViewerModel.swift:295-297`), and the entries-loading phase keeps the old cards on
  screen (`:164-172`).
- The doc comments claim more than the code does: `DiffViewerModel.swift:158-163` ("RenderPipeline keeps its
  previous file/cards published throughout a side's reload") and `RenderPipeline.swift:101` ("published in this very
  update, before any task hop").
- Tests: `DiffViewerModelReloadContinuityTests` "detailState keeps the previous cards mounted while a reload is
  still fetching entries" covers only the loading phase. No test checks `detailState` while a changed card
  re-renders, or during a two-sided reload.
- Commits: `c094ef9`, `c10d36e`.

#### GIT-04 · Re-comparison keeps loaded files — **Partially met**
- Met: pairs are reused by path and blob identity, and unhashed files are never reused
  (`DiffComparison/RenderPipeline.swift:276-347`). Only changed pairs are prepared and rendered (`:427-496`). A change
  of diff options re-renders everything (`:319-322`).
- Gap: a two-sided reload clears the pipeline first (GIT-03), so nothing is left to reuse when both sides land.
- Tests: `DiffViewerModelReloadContinuityTests` "a reload keeps an unchanged card's identity and re-renders only the
  file whose blob changed", "a reload that adds and removes files keeps the untouched cards' identity", "changing
  the granularity re-renders every card even though no pair changed".
- Commits: `c094ef9`, `c10d36e`.

### WIN: Window chrome and stability

#### WIN-01 · Toolbar persists — **Needs visual confirmation**
- The model is built with the window, so the customizable toolbar exists on the first body pass
  (`GitDiffViewer/Views/ComparisonWindow.swift:24-29`, `:46-48`). The default item set no longer changes with the
  explorer placement (`GitDiffViewer/Views/ContentView.swift:27-36`). The autosave name moved to `main.3` to shed
  two inconsistent saved configurations (`ContentView.swift:281-287`).
- Commits: `b5015f0`, `90374b7`.
- Confirm by eye: in the installed app, customize the toolbar, quit, relaunch from Finder; the arrangement must
  return.

#### WIN-02 · A saved toolbar never crashes the app — **Needs visual confirmation**
- The fix renames the autosave key (`GitDiffViewer/Views/ContentView.swift:281-287`, `90374b7`). The Findings item
  was added later, in `c10d36e`, without another rename. The comment at `:281-286` names added items as the cause of
  the 09-22 crash, so a customization saved before `c10d36e` may trap again. No test can cover this.
- Confirm by eye: with a toolbar customized under an older build, launch a build of `10ae905` and open a
  comparison; then customize and relaunch again.

#### WIN-03 · Symmetric source selectors — **Met**
- `ComparisonSource.descriptor(repository:)` names a working tree at the repository root "Working Tree", with the
  repository as its context, just as a ref side names its ref (`AtelierSources/ComparisonSource.swift:50-97`). Both
  selectors draw from it (`GitDiffViewer/Views/SourceToolbarControl.swift:69-102`). The baseline capture shows both
  selectors as repository name plus ref or "Working Tree", with matching icons.
- Tests: `SourceDescriptorTests` (7).
- Commit: `b5015f0`.

### PERF: Performance and non-blocking work

#### PERF-01 · Tool runs never block the UI — **Met**
- Tools run in an actor over their own two-thread pool (`GitDiffViewer/App.swift:181-185`), one child task per tool
  (`AtelierDiagnostics/DiagnosticsSession.swift:41-56`). Output parses in a `@concurrent` function
  (`AtelierDiagnostics/DiagnosticsEngine.swift:248-267`). The model debounces and supersedes runs
  (`DiffComparison/DiagnosticsModel.swift:167-185`).
- Tests: `DiagnosticsSessionTests` (4); `OffMainExecutionTests` (core) "a tool run, called from the main actor,
  executes its runner and parses its output off the main thread".
- Commits: `8fdec51`, `dc9eb77`, `18950b3`.
- Risk: quitting calls the pools' blocking `shutdown()` on the main thread (JSON #5).

#### PERF-02 · `@concurrent` offload with off-main tests — **Partially met**
- Met in GitDiffViewer and the diagnostics core: the offload wave made four passes `@concurrent`, each with a
  `pthread_main_np` debug assert: row mapping (`DiffTextKit/DiagnosticOverlay.swift:78`), explorer trees
  (`DiffComparison/ExplorerTrees.swift:68`), the corpus fingerprint
  (`DiffComparison/DiffViewerModel+Diagnostics.swift:122`) and SARIF parsing (`DiagnosticsEngine.swift:248`). Card
  rendering (`DiffComparison/RenderPipeline.swift:250`) and diff preparation (`DiffComparison/DiffPreparer.swift:100`)
  were already `@concurrent` at `7853f42`.
- Gap 1: "across the whole codebase" did not happen. KittyCode has 39 files with `@MainActor` and no `@concurrent`,
  and no review of it is recorded.
- Gap 2: the full relayout after a mode, palette or gap change still renders every card synchronously on the main
  actor (`RenderPipeline.swift:149-161`; GDV B7).
- Gap 3: the app tests check results and rely on the production asserts, not on a thread probe inside the seam.
  Only the core test records the thread (`AtelierDiagnosticsTests/OffMainExecutionTests.swift`). `Thread.isMainThread`
  is not used, which is correct in async code.
- Tests: `OffMainExecutionTests` (app, 4; core, 1).
- Commit: `18950b3`.

#### PERF-03 · No feedback loops — **Partially met**
- Met: the reported loop is fixed. The watcher ignores hidden paths such as `.build/index-build`, where
  sourcekit-lsp writes its index (`DiffComparison/RepositoryFreshness.swift:270-280`, `4452731`). The reviews found
  no remaining cycle (GDV "Checked and found sound").
- Gap: no regression test pins the fix. `4452731` changed no test, and `RepositoryFreshnessTests` covers skipped
  directories (`:65`) but not hidden ones.
- Also: reloads without a real change still happen. IDE files that git ignores trigger reloads (GDV S2), and a fetch
  reloads twice, once from the fetch and once from the refs watcher (GDV S3).

#### PERF-04 · Hovering folded headers is free — **Met**
- Folded bodies unmount (`GitDiffViewer/Views/CombinedDiffView.swift:281`), so no text view, tracking area or hover
  controller exists for them. With no rendered content the controller does nothing
  (`DiffTextKit/DocHoverController.swift:166-170`).
- Tests: `DocHoverControllerTests` "pointerMoved with no rendered content does zero resolver or hit-test work".
- Measurement: the profiling agent reported 5,150 of 5,150 idle main-thread samples at 300 synthetic moves per
  second (session transcript, 09-22 16:59). The data is not in the repository.

#### PERF-05 · Smooth scrolling — **Needs visual confirmation**
- The pinned state is written only when it flips, and the edges live in an unobserved reference
  (`GitDiffViewer/Views/CombinedDiffView.swift:78-81`, `:131-144`), so a scroll frame re-renders no card.
- Risk: each gutter label recomputes `maximumLineNumber`, an O(rows) reduce, and card gutters have no clip view, so
  a draw walks every fragment (`DiffTextKit/DiffGutterView.swift:112-120`, `:282`;
  `DiffRendering/RenderedDiff.swift:105-107`; GDV B8, confirmed). A card for a large file costs O(rows²) per draw.
- No measurement exists after `eeb7ffa`.
- Confirm by eye: on a build of `10ae905`, scroll a comparison of 33 or more files, including one large new file,
  and record a Core Animation trace in Instruments; frames must hold the display rate.

#### PERF-06 · Few live materials — **Partially met**
- Met: a header carries one fill, which is material only while pinned
  (`GitDiffViewer/Views/CombinedDiffView.swift:181-183`, `eeb7ffa`). A fully folded list has no header material.
- Gap: every realized, expanded card body has a `.regularMaterial` background (`CombinedDiffView.swift:288`) that
  the opaque panes cover except for the divider (GDV S5). The status bar adds one more (`StatusBarView.swift:25`).
  Per GDV S5, the body's shadow also forces an offscreen pass.

#### PERF-07 · The app does not slow the system — **Partially met**
- Met: the fix for the measured cause, sixty-six header materials, is in `eeb7ffa`.
- Gap: the installed build predates that commit, and nobody has measured WindowServer after it. The only number is
  38.4% before the fix (session transcript, 09-22 17:02).

#### PERF-08 · No unnecessary work — **Partially met**
- Met: the render pipeline reuses unchanged pairs, the diagnostics engine caches runs per tool, configuration and
  payload, and the doc index skips unchanged content.
- Gaps, each confirmed in code:
  - The hover corpus is re-read and re-parsed on every publish, finish and relayout
    (`DiffComparison/HoverDocumentation.swift:116-160`, `AtelierDocIndex/DocCommentIndex.swift:39-51`; GDV B6).
  - A gap drag re-renders every card on the main actor (`DiffComparison/RenderPipeline.swift:166-172`; GDV B7).
  - Each comparison change clears every finding, so squiggles vanish and return
    (`DiffComparison/DiagnosticsModel.swift:97-98`, `:133-140`; GDV S9).
  - Corpus tools run for repositories with no Swift file (`AtelierDiagnostics/DiagnosticsEngine.swift:113-117`).
  - Each hover re-parses the whole document with swift-syntax (Core S5).
  - The language server, started for hover, indexes the repository in the background and writes into
    `<root>/.build/index-build` (`RepositoryFreshness.swift:272-275`). No initialization option limits it
    (`AtelierLSP/SourceKitLSPService.swift:225-234`).

### JSON: AemiJSON

#### JSON-01 · Benchmark Foundation against AemiJSON — **Partially met**
- Met: a benchmark ran on the three workloads, with medians of five in release mode (session transcript,
  09-21 16:11: SARIF 50k results 337 ms to 45 ms; hover classification 33 µs to 0.62 µs). The numbers are quoted in
  `AtelierDiagnostics/SARIFDecoder.swift:8-9` and `AtelierLSP/JSONRPC.swift:160-161`.
- Gap: the benchmark lived in a scratch package outside the repository. No gated benchmark in the repository can
  reproduce these numbers.

#### JSON-02 · Fast paths to the largest extent — **Partially met**
- Met: SARIF decoding walks AemiJSON's lazy tape with no Codable mirror (`AtelierDiagnostics/SARIFDecoder.swift:17-37`).
  JSON-RPC classification reads `method` and `id` off the tape (`AtelierLSP/JSONRPC.swift:162-187`). Settings stay on
  Foundation by verdict.
- Gap: each LSP response is parsed twice. `IncomingMessage.decode` parses it and copies the result's bytes into a new
  `Data` (`JSONRPC.swift:186`); `requestOptional` then parses that copy again (`AtelierLSP/LSPConnection.swift:70-73`).
  The doc comment calls the handoff "zero-copy" (`JSONRPC.swift:158`). AemiJSON can decode at a tape index, but no
  public API exposes it (JSON #16, confirmed on the Atelier side). The `@JSONCodable` macro path is unused.

#### JSON-03 · AtelierLSP uses AemiJSON — **Met**
- Encoders: `AtelierLSP/JSONRPC.swift:121-143`; classification: `:162-187`; typed payloads:
  `AtelierLSP/LSPConnection.swift:25`, `:70-73`.
- Tests: `JSONRPCTests` (8), `LSPConnectionTests` (9).
- Commit: `8fdec51`.

### MOD: Modularization

#### MOD-01 · Generic parts in the core — **Partially met**
- Met: diagnostics (`AtelierDiagnostics`), the language-server client and registry (`AtelierLSP`), the doc index
  (`AtelierDocIndex`), `ProcessSession`, the file watcher (moved from KittyCode in `ac42c63`), the source descriptor
  and the git network features are in the core.
- Gap: `TieredHoverProvider` survives in the app with tests only (`DiffComparison/HoverDocumentation.swift:13-29`),
  duplicating the core's `TieredHoverProviders`. `renderHoverMarkdown` is called only from tests
  (`DiffComparison/HoverMarkdownRenderer.swift:9`). Hover structuring (`DiffRendering/HoverMarkdownStructurer.swift`)
  stays app-side. The grammar corpus stays in `KittySyntax/Grammars`.

#### MOD-02 · Plug and play between terminal and GUI — **Partially met**
- Met: `Apps/GitDiffViewer/docs/gaps-and-modularization.md` maps the modules and their costs. KittyCode consumes the
  shared watcher and `AtelierGit`.
- Gap: core names still belong to one app. `GDV_*` override variables live in `AtelierDiagnostics/DiagnosticTool.swift:42-51`,
  and the watcher's queue label is `com.kittycode.fswatcher` (`AtelierFileTree/AtelierFileWatcher.swift:89`; Core S16).
  KittyCode still polls git through `KittyWorkspace/GitRefreshManager.swift`, and `KittyGit/GitStatusProvider.swift`
  has not moved to the core. Neither app shares the other's diagnostics or hover.

#### MOD-03 · AGENTS tier rules in the core — **Not met**
- Five unstructured tasks remain in core targets: `AtelierProcess/ProcessSession.swift:88`,
  `AtelierLSP/LSPConnection.swift:47`, `:112`, `:121`, and `AtelierLSP/SourceKitLSPService.swift:268`. The Codex review
  raised them as finding 15, and the fix was deferred.
- `DiagnosticsSession` is compliant: a task group the caller drives (`AtelierDiagnostics/DiagnosticsSession.swift:41-56`).

### QUAL: Code quality, review processes and safety

#### QUAL-01 · Latest APIs — **Partially met**
- Met: swift-subprocess backs `ProcessSession`, typed throws appear in `LSPFrameCodec` and `SARIFDecoder`, and
  `@concurrent`, `Mutex` and Liquid Glass tabs are used.
- Gap: the plan review's Observation-based subscription (SE-0475 `Observations`) was never used; the model still
  uses the hand-written observer list (`DiffComparison/ViewerSettings.swift:118-122`). `DiagnosticsEngine.run` throws
  untyped (`AtelierDiagnostics/DiagnosticsEngine.swift:107`). The hover panel uses `NSVisualEffectView`, not
  `NSGlassEffectView`.

#### QUAL-02 · Codex review — **Met**
- Session `~/.codex/sessions/2026/09/22/rollout-2026-09-22T14-33-32-…`: `codex_exec`, model `gpt-6-astra`,
  read-only sandbox, effort `xhigh`, working directory Atelier, 23 findings (`/tmp/codex-review.md`).
- Commit `c10d36e` answers 22 of them; finding 15 was deferred (MOD-03). The fix for finding 10, reloads removing the
  views, covered only the loading phase (GIT-03).

#### QUAL-03 · Strip verbose comments — **Partially met**
- 13 commits on three branches, each verified comment-only by a parse-tree check (`/tmp/reviews/sweep-*.md`):
  AtelierCore 2,394 to 1,935 comment lines, GitDiffViewer 2,158 to 1,382, KittyCode 2,706 to 1,943.
- Gap: nothing is on `main` yet, and four files (`CombinedDiffView`, `TabBarView`, `ChangeBadge`, `DiffDetailView`)
  were excluded while other agents edited them.

#### QUAL-04 · Requirements book, plan and audit — **Met**
- This document, `book.md` and `plan.md`.

#### QUAL-05 · Code review of the codebase and owned dependencies — **Met**
- Six reports in `/tmp/reviews/`: GitDiffViewer, KittyCode, AtelierCore, aemi with AemiJSON, the analyzers with
  project-hooks, and security. Their fixes are not started (`plan.md`).

#### QUAL-06 · Definition of Done — **Not met**
- See the cross-cutting section below: force unwraps, tests that break `AGENTS.md`, missing regression tests,
  documentation that contradicts the code, and commits in a form the repository does not use.

#### QUAL-07 · Untrusted repositories cannot run code — **Not met**
- Sec C1, confirmed: hover starts sourcekit-lsp with the repository as `rootUri` and working directory
  (`DiffComparison/HoverDocumentation.swift:191-197`, `GitDiffViewer/App.swift:244-255`,
  `AtelierLSP/SourceKitLSPService.swift:225-234`, `:341-349`), with no trust decision. The reviewer rates
  `buildServer.json` execution as high confidence and the other vectors as medium.
- Sec C2 and H1, confirmed on the Atelier side: the pinned keys (`AtelierGit/GitIsolation.swift:73-97`) do not cover
  `filter.*`, `gpg.program`, `log.showSignature`, `credential.helper`, `core.askPass`, `core.gitProxy`,
  `remote.*.uploadpack` or `protocol.*.allow`. Whether each key executes under these exact commands is the
  reviewer's claim, not tested here.
- Sec M1: prose keeps markdown links (`DiffRendering/HoverDocument.swift:166-181`) in selectable text views with no
  delegate, so a doc comment's link can open any URL scheme.
- Sec L2: a per-project sourcekit-lsp disable is ignored (`GitDiffViewer/App.swift:262-267`).

## Cross-cutting: the Definition of Done across today's changes

The global standard's DEFINITION OF DONE, checked against `7853f42..10ae905`.

- **TODO, FIXME and stubs.** None of the added lines contains TODO, FIXME or XXX. Deferred work without a tracking
  reference remains:
  - `GitDiffViewer/Views/FindingsNavigator.swift:64-67`: "a further scroll to the finding's own line is not wired yet".
  - `DiffRendering/HoverDocument.swift:94`: "Reserved for the diagnostics-hover unification: always empty today". It
    is stale: `GitDiffViewer/Views/DiagnosticDiffTextView.swift:91-104` fills it.
  - `AtelierDiagnostics/ToolLocation.swift:11-12`: a `bookmark` field "unused today".
- **Unwired code.** `TieredHoverProvider` (`DiffComparison/HoverDocumentation.swift:13-29`) and `renderHoverMarkdown`
  (`DiffComparison/HoverMarkdownRenderer.swift:9`) are called only from tests. `Provenance.label`
  (`DiffRendering/HoverDocument.swift:74-82`), `isPopoverVisible` (`DiffTextKit/DocHoverController.swift:40-41`) and
  `Language.lspLanguageID` (`AtelierSyntaxModel/Language.swift:65-71`) have no caller.
- **Tests for new behavior.**
  - No regression test for the reported reload loop (`4452731` touched no test), for the streaming hover feed in
    `eeb7ffa`, for native window tabs (`c1be5ac`), for the badge scheme's propagation, for the observation of the
    toolbar summary, or for `detailState` during a re-render.
  - 62 tests in 10 new files use camelCase names instead of the backtick sentences `AGENTS.md` requires, for example
    all 14 in `HoverDocumentationTests.swift` and all 9 in `HoverMarkdownStructurerTests.swift`. The other 352
    tests in the 60 new test files follow the rule.
  - 14 waits use `Task.sleep` or `Task.yield` in 8 new test files, which `AGENTS.md` forbids:
    `GitDiffViewerTests/DocHoverControllerTests.swift:21`, `:166`, `:182`; `GitDiffViewerTests/HoverDocumentationTests.swift:114`,
    `:149`, `:174`, `:212`; `GitDiffViewerTests/SideStateFetchTests.swift:97`, `:156`;
    `AtelierProcessTests/ProcessSessionTests.swift:63`; `AtelierLSPTests/SourceKitLSPServiceTests.swift:33`;
    `AtelierLSPTests/SDKDocumentationProviderTests.swift:23`; `AtelierFileTreeTests/FileWatcherTests.swift:25`;
    `AtelierDiagnosticsTests/DiagnosticsEngineTests.swift:312` (Core S25).
  - `GitDiffViewerTests/TabBarLayoutTests.swift:33-38` repeats two earlier cases, and `:9-11` restates a constant.
- **Documentation that disagrees with the code.**
  - `DiffComparison/DiffViewerModel.swift:158-163` and `DiffComparison/RenderPipeline.swift:101`: reload continuity
    (GIT-03).
  - `DiffComparison/DiffViewerModel+Freshness.swift:13-14` says the watcher is "Left unwired to any window's launch";
    `GitDiffViewer/Views/ComparisonWindow.swift:83` wires it.
  - `AtelierLSP/JSONRPC.swift:157-159` says "zero-copy"; `:186` copies.
  - `AtelierLSP/SDKDocumentationProvider.swift:23-24` places probes "under a scratch temp directory"; `:112` uses
    `/tmp` while the workspace root is `$TMPDIR` (`:265-267`; Sec M4).
  - `Apps/GitDiffViewer/docs/roadmap.md`: stale "In flight", "Phase M4" and "UI wave" sections (PROC-06).
  - `hover-panel-design.md`: a "symbol header row" and a "provenance footer" that the panel does not have.
  - `settings-design.md` R5 versus `projectScopedKeys` (SET-03).
  - `gaps-and-modularization.md`: fetch "NOT on the width-4 diff pool" and a 500 ms debounce; the code shares the
    pool and waits 600 ms.
  - `hig-liquid-glass-plan.md`: three Settings tabs and a tab bar drawing `.bar`; the app has four tabs and no tab-bar
    background.
  - The sweep branches fix some comments, but none is on `main` at `10ae905`.
- **FORBIDDEN list.** Force unwraps: `DiffTextKit/HoverDocPanel.swift:309`, `:326`, `:346`, `:412`, `:426`, and
  `AtelierProcess/ProcessSession.swift:271`. Catch blocks with no logging: `AtelierDiagnostics/ToolDiscovery.swift:143-145`,
  `DiffComparison/HoverDocumentation.swift:23-25`, `AtelierLSP/LSPConnection.swift:171-174` and `:200-203`,
  `AtelierLSP/TieredHoverProviders.swift:38-40`, `AtelierLSP/SourceKitLSPService.swift:143-147`. `DispatchQueue` in
  `AtelierFileTree/AtelierFileWatcher.swift:89` is required by `FSEventStreamSetDispatchQueue`; the CONFLICT rule allows
  it, but no comment records the exception.
- **Performance statements.** The SARIF and JSON-RPC timings in source comments come from a benchmark that is not in
  the repository (JSON-01). No measurement backs the WindowServer fix (PERF-07).
- **Build and tests.** I ran neither. The pre-push hook ran both packages' suites on `eeb7ffa` and passed (session
  transcript, 09-23 07:51). `10ae905` passed the pre-commit hook, which formats and lints.
- **Commits (STEP 12).** Before `7853f42`, titles read `<Scope>: <sentence>` with a median of 63 characters. Today's 24
  titles have no scope and a median of 276 characters (longest 474). Several commits bundle unrelated work:
  `4452731` (the watcher fix and a panel sizing fix), `c10d36e` (23 review findings, the findings navigator, the
  sticky headers and the fold symbols), `1752778` and `eeb7ffa`.
- **Tier rules.** Five unstructured tasks in the core (MOD-03).

## Visual confirmation checklist

Build `10ae905` with `Apps/GitDiffViewer/scripts/bundle.sh`, install it, and open a working-tree comparison of 30 or
more Swift files in a repository with lint warnings.

1. **HOVER-03.** While the list loads, hover a symbol whose `///` comment is in a changed file; the comment's text must
   appear. Repeat on a documented computed property inside an extension.
2. **HOVER-07.** Hover an undocumented symbol: one declaration plus "No documentation", no empty band. Hover a
   documented function with parameters: no empty space below the last section.
3. **HOVER-08.** Hover over a busy, colored area; no square corner of material past the rounded edge. Decide whether
   the material reads as glass (Q3).
4. **HOVER-10.** Hover `View` in a SwiftUI file, in the card list and in the single-file view; the panel must not
   flash.
5. **HOVER-12.** Hover a comment with bold, italic and inline code; system font throughout, stroked declaration box.
6. **CARD-02 and CARD-05.** Scroll until a header pins: one list-gap below the toolbar, rounded, one soft shadow; the
   top card's shadow and the scroll bar render in full.
7. **CARD-10.** Select a file in the explorer: white badge with colored text. Click the diff: gray selection, normal
   badge.
8. **TAB-03.** Open two files as tabs: glass tabs with a barely visible shadow.
9. **WIN-01 and WIN-02.** With a toolbar customized under an older build, launch `10ae905`; customize, quit, relaunch;
   no crash, and the arrangement returns.
10. **PERF-05 and PERF-07.** Record a Core Animation trace while scrolling, and read WindowServer's CPU with the app in
    front and at rest; compare with 38.4%.
11. **DIAG-05 and DUI-01 (Not met, to confirm).** Enable diagnostics; after the run, the status bar shows counts while
    the toolbar item and the Findings button stay hidden.

## Review findings used

| Finding | Requirement | Confirmed at |
|---|---|---|
| GDV B1: broadcasts and project switches create overrides | SET-03, SET-05 | `DiffComparison/ViewerSettings.swift:284-293`, `DiffComparison/ViewerSettings+ProjectOverrides.swift:30-33`, `:193-199` |
| GDV B2: a two-sided reload clears the comparison | GIT-03, GIT-04 | `DiffComparison/DiffViewerModel.swift:282-290` |
| GDV B3: render unpublishes before its replacement | GIT-03 | `DiffComparison/RenderPipeline.swift:122-124`, `DiffComparison/DiffViewerModel.swift:168`, `GitDiffViewer/Views/DiffDetailView.swift:23-24` |
| GDV B4: the watcher re-attaches on every change | GIT-01 | `DiffComparison/RepositoryFreshness.swift:165-171` |
| GDV B5, Core B7: a second directory watch is ignored | GIT-01 | `AtelierFileTree/AtelierFileWatcher.swift:86-87`, `DiffComparison/RepositoryFreshness.swift:192-195` |
| GDV B6: the hover corpus is re-read on every publish | HOVER-03, PERF-08 | `DiffComparison/HoverDocumentation.swift:116-160`, `AtelierDocIndex/DocCommentIndex.swift:39-51` |
| GDV B7: relayout re-renders every card on the main actor | PERF-02, PERF-08, SET-05 | `DiffComparison/RenderPipeline.swift:149-172` |
| GDV B8: gutter draw cost grows with the square of the rows | PERF-05 | `DiffTextKit/DiffGutterView.swift:112-120`, `:282`; `DiffRendering/RenderedDiff.swift:105-107` |
| GDV B9: the toolbar summary is never observed | DIAG-05, DUI-01 | `DiffComparison/DiagnosticsModel.swift:20-39`, `:51`; `GitDiffViewer/Views/ToolbarItems.swift:43`; `GitDiffViewer/Views/FindingsNavigator.swift:14` |
| GDV S2, S3, S5, S9, S17 | PERF-03, PERF-06, PERF-08, SET-03 | as cited in each entry |
| Core B9: SDK misses cached forever | HOVER-04 | `AtelierLSP/SDKDocumentationProvider.swift:78-86`, `AtelierLSP/SourceKitLSPService.swift:143-147` |
| Core B10: the login-shell PATH probe under fish | TOOL-01 | `AtelierDiagnostics/ToolDiscovery.swift:130-148`; the user's login shell is fish |
| Core S16: app names in the core | MOD-02 | `AtelierDiagnostics/DiagnosticTool.swift:42-51`, `AtelierFileTree/AtelierFileWatcher.swift:89` |
| Core S25: sleeps and yields in tests | QUAL-06 | the 14 sites listed above |
| Analyzers A-1, D-2, W-3: absolute SARIF paths | DIAG-01 | Atelier side: `AtelierDiagnostics/SARIFDecoder.swift:80-93`, `AtelierDiagnostics/DiagnosticsEngine.swift:271-275`. The analyzers' output format is the reviewer's reading. |
| Analyzers PH-2: formatter chosen by PATH | PROC-02 | not in this repository; the 09-22 formatter disagreement in the session transcript agrees |
| JSON #5: blocking pool shutdown on quit | PERF-01 | `GitDiffViewer/App.swift:233-236`, `:282` |
| JSON #16: LSP responses parsed twice | JSON-02 | `AtelierLSP/JSONRPC.swift:186`, `AtelierLSP/LSPConnection.swift:70-73` |
| Sec C1, C2, H1, M1, L2 | QUAL-07, TOOL-02 | as cited under QUAL-07 |
| Sec M4: probe URIs under `/tmp` | QUAL-06 | `AtelierLSP/SDKDocumentationProvider.swift:112`, `:265-267` |
| Sec M5: bundle.sh signs what it finds | TOOL-03 | `Apps/GitDiffViewer/scripts/bundle.sh:28-79` |
