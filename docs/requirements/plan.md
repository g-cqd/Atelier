# Requirements plan

**Revision 2, 2026-09-23 14:40 CEST.** Statuses come from `audit.md`, at `main` `ebafb9f`. The order of work is the
fix plan's, `docs/reviews/2026-09-23-fix-plan.md`: Wave 1 (safety and security), Wave 2 (correctness), Wave 3
(rendering performance), Wave 4 (modularization). This plan maps each open requirement onto those waves, the roadmap,
a user decision, or "unplanned", and proposes a home for the unplanned ones.

## Snapshot at 14:40

- `main` is `ebafb9f` (14:26), pushed: `origin/main` equals it. No worktree or branch is left; the checkout is clean
  apart from these three documents.
- Wave 1 is merged except 1K: 1A (8 commits), 1B (4), 1C, 1D, 1E (2), 1F, 1G, 1H (11), 1I, 1J. Track 1K
  (project-hooks) has not started and waits on OQ3.
- The move to AemiJSON is complete in code (`f06b291`, `4b84c84`, `475fc93`, `da05476`, `45dce85`); its measurement
  is not committed.
- Waves 2, 3 and 4 have not started.
- The installed app was built from `ce0880c` (13:52). It lacks the 33 later commits, among them the trust gate and
  the git configuration gate, so a reinstall is due.
- The user has twelve open questions (`book.md`, "Open questions (09-23)").

| | Implemented | Partially | In progress | Designed | Planned | Not started | Superseded | Decision | Visual | Total |
|---|---|---|---|---|---|---|---|---|---|---|
| Requirements | 26 | 43 | 1 | 1 | 10 | 1 | 4 | 2 | 33 | 121 |

91 requirements are open: every one that is neither Implemented nor Superseded. The 33 that need a visual check need
nothing else unless the check fails.

## Where each open requirement's work is

A requirement can appear in several places when its criteria fall to different tracks.

### Wave 1, merged except 1K

| Track | Requirements it moved | State at `ebafb9f` |
|---|---|---|
| 1A: trust gate, registry, SDK probe, quit | QUAL-07 (criteria 1 and 4), TOOL-02 and SET-03 (Sec L2), HOVER-04 (Sec M4, GDV S11), PERF-01 (quit), PERF-03 (indexing off), GIT-02 (Fetch off while untrusted) | Merged; a visual check remains (QUAL-07, PERF-01) |
| 1B: git configuration gate | QUAL-07 (criterion 2), GIT-02 (Sec H1), CARD-11 (Sec C2) | Merged |
| 1C to 1J | QUAL-07 (M1, H2), DIAG-01, TOOL-01, GIT-01 (core half), GIT-05, PERF-03 (Aemi #26), PERF-09 (1H: parser termination and G1), PROC-11 | Merged |
| 1K: project-hooks PH-6 | QUAL-09, PROC-12, PROC-05 | Not started; OQ3 |

### Wave 2, correctness

| Track | Requirements | What the track fixes for them |
|---|---|---|
| 2A | SET-03, SET-05 | Spurious overrides (GDV B1, S10), granularity scoped (S17). Starts from the settings files as the JSON switch left them. |
| 2B | GIT-03, GIT-04, SET-05, PERF-02, PERF-08, DIFF-02 | Reload continuity (GDV B2, B3, S1), one card per gap step off the main actor (B7), the theme's scroll reset. Needs OQ7 (Swap) first. DIFF-02 joins it if OQ8 (a). |
| 2C | GIT-01, PERF-03, PERF-08, QUAL-06 | The watcher kept across reloads (GDV B4), linked worktrees (B5, HEAD watch), ignored paths (S2), one reload per fetch (S3), the `.build/index-build` regression test, two test waits. |
| 2D | DIAG-04, DIAG-05, DUI-01, PERF-08 | An observed summary (GDV B9), findings kept across unchanged reloads (S9). |
| 2E | HOVER-03, HOVER-06, HOVER-14, PERF-08, MOD-01, QUAL-06 | The hover corpus (GDV B6, Core S4, S5, fix 4), the chip on rows with findings, the dead `TieredHoverProvider` (S20), four test waits. |
| 2F | HOVER-04, JSON-02, JSON-04, QUAL-06 | Timeouts no longer cached (Core B9), the `initialize` decode (Aemi #28), the LSP decoder's depth cap (Aemi #6), two test waits and silent catches. |
| 2M | PERF-08 | Mapped reads and size caps in search, hashing and loading. |
| 2O | PROC-12, TOOL-03, PROC-02 | aemi pinned (Aemi #24; OQ2), `bundle.sh` verifying what it signs (Sec M5), one build command (GDV N5). |

### Wave 3, rendering performance

| Track | Requirements |
|---|---|
| 3H | REND-03 (renderer M0 items 1 and 6), PERF-05, PERF-02 (`loadSides` off the main actor, with a thread probe). Item 4, the wrapped-height memo, already landed in `ce0880c`: re-scope the track before it starts. |
| 3B, 3J | PERF-02 (KittyCode highlighting and search off the main actor) |
| 3A to 3K, then the pipeline P1 to P3 | PERF-09 (P2 includes renderer M0 item 8) |

### Wave 4, modularization

| Track | Requirements |
|---|---|
| 4A | MOD-01 (the grammar corpus); a prerequisite of HOVER-16 |
| 4B | MOD-01, MOD-02 (`GitStatusProvider` in the core, event-driven git refresh in KittyCode) |
| 4C | MOD-02 (neutral names in the core) |
| 4E | MOD-03, QUAL-06 (the last force unwrap and a test wait) |
| 4F | QUAL-03 (the four files the sweep excluded), QUAL-06 (documents that contradict the code) |

### The roadmap only

| Roadmap section | Requirements |
|---|---|
| Phases M1 to M3 (multi-language hover) | HOVER-16, after track 4A (track 1A has merged) |
| Accent-color adaptation (research) | SET-08 |
| Diff interaction refinements, "not scheduled yet" | DIFF-01, DIFF-02, DIFF-03, DIFF-04 (OQ8) |
| In flight: the AemiJSON benchmark | JSON-01 |
| `docs/design/text-renderer.md` §5, M1 and M2 | REND-02 (OQ1) |

### Waiting on a user decision

| Question | Requirements |
|---|---|
| OQ1 | REND-02, REND-03 |
| OQ2 | PROC-12 (criterion 3) |
| OQ3 | QUAL-09, PROC-12 (project-hooks), PROC-05 (PH-5) |
| OQ4 | DIAG-01 (the live run), TOOL-03 (bundling the analyzers) |
| OQ5 | SET-03 (criteria 3 to 5) |
| OQ6 | DIAG-08 |
| OQ7 | GIT-03 (criterion 3) |
| OQ8 | TAB-07, DIAG-03, DUI-03, HOVER-14, HOVER-05, HOVER-08, DIFF-01 to DIFF-04 |
| OQ9 | CARD-09 (the `new ← old` label) |
| OQ10 | TAB-09 |
| OQ11 | a possible Xcode diff palette (no requirement yet) |
| OQ12 | PROC-09 (commit titles) |

### Unplanned, with a proposed home

No wave, track or roadmap section holds these. The proposed home is the track that already owns the file.

| Requirement | Gap | Proposed home |
|---|---|---|
| QUAL-07, PERF-08 | Rename detection writes `.git/index` (`AtelierGit/GitClient.swift:122-127`) | 2C (owns `GitClient.swift` in Wave 2) |
| GIT-01 | The ref menus go stale after a commit | 2C (owns `DiffViewerModel+Freshness.swift`) |
| PERF-08 | Any change inside `.git` runs a full `git status` | 2C (owns `RepositoryFreshness.swift`) |
| PERF-08 | Every reload re-hashes the working tree | 2M (owns `SourceLoader.swift`) |
| DIAG-01 | The analyzers run on changesets with no Swift file | 2E (owns `DiffViewerModel+Diagnostics.swift`) |
| HOVER-11 | Old declarations listed when both sides are refs or a file was renamed | 2E (owns `DocCommentIndex.swift`) |
| HOVER-04 | No iOS SDK for the SDK probe (criterion 3) | 2F (owns `SDKDocumentationProvider.swift`) |
| MOD-01 | `renderHoverMarkdown`, called only from tests; hover structuring in the app | 2E |
| SET-01 | The toolbar's short labels | A new small track owning `ContentView.swift` |
| — | Sidebar visibility shared by every window; a tool missing from saved settings never runs | 2A (owns `ViewerSettings.swift`) |
| TOOL-01, TOOL-02 | Refresh keeps the discovery caches; the Tools and Language Servers sections locked while diagnostics are off; a broken pin shows green; a new sourcekit-lsp pin needs a restart | A new Wave 2 track, "2Q, tool settings", owning `ToolsSettings.swift`, `ToolDiscovery.swift` and `SourceKitLSPRegistry.swift` |
| CARD-09, CARD-11 | The ref side's tree draws unstaged changes filled | A new small track owning `FileExplorerView.swift` |
| HOVER-09 | The card list's hover panel ignores list scrolling | A new small track owning `DocHoverController.swift` and `EmbeddedDiffTextView.swift` |
| PERF-06 | The status bar's material, with nothing beneath it | The feature wave (OQ8) |
| JSON-04, JSON-01 | No committed measurement of the switch | Commit `/private/tmp/w1json-bench` as a gated benchmark, which also serves JSON-01 |
| PROC-02 | Plain `swift` resolves to Xcode's 6.3.3; `AGENTS.md:49` recommends `xcrun swift` | 2O for the build command; `AGENTS.md` in 4F |
| PROC-06 | Stale roadmap sections; no link to the fix plan | Now: documents only, no collision with any track |
| MOD-02 | The module map of tiers and consumers | 4F |
| QUAL-06 | 62 tests with camelCase names | 4F, or each track for the files it touches |
| QUAL-01 | SE-0475 `Observations`, typed throws in `DiagnosticsEngine` | After Wave 2, with 2A and 2D's files |
| PERF-04, PERF-05, PERF-07 | Measurements, kept in the repository | With the visual checklist, now |
| GIT-05 | Evidence that the stress test passes repeatedly | Run `FileWatcherTests` 20 times once the machine is free |

## Dependencies

- **OQ7 comes before track 2B.** Swap's behaviour decides one of 2B's tests.
- **Track 2A builds on the settings files** the JSON switch changed (`ViewerSettings.swift`,
  `ViewerSettings+ProjectOverrides.swift`).
- **Track 2C** takes the `.git/index` fix with `GitClient.swift`, which 1B changed last.
- **DIFF-02 goes with track 2B,** or after it: both change `RenderPipeline.adjustGap`.
- **Track 3H** loses its wrapped-height item, which `ce0880c` delivered; **track 3F** loses the stack copies, which 1H
  removed (`d74c4f6`).
- **HOVER-16** can start after track 4A: the trust gate it needed has merged.
- **OQ5 comes before** SET-03's selector and list; **OQ6 before** DIAG-08; **OQ1 before** the renderer seam.
- **1K and the PH-5 fix** let pushes go out while agents edit (OQ3).

## Recommended order

1. **Reinstall from `ebafb9f`** (PROC-03), then run the visual checklist in `audit.md` and record the three
   measurements (PERF-04, PERF-05, PERF-07) in the repository. 33 requirements close or reopen on it.
2. **Record the answers** to the open questions in `book.md`, start 1K if OQ3 says so, and refresh the roadmap so it
   points at the fix plan (PROC-06).
3. **Wave 2** in parallel, with the proposed additions: 2A, 2B (after OQ7), 2C, 2D, 2E, 2F, 2M, 2O, the new "2Q",
   and the three small tracks.
4. **The feature wave** that OQ8 settles: TAB-07, card-list diagnostics, HOVER-08 and HOVER-05, SET-03's selector,
   DIAG-08's modes, DIFF-01, DIFF-03 and DIFF-04.
5. **Wave 3,** with the renderer seam and M1 if OQ1 says so.
6. **Wave 4.**

## Cross-reference with the roadmap

`Apps/GitDiffViewer/docs/roadmap.md` at `ebafb9f`, where it disagrees with the code or the plans:

| Roadmap section | Disagreement |
|---|---|
| In flight | "adoption verdicts pending numbers": AemiJSON now backs every JSON call site (JSON-04), and no benchmark is in the repository (JSON-01). |
| Phase M4 | Expects settings to stay on Foundation, which JSON-04 overturned. |
| UI wave | Promises a provenance footer and an apple-docs tier (both dropped), a trailing-edge chip (never built), and a LazyVStack sticky header (replaced by `840d4e1`). |
| Reload continuity wave | Presents continuity as planned work and native tabs as "investigate"; GIT-03 is track 2B, and native tabs shipped in `c1be5ac`. |
| Badge state fidelity | Describes work finished in `2cd8a60` and `2d6d788`. |
| Diff interaction refinements | Consistent: "not scheduled yet" (OQ8). |
| Missing | The fix plan and its waves, the security work (Wave 1), the renderer decision (OQ1), TAB-07, and the defects outside every plan. |
