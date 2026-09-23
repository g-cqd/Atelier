# Requirements plan

This plan groups the requirements of `book.md` by delivery state, gives their dependencies, and recommends an
order for the rest. Verdicts come from `audit.md`, taken against `main` at `10ae905` (2026-09-23 08:11 CEST).

## Snapshot

- `main` is at `10ae905` and pushed. The tab bar restyle was uncommitted when the audit began and landed as
  `10ae905` at 08:11. The only other change in the main checkout is the sticky-header file below.
- The sticky-header rework is underway. Its agent resumed at 07:43, made a baseline capture of `main` at 08:22, and
  at 09:27 added an untracked `Apps/GitDiffViewer/Sources/DiffTextKit/StickyCardGeometry.swift` (a clip geometry
  for pinned headers). Nothing uses it yet.
- The comment sweep is done on three branches: `chore/comments-core` (4 commits), `chore/comments-gdv` (5) and
  `chore/comments-kitty` (4). Nothing is on `main` yet.
- Six code reviews finished between 08:20 and 08:27 (`/tmp/reviews/`). No fix has started.
- The installed app dates from 2026-09-22 16:32 and predates `eeb7ffa` and `10ae905`.

| Area | Delivered | In progress | Remaining | Superseded |
|---|---|---|---|---|
| PROC | 6 | 1 | 1 | 0 |
| DIAG | 4 | 0 | 4 | 0 |
| TOOL | 1 | 0 | 2 | 1 |
| HOVER | 6 | 0 | 10 | 2 |
| DUI | 2 | 0 | 2 | 0 |
| SET | 4 | 0 | 4 | 0 |
| CARD | 3 | 5 | 3 | 0 |
| TAB | 4 | 1 | 0 | 1 |
| GIT | 1 | 0 | 3 | 0 |
| WIN | 1 | 0 | 2 | 0 |
| PERF | 2 | 3 | 3 | 0 |
| JSON | 1 | 0 | 2 | 0 |
| MOD | 0 | 0 | 3 | 0 |
| QUAL | 3 | 1 | 3 | 0 |
| **Total** | **38** | **11** | **42** | **4** |

## Delivered

Requirements with the verdict Met, with the commits that delivered them.

| Area | Requirements | Commits |
|---|---|---|
| PROC | PROC-01, PROC-02, PROC-04, PROC-05, PROC-07, PROC-08 | `8fdec51` (toolchain pin); process work on 09-21 |
| DIAG | DIAG-02 toggles, DIAG-04 status bar, DIAG-06 project configurations, DIAG-07 Lockwood's SwiftFormat | `dc9eb77`, `c6d12ea`, `7b9a7a3`, `1c5bdec` |
| TOOL | TOOL-03 optional bundling | `c6d12ea` |
| HOVER | HOVER-01 hover tiers, HOVER-02 every pane, HOVER-09 follows its line, HOVER-11 no duplicates, HOVER-13 no source label, HOVER-15 multi-language design | `8fdec51`, `661c8b1`, `90374b7`, `b30579b`, `c10d36e`, `eeb7ffa` |
| DUI | DUI-02 no gutter shift, DUI-04 line-anchored popover | `c10d36e` |
| SET | SET-01 research-based Settings, SET-02 platform conventions, SET-04 light and dark, SET-06 appearance from the theme | `1c5bdec`, `1752778`, `eeb7ffa` |
| CARD | CARD-01 sticky headers, CARD-07 gap kept when folded, CARD-08 fold symbols | `c10d36e`, `eeb7ffa` |
| TAB | TAB-01 native window tabs, TAB-02 equal gaps, TAB-04 close in the badge slot, TAB-05 badge instead of the icon | `c1be5ac`, `10ae905` |
| GIT | GIT-02 fetch in the core | `16d22fe`, `c10d36e` |
| WIN | WIN-03 symmetric selectors | `b5015f0` |
| PERF | PERF-01 non-blocking tool runs, PERF-04 folded headers cost nothing | `dc9eb77`, `18950b3`, `eeb7ffa` |
| JSON | JSON-03 JSON-RPC on AemiJSON | `8fdec51` |
| QUAL | QUAL-02 Codex review, QUAL-04 this book, QUAL-05 code reviews | `c10d36e`; `/tmp/reviews/` |

## In progress

| Work | Where | Requirements | State |
|---|---|---|---|
| Sticky-header rework | the resumed agent in the main checkout; review builds in `/private/tmp/gdv-cards` | CARD-02, CARD-03, CARD-04, CARD-05, CARD-06, PERF-05, PERF-06 | Baseline captured; one untracked file, not wired |
| Install and measure | the next build | PROC-03, PERF-07 | Waits on the sticky-header rework |
| Tab bar restyle | landed as `10ae905` | TAB-03 | Committed; needs a visual check |
| Comment sweep | three `chore/comments-*` branches | QUAL-03 | 13 commits verified comment-only; not on `main`; four files excluded |

## Remaining

| Verdict | Requirements |
|---|---|
| Regressed | TOOL-02 |
| Not met | DIAG-05, DUI-01, GIT-03, HOVER-16, SET-08, CARD-11, MOD-03, QUAL-06, QUAL-07 |
| Partially met | PROC-06, DIAG-01, DIAG-03, DIAG-08, TOOL-01, HOVER-04, HOVER-05, HOVER-06, HOVER-14, DUI-03, SET-03, SET-05, SET-07, CARD-09, GIT-01, GIT-04, PERF-02, PERF-03, PERF-08, JSON-01, JSON-02, MOD-01, MOD-02, QUAL-01 |
| Needs visual confirmation | HOVER-03, HOVER-07, HOVER-08, HOVER-10, HOVER-12, CARD-10, WIN-01, WIN-02 |

The in-progress items also carry these verdicts: CARD-03 and CARD-06 Not met; CARD-04, PERF-06, PERF-07, PROC-03
and QUAL-03 Partially met; CARD-02, CARD-05, PERF-05 and TAB-03 Needs visual confirmation.

## Dependencies

- **QUAL-03** (the sweep) comes before any other change to the files it touches, since every later edit would
  conflict with it, and before the documentation fixes of QUAL-06.
- **QUAL-07** (a trust gate for the language server) comes before **HOVER-16**: each new language server widens the
  exposure Sec C1 describes.
- **GIT-03** (keep the viewer during reloads) comes before the visual checks of **CARD-02** to **CARD-06** and the
  scroll measurement of **PERF-05**: today every save unmounts the cards being judged.
- **GIT-01**'s watcher changes (one stream over several roots, no re-attach per reload) come before **MOD-02**'s
  removal of KittyCode's polling `GitRefreshManager`, because both apps share `AtelierFileWatcher`.
- **SET-03**'s fix for spurious overrides (GDV B1) comes before the rest of **SET-03** and **SET-05**.
- **DIAG-05**'s observation fix (GDV B9) also fixes **DUI-01**'s hidden button.
- The sticky-header rework precedes the install of **PROC-03** and the WindowServer measurement of **PERF-07**.
- **MOD-01** and **MOD-02** (an `ExecutableLocating` seam, the grammar corpus in a shared target) come before
  **HOVER-16**.
- The move of `GitStatusProvider` to `AtelierGit` (**MOD-02**) comes before **CARD-11**, as the roadmap's "Badge
  state fidelity" section already says.
- **DIAG-03** (diagnostics in the card list) comes after the sticky-header rework, which owns
  `CombinedDiffView.swift` today.

## Recommended order

1. **Land the comment sweep (QUAL-03).** It is verified comment-only and conflicts with everything else. Sweep the
   four excluded files once the sticky-header rework lands.
2. **Close the safety gaps (QUAL-07, part of TOOL-02).** Add a per-repository trust decision before sourcekit-lsp
   starts in a repository (Sec C1). Pin or reject every git configuration key that runs a command (Sec C2), and pin
   the fetch transport (Sec H1). Filter link schemes in the hover panel (Sec M1). Honor a per-project sourcekit-lsp
   disable (Sec L2). Hover is on by default, so this protects every user of the next build.
3. **Make reloads keep the viewer (GIT-03, GIT-04, GIT-01, PERF-03).** Keep what is published until both sides of a
   reload land (GDV B2). Keep cards and the file pane published across the render hop (GDV B3, with S1). Keep the
   watcher's stream across reloads (GDV B4), and watch every root in one stream (GDV B5, Core B7, Core B8). Add the
   missing tests: `detailState` during a re-render and during a two-sided reload, and the hidden-path loop.
4. **Ship the small correctness fixes.** Each is local and independent:
   - DIAG-05 and DUI-01: make the diagnostics summary observed (GDV B9); add the line jump.
   - SET-05 and SET-07: reload `badgeScheme` on broadcast; draw every badge in the chosen scheme; stop writing
     project overrides while applying a broadcast or adopting a project (GDV B1).
   - HOVER-06: keep `chipBackground` when diagnostics join the hover document.
   - TOOL-02: enable the Language Servers section whatever the diagnostics toggle; show a broken pin; apply a new
     sourcekit-lsp pin without a restart.
   - TOOL-01: read the login shell's `PATH` in a way fish supports (Core B10).
   - HOVER-04: cache real answers only, never timeouts (Core B9).
   - DIAG-01: relativize absolute SARIF paths; install arcleak, dolly and deadwood and verify them; skip corpus
     tools in repositories without Swift files.
5. **Finish the sticky headers (CARD-02 to CARD-06, PERF-05, PERF-06),** then install, run the visual checklist in
   `audit.md`, and measure WindowServer against the 38.4% baseline (PROC-03, PERF-07). The checklist settles all
   twelve verdicts that wait for a visual check.
6. **Bring diagnostics to the card list (DIAG-03, DUI-03, HOVER-14).** Add the overlay to `EmbeddedDiffTextView`,
   the trailing-edge marker, range-based hover diagnostics, and the Show Documentation and Show Issue menu.
7. **Complete per-project settings (SET-03, DIAG-08).** Add per-window controls for the scoped diagnostics
   settings, tool locations and context lines, after the user answers Q2. Analyze the older side for real, or keep
   the echo, after Q5.
8. **Remove unnecessary work (PERF-08, PERF-02, JSON-01, JSON-02).** Upsert the hover corpus instead of replacing
   it (GDV B6). Render one card per gap drag and move the full relayout off the main actor (GDV B7). Keep findings
   across unchanged reloads (GDV S9). Reload only for paths git tracks (GDV S2), and once per fetch (GDV S3). Limit
   sourcekit-lsp's background indexing. Decode LSP payloads from the parsed tape (JSON #16). Commit the AemiJSON
   benchmark, gated. Review KittyCode for `@concurrent` candidates.
9. **Honor the tier rules and finish modularizing (MOD-03, MOD-01, MOD-02).** Reshape the five unstructured tasks
   into caller-driven APIs (Core S1). Delete the app's `TieredHoverProvider` and `renderHoverMarkdown`. Take app
   names out of the core (Core S16). Move `GitStatusProvider` to `AtelierGit`, switch KittyCode to the shared
   watcher and delete `GitRefreshManager`. Move the grammar corpus to a shared resource target.
10. **Hover for other languages (HOVER-16, HOVER-05).** Follow phases M1 to M3 of the roadmap, behind the trust
    gate. Add the Quick Help title row and section headers from image 02.
11. **Badge fidelity (CARD-11, CARD-09).** Carry git's index and worktree columns into the comparison model.
12. **Definition of Done (QUAL-06, QUAL-01, PROC-06).** Each wave adds its own tests. Then rename the 62 camelCase
    tests, replace the 14 sleeps and yields with probes, remove the six force unwraps, log swallowed errors, and
    align the design documents and the roadmap with the code. Title future commits in the repository's
    `<Scope>: <sentence>` form.
13. **Research and questions (SET-08, Q1 to Q5).** Write the accent-color note, and put the five open questions to
    the user.

## Cross-reference with the roadmap

`Apps/GitDiffViewer/docs/roadmap.md` at `10ae905`, section by section.

| Roadmap section | State per the audit | Disagreement |
|---|---|---|
| In flight: Track A chrome and glue | Delivered, except DIAG-05 | The section still reads "in flight", although `c6d12ea` shipped it. The toolbar readout does not update (GDV B9). |
| In flight: Track B language server and tiered provider | Delivered | Still "in flight". |
| In flight: AemiJSON benchmark, "adoption verdicts pending numbers" | Adopted for SARIF and JSON-RPC in `8fdec51` | Stale. The benchmark itself is not in the repository (JSON-01). |
| Phase M1: language-server genericization | Only `Language.lspLanguageID` exists | The roadmap schedules it "after the Swift hover lands", which happened; it should now also wait for the trust gate (QUAL-07). |
| Phase M2: descriptor registry | Not started | None. |
| Phase M3: doc-comment tier | Not started | None. |
| Phase M4: JSON, "gated on benchmark verdicts" | Mostly applied in `8fdec51` | What remains is not listed: the double parse of LSP responses (JSON #16) and the unused `@JSONCodable` path. |
| Later: arcleak baseline, blob `didOpen`, semantic tokens, bundled servers, shim removal | Not started | None. The blob `didOpen` item relates to Q5 (DIAG-08). |
| Non-goals: no offline docsets | Consistent | HOVER-04 still needs a route to iOS-only frameworks; an iOS SDK probe would not be a docset. |
| UI wave: findings navigator, "row click jumps to the line" | Built, but the button never appears; the jump stops at the file | The roadmap promises the line jump (GDV S18). |
| UI wave: markers without layout shift, trailing chip, popover on the line | Gutter marker and popover delivered; trailing chip dropped | The roadmap does not record that the chip was cut. |
| UI wave: unified hover and context menu | Single-file view only; no context menu | Not recorded. |
| UI wave: rich popover with "provenance footer, apple-docs corpus as the system-API tier" | Panel delivered | Stale: the footer was removed (HOVER-13) and apple-docs was declined (HOVER-04). |
| UI wave: sticky file headers | Delivered with open visual defects | The defects the user reported on 09-22 are not recorded (CARD-02 to CARD-06). |
| Reload continuity wave | Partly delivered | Presented as planned work; GIT-03 is Not met (GDV B2, B3). |
| Reload continuity wave: native tabs, "investigate" | Delivered in `c1be5ac` | Still "investigate". |
| In-app tab bar styling, "shipped" | Delivered in `10ae905` | Consistent; TAB-03 needs a visual check. |
| Accent-color adaptation (research) | Not started | Consistent with SET-08. |
| Badge state fidelity (follow-up) | Not started | Consistent with CARD-11. |

The roadmap does not mention these open requirements at all: QUAL-07 (the security findings), MOD-03 (Codex finding
15), TOOL-02's regression and TOOL-01's fish failure, SET-03's missing per-window controls and spurious overrides,
SET-05's badge-scheme propagation, GIT-01's multi-root watcher, DIAG-01's dropped SARIF findings, and HOVER-04's iOS
frameworks.

Other design documents disagree with the code as well (details in `audit.md`, cross-cutting section):
`hover-panel-design.md` (title row, provenance footer), `settings-design.md` (R5's overridable set),
`gaps-and-modularization.md` (fetch pool, debounce value) and `hig-liquid-glass-plan.md` (three Settings tabs, the tab
bar's background).
