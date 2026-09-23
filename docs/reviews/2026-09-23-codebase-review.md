# Codebase review: Atelier and its owned dependencies

Consolidated from six code reviews, four adversarial verification passes, three measured rendering reviews and three
comment-sweep reports, all dated 2026-09-23. The companion fix plan is `2026-09-23-fix-plan.md` in this directory.

## 1. Scope, revisions and method

**Scope.** The Atelier monorepo (`Apps/GitDiffViewer`, `Apps/KittyCode`, `Packages/AtelierCore`) and the dependencies
the user owns and uses: aemi (`dacd5f1`), AemiJSON (`b98f139`), project-hooks (`8e1573f`), arcleak (`35b5b86`), dolly
(`06ecc5a`) and deadwood (`0f4541d`).

**Revisions.**
- Reviewed: `10ae905` (`main`, 2026-09-23 08:11 CEST).
- Statuses are current to `5a990db` (`main`, 11:39).
- `main` has since moved to `d662777` through two documentation-only commits: `47f2985` adds
  `docs/design/text-renderer.md`, and `d662777` updates the roadmap and the requirements book. Neither changes a
  status. Sections 5, 7 and 8 cite them where they add information.

**Line references.** Every file:line refers to `10ae905` unless it says otherwise; read one with
`git show 10ae905:<path>`. Paths start at the target directory: `Atelier*` targets live in
`Packages/AtelierCore/Sources/`, `Kitty*` targets in `Apps/KittyCode/Sources/`, and `DiffComparison`,
`DiffRendering`, `DiffTextKit` and `GitDiffViewer` in `Apps/GitDiffViewer/Sources/`. Paths in the other repositories
are relative to their own roots.

**Method.**
- Six reviews, all written against `10ae905`:
  - `gitdiffviewer.md`: B1–B9, S1–S20 and five unnumbered nits, numbered N1–N5 here in the order they appear.
  - `ateliercore.md`: B1–B13, S1–S25, N1–N12.
  - `kittycode.md`: B1–B11, S1–S18, N1–N6.
  - `aemi-aemijson.md`: #1–#36.
  - `analyzers-hooks.md`: PH-1–PH-13 (project-hooks), A-1–A-9 (arcleak), D-1–D-9 (dolly), W-1–W-6 (deadwood).
  - `security.md`: C1, C2, H1, H2, M1–M5, L1–L3, and hardening notes without IDs.
- Four adversarial verification passes re-checked 76 of the 204 findings, by experiment where they could:
  - `verify-gitdiffviewer.md`: GDV B1–B9, S1, S10, S11 and Sec M1, M4, L2.
  - `verify-ateliercore.md`: Core B1–B13, S2, S8, S23, Aemi #3, #4, #6, #26, #29, #30 and Sec C2, H1, plus five
    defects no review reported.
  - `verify-kittycode.md`: Kitty B1–B11, S2, S4, S13 and Sec H2.
  - `verify-deps.md`: Aemi #1, #2, #5, #7, #9, #10, #15, #18; PH-1–PH-6; A-1, A-2, A-5; D-1, D-2; W-1–W-3.

  Where a verifier disagrees with a review, this document uses the verifier's verdict, severity, fix and interaction
  notes, and says so.
- Three measured rendering reviews: `perf-gui.md`, `perf-tui.md` and `perf-core.md`.
- Three comment-sweep reports: `sweep-core.md`, `sweep-gdv.md` and `sweep-kitty.md`.
- The requirements book and audit (`docs/requirements/book.md`, `docs/requirements/audit.md`) for requirement IDs.
- The input reports live in `/tmp/reviews/`, outside the repository.
- Statuses: this review read every diff in `10ae905..5a990db` (26 commits). The 13 comment-sweep commits change
  only comment and blank lines: in each, the count of changed lines that are neither is zero. Every finding in a
  file that one of the other 13 commits touches was re-read at `5a990db`.

**Terms.**
- Severity. The five code reviews rate Blocking, Suggestion or Nit. The verifiers re-rated some blocking findings to
  High, Medium or Hardening (a defence against deliberately absurd input). The security review rates Critical,
  High, Medium or Low. The two scales are counted apart.
- Verdict. Confirmed, Plausible or Refuted, from the verifiers. Unverified means no verifier re-checked the finding;
  its severity is then the reviewer's.
- Status. Fixed `<commit>`; Partial `<commit>`, where the commit fixes part of the finding and the area notes say
  which part; or Open.
- Prefixes outside the tables: GDV, Core, Kitty, Aemi (the audit writes "JSON #n" for the same items) and Sec.
  dolly's D-1 to D-9 carry a hyphen; perf-core's D1 to D9 do not and carry the prefix "perf-core". perf-core's M1–M3
  and G1–G3 also carry it, to keep them apart from Sec M1 and perf-tui's version gates.

**Commit hashes.** The brief for this review cited eight hashes of pre-rebase copies that are not on `main`. Each has
the same `git patch-id` as a commit on `main`, and this document cites the `main` hash. `840d4e1`, `2b3a5c3` and
`5a990db` are on `main` as cited.

| Change | On `main` | In the brief |
|---|---|---|
| File watcher use-after-free | `8fd26e5` | `567dbb2` |
| git status keeps both columns | `2cd8a60` | `6814248` |
| Badges follow git, file by file | `2d6d788` | `82abf75` |
| Capsule tabs and the tab-bar backdrop | `130fa5c` | `ee4af41` |
| Tab badge at its own size | `bbe50e7` | `5b8ac6b` |
| NSFont Sendable warning | `679bf88` | `d3070e8` |
| Model harness failure bound | `609d757` | `ff2abe2` |
| Tolerant spy for every suite | `e56c8b0` | `a10ab1b` |

**Commits between the two revisions.**

| Commit | What changed | Effect on findings and requirements |
|---|---|---|
| `8fd26e5` | FSEvents owns the watcher's context box through retain and release callbacks; the stream stops and releases on its own queue; `FileWatcher` gains a `deinit`; the queue becomes `Atelier.FileWatcher.events`, documented as required | Core S15 fixed; Aemi #27, Core S16 and GDV S16 partial |
| `840d4e1` | One AppKit view per sticky card; no-wrap panes size without layout; gutter and cursor-rect walks cover only the dirty or visible rect, with cached metrics | GDV B8, S5, S6 fixed; GDV S7, N4 partial; perf-gui fixes 1 and 2; CARD-02 to CARD-06, CARD-12, PERF-06 |
| `2cd8a60` | git status keeps the staged and unstaged columns; a source reader can ask for a working tree's per-file status | CARD-11 groundwork |
| `2d6d788` | Per-file badge states; an index watch refreshes badges; `badgeScheme` and `matchesThemeAppearance` reach open windows | CARD-11, SET-05, SET-07. GitDiffViewer now runs `git status` on every load and every index change, which widens Sec C2 |
| `2b3a5c3`, `b693b70`, `5a990db` | Card headers draw the chosen scheme and the git state; white badges on a focused selection, forwarded by the cell | SET-07, CARD-09, CARD-10 |
| `130fa5c`, `bbe50e7` | Capsule tabs with hover, close disc and pin; the card list scrolls beneath the tab bar | TAB-08; TAB-09 for the card list only |
| `679bf88` | Removes the NSFont Sendable build warning | QUAL-06 |
| `609d757`, `e56c8b0` | Test failure bounds rise from 1–2 s to 15 s | No finding: the 14 forbidden `Task.sleep` and `Task.yield` waits remain |
| `c375952` | Requirements book, plan and audit | QUAL-04 |
| 13 sweep commits, `fe98a89` to `195cf93` | Comments only; the sweep reports list 28 wrong comments corrected (7 core, 11 GitDiffViewer, 10 KittyCode) | QUAL-03 |

## 2. Executive summary

### Counts

There are 204 findings: 192 from the five code reviews and 12 from the security review. The verifiers re-checked 76:
74 Confirmed, 1 Plausible (A-2) and 1 Refuted as stated (Sec M4, whose underlying hygiene defect is real). They
re-rated 13 of the 53 blocking findings and lowered Sec M4 from Medium to Low. At `5a990db`, 4 findings are Fixed, 5
Partial and 195 Open.

Code-review findings, by severity after verification:

| Severity | Findings | Re-verified | Fixed | Partial | Open |
|---|---|---|---|---|---|
| Blocking | 40 | 40 | 1 | 0 | 39 |
| High (re-rated from Blocking) | 4 | 4 | 0 | 0 | 4 |
| Medium (re-rated from Blocking) | 1 | 1 | 0 | 0 | 1 |
| Suggestion | 109 | 22 | 3 | 4 | 102 |
| Hardening (re-rated from Blocking) | 3 | 3 | 0 | 0 | 3 |
| Nit | 35 | 0 | 0 | 1 | 34 |
| **Total** | **192** | **70** | **4** | **5** | **183** |

Security findings:

| Severity | Findings | Re-verified | Fixed | Partial | Open |
|---|---|---|---|---|---|
| Critical | 2 | 1 | 0 | 0 | 2 |
| High | 2 | 2 | 0 | 0 | 2 |
| Medium | 4 | 1 | 0 | 0 | 4 |
| Low | 4 | 2 | 0 | 0 | 4 |
| **Total** | **12** | **6** | **0** | **0** | **12** |

By area:

| Area | Findings | Re-verified | Blocking after verification | Fixed | Partial | Open |
|---|---|---|---|---|---|---|
| GitDiffViewer | 34 | 12 | 9 | 3 | 3 | 28 |
| AtelierCore | 50 | 16 | 10 | 1 | 1 | 48 |
| KittyCode | 35 | 14 | 5 | 0 | 0 | 35 |
| aemi and AemiJSON | 36 | 14 | 5 | 0 | 1 | 35 |
| Analyzers and hooks | 37 | 14 | 11 | 0 | 0 | 37 |
| Security | 12 | 6 | 2 Critical, 2 High | 0 | 0 | 12 |
| **Total** | **204** | **76** | | **4** | **5** | **195** |

The 13 re-rated blocking findings: Core B4, B5 and B9 became Suggestions; Kitty B1, B5, B9 and B10 became High; Kitty
B7 and B8 became Hardening; Aemi #3 became Medium; Aemi #6 became Hardening; A-2 and W-1 became Suggestions.
Verification and the sweeps also surfaced 8 defects no review reported (section 5).

### Top 10 open issues by user impact

Ranked by verified severity, then by reach: on by default, present in the user's own setup, or putting data or code
execution at stake.

1. **Hovering can run code from any repository the user opens (Sec C1, Critical, unverified).** Hover is on by
   default, and GitDiffViewer starts sourcekit-lsp with the repository as `rootUri` and working directory
   (`DiffComparison/HoverDocumentation.swift:191-197`, `GitDiffViewer/App.swift:244-255`,
   `AtelierLSP/SourceKitLSPService.swift:225-229` and `:341-345`). A committed `buildServer.json` names a command
   that sourcekit-lsp launches; manifests, plugins and compile commands are further vectors. No verifier ran it; the
   audit confirmed the Atelier-side path. QUAL-07.
2. **git runs commands chosen by the repository's configuration (Sec C2 and H1, Critical and High, both
   reproduced).** A clean filter runs on every `git status` and working-tree `git diff -M`; `log.showSignature` with
   `gpg.program` runs during `git log`; four fetch transports run commands, and the pins the review proposed miss
   `protocol.ext.allow`. The verifier ran every C2 payload on three git builds, and all four H1 transports ran too.
   Since `2d6d788`, GitDiffViewer also runs `git status` on every load and index change. QUAL-07, GIT-02.
3. **KittyCode corrupts CRLF files (Kitty B6, Blocking, worse than reported).** Each open-and-save cycle adds a CR to
   every line; on the third cycle the line-ending detector flips to CR and every LF is dropped.
4. **KittyCode silently overwrites changes made outside the editor (Kitty B3 and B4 Blocking, B5 High).** The file
   watch dies after the first atomic save, nothing reads `externallyModified`, and an inactive autosave clears
   `isDirty` without `markSaved`. After such an autosave, undoing back to the original text lets the tab close
   without a prompt while the disk keeps the undone edits.
5. **Every reload collapses the diff viewer (GDV B2 and B3 with S1, Blocking).** Reload, Swap, a commit in a terminal,
   or a save of the file on screen blanks the view into "Comparing…" and loses scroll, folds and reuse. This is the
   audit's first gap. GIT-03, GIT-04.
6. **KittyCode spins forever on small JSON files (new: the `ParseStack.popNodes` off-by-one and the unbounded reduce
   loop).** `[{},{}]`, `[[]]` and `[true,false,null]` never return. Each open pins a pool thread that keeps spinning
   after the buffer closes. The same off-by-one makes every JSON parse wrong.
7. **The repository watcher loses edits and misses linked worktrees (GDV B4 and B5, Core B7 and B8, Blocking).** A
   save made while a reload runs is dropped, and a linked worktree's refs are never watched, so the left side stays
   stale after a commit there. The user works in linked worktrees: the three `Atelier-comments-*` checkouts are
   worktrees of this repository (audit, PROC-01). GIT-01.
8. **File names can write escape sequences to the terminal (Sec H2, High, confirmed for file names).** A tab title
   carrying `ESC ] 52` writes the clipboard in kitty, whose default allows it without a prompt; with
   `allow_remote_control` on, a DCS command can launch programs. QUAL-07.
9. **Quitting GitDiffViewer freezes its main thread (Aemi #5, Blocking).** `applicationShouldTerminate` waits for
   every running and queued pool job. Diagnostics time out at 60 s or 300 s, and git runs have no timeout except
   fetch (120 s). PERF-01.
10. **Three of the five analyzers deliver nothing usable (A-1, D-2, W-3 with Core S23, Blocking).** The corpus filter
    drops every dolly and deadwood finding, and arcleak findings never attach to a row. Passing `--relative-to <root>`
    fixed all three in the verifier's experiment. DIAG-01.

### What is done well

Taken from the reviews' own assessments; where a verifier contradicted one, this list says so.
- **GitDiffViewer.** Every async publish is generation-guarded. `RenderPipeline` reuses diffs keyed on blob IDs and
  never reuses an unhashed file. One hover resolves at a time, and card edges are unobserved, so scrolling does not
  re-render cards. `Mutex` and `Atomic` guard what TextKit draws from; heavy builders are `@concurrent` with off-main
  asserts; the app target has no `DispatchQueue` or `DispatchSemaphore`; quitting uses `.terminateLater`. The review
  also found sound: the notification token's removal in `deinit`, pin-state writes only on a flip, the guarded hover
  scroll-follow, the 180 s idle shutdown of LSP sessions, the absence of a fetch → refs → reload cycle, and a doc
  index that keeps entries, not file content.
- **AtelierCore.** `Mutex` throughout, with no `NSLock`, `os_unfair_lock` or semaphore. Careful git hardening:
  `checked()`, `--end-of-options`, pinned `-c` keys and `GIT_OPTIONAL_LOCKS=0`. Iterative, bounded Myers and
  histogram solvers, a depth limit in `QueryParser`, grammar compile limits and an LSP payload cap. Every
  `group.addTask` is structured. The review also listed `SyntaxTree.deinit` as iterative; verify-ateliercore shows the
  tree is still destroyed recursively (section 5).
- **KittyCode.** Decoders with per-sequence caps and overflow-checked digit parsing. A renderer with synchronized
  output, a CTZ-scanned dirty bitset, a reused output buffer, a DECSTBM scroll fast path and signposts. One task
  provider, clock and pool injected at the composition root; git with `GIT_OPTIONAL_LOCKS=0` and a timeout. No
  feedback loop between saving, git polling, config reloads, resizing and highlighting. `ScreenBuffer.write`
  neutralises control characters, though Sec H2 shows other writers bypass it.
- **aemi and AemiJSON.** The C kernels are bounds-correct, with scalar tails and safe backend fallbacks.
  `BlockingOffloadPool`'s wakeup accounting, worker joins and exactly-once resumption hold. AemiJSON's tape parser is
  iterative and reads under one validated length, rejects lone surrogates in strict mode, seeds its duplicate-key
  hashing, and records correct container spans. On the Atelier side, `SARIFDecoder` walks the lazy tape,
  `RepositoryFreshness` filters its own `.git` and `.build` writes, and `HardenedProcessRunner` avoids pipe deadlocks
  with temporary files.
- **Analyzers and hooks.** project-hooks' process plumbing (temporary-file output, whole-tree kill on timeout,
  NUL-separated git output, no stash) and its changed-file detection are correct. arcleak caps reads, keeps a
  fail-open cache outside the repository, detects cycles iteratively and sorts its output. dolly builds its suffix
  and LCP arrays in linear time with deterministic results. deadwood keeps excluded files in the corpus and never
  saves a partial cache on cancellation.
- **Security.** The security review found no data race, no out-of-bounds access in the C kernels it scanned, and no
  defect in AemiJSON's parser. It did not review AemiJSON's Codable decoder, where Aemi #7 sits.

## 3. Findings by area

In every table, the severity is the one after verification, and "(was …)" marks a re-rating. The Requirements
column names the book's IDs the finding affects, from the audit where it cites the finding.

### 3.1 GitDiffViewer

| ID | Title | Severity (verified) | Verdict | Status | Requirements |
|---|---|---|---|---|---|
| B1 | Settings broadcasts and project switches write project overrides nobody asked for | Blocking | Confirmed | Open | SET-03, SET-05 |
| B2 | A two-sided reload clears the whole comparison when the first side lands | Blocking | Confirmed | Open | GIT-03, GIT-04 |
| B3 | `render` unpublishes the file and cards before their replacement is ready | Blocking | Confirmed | Open | GIT-03 |
| B4 | The watcher is torn down and re-attached on every comparison change, dropping edits made during a reload | Blocking (light end) | Confirmed | Open | GIT-01 |
| B5 | A linked worktree's refs are never watched, and the HEAD and packed-refs watches die after one rename | Blocking | Confirmed | Open | GIT-01 |
| B6 | The hover corpus is re-read and re-parsed on every publish, finish and relayout | Blocking | Confirmed | Open | HOVER-03, PERF-08 |
| B7 | Each gap-drag step re-renders every card on the main actor | Blocking | Confirmed | Open | PERF-02, PERF-08, SET-05, DIFF-02 |
| B8 | Gutter draw cost grows with the square of the row count | Blocking | Confirmed | Fixed `840d4e1` | PERF-05 |
| B9 | The toolbar's Findings button and Diagnostics label never update | Blocking | Confirmed (reason partly wrong) | Open | DIAG-05, DUI-01 |
| S1 | The differential card render reads its options before its await, so a gap drag during the hop is lost | Suggestion | Confirmed | Open | GIT-03 |
| S2 | Writes under ignored paths trigger reloads that re-hash the whole tree | Suggestion | Unverified | Open | PERF-03, PERF-08 |
| S3 | Any refs change reloads both sides while parked on HEAD; an in-app fetch reloads twice | Suggestion | Unverified | Open | PERF-03 |
| S4 | The appearance applier re-parses the theme and reassigns the appearance on every change | Suggestion | Unverified | Open | PERF-08 |
| S5 | Card bodies carry a covered `.regularMaterial` and a subtree shadow that forces an offscreen pass | Suggestion | Unverified | Fixed `840d4e1` | PERF-06 |
| S6 | Each card mount builds a throwaway `CardLayouts` | Suggestion | Unverified | Fixed `840d4e1` | PERF-08 |
| S7 | `StaticTextLayout` lays out the whole document on every `layOut` and `height` call | Suggestion | Unverified | Partial `840d4e1` | PERF-05, PERF-08, CARD-14 |
| S8 | The prepared-diff cache is capped by entries, not bytes, and its flush drops the selection | Suggestion | Unverified | Open | PERF-08 |
| S9 | Every comparison change clears all findings, even for an unchanged changeset | Suggestion | Unverified | Open | PERF-08 |
| S10 | Setting observers fire on equal values and write overrides | Suggestion | Confirmed | Open | SET-03 |
| S11 | Two windows can start two SDK scratch servers, and quitting drains only one | Suggestion | Confirmed | Open | — |
| S12 | The source menu rebuilds every commit item on every snapshot change | Suggestion | Unverified | Open | PERF-08 |
| S13 | Every reload re-lists ignored files, and a failure silently empties the section | Suggestion | Unverified | Open | PERF-08 |
| S14 | Five force unwraps of `textStorage!` in the hover panel | Suggestion | Unverified | Open | QUAL-06 |
| S15 | Every pane coordinator eagerly builds a hover panel with four text views | Suggestion | Unverified | Open | PERF-08 |
| S16 | The core watcher's `DispatchQueue` uses: document the FSEvents exception, drop the per-file source | Suggestion | Unverified (second half refuted as stated) | Partial `8fd26e5` | QUAL-06 |
| S17 | Granularity is not project-scoped, although the settings design lists it | Suggestion | Unverified | Open | SET-03 |
| S18 | A Findings row pins the file but does not jump to the line | Suggestion | Unverified | Open | DUI-01 |
| S19 | `ComparisonWindow` rebuilds settings and the model on every struct init | Suggestion | Unverified | Open | PERF-08 |
| S20 | The app's `TieredHoverProvider` is dead code with a log-free catch | Suggestion | Unverified | Open | MOD-01 |
| N1 | `RenderPipeline.clear` sets `isRendering = false` twice | Nit | Unverified | Open | — |
| N2 | `SplitPaneController.unregister` leaves the view's `appliedSpacing` entry behind | Nit | Unverified | Open | PERF-08 |
| N3 | The `@unchecked Sendable` invariants of `RenderedText` and `DiffPalette` are not written down | Nit | Unverified | Open | QUAL-06 |
| N4 | Every scroll invalidates cursor rects, which adds a second fragment walk | Nit | Unverified | Partial `840d4e1` | PERF-05 |
| N5 | `bundle.sh` mixes build commands and signs the first binary on `PATH`; aemi is pinned to `main` | Nit | Unverified | Open | TOOL-03, PROC-02 |

Notes:
- The review marked its findings in `CombinedDiffView.swift` and `DiffDetailView.swift` provisional, since other
  agents were editing them; the verifier read both at `10ae905`. `840d4e1` has since rewritten `CombinedDiffView.swift`.
- **B4.** The verifier rates it at the light end of blocking: an edit is missed, not corrupted.
- **B5.** Blocking for linked worktrees. Its rename half is latent while B4's re-attach re-arms the per-file watches.
- **B7.** `840d4e1` removed the whole-document layout that each rebuilt card paid in no-wrap mode. Every drag step
  still re-renders every card on the main actor; the text-renderer design lists B7 as open too (`47f2985`, §1.3).
  Verifier: `timer.abandon()` does not invalidate the status bar; the per-step waste is `prefetch()` and
  `updateHoverDocs()`.
- **B8.** Fixed as the verifier required: `840d4e1` caches the font and column width when `rendered` changes,
  including the `rendered == nil` case, and starts every walk at the fragment under the dirty or visible rect
  (`DiffTextKit/DiffGutterView.swift:79-95` and `:231-254` at `5a990db`). `maximumLineNumber` is still an O(rows)
  computed property, now read once per text.
- **B9.** The conclusion holds, but for the label the reason differs: `DiagnosticsLabel` reads the observed
  `runStates`, only inside a branch gated on `summary`, so it never makes the empty-to-non-empty transition. A stored
  summary must also reset in `clear()` and `resetForNewRun()`.
- **S5.** At `5a990db`, no card surface blurs: bodies and pinned headers are opaque, and the card shadow is one
  `CALayer` with an explicit `shadowPath` (`DiffTextKit/StickyCardView.swift:32-59` at `5a990db`). The status bar
  keeps `.ultraThinMaterial` (`GitDiffViewer/Views/StatusBarView.swift:25`), each open tab keeps `.glassEffect`
  (`TabBarView.swift:112` at `5a990db`), and the list keeps the system's soft top edge effect. The brief states that
  no blur surface remains at rest; that holds for the cards, not for the status bar or the tabs.
- **S7.** No-wrap sizes are analytic since `840d4e1`. With wrapping, `layOut` and `height` still lay out the whole
  document on every call (text-renderer design, M0 item 4).
- **S16.** `8fd26e5` documents why the FSEvents stream needs its queue. verify-gitdiffviewer calls the review's
  second half wrong, in its words "S16's 'lines 137-141 go away' is wrong": `watchFile`, `unwatchFile` and
  `suppressNotifications` must stay on `FileWatcher`, because KittyCode calls them. The per-file `DispatchSource`
  behind them goes with Core B8's fix.
- **N4.** `840d4e1` bounds `resetCursorRects` to the visible rect (`DiffGutterView.swift:161-168` at `5a990db`). The
  invalidation on every scroll remains.

### 3.2 AtelierCore

| ID | Title | Severity (verified) | Verdict | Status | Requirements |
|---|---|---|---|---|---|
| B1 | The rope never rebalances, so appends at the end build a deep spine | Blocking | Confirmed (crash part plausible) | Open | — |
| B2 | The GLR parser drops precedence, never merges stacks and stops reducing forked stacks | Blocking | Confirmed (consequences masked, see notes) | Open | PERF-09 |
| B3 | `QueryMatcher.matchInNode` recurses once per tree level | Blocking | Confirmed | Open | — |
| B4 | `HighlightMerger` sorts by width before layer, against its documented precedence | Suggestion (was Blocking) | Confirmed | Open | — |
| B5 | The semantic-token decoder traps on overflowing server input | Suggestion (was Blocking) | Confirmed | Open | — |
| B6 | `deleteBackward` does not clamp the column and traps | Blocking | Confirmed | Open | — |
| B7 | A second `watchDirectory` call is silently ignored | Blocking | Confirmed | Open | GIT-01 |
| B8 | A per-file watch dies after the first atomic save | Blocking | Confirmed | Open | GIT-01 |
| B9 | SDK hover caches timeouts and connection failures as misses | Suggestion (was Blocking) | Confirmed | Open | HOVER-04 |
| B10 | The login-shell `PATH` probe fails under fish | Blocking | Confirmed | Open | TOOL-01 |
| B11 | Regex replace can write the raw template, such as `$1`, into the file | Blocking | Confirmed | Open | — |
| B12 | `PathNode` recurses once per path component taken from a patch | Blocking | Confirmed | Open | — |
| B13 | Myers has no cost limit and no cancellation | Blocking | Confirmed | Open | PERF-09 |
| S1 | Caller-driven shapes for the five unstructured tasks (Codex finding 15) | Suggestion | Unverified | Open | MOD-03 |
| S2 | Process output is unbounded, and a grandchild can hang the timeout | Suggestion | Confirmed (fix flawed) | Open | PERF-01 |
| S3 | Blocking I/O runs on the cooperative pool while hashing and scanning directories | Suggestion | Unverified | Open | PERF-08 |
| S4 | `DocCommentIndex.update` is serial and uncancellable, blocks hovers, and lookups scan every entry | Suggestion | Unverified | Open | HOVER-03, PERF-08 |
| S5 | Every hover re-parses the whole document with swift-syntax | Suggestion | Unverified | Open | PERF-08 |
| S6 | Concurrent first lookups each spawn a login shell | Suggestion | Unverified | Open | TOOL-01 |
| S7 | Diagnostics cache keys are large, and five LRUs are written by hand | Suggestion | Unverified | Open | PERF-08 |
| S8 | The LSP header buffer is unbounded and rescanned on every chunk | Suggestion | Confirmed | Open | — |
| S9 | The LSP registry hard-wires its services and keys them by raw URL | Suggestion | Unverified | Open | — |
| S10 | The GLR lexer allocates and scans keywords linearly per token | Suggestion | Unverified | Open | PERF-09 |
| S11 | `QueryMatcher` tries every pattern at every node | Suggestion | Unverified | Open | PERF-09 |
| S12 | The code scanner hashes a set per character, and its API forces a document copy | Suggestion | Unverified | Open | PERF-09 |
| S13 | Line similarity ignores line length and wastes bigram work | Suggestion | Unverified | Open | PERF-08 |
| S14 | Moved-block detection interns every changed line a second time | Suggestion | Unverified | Open | PERF-08 |
| S15 | `FileWatcher` has no `deinit`, so a dropped watcher leaves FSEvents calling a freed box | Suggestion | Unverified | Fixed `8fd26e5` | GIT-01 |
| S16 | App names leak into the core: `GDV_*` variables, `com.kittycode.fswatcher`, `com.kittytui.search` | Suggestion | Unverified | Partial `8fd26e5` | MOD-02 |
| S17 | `TextDocument` keeps stale caches and splits then rejoins on init | Suggestion | Unverified | Open | — |
| S18 | A paste copies the line cache per line; a load copies every rope level | Suggestion | Unverified | Open | PERF-09 |
| S19 | Search opens each file twice, walks ignored directories and has no size cap | Suggestion | Unverified | Open | PERF-08 |
| S20 | Blob batch output is copied with `subdata` | Suggestion | Unverified | Open | PERF-08 |
| S21 | `PatchCache` is unbounded and parses a patch twice | Suggestion | Unverified | Open | PERF-08 |
| S22 | Every SDK hover scans the whole document twice, even on a cache hit | Suggestion | Unverified | Open | PERF-08 |
| S23 | SARIF and Xcode path relativization match a bare string prefix | Suggestion | Confirmed (symlink case plausible) | Open | DIAG-01, DIAG-06 |
| S24 | Relative `PATH` entries are accepted | Suggestion | Unverified | Open | TOOL-01, QUAL-07 |
| S25 | Core tests sleep, yield and poll, against the AGENTS waiting rules | Suggestion | Unverified | Open | QUAL-06 |
| N1 | A force unwrap in `ProcessSession` | Nit | Unverified | Open | QUAL-06 |
| N2 | An `isOnMainThread` assert that `@concurrent` already guarantees | Nit | Unverified | Open | — |
| N3 | `removeFirst` shifts the stderr tail on every chunk | Nit | Unverified | Open | — |
| N4 | `withUnsafeBytes` plus `bindMemory` where `data.span` exists | Nit | Unverified | Open | QUAL-01 |
| N5 | Dead state in `ParseStack` and `QueryCursor` | Nit | Unverified | Open | — |
| N6 | `GrammarLoader` uses `[String: Any]` | Nit | Unverified | Open | QUAL-06 |
| N7 | `String(data:encoding:) ?? String(decoding:)` makes two passes | Nit | Unverified | Open | — |
| N8 | The private stderr file is closed and reopened by path | Nit | Unverified | Open | — |
| N9 | `DiagnosticsSession.run` could declare typed throws | Nit | Unverified | Open | QUAL-01 |
| N10 | LSP and tiered-hover catch blocks drop errors without a log | Nit | Unverified | Open | QUAL-06 |
| N11 | The GLR root node's `pointRange` ends on row 0 | Nit | Unverified | Open | — |
| N12 | Unneeded `@unchecked Sendable` on rope nodes and `SyntaxTree` | Nit | Unverified | Open | — |

Notes:
- **B1.** The crash half is plausible only: `byteOffset(forLine:)` overflowed a 512 KiB thread at height 4,094, but
  KittyCode edits buffers on the 8 MB main thread. The proposed single rotation handles inserts only; `removing` and
  `mergeOrBranch` join very different heights and need a real recursive join.
- **B2.** The code facts hold, but the consequences do not happen today, because the `popNodes` off-by-one (section 5)
  sends every reduction to the wrong GOTO state, so conflict states are never reached. With that line fixed, the
  review's numbers reproduce: stacks double per operator, reach 256 at 9 operators, and `a + b * c` parses as
  `((a+b)*c)`. "Paid on every keystroke" is refuted: editor sessions use `preferGrammar: false`
  (`KittyEditor/EditorStateCore.swift:658-662`), so the parser runs once per file open, on a pool thread. Only JSON
  reaches the grammar path: go, python, bash and ruby exceed 4,000 states after 18–150 s of compiling; rust, java, c,
  cpp, swift, kotlin, lua and markdown exceed the item limit; javascript and typescript fail to load; css, toml, html
  and yaml need external scanners.
- **B3.** In KittyCode's file-open task (a 524 KiB stack) the matcher crashes at 1,000 nested arrays, so the review's
  5,000 is conservative. The parse alone survives 1,000 levels and crashes at 2,000, in `SyntaxTree.deinit`.
- **B4, B5.** Neither is reached in production: `HighlightMerger.merge` runs only from grammar paths the editor never
  takes, and nothing implements `SemanticTokenProvider`. B4's proposed order is wrong; section 6 gives the corrected
  one.
- **B6.** Reachable: replace-all (`KittyEditor/EditorPrompt.swift:389-394`) swaps the buffer without clamping the
  cursor, and Backspace then traps.
- **B7, B8.** Verified by experiment. FSEvents reports canonical `/private/...` paths and the `a.txt.sb-…` temporary
  file of an atomic save, so routing and suppression need `realpath`'d keys; restart a stream from
  `FSEventStreamGetLatestEventId` so no event is lost.
- **B9.** The cached miss lives until the 256-entry cache evicts it, not for the whole process.
- **B11.** Expand the template against the original line, not the partly rewritten one, or a lookaround that reaches
  a neighbouring replacement is skipped.
- **B12.** About 1 GB at 30,000 components, not 1.8 GB.
- **B13.** perf-core D2 corrects the snippet, and the verifier adds a cancellation rule (section 6).
- **S2.** `.gracefulShutDown` defaults to `toProcessGroup: false`, a daemon that calls `setsid()` escapes the group,
  and collected output still waits for end of file: stop reading once the child exits.
- **S15.** Fixed by `8fd26e5`. `RepositoryFreshness.deinit` still spawns a bare `Task { await watcher.stop() }`
  (`DiffComparison/RepositoryFreshness.swift:96-104` at `5a990db`), which the new `deinit` makes unnecessary.
- **S16.** `8fd26e5` renamed the watcher queue. At `5a990db`, the override variables `GDV_SWIFTLINT` and its siblings
  (`AtelierDiagnostics/DiagnosticTool.swift:40-45`), `GDV_GIT` (`AtelierGit/GitClient.swift:194`), `GDV_TRACE`
  (`AtelierProcess/PhaseTrace.swift:9`) and the `com.kittytui.search` logger (`AtelierSearch/RegexMatcher.swift:6`)
  remain.
- **S23.** `resolvingSymlinksInPath()` yields `/tmp/...` while the tools report `/private/tmp/...`; use `realpath(3)`.
- **S25.** The five core waits remain at `5a990db` with shifted lines.

### 3.3 KittyCode

No commit in `10ae905..5a990db` changed KittyCode code; only the comment sweep touched it.

| ID | Title | Severity (verified) | Verdict | Status | Requirements |
|---|---|---|---|---|---|
| B1 | Private-mode CSI replies become keystrokes, and the terminal-derived theme never applies | High (was Blocking) | Confirmed | Open | — |
| B2 | After a paste or OSC reply passes 1 MiB, the rest is typed as keys | Blocking | Confirmed | Open | — |
| B3 | File watching stops after the first save, so external edits never reload | Blocking | Confirmed | Open | — |
| B4 | Nothing reads `externallyModified`, so saves overwrite external changes | Blocking | Confirmed | Open | — |
| B5 | Inactive autosave clears `isDirty` unconditionally and skips `markSaved` | High (was Blocking) | Confirmed | Open | — |
| B6 | CRLF files keep `\r` in every line, and each save adds another CR | Blocking | Confirmed (worse than stated) | Open | — |
| B7 | An absurd terminal size allocates two cell buffers of about 172 GB each | Hardening (was Blocking) | Confirmed | Open | — |
| B8 | A zero cell height traps, and a huge cell size allocates gigabytes | Hardening (was Blocking) | Confirmed | Open | — |
| B9 | Duplicate symbol names trap in `EditorState.init` | High (was Blocking) | Confirmed | Open | — |
| B10 | Full-document highlighting runs on the main actor | High (was Blocking) | Confirmed (second trigger overstated) | Open | PERF-02, PERF-09 |
| B11 | A zero, negative or huge refresh interval spins or traps | Blocking | Confirmed | Open | — |
| S1 | Git status is polled every 10 s | Suggestion | Unverified | Open | MOD-02 |
| S2 | Every FSEvents path triggers a full tree rescan, the app's own saves included | Suggestion | Confirmed | Open | PERF-03 |
| S3 | Git status lookups resolve symlinks for every visible row | Suggestion | Unverified | Open | — |
| S4 | A git status failure wipes the decorations, and stale refreshes can win | Suggestion | Confirmed | Open | — |
| S5 | `GitStatusProvider` and the line decorations are core logic kept in the app | Suggestion | Unverified | Open | MOD-01, MOD-02 |
| S6 | The grammar corpus, registry and caches live in the app | Suggestion | Unverified | Open | MOD-01 |
| S7 | `front = back` copies the whole grid on every frame | Suggestion | Unverified | Open | — |
| S8 | Each event renders and flushes on its own, and resizes are not coalesced | Suggestion | Unverified | Open | — |
| S9 | The blocking tty read parks a cooperative-pool thread for the whole session | Suggestion | Unverified | Open | — |
| S10 | Signals use `DispatchSource` on the main queue, and SIGHUP is not handled | Suggestion | Unverified | Open | QUAL-06 |
| S11 | A lone ESC waits for the next byte and turns into Alt+key | Suggestion | Unverified | Open | — |
| S12 | UTF-8 continuation bytes are not validated, and one bad byte drops a paste | Suggestion | Unverified | Open | — |
| S13 | The reply to the OSC 52 paste request is dropped | Suggestion | Confirmed | Open | — |
| S14 | Command feedback does not expire without new input | Suggestion | Unverified | Open | — |
| S15 | Search materializes every line and builds unbounded matches on the main actor | Suggestion | Unverified | Open | PERF-02 |
| S16 | Two highlighters disagree, and highlighted lines copy the whole document | Suggestion | Unverified | Open | PERF-09 |
| S17 | Dead or unwired code: dirty regions, merged highlighting, the marquee mode | Suggestion | Unverified | Open | — |
| S18 | Unstructured tasks, and tasks started from `init` | Suggestion | Unverified | Open | — |
| N1 | A 65,536-entry cursor-digit table stays resident | Nit | Unverified | Open | — |
| N2 | Decoders free their buffers per sequence, and `appendDigit` is copied three times | Nit | Unverified | Open | — |
| N3 | An unneeded `@unchecked Sendable`, and a mock connection shipped in production | Nit | Unverified | Open | — |
| N4 | Render globals duplicate `EditorState` state | Nit | Unverified | Open | — |
| N5 | `ClockInstant` boxes on every `erasedNow()` | Nit | Unverified | Open | — |
| N6 | Pixel chrome builds an array literal per pixel | Nit | Unverified | Open | — |

Notes:
- **B1.** `themeFromTerminal` is off by default (`KittyEditor/Config.swift:275`); for users who turn it on, the reply's
  tail arrives as keystrokes at startup, which the verifier rates High.
- **B2.** The fix is right but still loses the paste; delivering it in chunks would keep it. The OSC half matters once
  S13 lands: a clipboard of about 768 KiB overflows.
- **B3.** Reproduced with the real `AtelierFileWatcher.swift`. App-side routing does not help the config watcher,
  which watches only the file, so the core fix (Core B8) is required. FSEvents reports `/private/tmp/...` where the
  per-file source used `/tmp/...`. The inactive autosave sets its date only after a main-actor hop, so its own write
  can read as external.
- **B4.** Three gaps in the proposed fix: `:w!` does not exist (`KittyEditor/VimCommandLine.swift:44-73`) and non-vim
  keymaps cannot force a save; the autosave filter needs the disk-mtime check, since B3 stops the flag from being
  set; and a Save As over another existing file must not be refused.
- **B5.** The race the review described is narrow, but the missing `markSaved` gives a deterministic loss (Top 10,
  item 4). It must land with B6's fix, or `serializedText()` spreads `\r\r\n` to this path. No pool is injected into
  `AutoSaveManager`.
- **B6.** Reproduced: the saved bytes read `61 0d 0d 0a` after one save and `61 0d 0d 0d 0a` after two. The CR shows
  as a trailing blank, not U+FFFD. `KittyGit/GitStatusProvider.swift:186-188` has the same `Character` split, so a
  CRLF file's base from HEAD is one line.
- **B7, B8.** Both need a deliberately absurd window size. The 2.8 GB example in B8 may not lay out an editor at all;
  the zero-height crash is certain.
- **B9.** It needs a hand-edited file; a truncated one fails to decode instead.
- **B10.** The second trigger fires once per open or reload, not on every keystroke. This review checked the code:
  the first keystroke's fallback refills `highlightedLines`, after which `isMutationApplicable` passes
  (`KittyEditor/EditorStateCore.swift:726-731`) and the post-load result is dropped by its version check
  (`KittyEditor/EditorStateFileSystem.swift:494`). perf-tui R9 says every keystroke falls back until the grammar
  parse ends; the code sides with the verifier. Undo and redo also re-highlight the whole file on the main thread
  (`EditorStateCore.swift:1484`, `:1504`).
- **B11.** `Duration.seconds(1e300)` traps ("Double value cannot be converted to _Int128"), and git refresh is on by
  default, so such a value crashes the app on the first loop. Zero or negative values run `git status` back to back.

### 3.4 aemi and AemiJSON

| ID | Title | Severity (verified) | Verdict | Status | Requirements |
|---|---|---|---|---|---|
| #1 | The NEON Hamming reduction truncates its 16-bit sum | Blocking (aemi only) | Confirmed | Open | — |
| #2 | `DependantTask` reads an `unowned` reference after the object is freed | Blocking (aemi only) | Confirmed | Open | — |
| #3 | Workspace search maps files that another process can truncate, raising SIGBUS | Medium (was Blocking) | Confirmed (race) | Open | — |
| #4 | A second `watchDirectory` call is ignored, so linked-worktree refs go unwatched | Blocking | Confirmed (same as Core B7) | Open | GIT-01 |
| #5 | `BlockingOffloadPool.shutdown()` blocks the main thread on quit and starts queued jobs | Blocking | Confirmed | Open | PERF-01 |
| #6 | The default Codable decode depth overflows 512 KiB stacks on LSP input | Hardening (was Blocking) | Confirmed (worse than stated) | Open | — |
| #7 | `FastDecodeCursor.memberValueIndex` reads past the tape on a non-object slot | Blocking | Confirmed (wider than stated) | Open | — |
| #8 | `queue.removeFirst()` under the pool lock is O(n) | Suggestion | Unverified | Open | — |
| #9 | A job cancelled just before admission still runs | Suggestion | Confirmed | Open | — |
| #10 | `mapConcurrently` never checks cancellation | Suggestion | Confirmed | Open | — |
| #11 | The two `TaskProvider` and `TestClock` families have drifted apart | Suggestion | Unverified | Open | — |
| #12 | x86 `firstDisallowedText` mishandles `minAllowed` of 0 or above 0x80 | Suggestion | Unverified | Open | — |
| #13 | The kernel facade takes raw pointers only, so callers copy their `Data` | Suggestion | Unverified | Open | — |
| #14 | The malloc-counting test shim is neither reentrant nor atomic | Suggestion | Unverified | Open | — |
| #15 | `ByteSource` validates and parses in two separate borrows | Suggestion | Confirmed (contract-breaking source only) | Open | — |
| #16 | Every LSP response is copied three times and parsed twice | Suggestion | Unverified | Open | JSON-02 |
| #17 | Container spans live in a hashed dictionary | Suggestion | Unverified | Open | — |
| #18 | No UTF-8 byte-order-mark skip; raw entry points ignore `assumesTopLevelDictionary` | Suggestion | Confirmed | Open | — |
| #19 | A key strategy converts every key on every lookup | Suggestion | Unverified | Open | — |
| #20 | Concurrent decode runs unstructured tasks without cancellation | Suggestion | Unverified | Open | — |
| #21 | The macro fast path accepts non-objects and may keep backticks in keys | Suggestion | Unverified | Open | — |
| #22 | Every escaped string allocates a scratch buffer and copies it again | Suggestion | Unverified | Open | — |
| #23 | A `Decoder` that escapes its scope can read through a dangling pointer | Suggestion | Unverified | Open | — |
| #24 | aemi is pinned to `branch: "main"` in AemiJSON and Atelier | Suggestion | Unverified | Open | — |
| #25 | Hashing blocks cooperative-pool threads, so its concurrency limit cannot scale | Suggestion | Unverified | Open | PERF-08 |
| #26 | FSEvents events bypass the suppression window | Suggestion | Confirmed | Open | PERF-03 |
| #27 | The watcher's stream buffers without limit and excludes nothing; its box lifetime was unproven | Suggestion | Unverified | Partial `8fd26e5` | GIT-01, PERF-08 |
| #28 | The `initialize` reply is decoded through Atelier's own `JSONValue` and thrown away | Suggestion | Unverified | Open | JSON-02 |
| #29 | `LSPConnection` spawns three unstructured tasks, and sends can reorder | Suggestion | Confirmed (ordering plausible) | Open | MOD-03 |
| #30 | A frame that fails to decode is dropped without a log and reported as a timeout | Suggestion | Confirmed | Open | QUAL-06 |
| #31 | Line interning hashes untrusted content with XXH64 and a fixed seed | Suggestion | Unverified | Open | — |
| #32 | The SWAR doc promises exact lanes, but borrows flag lanes above a match | Nit | Unverified | Open | — |
| #33 | aemi batch: types and memory orderings to tighten | Nit | Unverified | Open | — |
| #34 | Every parse bumps shared global counters | Nit | Unverified | Open | — |
| #35 | AemiJSON batch: a misplaced doc, a PROTOTYPE label, a digit budget, a duplicate helper | Nit | Unverified | Open | — |
| #36 | Atelier batch: a benchmark imports both families; `GitClient` imports an unused function | Nit | Unverified | Open | — |

Notes:
- **#1, #2.** Nothing in Atelier or AemiJSON calls these; they matter to aemi alone.
- **#3.** A race: SIGBUS reproduces with `RawFileMap`'s mapping flags and a truncation. Add a size cap, and make the
  same change in `SourceLoader.blobID`.
- **#5.** aemi's proposed async `shutdown()` is correct but breaks synchronous callers such as KittyCode's `defer`
  (`KittyCode/AppMain.swift:86-87`). The freeze is fixed on Atelier's side: cancel diagnostics first, then shut the
  pools down off the main thread with a time limit.
- **#6.** Pool and actor threads have 524 KiB stacks. Decoding Atelier's `JSONValue` in an actor crashes in release
  between 225 and 250 nested objects and between 300 and 400 nested arrays, and in debug between 110 and 120 objects,
  all below the parser's 512 limit. A cap of 128 or 64 makes a 300-deep reply throw instead. The input is
  sourcekit-lsp's own `initialize` reply, hence Hardening.
- **#7.** AddressSanitizer reports a heap overflow, and a 3-character string is enough. It also reaches arcleak and
  deadwood, which check their cache version only after decoding: the released arcleak build crashes (SIGBUS) on a
  malformed facts cache. Prefer throwing `typeMismatch` to returning nil.
- **#9, #10.** 152 of 100,000 jobs ran after `cancel()` returned; none with the check under the lock. A
  `mapConcurrently` cancelled at 171 of 500 items ran all 500; add a final `checkCancellation()` too.
- **#15.** Atelier cannot reach it: `parse(Data)` copies into an array first.
- **#18.** Strip the mark before the `{…}` wrapping as well.
- **#26.** The sweep (`f8a066b`) corrected the doc of `suppressNotifications` to cover `watchFile` events only; the
  behaviour gap remains.
- **#27.** `8fd26e5` settles the lifetime question: FSEvents retains the box, and teardown runs on the callback queue.
  The unbounded `AsyncStream` and the missing exclusion paths remain.
- **#29.** Remove the pre-registered slot when `send` throws.

### 3.5 Analyzers and hooks

All 37 findings live in external repositories. The Atelier-side parts of A-1, D-2, W-3 and A-5 are in the fix plan.

| ID | Title | Severity (verified) | Verdict | Status | Requirements |
|---|---|---|---|---|---|
| PH-1 | Every non-zero SwiftLint exit reads as violations, and excluded files are linted | Blocking | Confirmed (fix corrected) | Open | — |
| PH-2 | Which swift-format runs depends on `PATH` order | Blocking | Confirmed | Open | PROC-02 |
| PH-3 | Linters read the working tree, not the staged blobs | Blocking | Confirmed | Open | — |
| PH-4 | `restage` stages whole files, committing unstaged hunks | Blocking | Confirmed | Open | — |
| PH-5 | Pre-push lints and tests the working tree, not the pushed commit | Blocking | Confirmed | Open | — |
| PH-6 | The hook runs a repository's committed `.build/release/project-hooks` before the installed one | Blocking | Confirmed (reproduced) | Open | — |
| PH-7 | Every push rebuilds from a cold scratch directory, and Ctrl-C leaks it | Suggestion | Unverified | Open | — |
| PH-8 | Nothing remembers a tree that already passed | Suggestion | Unverified | Open | — |
| PH-9 | `waitForProcess` sleeps 0.5 s before its first check | Suggestion | Unverified | Open | — |
| PH-10 | The environment is recomputed, spawning `java_home`, before every command | Suggestion | Unverified | Open | — |
| PH-11 | `linterHasConfig` checks only the repository root | Suggestion | Unverified | Open | — |
| PH-12 | Pre-push re-lints committed files and stops at the first failing group | Suggestion | Unverified | Open | — |
| PH-13 | An empty catch and stale docs | Nit | Unverified | Open | — |
| A-1 | arcleak writes absolute paths into SARIF `uri`, which Atelier keeps absolute | Blocking | Confirmed | Open | DIAG-01 |
| A-2 | The facts cache is invalidated only by a hand-bumped version | Suggestion (was Blocking) | Plausible | Open | — |
| A-3 | Each diff-only run prunes the shared cache to the diff's files | Suggestion | Unverified | Open | DIAG-01 |
| A-4 | The cache is size-capped on load but not on persist | Suggestion | Unverified | Open | — |
| A-5 | A fully degraded run exits 70 before printing any SARIF | Suggestion | Confirmed | Open | DIAG-01 |
| A-6 | The directory walk follows symlinked directories without a cycle guard | Suggestion | Unverified | Open | — |
| A-7 | Branch and revision pins block version-based consumers | Suggestion | Unverified | Open | — |
| A-8 | The README's exit-code tables contradict each other | Nit | Unverified | Open | — |
| A-9 | SARIF columns count UTF-8 bytes, not UTF-16 units | Nit | Unverified | Open | — |
| D-1 | The walk follows symlink loops and `/` without a visited set | Blocking | Confirmed | Open | DIAG-01 |
| D-2 | Absolute SARIF paths make Atelier drop every dolly finding | Blocking | Confirmed | Open | DIAG-01 |
| D-3 | Merging repeat groups is quadratic on clone-heavy corpora | Suggestion | Unverified | Open | — |
| D-4 | Suffix-array structures use 8 bytes per entry | Suggestion | Unverified | Open | — |
| D-5 | The README claims one shared suffix-array pass | Nit | Unverified | Open | — |
| D-6 | Unwired repeat-finding APIs and a field nothing reads | Suggestion | Unverified | Open | — |
| D-7 | `throw error as! Failure` | Nit | Unverified | Open | — |
| D-8 | Invalid UTF-8 is replaced instead of marking the file degraded | Nit | Unverified | Open | — |
| D-9 | The README suggests an in-repository cache path, and a comment contradicts the code | Nit | Unverified | Open | — |
| W-1 | Oversized functions count as skipped files, so deadwood exits 70 | Suggestion (was Blocking) | Confirmed | Open | — |
| W-2 | The walk follows symlink loops, and an out-of-repository link breaks baselines | Blocking | Confirmed | Open | DIAG-01 |
| W-3 | Absolute SARIF paths make Atelier drop every deadwood finding | Blocking | Confirmed | Open | DIAG-01 |
| W-4 | Every reference gets an edge to every same-named declaration before deduplication | Suggestion | Unverified | Open | — |
| W-5 | The corpus is read serially and decoded even on cache hits | Suggestion | Unverified | Open | — |
| W-6 | `--cache` is a documented no-op | Suggestion | Unverified | Open | — |

Notes:
- **PH-1.** The proposed flag does not exist in the installed SwiftLint (section 6).
- **PH-2.** In this shell `~/.swiftly/bin` comes after `/usr/bin`; it wins only because nothing else provides
  swift-format. A GUI-launched git falls back to Xcode's swift-format 6.3.0. The proposed `which("swiftly")` still
  depends on `PATH`, and fails when `.swift-version` names a toolchain that is not installed.
- **PH-3.** Also copy `.swiftlint.yaml` and parent configurations into the snapshot, and read `.swift-version` from
  the real repository root.
- **PH-4.** The unstaged-changes check must run before the task, or it fires after every formatter run.
- **PH-5.** Clear the hook's `GIT_*` variables for the worktree, use one worktree per distinct commit, and clean up.
- **PH-6.** Reproduced on this machine: a clone in `/tmp` ran its own committed `.build/release/project-hooks` on its
  first `git commit`, through the hooks installed in `~/.git-templates/hooks/{pre-commit,pre-push}` (line 9). The fix
  is necessary but not enough: existing hooks must be regenerated, and under a global install a repository's
  `.project-hooks.yml` tasks and pre-push build and test still run its code, so it needs a per-repository trust
  opt-in.
- **A-1.** The fix point that matters to Atelier is Atelier's own (`AtelierDiagnostics/ToolCommand.swift`,
  `SARIFDecoder.swift:80-93`). `--relative-to <root>` works, including through a symlinked root. Switching the tools
  to `file://` alone is not enough, because of Core S23.
- **A-2.** Plausible: the README promises no staleness only relative to rules and configuration. Keying the cache on
  the build's identity is more robust than a fixture digest.
- **A-5.** Atelier shows the stderr sentence, so "bare failure" is overstated. Accept exit 70 only when stdout
  parses: 70 also means cancelled, with empty output.
- **D-1.** With two `..` symlink loops the walk never finished (killed at 25 s).
- **W-1.** It needs at least as many oversized functions as files.
- **W-2.** The containment check deliberately stops following out-of-repository links; decide whether that is
  intended.

### 3.6 Security

| ID | Title | Severity (verified) | Verdict | Status | Requirements |
|---|---|---|---|---|---|
| C1 | Hovering starts sourcekit-lsp with the repository as workspace and working directory | Critical | Unverified (Atelier-side path confirmed by the audit) | Open | QUAL-07, HOVER-01 |
| C2 | "Strict" git isolation still runs commands from `.git/config` during status, diff and log | Critical | Confirmed | Open | QUAL-07 |
| H1 | One click on Fetch runs a command the repository chose | High | Confirmed (proposed pins incomplete) | Open | QUAL-07, GIT-02 |
| H2 | KittyCode writes escape sequences from file names and contents to the terminal | High | Confirmed for file names; file contents plausible | Open | QUAL-07 |
| M1 | A hover-panel link can open any URL scheme | Medium | Confirmed | Open | QUAL-07 |
| M2 | Attacker input drives unbounded resource use | Medium | Unverified | Open | PERF-08 |
| M3 | A mapped file that shrinks crashes the app with SIGBUS | Medium | Unverified (overlaps Aemi #3, confirmed) | Open | — |
| M4 | SDK probe documents use URIs in world-writable `/tmp` | Low (was Medium) | Refuted as stated | Open | QUAL-06 |
| M5 | `bundle.sh` signs whatever binaries it finds | Medium | Unverified | Open | TOOL-03 |
| L1 | Relative `PATH` entries are searched | Low | Unverified | Open | TOOL-01 |
| L2 | A per-project sourcekit-lsp disable is ignored | Low | Confirmed | Open | TOOL-02, QUAL-07 |
| L3 | Diagnostic tools read configuration from the repository, including remote SwiftLint configs | Low | Unverified | Open | QUAL-07 |

Notes:
- **C1.** No verifier executed it. The audit confirmed the Atelier-side path. verify-gitdiffviewer's M4 experiment,
  with the shipped sourcekit-lsp, saw one workspace created at `rootUri` and none at a document's directory; that
  refutes M4's vector, not C1's.
- **C2.** Reproduced with the exact argv and environment of `GitIsolation` and `GitClient` on Homebrew git 2.55.0,
  Xcode's Apple Git-155 (2.50.1) and the Command Line Tools' Apple Git-157 (2.54.0). `.git/info/attributes` alone is
  enough; no committed `.gitattributes` is needed. Because `GIT_OPTIONAL_LOCKS=0` stops git from refreshing the index,
  the filter runs again on every status call. `git config --list -z --includes` executed nothing, even with
  `core.fsmonitor` set. Blanking the filter's `clean`, `smudge` and `process` keys with `required=false` stopped the
  filter vector; `--no-show-signature` or `-c gpg.program=false` stopped the gpg one.
- **H1.** All four vectors ran, `credential.helper` included despite `GIT_TERMINAL_PROMPT=0`. Section 6 gives the
  corrected pins.
- **H2.** The app side is shown end to end: a name with ESC reaches the terminal as raw bytes, through the tab label
  (`KittyEditor/EditorStateCore.swift:1107-1108`, `KittyWidgets/TabRibbon.swift:241-265`). The file-contents path
  depends on kitty treating U+009D and U+009C as OSC and ST; `printf '\xc2\x9d52;c;aGk=\xc2\x9c'` followed by
  `pbpaste` settles it. `renderStyledText` (`KittyWidgets/ViewRenderer.swift:84-90`) also writes unchecked, though no
  untrusted text reaches it today.
- **M1.** Verified by execution. The fix must cover every prose view the panel builds, and the delegate must return
  `true` from `textView(_:clickedOnLink:at:)` to suppress the default open.
- **M4.** Refuted as stated: sourcekit-lsp created no workspace at the document's directory and never read the
  `/tmp` probe directory, since the probe content arrives inline through `didOpen`. The literal
  `file:///tmp/atelier-sdk-probe/…` URI (`AtelierLSP/SDKDocumentationProvider.swift:112`) still contradicts the
  `$TMPDIR` workspace root (`:259-272`) and its own doc comment, and `try?` swallows a failed directory creation.
- **L2.** Reachable today only through GDV B1: a broadcast copies the base value into
  `project.<P>.lspServerLocations`, after which a base-key re-enable is ignored by the window but honoured by
  `AppServices`. The SDK scratch tier has no root and can only honour the base key; that asymmetry needs a decision.
- **Hardening notes** (no exploitation path; not counted): the LSP header buffer (Core S8); `ProcessSession.output`
  buffers without limit; the decode depth on small stacks (Aemi #6); `GitParsers.batch` does not check
  `cursor + size`; `blobs()` does not check that ids are hex; the root from `rev-parse --show-toplevel` is not checked
  to contain the opened directory; `GitMetadataLocation` reads on the main actor without a size limit;
  `KittySequences.notify` embeds an unescaped title (no caller yet); `TextSanitizer` misses C1 controls; the SARIF
  prefix bug (Core S23); the orphaned SDK server (GDV S11); the stderr file reopened by path (Core N8); no
  `-fbounds-safety` in the C kernels and debug-only bounds in `RawFileMap`; force unwraps (GDV S14, Core N1);
  swallowed errors (Core N10, `AtelierDiagnostics/ToolDiscovery.swift:143-145`,
  `DiffComparison/HoverDocumentation.swift:23-25`); `HoverMarkdownRenderer.swift` called only from tests; and the
  watcher's `DispatchQueue`, which `8fd26e5` now documents. The rest are open.

## 4. Cross-cutting themes

### 4.1 Untrusted-repository execution

Opening, hovering or fetching in a repository can run code the repository chose. The git hardening pins some keys
but not the ones that run filters, signature programs, transports or credential helpers, and nothing asks whether a
repository is trusted before sourcekit-lsp starts in it. The same boundary exists outside the app: project-hooks runs
a repository's own binary under a global install. `2d6d788` added a `git status` call on every load and index change
in GitDiffViewer, which gives C2's filter vector another trigger.
- Findings: Sec C1, C2, H1, PH-6.
- Related: Sec M1 (link schemes), L2 (per-project disable ignored), L3 (remote SwiftLint configurations), M4 (probe
  directory), M5 and Aemi #24 (build and dependency supply chain), Core S24 and Sec L1 (relative `PATH`), Sec H2
  (terminal escapes from repository file names), Kitty S13 (clipboard reads).

### 4.2 Watchers and reload continuity

Both apps share `AtelierFileWatcher`, and two of its defects surface in both: a second watched directory is ignored,
and a file watch dies on the first rename. GitDiffViewer misses linked-worktree refs; KittyCode stops seeing external
edits and then overwrites them. GitDiffViewer hides the rename defect by tearing the watcher down on every reload,
which itself drops pending debounces. The reload path then clears or unpublishes what is on screen before the
replacement is ready.
- Findings: GDV B2, B3, B4, B5, S1, S2, S3, S9, S13; Core B7, B8, S15 (fixed); Aemi #4, #26, #27 (partial); Kitty B3,
  B4, B5, S1, S2; the HEAD-watch defect in section 5.
- Requirements: GIT-01, GIT-03, GIT-04, PERF-03.

### 4.3 Main-thread and whole-document work

Both apps do work proportional to the document or the repository on the main actor, often only to show what is
visible. `840d4e1` removed the GUI's no-wrap whole-document layouts and its quadratic gutter; the rest remains.
- Findings: GDV B7, S7 (partial), S19; perf-gui fixes 3 and 7; Kitty B10, S15, S16; perf-tui R1 to R6, R10, R11;
  Core S3 and Aemi #25 (blocking I/O on the cooperative pool); Aemi #5 (a blocking shutdown on the main thread); the
  quadratic storage replace found after `5a990db` (section 5).
- Requirements: PERF-02, PERF-05, PERF-08, PERF-09.

### 4.4 SARIF path handling

arcleak, dolly and deadwood write plain absolute paths into SARIF `uri`, and Atelier strips a root only from a
`file://` URI, by bare string prefix. The tools also spell one root in different ways. Tools that report `getcwd`'s
physical path give `/private/tmp/...` (Core S23, tested by verify-ateliercore), while the three Swift analyzers report
paths resolved through Foundation, which strips `/private` (`/var/folders/...`, verify-deps). As a result, dolly and
deadwood findings are dropped and arcleak findings float free of their rows.
- Findings: A-1, D-2, W-3, Core S23, A-5 (exit 70), A-9 (column units), Aemi #18 (byte-order mark).
- Requirements: DIAG-01, DIAG-06.

### 4.5 Robustness against unbounded input

Recursion, unchecked arithmetic and unbounded buffers turn large or hostile input into crashes, hangs or allocations
of gigabytes.
- Findings: Core B1, B3, B5, B6, B12, B13, S2, S8, S13, S19, S21; Aemi #3, #6, #7, #15, #23, #31; Sec M2, M3; Kitty
  B2, B7, B8, B9, B11; D-1, W-2; the GLR loop, CSS trap and `SyntaxTree.deinit` recursion in section 5.

### 4.6 Duplicated TaskProvider and TestClock families

aemi defines `TaskProvider`, `TaskRole`, `TestClock`, `TaskProviderSpy` and `AsyncProbe` twice, in AemiCore with
AemiTesting and in AemiRuntime with AemiTestKit. The copies have drifted: different protocol members, `Hashable` on
only one `TaskRole`, and two `TestClock`s that wake sleepers in different orders, so a test can pass on one clock and
fail on the other. Atelier's `AGENTS.md` carries an import rule to keep the families apart, and one benchmark breaks
it.
- Findings: Aemi #11, #36.

### 4.7 App names leaking into the core

Core modules carry one app's names, so the other app inherits foreign conventions: KittyCode users would set `GDV_*`
variables.
- Findings: Core S16 (partial since `8fd26e5`); related modularisation gaps in Kitty S5 and S6 (core logic kept in
  KittyCode) and GDV S20 (a dead app copy of a core type).
- Requirements: MOD-01, MOD-02.

## 5. New defects from verification and the sweeps

Eight defects that no review reported: five from verify-ateliercore and three from the sweeps. The verifiers also
extended existing findings, and the performance reviews and the text-renderer design found more; both are listed
after.

### 5.1 Found by verify-ateliercore

Each was reproduced with the untouched parser source, except the fifth.
1. **`ParseStack.popNodes` off-by-one** (`AtelierParser/ParseStack.swift:45-54`). `pushNode` records the state before
   each node; `popNodes` removes those entries and then takes `stateStack.last`, one entry below the state before
   the first popped node. Every reduction above the stack bottom then looks up GOTO from the wrong state. `{"a": 1}`
   comes out mostly as ERROR nodes. This is Core B2's real cause.
2. **Infinite reduce loop** (`AtelierParser/GLRParser.swift:177-184` with `:245-249`). A missing GOTO leaves `state`
   unchanged, so the same reduction repeats forever. `[[]]`, `[{},{}]` and `[true,false,null]` never return. In
   KittyCode each such open pins a pool thread, and the loop never checks cancellation.
3. **CSS trap** (`AtelierParser/GLRParser.swift:236`). `a /* x */ {` traps with "Range requires lowerBound <=
   upperBound"; `/**/ a {` loops forever. CSS is not grammar-backed in the app today.
4. **`SyntaxTree.deinit` is not iterative in effect** (`AtelierParser/SyntaxTree.swift:28-42`). The stored
   `let root` keeps the whole tree alive until the loop ends, and the tree is then destroyed recursively (a
   163,358-frame backtrace).
5. **The HEAD watch dies in linked worktrees**, by mechanism, not run (`DiffComparison/RepositoryFreshness.swift:193-194`).
   git replaces `HEAD` and `packed-refs` by rename, which kills the per-file watches as in Core B8, and in a linked
   worktree they are the only coverage of HEAD. At `5a990db` the re-comparison that a HEAD change triggers
   re-attaches the watcher (`DiffComparison/DiffViewerModel+Freshness.swift:32-35`), which re-arms the watch, so the
   defect shows once GDV B4 stops the re-attach. The git-directory watch that `2d6d788` added classifies a change to
   the directory as an index change (`RepositoryFreshness.swift:241` at `5a990db`), which refreshes badges and does not
   re-compare.

### 5.2 Possible bugs the sweeps left in the code

1. **The hover chip loses its background on rows with findings** (`GitDiffViewer/Views/DiagnosticDiffTextView.swift:101-104`,
   sweep-gdv). The resolver rebuilds the hover document without `chipBackground`. The audit confirms it (HOVER-06).
2. **An extension registered without its dot is never found** (`KittySyntax/GrammarRegistry.swift:58-61` against
   `:118-119`, sweep-kitty). `register(_:)` stores extensions verbatim; `entry(forExtension:)` adds a leading dot.
3. **`ConfigError` is dead code** (`KittyEditor/Config.swift:12`, sweep-kitty): nothing throws or catches it.

### 5.3 Extensions of existing findings, from the verifiers

- Kitty B5: after an inactive autosave, undoing back to the original text sets `isDirty` to false
  (`KittyEditor/EditorStateCore.swift:1501`); the tab then closes without a prompt while the disk keeps the undone
  edits.
- Kitty B6: `KittyGit/GitStatusProvider.swift:186-188` splits on the `Character` `"\n"`, so a CRLF file's base is one
  line and its gutter markers are wrong; the inactive autosave turns CRLF into LF.
- Kitty B8: after a resize to a size with no valid cell size, `KittyApp/ApplicationRuntime.swift:50` keeps the old
  pixel chrome.
- Kitty B9: symbol discovery joins public and private names without removing duplicates
  (`KittySymbols/SymbolDiscovery.swift:42`); latent, since this machine's 9,868 names are unique.
- Kitty B10: every undo and redo re-highlights the whole file on the main thread.
- Sec H2: `renderStyledText` writes unchecked (section 3.6).
- Aemi #7: the released arcleak crashes on a malformed facts cache.
- GDV B3: `renderFresh` uses `prepared.isEmpty` (`DiffComparison/RenderPipeline.swift:387`) as its "head already
  prepared" sentinel, which constrains the fix (section 6).
- Sec L2: its reachable path runs through GDV B1 (section 3.6).

### 5.4 Correctness defects found by the performance reviews

- **Raw strings are not lexed** (perf-core L5, `AtelierLexers/Scanners/CodeScanner.swift`). A `#"""…"""#` raw string
  holds an inner `"""` that flips string and code state; in a real 50k-line file one string token ran 926 KB (24,470
  lines), and the whole file produced 372 tokens.
- **Markdown gets no highlighting in either app** (perf-core L6): `md` maps to `.plain`
  (`AtelierSyntaxModel/Language.swift:116`), and GitDiffViewer still copies UTF-16 for it.
- **A failed grammar compile is retried on every use** (perf-core G2, perf-tui R9). The Swift grammar fails after
  43 ms at the 20,000-item limit, and Go spends 15.1 s per attempt. This settles verify-ateliercore's open question:
  failures are not cached.
- **The syntax tier's offset conversion is quadratic in comment length** (perf-core X1,
  `AtelierSwiftSyntax/SwiftSyntaxTokenRanges.swift`).
- **Hover indexing runs while hover documentation is off** (perf-gui fix 4): `updateHoverDocs`
  (`DiffComparison/DiffViewerModel+Diagnostics.swift:51-52`) never reads the setting.
- **Moved-block detection has a quadratic worst case** (perf-core D6), by complexity argument: a 5,000-line run of `}`
  gives about 25 million comparisons.

### 5.5 Found after `5a990db` by the text-renderer design

`docs/design/text-renderer.md` (`47f2985`, §1.3) cites `c375952` for its locations.
- **Replacing a live text storage is quadratic in attribute runs** (`DiffTextKit/DiffTextView.swift:233-235`): 5.8 s
  for a 50,000-line re-render, 11.3 ms when the storage is emptied first. Every single-file re-render takes this path.
- **Bidi override characters reorder code on screen** (the Trojan Source class, CVE-2021-42574). No code handles
  U+202A–U+202E or U+2066–U+2069, so a reviewer can be shown code that differs from what compiles.
- **Split alignment rewrites paragraph styles row by row** (`DiffTextKit/RowSpacing.swift:31-48`): 515 ms at 50,000
  lines.
- **The minimap caches its bars by size only** (`DiffTextKit/MinimapView.swift:40-42`, `:90`), so an appearance or
  backing-scale change keeps old bars.
- Change kinds are colour-only for assistive technology, and find is off (`usesFindBar == false`).

## 6. Interactions that constrain fixes

### 6.1 GDV B4 × B5: the watcher changes as one piece

From verify-gitdiffviewer. Today's teardown-and-reattach on every reload is what re-arms the per-file sources on
`HEAD` and `packed-refs`, which git replaces by lock-and-rename. B4 alone therefore regresses HEAD detection: the first
`git checkout` fires `onHeadChanged`, the second does not. The combined change must:
1. Replace the per-file `watchFile` calls in `RepositoryFreshness.attach` with one multi-root FSEvents stream over
   `{root, gitDir, commonDir}`, which also fixes the ignored second `watchDirectory`. Keep `watchFile`, `unwatchFile`
   and `suppressNotifications` on `FileWatcher`, because KittyCode uses them.
2. Key the "same comparison" guard on the whole `WatchedPaths`, not the root alone, so a changed git metadata location
   still re-attaches.
3. Place that guard before `teardown()`. `teardown()` bumps `generation`, and the surviving consumer loop exits on a
   mismatch, so keeping the stream while bumping the generation silently stops all events.
4. Keep `teardown()` clearing the attachment, so `setEnabled(false)` then `setEnabled(true)` re-attaches.
5. Update the `WatchEventSource` protocol and its test double.

Two facts from after the verification:
- `2d6d788` added a third per-file watch, `watchFile(paths.gitDir)`, for the index
  (`RepositoryFreshness.swift:172` at `5a990db`). The combined change must fold it into the stream as well, and keep
  `classify` mapping `<gitDir>/index` to `.index`.
- The core half (Core B7 and B8) can land first. While GitDiffViewer still re-attaches on every reload, a multi-path
  stream and rename-proof file routing change nothing it relies on. The fix plan uses that order.

### 6.2 GDV B3 × S1: the render hop

From verify-gitdiffviewer. S1's lost gap drag is unreachable today only because B3 unmounts the card list during the
hop; fixing B3 makes it reachable. The model's `relayout` fallback covers settings-driven relayouts, not `adjustGap`,
which calls `pipeline.relayout` directly. The combined change must:
1. keep `file` and `cards` published across the hop (B3);
2. keep gap drags and relayouts working while the replacement prepares: either keep `prepared` and replace the
   `prepared.isEmpty` sentinel (`RenderPipeline.swift:387`) with an explicit "head prepared" flag, or give
   `adjustGap` the same full-`render()` fallback the model's `relayout` has; `reusableGapExpansions` must keep the
   expansions of cards that stay on screen temporarily;
3. read `options` and `renderLayout` after the `prepare` await and the generation check (S1);
4. close the second await, the concurrent render step: either bump the pipeline generation in `relayout` and
   `adjustGap` so the in-flight render is dropped and reissued with current options, or compare at publish the options
   a render used with the current ones and re-render on a mismatch;
5. keep `isRendering` true throughout, so stale content never reads as final.

Moving the full relayout off the main actor (B7's second half) needs its own generation guard: `relayout` is
synchronous today and bumps nothing, so an async version can land over a newer render.

### 6.3 GDV B2: the source-switch rule

From verify-gitdiffviewer. `reloadSources()` sets both `isLoading` flags in one turn, so the first side to land always
sees the other loading. The review's bare `return` restores continuity, but it would keep showing the previous
comparison after a real source switch (Swap sides, a toolbar ref or folder change), because `Comparison` does not keep
its sources (`DiffComparison/Comparison.swift:47-52`). The fix must:
- remember the sources behind what is published, and clear only when they differ;
- keep calling `updateFreshness()` in the early-return path;
- leave the diagnostics and hover clears out, which is also S9's request.

### 6.4 GDV B6: three flaws in the proposed fix

From verify-gitdiffviewer.
- (a) The feed fingerprint must treat a nil blob ID as always different, as `PairIdentity.isReusable` does. A
  working-tree file above `maximumHashedSize` has no blob ID, so its content can change while the feed compares equal.
- (b) `upsert` fixes the eviction but lets the index grow without bound across comparisons, and
  `documentation(forIdentifier:)` scans every entry: lookups slow down and stale-blob URIs keep surfacing. It needs an
  eviction or per-comparison scoping policy; Core S4's by-name index belongs here.
- (c) `indexedBlobIDs` does not exist and cannot be derived from the URIs, since corpus files are indexed under plain
  `file://` URIs. The index needs a new path-to-blob map.

### 6.5 Fixes the verifiers corrected

- **PH-1** (verify-deps). SwiftLint 0.65.1 has no `--allow-zero-lintable-files` flag, so the review's argv would make
  every run exit 64. Measured exit codes: 1 for "No lintable files found", 2 for violations, 64 for usage errors, 134
  for a bad configuration path. Pass `--force-exclude`, and treat exit 1 with "No lintable files found" as a skip. The
  configuration key `allow_zero_lintable_files: true` works too.
- **Core B4, the merge order** (verify-ateliercore). Sort by layer, then width (wider first), then priority, and fix
  the doc comment. The review and perf-core M3 both propose layer, then priority, then width. This review checked the
  verifier's reason in the code: `Highlighter.buildTokens` sets `priority: maxPatternIndex - match.patternIndex`
  (`KittySyntax/Highlighter.swift:199`), and the JSON query lists `(string)` as pattern 1 and `(escape_sequence)` as
  pattern 4 (`KittySyntax/Grammars/json/highlights.scm`), so a priority-before-width sort paints the string over its
  escapes. The review's own case, a narrow lexical token inside a wide semantic one, still resolves correctly because
  layer comes first.
- **Sec H1, `protocol.ext.allow`** (verify-ateliercore). The proposed `-c protocol.allow=never` did not stop an `ext::`
  URL, because the repository's more specific `protocol.ext.allow=always` wins; add `-c protocol.ext.allow=never`. A
  repository `url."ext::…".insteadOf=https://` rewrite bypassed "fetch by explicit https URL"; add `url.*` to C2's
  deny list. The pinned `protocol.file.allow=user` is what lets a local-path `uploadpack` run.
- **Core B13, as corrected by perf-core D2.** B13's snippet reads the diagonals of round `d` before round `d` writes
  them, and can return a degenerate split at (0,0) or (n,m) that recurses forever. perf-core's corrected snippet,
  quoted from `perf-core.md` §D2:

  ```swift
  // LineDiff.swift:354, top of each round
  if d >= costLimit {                                   // costLimit = max(256, 4 * Int(sqrt(Double(n + m))))
      var bestK = 1 - d, bestReach = -1
      for k in stride(from: 1 - d, through: d - 1, by: 2) {         // round d−1 wrote these diagonals
          let x = min(forward[offset + k], n), y = x - k
          if y >= 0, y <= m, x + y > bestReach { bestReach = x + y; bestK = k }
      }
      var x = min(forward[offset + bestK], n), y = max(0, min(m, x - bestK))
      if x + y == 0 || (x == n && y == m) { x = n / 2; y = m / 2 }  // any inner point is a valid split
      return Snake(x: x, y: y, u: x, v: y, edits: 2 * d)
  }
  if d & 63 == 0, Task.isCancelled { … }                // readable from synchronous code running in a task
  ```

  verify-ateliercore adds that the cancellation check must not produce a split: `d & 63 == 0` also fires at `d = 0`,
  where a returned split makes no progress. Cancellation must abort `solve`. The quoted snippet keeps that placeholder
  line, so apply both corrections.

### 6.6 Other constraints the verifiers set

| Finding | Constraint |
|---|---|
| GDV B1 | Pair with S10, or re-selecting an equal value re-creates the override. |
| GDV B8 | Start the enumeration near the dirty rect and initialize the cached width for `rendered == nil`; `840d4e1` does both. |
| GDV B9 | Reset a stored summary in `clear()` and `resetForNewRun()`, which bypass `recomputeFindingsByFile()`. |
| GDV S11 | Store the memoized `Task` before any suspension; its impact is bounded by the 180 s idle shutdown. |
| Sec L2 | `AppServices` has no project context; resolving the project key means building `ProjectIdentity(root:)` in the registry closure and duplicating the key format. |
| Core B1 | Rebalancing needs a recursive join for `removing` and `mergeOrBranch`, not one rotation. |
| Core B2 | Fix `popNodes` first. Reduce from a worklist with a budget and treat a missing GOTO as an error, which also cures the hang. Resolve precedence as tree-sitter does, reducing a production against the shifting items' precedence, not "token precedence". Merge stacks only when there is more than one, since the key costs O(depth) per token. |
| Core B3 | Also make `SyntaxTree.deinit` iterative in effect, and cap the depth. |
| Core B7 | Canonicalize paths, and restart from `FSEventStreamGetLatestEventId`. |
| Core B8 | Use `realpath`'d keys for routing and suppression; the temporary-file echo of an atomic save remains. |
| Core B9 | Pass "unavailable" through from both probes. |
| Core B11 | Expand against the original line. |
| Core S2 | `.gracefulShutDown` does not signal the process group by default, `setsid()` escapes it, and output collection must stop once the child exits. |
| Core S23 | Use `realpath(3)`, not `resolvingSymlinksInPath()`. |
| Aemi #3 | Add a size cap, and change `SourceLoader.blobID` the same way. |
| Aemi #5 | Fix the freeze on Atelier's side; aemi's async version breaks synchronous callers. |
| Aemi #7 | Throw `typeMismatch` rather than return nil. |
| Aemi #10 | Add a final `checkCancellation()` after the last item is queued. |
| Aemi #29 | Remove the pre-registered slot when `send` throws. |
| Kitty B2 | The paste is still lost; chunked delivery would keep it. Handle the OSC half before S13 ships. |
| Kitty B3 | The config watcher needs the core fix; match canonical paths; consult suppression for FSEvents paths. |
| Kitty B4 | Add a force-save and reload flow, check the disk mtime, and never refuse Save As over another path. |
| Kitty B5 | Land with B6; apply B4's guard to this path too. |
| Kitty B6 | Make the core `serializedText` idempotent, fix `GitStatusProvider.splitLines`, and add a disk round-trip test. |
| Kitty B8 | Clear the pixel chrome after a resize to an invalid cell size. |
| Kitty B9 | Apply the fix at both sites. |
| Kitty B10 | Also take undo, redo and `textDidChange(previousSnapshot:)` off the main actor; `searchPool` has width 1 and is shared with search. |
| Kitty S2 | Route open buffers before returning on ignored paths. |
| Kitty S4 | Reset the in-flight base-content map per generation. |
| Kitty S13 | `handlePaste` is private; accept a reply only while a request is pending, handle an empty or denied reply, and respect the 1 MiB OSC cap. |
| Sec H2 | Enforce the check in the cell setter, and keep an ASCII fast path, since the setter is hot. |
| PH-2 | `which("swiftly")` still depends on `PATH`, and fails when `.swift-version` names a missing toolchain. |
| PH-3, PH-4, PH-5, PH-6 | As in the notes of section 3.5. |
| A-5 | Accept exit 70 only when stdout parses. |
| W-2 | Decide whether out-of-repository links should be followed. |

## 7. Rendering performance

### 7.1 How the three reviews measured

- **perf-gui.** Release builds of `10ae905` in `/tmp/gdv-perf` with the user's settings: inline, no wrap, `syntax`
  granularity, MapleMono NF CN 12 pt, minimap on. An instrumented build logged first text pixels; a prototype build
  added the fixes. The machine is an M3 with two other sessions each holding a core, so batches vary: the small
  repository's first text measured 448 ms in one batch and 737 ms in another. Medians of 5; exact allocation counts
  from a malloc interposer.
- **perf-tui.** Release Swift 6.4.0 builds of byte-identical copies in `/tmp/kc-src`, on 10k, 100k and 1M-line inputs
  made from real Swift files, with a malloc interposer and a load average of 15–30. The fixes under test passed 935
  KittyCode and 146 core tests and produced identical frame bytes.
- **perf-core.** A scratch SwiftPM package over AtelierCore with the same pins; thread CPU time as the median and
  interquartile range of at least 10 runs; every prototype checked against the shipped output.

### 7.2 Key numbers

GUI, from perf-gui unless noted:

| Path | Before | After | Fix | At `5a990db` |
|---|---|---|---|---|
| Single-file publish → first text, L (2,374 rows) / XL (9,292 rows) | 616 / 1,253 ms | 78 / 70 ms (prototype) | fix 1, with fix 2's cursor-rect part | Landed, `840d4e1` |
| Expanding a 9,027-row card | 2,346 ms | 40 ms | fix 1 | Landed |
| Card-list mount on the main actor | 118.5 ms | 5.5 ms | fixes 1 and 2 | Landed |
| Gutter, one 900 pt tile, M / L / XL | 27.7 / 292 / 1,243 ms | 1.3–2.0 ms | fix 2 (GDV B8) | Landed |
| Scroll cost per event, median | 8.2–15.5 ms | 5.8–8.5 ms | `840d4e1` | Reported in the brief; not re-measured here, and no report in `/tmp/reviews` carries it |
| First text with `loadSides` off the main actor (medians, interleaved; perf-gui does not name the comparison) | 737 ms | 617 ms | fix 3 | Open |
| Hover corpus indexing while hover is off | about 1 s of pool CPU during load | none | fix 4 | Open |
| Keyword lookups, L | 8.1 ms, 78,572 allocations | 0.13 ms, 0 | fix 6 | Open |
| SwiftSyntax on the first-text path, one side of L | 17–39 ms | 2.7–3.9 ms with the code lexer | fix 7 | Open |
| Colours through storage edits, L / XL | 743 / 1,911 ms of relayout | 34 ms for every token as rendering attributes; 0.84 ms for the first 60 rows | fix 5 | Design constraint |
| Stage 0 text first, end to end, M / L / XL | 72 / 454 / 2,163 ms | 10.9 / 15.1 / 25.6 ms (prototype) | §3 pipeline | Open |
| Gap drag with 64 cards | 58–92 ms per step | one card per step | GDV B7 | Open |

TUI, from perf-tui:

| Path | Before | After | Fix | At `5a990db` |
|---|---|---|---|---|
| Chrome, page or Enter frame | 6.6–12.4 ms, 58.3 MB | 0.39–0.56 ms, 495 KB | R1 | Open |
| Keystroke at 1M lines | 78–105 ms, 32.2 MB | 0.47 ms, 207 KB | R2, R3 | Open |
| Keystroke to bytes written, 10k lines | 0.72–1.66 ms | 0.59–0.64 ms | R1–R4 | Open |
| Opening a 1M-line file, main actor blocked before text | 3–6.5 s | an install plus a 4–5 ms first frame (estimate) | R4 | Open |
| Viewport highlight, 10k / 100k / 1M lines | 7.3 / 62 / 728 ms | 54–102 µs from the rope | R5 | Open |
| `renderFrame`, 200 lines of 20 KB | 156–171 ms | 1.27 ms | R6 | Open |
| Lexer, 1M lines | 475–687 ms | 259–351 ms (1.93×) | R12 | Open |
| JSON grammar parse of 94 KB, then discarded | 85.9 s | skipped or budgeted | R9 | Open |
| Full re-highlight on the main actor, 10k / 100k / 1M | 7.4 / 72 / 807 ms | off the main actor | Kitty B10 | Open |

Core engines, from perf-core:

| Path | Before | After | Fix | At `5a990db` |
|---|---|---|---|---|
| GLR parse, 16 KB of JSON | 722 ms, quadratic | 8.6 ms, linear; identical trees | G1 | Open |
| Myers, 50k lines of real history | 113 ms | 11.2 ms; same D | D1 | Open |
| 50k rewrite / 50k disjoint | 23.0 s / 13.9 s | 314 ms (D +0.9%) / 0.47 ms | D1 + D2 | Open |
| GitDiffViewer lexing per 50k-line pair | 157 ms, 2.16 M allocations | 7.0 ms, 2; identical tokens | L1, L2 | Open |
| GitDiffViewer core work before any text, per file | 188 ms | lines 1.75 ms, edit script 9.6 ms, viewport tokens 3 µs | §7 phased APIs | Open |
| Capture role per capture | 335 ns | 0.8 ns | M2 | Open |
| Rope build, 3.4 MB | 41 ms, 27 of them counting newlines | newline count 1.4 ms | T1 | Open |
| Display width, 100k lines | 116.6 ms | 9.4 ms | T5 | Open |

All other perf-gui items are open except GDV S6, which is fixed; GDV S7 is partial. No perf-tui or perf-core item has
landed.

### 7.3 After `5a990db`: the text-renderer design

`docs/design/text-renderer.md` (`47f2985`) measures TextKit 2 as the app uses it, TextKit 2 used correctly, and a
CoreText prototype. A new 50k-row document takes 7,034 ms, 25.5 ms and 3.8 ms respectively; the quadratic storage
replace (section 5.5) accounts for most of the first figure. The design recommends finishing its M0 list (TextKit used
correctly, plus a backend seam) and then starting a CoreText renderer, M1, time-boxed by exit criteria. Whether to
build the renderer is a user decision (fix plan, section 7).

### 7.4 The text-first pipeline both apps share

The three reviews agree on the shape, and PERF-09 states it as a requirement: text first on the main actor; colour and
emphasis later, off the main actor, visible lines first; every stage cancellable, budgeted and failing safe to plain
text; colour as attribute-only updates that cause no relayout.

**Core APIs** (perf-core §7; caller-driven, with no `Task` or `TaskProvider` in the core):
- A `LineSource` protocol in AtelierText that lends a line as `Span<UInt8>`. The rope conforms for KittyCode, and a
  `TextLines` type (the string plus `[Int32]` line starts built with memchr) serves GitDiffViewer. `DiffSource`
  becomes an alias.
- Resumable lexing: a 32-bit `LexState` (mode, quote, block-comment depth), a `LineLexer` that scans one line from a
  state and returns the next, `LexStates` checkpoints at line starts, and `ProgressiveHighlighting`, which lexes the
  viewport first, then chunks outward, checking cancellation every 256 lines. `lexAll` adds speculative parallel
  chunks with repaired seams, 2.95× on 4 chunks.
- `LineTokens`: one flat per-line token buffer (perf-core M1) replacing GitDiffViewer's `[[HighlightToken]]` and
  KittyCode's `[[StyledSpan]]`.
- A phased diff: `DiffLimits` (cost limit, unmatched-line discard, intraline and pair caps, moved-candidate cap), then
  `DiffStructure` (edits, changes, interned ids, `isMinimal`), then `IntralineEmphasis` for visible changes, then
  `MovedBlocks.detect`.
- Capture roles resolved once per query (perf-core M2), and a grammar capability registry that remembers failures by
  grammar hash, over a budgeted, cancellable GLR parser.

**GUI stages** (perf-gui §3):
- Stage 0, text: off the main actor, decode, split lines, run `LineDiff`, build rows and one plain attributed run; on
  the main actor, set the storage and the analytic frame, lay out the viewport, draw.
- Stage 1, syntax colours for displayed fragments only, through `renderingAttributesValidator`: 0.84 ms per screen,
  no relayout.
- Stage 2, intraline emphasis, moved blocks and the SwiftSyntax tier, into a side table that `DiffLayoutFragment.draw`
  reads by row.
- Stage 3, the diagnostics overlay.
- Type changes: `PreparedDiff` splits into `DiffStructure` and `DiffDecorations`; `RenderedText` keeps only the plain
  layer; a `@MainActor` `DecorationStore` per displayed text holds the layers; `RenderPipeline` emits
  `.decorated(textID, layer)` between `.published` and `.finished`.
- Guards: decoration tasks are children of the render task; every result carries the pipeline generation and the text
  ID; each stage races a deadline against an injected clock; `LineDiff` gets a 200 ms deadline plus the cost limit;
  on a failure the plain text stays. Stage 0 runs at user-initiated QoS, stages 1 and 2 at utility, the hover index
  at background.

**TUI order of work** (perf-tui §3):
1. Text first: apply the edit to the rope in O(log n), bump `documentVersion`, render the dirty rows and flush. The
   text path never calls the highlighter.
2. Lexical colours, viewport first: re-lex the edited line from its stored entry state until a line starts in its old
   state, usually one line at 1–2.5 µs.
3. A background checkpoint pass in 2,000-line chunks: visible rows first, then below, then above.
4. Grammar refinement only for grammar-backed languages within the size cap, with a budget and a per-language breaker
   keyed by grammar hash.
5. The gutter diff off the main actor, from a rope snapshot.

Version gates: each background job carries its start version (G1, producer); the main-actor consumer applies a patch
only for the current `documentVersion` (G2); render clips stale or missing tokens and draws plain text (G3).

**Budgets.**
- GUI: stage 0 at most 16 ms of main-thread work and under 100 ms from the click with a cached diff; visible colours
  one frame later; emphasis within 250 ms for L; no main-thread slice over 16 ms.
- TUI: keystroke to bytes written at most 8 ms at p99 and 1 ms at the median; scroll or chrome change at most 4 ms;
  open to first text at most 50 ms after the read; viewport colours within 16 ms after the text; grammar refinement
  250 ms per pass; gutter within 100 ms after the 150 ms debounce, with at most 0.5 ms on the main actor.

### 7.5 Where the performance reviews disagree

- **Kitty B10's second trigger.** perf-tui R9 says every keystroke falls back to a full pass until the JSON grammar
  parse ends; the code shows one fallback per open (section 3.3, note B10).
- **Core B4's order.** perf-core M3 keeps the review's order; the verifier's order is right (section 6.5).
- **Lexer code units.** perf-tui §4 proposes a lexer generic over UTF-8 and UTF-16 units. perf-core L1 measured the
  GUI on a UTF-8 lexer that converts offsets to UTF-16 only at the `NSAttributedString` boundary, 157 ms down to
  7.0 ms, which removes the need for the UTF-16 path. This document follows perf-core.
- **Token layout.** perf-tui proposes 8 bytes per token (a `UInt32` start, a `UInt16` length, a role byte, a layer
  byte); perf-core M1 proposes 12 bytes (`UInt32` start and length, `UInt16` role and modifiers). The 8-byte form caps
  a token at 65,535 bytes and has no modifiers; the core API step decides.
- **The Myers cost limit.** perf-core D2 corrects Core B13's snippet, and verify-ateliercore corrects its
  cancellation (section 6.5).

## 8. Cross-reference to the requirements audit

Verdicts at `10ae905` come from `docs/requirements/audit.md`.

| Requirement | Verdict at `10ae905` | Findings that explain it | At `5a990db` |
|---|---|---|---|
| GIT-03 | Not met | GDV B2, B3, S1 | Unchanged: all three open |
| GIT-04 | Partially met | GDV B2 | Unchanged |
| GIT-01 | Partially met | GDV B4, B5; Core B7, B8, S15; Aemi #4, #27; the HEAD-watch defect | Still Partially met: Core S15 fixed and #27 partial (`8fd26e5`); an index watch added (`2d6d788`); the rest open |
| QUAL-07 | Not met | Sec C1, C2, H1, M1, L2 | Unchanged; C2 gained a trigger with `2d6d788` |
| DIAG-05, DUI-01 | Not met | GDV B9; S18 for DUI-01's line jump | Unchanged |
| DIAG-01 | Partially met | A-1, D-2, W-3, A-5, D-1, W-2; Core S23 | Unchanged |
| DIAG-06 | Met, with a risk | Core S23 | Risk open |
| HOVER-03 | Needs visual confirmation, with a risk | GDV B6, Core S4 | Risk open |
| HOVER-04 | Partially met | Core B9 | Unchanged |
| HOVER-06 | Partially met | The sweep's hover-chip bug (section 5.2) | Unchanged |
| TOOL-01 | Partially met | Core B10, S6, S24; Sec L1 | Unchanged |
| TOOL-02 | Regressed | Sec L2. The regression itself, a settings gate from `1c5bdec`, is no review finding | Unchanged |
| TOOL-03 | Met, with a risk | Sec M5, GDV N5 | Risk open |
| SET-03 | Partially met | GDV B1, S10, S17 | Unchanged |
| SET-05 | Partially met | GDV B1, B7 | Still Partially met: the badge scheme and theme matching reach open windows (`2d6d788`); spurious overrides and the scroll reset on a theme change remain |
| SET-07 | Partially met | No review finding | Still Partially met: explorer rows, tabs, card headers and open windows follow the scheme (`2d6d788`, `2b3a5c3`, `5a990db`); the single-file status bar badge still draws the classic scheme (`GitDiffViewer/Views/StatusBarView.swift:44` at `5a990db`) |
| CARD-09 | Partially met | No review finding | Still Partially met: states now come from git; the status bar badge keeps the defaults |
| CARD-11 | Not met | No review finding | Partially met: explorer rows, tabs and card headers take git's per-file state (`2cd8a60`, `2d6d788`, `2b3a5c3`); the status bar badge still draws `.staged` |
| CARD-10 | Needs visual confirmation | No review finding | Code for both refinements landed (`b693b70`, `5a990db`), and the brief reports it fixed; this review made no visual check |
| CARD-02 to CARD-06, CARD-12 | CARD-03 and CARD-06 Not met; CARD-04 Partially met; CARD-02 and CARD-05 need visual confirmation; CARD-12 came after the audit | No review finding | Addressed in code by `840d4e1`; each needs visual confirmation |
| PERF-01 | Met, with a risk | Aemi #5 | Risk open |
| PERF-02 | Partially met | GDV B7; Kitty B10, S15; perf-gui fix 3 | Unchanged |
| PERF-03 | Partially met | GDV S2, S3; Kitty S2; Aemi #26 | Unchanged |
| PERF-05 | Needs visual confirmation, with a risk | GDV B8, N4 | B8 fixed (`840d4e1`); the frame-rate measurement in Instruments is still missing |
| PERF-06 | Partially met | GDV S5 | Met: since `840d4e1` no card carries a material, and the live blur surfaces no longer grow with the number of files |
| PERF-07 | Partially met | GDV S5, B8 | Still Partially met: the per-card materials are gone, but no WindowServer measurement follows the fix |
| PERF-08 | Partially met | GDV B6, B7, S2, S6, S9; Core S4, S5 | GDV S6 fixed; the rest open |
| JSON-02 | Partially met | Aemi #16, #28 | Unchanged |
| MOD-01 | Partially met | GDV S20; Kitty S5, S6 | Unchanged |
| MOD-02 | Partially met | Core S16; Kitty S1, S5 | The watcher's queue label is neutral (`8fd26e5`); the rest open |
| MOD-03 | Not met | Core S1; Aemi #29 | Unchanged |
| QUAL-06 | Not met | Core S25, N1, N10; GDV S14; Sec M4 | A build warning removed (`679bf88`); the 14 forbidden waits remain |
| QUAL-03 | Partially met | The sweeps | Still Partially met: the 13 sweep commits are on `main` and change only comments; the four files the sweep excluded (`CombinedDiffView`, `TabBarView`, `ChangeBadge`, `DiffDetailView`) have had no sweep pass |
| PROC-02 | Met, with a note | PH-2 | Unchanged |

**Requirements now Met because of the fixed items.**
- PERF-06, through `840d4e1`.
- CARD-10, as the brief reports; its code landed in `b693b70` and `5a990db`.

CARD-11, SET-05, SET-07 and CARD-09 improved but stay Partially met: the single-file status bar badge
(`StatusBarView.swift:44` at `5a990db`) still ignores the scheme and the git state. CARD-02 to CARD-06 and CARD-12 wait
for a visual check.

**Requirements added after the audit.**
- TAB-08: built in `130fa5c` and `bbe50e7`; visual check pending.
- TAB-09: met for the card list; the single-file panes keep a divider, because SwiftUI hands neither the bar's inset
  nor its edge effect to an `NSScrollView` (comment in `GitDiffViewer/Views/DiffDetailView.swift` at `5a990db`).
- TAB-07: not addressed.
- PERF-09 and QUAL-08: the three performance reports satisfy QUAL-08's report criterion, and this document records
  them in the repository; PERF-09 is Wave 3 of the fix plan.
- CARD-13, CARD-14, CARD-15 and DIFF-01 to DIFF-04 were added by `d662777`. DIFF-02 (gap drags) shares
  `RenderPipeline.adjustGap` with GDV B7 and S1. CARD-14 (split card heights) relates to GDV S7's note that
  `apply(spacing:)` changes heights after layout.
