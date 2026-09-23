# Requirements audit

**Revision 2, written 2026-09-23 14:40 CEST.** Statuses are at `main` `ebafb9f` (14:26), which is pushed:
`origin/main` equals it. Every file:line refers to `ce0880c` (13:37), where six agents verified the code; read one
with `git show ce0880c:<path>`. The 33 commits after `ce0880c` finished Wave 1 and the move to AemiJSON. Where they
change a status or its evidence, the entry says so and cites "at `ebafb9f`". Revision 1 audited `10ae905`; "Was"
gives its verdict.

One status per requirement of `book.md`:
- **Implemented:** every acceptance criterion holds in the code, and a test covers it; for a document or a process,
  the artifact exists.
- **Partially implemented:** some criteria hold. The entry says what is missing and where it is planned.
- **In progress:** the work is on a branch, in a worktree, or uncommitted.
- **Designed:** a design exists, and no code.
- **Planned:** a wave and track of `docs/reviews/2026-09-23-fix-plan.md`, or a section of the roadmap, schedules it.
- **Not started:** in no plan.
- **Superseded.**
- **Needs user decision:** names the open question of `book.md` (OQ1 to OQ12).
- **Needs visual confirmation:** the code for every criterion is on `main`, and at least one criterion can only be
  judged in the running app. The checklist at the end gives the steps.

## Summary

| Area | Implemented | Partially | In progress | Designed | Planned | Not started | Superseded | Decision | Visual | Total |
|---|---|---|---|---|---|---|---|---|---|---|
| PROC | 5 | 7 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 12 |
| DIAG | 2 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 8 |
| TOOL | 1 | 2 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 4 |
| HOVER | 3 | 8 | 0 | 0 | 1 | 0 | 2 | 0 | 4 | 18 |
| DUI | 0 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 4 |
| SET | 1 | 3 | 0 | 0 | 1 | 0 | 0 | 0 | 3 | 8 |
| CARD | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 13 | 16 |
| TAB | 3 | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 3 | 9 |
| GIT | 2 | 2 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 5 |
| WIN | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 3 |
| PERF | 0 | 4 | 0 | 0 | 1 | 0 | 0 | 0 | 4 | 9 |
| JSON | 1 | 2 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 4 |
| MOD | 0 | 2 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 3 |
| QUAL | 4 | 4 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 10 |
| DIFF | 1 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | 0 | 5 |
| REND | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 3 |
| **Total** | **26** | **43** | **1** | **1** | **10** | **1** | **4** | **2** | **33** | **121** |

Revision 1, at `10ae905`, counted 95 requirements: 38 Met, 29 Partially met, 11 Not met, 1 Regressed, 12 needing a
visual check and 4 Superseded. The scales differ: "Met" required no test, and "Implemented" does.

## What changed since the 10ae905 audit

**69 commits,** `10ae905..ebafb9f`:
- **Code, 50 commits.**
  - Cards: the custom sticky container (`840d4e1`), then fold, split heights and the NaN fix (`ce0880c`).
  - Badges from git's per-file state, in the chosen scheme, on every surface: `2cd8a60`, `2d6d788`, `2b3a5c3`,
    `b693b70`, `5a990db`, `510115a`.
  - Tabs as capsules: `130fa5c`, `bbe50e7`.
  - The watcher's use-after-free: `8fd26e5`.
  - Test failure bounds of 15 s: `609d757`, `e56c8b0`. The NSFont warning: `679bf88`.
  - Wave 1, every track but 1K:
    - 1A, the language-server trust gate, registry keys, background indexing off, the SDK probe directory, the
      per-project sourcekit-lsp setting, Fetch off while untrusted, one SDK session, and the quit sequence:
      `3bdb404`, `108ccea`, `3893897`, `1ad6cd4`, `f94d3be`, `2955136`, `9bc07d1`, `9a41cf1`.
    - 1B, the git configuration gate and its hostile-repository tests: `ab38879`, `52f77fc`, `57b9163`, `ebafb9f`.
    - 1C `bbaf80f` (hover links), 1D `704d7b0` (core watcher), 1E `2c44008` and `112a632` (KittyCode data loss), 1F
      `718c75c` (KittyCode traps), 1G `05aaf11` (terminal escapes), 1I `2342755` (SARIF paths), 1J `bfe8d1d` (fish
      `PATH`).
    - 1H, parser termination and depth: 11 commits, `47c628c` to `54e5a73`.
  - JSON on AemiJSON: `f06b291`, `4b84c84`, `475fc93`, `da05476`, `45dce85`.
- **Comments only, 13 commits:** the sweep, `fe98a89` to `195cf93`.
- **Documents, 6 commits:** this book's first revision (`c375952`), the renderer design (`47f2985`), the roadmap's
  refinements (`d662777`), the Xcode reference (`fd55a20`), the rename decision (`5128a14`), and the consolidated
  review and fix plan (`11ddbb6`).

**Status changes that code caused:**
- CARD-03 and CARD-06, Not met → Needs visual confirmation; CARD-04, Partially → Needs visual confirmation
  (`840d4e1`).
- CARD-11, Not met → Partially; SET-07, Partially → Needs visual confirmation (the badge commits).
- QUAL-07, Not met → Needs visual confirmation: Sec M1 (`bbaf80f`), H2 (`05aaf11`), C1 and L2 (track 1A), C2 and H1
  (track 1B) are fixed on `main`.
- QUAL-06, Not met → Partially: force unwraps went from 6 to 1, forbidden test waits from 14 to 9, and every new test
  has a sentence name.
- DIAG-01, TOOL-01 and GIT-01 stay Partially, with their largest gaps closed (`2342755`, `bfe8d1d`, `704d7b0`).
- TOOL-02, Regressed → Partially: nothing changed in the code; revision 2's scale has no "Regressed".

**Status changes from a stricter reading, with no code change:**
- To Partially implemented:
  - SET-01: the toolbar's short labels.
  - PROC-02: plain `swift` in the repository is Xcode's 6.3.3.
  - PROC-05, PROC-08.
  - HOVER-09: the card list's panel ignores list scrolling.
  - HOVER-11: two blobs of one path both show.
  - DUI-02: no test.
  - HOVER-03: GDV B6, and two criteria untested.
  - HOVER-08: Q3's answer asks for Liquid Glass.
- To Needs visual confirmation, because the code was rebuilt or has no test: DIAG-04, DIAG-06, SET-04, SET-06,
  TAB-01, HOVER-02, PERF-04, CARD-07, CARD-08; and PERF-01, whose quit freeze track 1A fixed, and whose third
  criterion was never measured.
- JSON-01, Partially → Planned: the only benchmark ran outside the repository, and `6c6ddd8` removed its numbers from
  the code.

**Corrections to revision 1:**
- DIAG-06's criterion 4 rested on a 09-21 17:32 message that compares no counts.
- HOVER-15's design came in `c6d12ea`, not `8fdec51`.
- PROC-02's "6.4" came from the swiftly shim, not from plain `swift`.
- The review and the fix plan still say the single-file status bar badge ignores the scheme; `510115a` fixed that.

## Top gaps by user impact

1. **The installed app still lets a repository run commands (QUAL-07).** The trust gate and the git configuration
   gate reached `main` after the 13:52 install, so the app on screen has neither until the next install (PROC-03). Outside the app, six clones beyond `~/Developer` still run a repository's own hook binary first,
   and the installed project-hooks has no fix (QUAL-09; OQ3).
2. **Every reload still blanks the viewer (GIT-03, GIT-04).** Reload, Swap, a commit in a terminal, or a save of the
   file on screen shows "Comparing…" and drops scroll and revealed lines (GDV B2, B3, S1). Track 2B has not started.
   What Swap should show is OQ7.
3. **The card list, the default view, has no diagnostics, and its hover panel ignores list scrolling (DIAG-03,
   DUI-03, HOVER-14, HOVER-09).** No plan covers any of these (OQ8).
4. **The toolbar's Findings button and diagnostics label never appear after a run (DIAG-05, DUI-01).** They read an
   unobserved value (GDV B9). Track 2D has not started.
5. **The watcher still loses edits made during a reload, and the ref menus go stale after a commit (GIT-01).** The
   core half landed in `704d7b0`; the app half is track 2C. The stale menus, and rename detection writing
   `.git/index`, are in no plan.
6. **Settings misbehave across windows (SET-03, SET-05).** An edit in Settings silently creates project overrides
   (GDV B1), a theme change resets scroll and revealed lines, and no selector chooses Default or a project. Tracks 2A
   and 2B; the selector waits on OQ5.
7. **Three analyzers have never run on this machine, and the tools run on changesets with no Swift file (DIAG-01).**
   sourcekit-lsp's location is locked whenever diagnostics are off, which is the default (TOOL-02). OQ4; the rest is
   in no plan.
8. **System documentation misses iOS frameworks, and a cold timeout hides a symbol's documentation until the cache
   evicts it (HOVER-04).** Track 2F fixes the cache; nothing plans the iOS SDK.
9. **In the ref side's tree, unstaged changes draw filled (CARD-09, CARD-11).** In the default placement, the HEAD
   tree contradicts the working tree next to it. No plan.
10. **33 requirements wait for a visual check.** Most of the checklist can run on the installed app (13:52, built
    from `ce0880c`); QUAL-07's and PERF-01's checks need a build of `ebafb9f`.

Also open: TAB-07 (native tab behaviour) is in no plan; PERF-05 and PERF-07 have no measurement in the repository,
and the 10:50 cleanup deleted the measured patches the review and the renderer design cite (`/tmp/gdv-perf`,
`/tmp/kc-src`).

## Method and limits

- **Verification.** Six read-only agents checked the 121 requirements, area by area, in a snapshot of `ce0880c`. I
  then read the 33 later commits for the requirements they touch (GIT-01, GIT-02, GIT-05, HOVER-01, HOVER-04, PERF-01,
  PERF-03, PERF-09, JSON-04, QUAL-06, QUAL-07, PROC-11, MOD-03, TOOL-02, SET-03), in snapshots of `05aaf11` and
  `ebafb9f`, and re-read the citations behind each top gap. Commit messages were not taken as evidence.
- **No build and no test run.** Six Wave 1 agents were building. The pre-push hook built and tested AtelierCore and
  GitDiffViewer on `ce0880c` at 13:48 and passed; the later commits were merged after their tracks' own checks, and
  pushed at `ebafb9f`. I re-ran none of them.
- **Installed app.** `~/Applications/GitDiffViewer.app` was signed at 13:52:56 (team `L2LRQKFJ3U`) from `ce0880c`, and
  runs on a work repository. I made no visual check.
- **Work in progress:** none on a branch at `ebafb9f`; Wave 1's tracks have merged except 1K, which has not started.
  Wave 2 has not started.
- **Evidence outside the repository.** `/tmp/reviews` (18 reports), `/tmp/codex-review.md` and
  `/tmp/text-renderer-lab` remain. The 10:50 cleanup deleted `/tmp/gdv-perf`, `/tmp/kc-src` and `/private/tmp/gdv-cards`,
  which the review, the renderer design and revision 1 cite.
- **One side effect.** A verifier ran a plain `git status` in the Xcode playground, which took and released an index
  lock there. Nothing else was written outside `/tmp`.

## Statuses

### PROC: Delivery and process

#### PROC-01 · One local source of truth — **Implemented**
- `~/Developer/Atelier` is a full clone (185 commits before `7853f42`) with both apps and `Packages/AtelierCore`;
  `origin` is `g-cqd/Atelier`, `upstream` is `g-cqd/Atelier`.
- No other GitDiffViewer or AtelierCore copy exists under `~/Developer`. The `Atelier-w1-*` directories are worktrees
  of this repository, and `experimental/010.xcode-diff-playground` is DIFF-05's Xcode project.
- The 13:52 release build ran in `Apps/GitDiffViewer` with `Package.swift` unmodified. Was: Met.

#### PROC-02 · Toolchain matches — **Partially implemented**
- Met: `.swift-version` is `6.4.0`; the three manifests declare `swift-tools-version: 6.4`; swiftly's
  `~/.swiftly/bin/swift` reports 6.4.
- Missing: plain `swift --version` in the repository reports 6.3.3 (`/usr/bin/swift`), because the fish configuration
  puts `/usr/bin` ahead of `~/.swiftly/bin`. `xcrun swift` is 6.3.3 too, yet `AGENTS.md:49` recommends it. Builds work
  only because every agent puts swiftly first.
- Findings: PH-2 (external). Plan: track 2O covers `bundle.sh`'s build command; the shell `PATH` order is in no plan.
  Was: Met.

#### PROC-03 · Install, re-sign, relaunch — **Implemented**
- The installed bundle was signed at 13:52:56 by the local development identity (team `L2LRQKFJ3U`),
  `codesign --verify --deep --strict` passes, and its binary is the one built from `ce0880c`. It runs on a work
  repository against `origin/develop`, as R87 asked.
- Between 12:30 and 13:52 the installed app lagged `main` by four code commits. At `ebafb9f` it lacks 33 commits,
  among them the trust gate and the git configuration gate. Wave 1 is done except 1K, so the next install is due.
- Findings: Sec M5 (track 2O). Was: Partially met.

#### PROC-04 · g-cqd mirror — **Implemented**
- `origin/main` equals `main` at `ebafb9f`. Between pushes it lags: the coordinator holds pushes while agents edit,
  because the pre-push hook tests the working tree (PH-5); from 11:41 to 13:48 the lag reached ten commits.
- AemiJSON resolves from `https://github.com/g-cqd/AemiJSON.git` at `b98f139` (`Packages/AtelierCore/Package.swift:50`).
  aemi does not resolve from a mirror yet (PROC-12). Was: Met.

#### PROC-05 · Straight to main — **Partially implemented**
- Met: `main` is linear; the sweep branches and `w1/1cij` were fast-forwarded and deleted; branches in flight are the
  Wave 1 worktrees (by design, PROC-11).
- Missing: criterion 3 (each commit builds and passes the hooks) is not shown. 22 commits were rebased in two seconds
  at 11:22, which runs no hook, and the pre-push hook checks the working tree, not each commit (PH-5).
- Plan: PH-5 is external (fix plan §7.1; OQ3). Was: Met.

#### PROC-06 · Roadmap kept and implemented — **Partially implemented**
- Met: `Apps/GitDiffViewer/docs/roadmap.md` gained "Diff interaction refinements" (`:102-126`).
- Missing: sections that contradict the code: "In flight" (`:6-10`), "Phase M4" (`:38-41`), the UI wave's provenance
  footer, apple-docs tier and LazyVStack sticky header (`:63-70`), native tabs "investigate" (`:79-80`), and "Badge
  state fidelity" (`:95-100`), which is done. The roadmap never mentions the review, the fix plan, the security work
  or the renderer decision.
- Of the list approved on 09-22 at 14:13, the trailing-edge chip and the Show Documentation / Show Issue menu are
  absent with no recorded deferral.
- Plan: no fix-plan track (see `plan.md`). Was: Partially met.

#### PROC-07 · Plan first — **Implemented**
- The 09-21 plan was approved at 14:45 (D3). Wave 1 started from the committed fix plan (`11ddbb6`, 12:29) after D4
  (12:34). The renderer has a design (`47f2985`) and no code. Was: Met.

#### PROC-08 · Skills and instruction files — **Partially implemented**
- Met: the sessions and every Wave 1 agent loaded `CLAUDE.md`, `AGENTS.md` and the skills their briefs named. The JSON
  migration agent read no skill file.
- Missing: criterion 2; the code does not yet obey `AGENTS.md` and the Definition of Done (QUAL-06, MOD-03). Was: Met.

#### PROC-09 · Incremental, atomic, tested tracks — **Partially implemented**
- Met: the fix plan gives each wave a file-ownership table and names each track's dependencies; the branches mostly
  keep to their files. `bbaf80f`, `2342755` and `bfe8d1d` each hold one track with its tests.
- Missing: `ce0880c` bundles six behaviours in 20 files, and `840d4e1` and `2d6d788` bundle several. Four behaviour
  commits add no test: `bbe50e7`, `2b3a5c3`, `5a990db`, `510115a` (views in the untestable app target). Titles have
  dropped the repository's `<Scope>: ` form (OQ12). Was: new.

#### PROC-10 · The machine stays usable — **Implemented**
- 48 GiB free at 13:45; no Copilot for Xcode process runs; 521 of the 2,666 processes allowed per user.
- Risks: the Copilot for Xcode extension is still enabled, and Xcode relaunches it on use. `$TMPDIR/project-hooks-build`
  holds 9.1 GB of pre-push scratch (PH-7). The cleanup deleted evidence the documents cite (see Method). Was: new.

#### PROC-11 · Fix the findings in waves — **Partially implemented**
- Merged on `main` at `ebafb9f`, each in its own worktree and branch, since removed: 1A (8 commits, `3bdb404` to
  `9a41cf1`), 1B (`ab38879`, `52f77fc`, `57b9163`, `ebafb9f`), 1C `bbaf80f`, 1D `704d7b0`, 1E `2c44008` and
  `112a632`, 1F `718c75c`, 1G `05aaf11`, 1H (11 commits, `47c628c` to `54e5a73`), 1I `2342755`, 1J `bfe8d1d`.
- Not started: 1K (project-hooks). Its mirror's `main` (`9466245`) is behind upstream `8e1573f`.
- Missing: criterion 3; Wave 2 has not started. 1I's acceptance run needs the analyzers installed (OQ4).
- Also: the JSON migration ran outside the plan's ownership table; it changed files that tracks 2A, 2L and 4A own.
  Was: new.

#### PROC-12 · External fixes in g-cqd mirrors — **Partially implemented**
- Met, criterion 1: private mirrors of aemi, arcleak, dolly and deadwood exist since 12:40, next to project-hooks and
  AemiJSON.
- Missing, criterion 2: no external fix has started; every new mirror equals its upstream.
- Missing, criterion 3: the three manifests still resolve `https://github.com/Aemi-Studio/aemi.git` on `branch: "main"`
  (`Packages/AtelierCore/Package.swift:45`, `Apps/GitDiffViewer/Package.swift:27`, `Apps/KittyCode/Package.swift:40`).
  Every `Package.resolved` pins `dacd5f1`, while upstream `main` is at `a061a80`. AemiJSON's own manifest follows
  aemi's `main` too.
- Plan: track 2O pins aemi; no track moves the manifests to the mirror or schedules §7.1 besides 1K (OQ2). Was: new.

### DIAG: Diagnostics tools

#### DIAG-01 · Five analyzers run — **Partially implemented**
- Met: arcleak runs `analyze <root> --only <file>…`, and all three analyzers get `--format sarif --relative-to <root>`
  (`AtelierDiagnostics/ToolCommand.swift:22-32`). One helper makes paths root-relative under every spelling of the
  root (`AtelierDiagnostics/RootRelativePath.swift:16-44`; used at `SARIFDecoder.swift:27`, `XcodeTextParser.swift:8`).
  Exit 70 counts only when the SARIF parses (`ToolCommand.swift:51-56`, `DiagnosticsEngine.swift:167-183`). A missing
  tool reports `.toolMissing` (`DiagnosticsEngine.swift:118-120`).
- Tests: `DiagnosticsEngineAnalyzerTests` "every dolly or deadwood finding on a symlinked root with a space under
  TMPDIR survives the corpus filter", "exit 70 with nothing on standard output is a failure that carries standard
  error"; `RootRelativePathTests`; `ToolCommandTests` "each analyzer writes its SARIF paths relative to the root,
  spaces and all".
- Missing:
  - Criterion 3: corpus tools run on a changeset with no Swift file. The engine skips them only when the fingerprint
    is nil (`DiagnosticsEngine.swift:104-108`), and the app always builds one from every changed path
    (`DiffComparison/DiffViewerModel+Diagnostics.swift:78-97`).
  - No live run: arcleak, dolly and deadwood are not installed on this machine (OQ4).
- Findings: A-1, D-2, W-3, A-5 (Atelier side) and Core S23 fixed by `2342755`; D-1 and W-2 open in the tools.
- Plan: the Swift-only rule is in no fix-plan track. Was: Partially met.

#### DIAG-02 · Global and per-tool toggles — **Implemented**
- Master toggle `GitDiffViewer/Views/ToolsSettings.swift:61`; per-tool toggles `:83-91`, `:161`; off by default
  (`DiffComparison/ViewerSettings.swift:295`); turning it off cancels and clears (`DiffComparison/DiagnosticsModel.swift:135-141`);
  only enabled tools run (`DiagnosticsModel.swift:80`, `AtelierDiagnostics/DiagnosticsSession.swift:35`).
- Tests: `DiagnosticsModelTests` "turning the master toggle off cancels the run and clears findings";
  `DiagnosticsSessionTests` "a disabled tool is never run". Was: Met.

#### DIAG-03 · Findings on their lines — **Partially implemented**
- Met in the single-file panes: squiggles (`DiffTextKit/DiffLayoutFragment.swift:73-96`) and a tinted line number
  (`DiffTextKit/DiffGutterView.swift:269-273`, `:306-311`), fed through `DiffTextView.swift:98-100`.
- Missing: criterion 3. The card list, the default view, draws neither; card headers show counts only
  (`GitDiffViewer/Views/CombinedDiffView.swift:363-364`). Neither card rebuild (`840d4e1`, `ce0880c`) added it.
- Plan: none (OQ8). Was: Partially met.

#### DIAG-04 · Status bar summary — **Needs visual confirmation**
- `GitDiffViewer/Views/StatusBarView.swift:65-89` shows a spinner, the counts and a per-tool tooltip. It refreshes only
  because it also reads the observed `isRunning` (`:67`); `summary` itself is unobserved (GDV B9).
- Tests: `DiagnosticsModelTests` "the summary totals errors and warnings, overall and per tool". Nothing tests the
  refresh when a run ends.
- Plan: track 2D makes the summary observed. Was: Met.

#### DIAG-05 · Toolbar summary — **Partially implemented**
- The item exists (`GitDiffViewer/Views/ContentView.swift:168-169`, `ToolbarItems.swift:38-62`) and draws only when
  `diagnostics.summary` is non-empty; `summary` reads the `@ObservationIgnored` `findingsByTool`
  (`DiffComparison/DiagnosticsModel.swift:16-35`, `:46`). It never appears after a run.
- Findings: GDV B9. Plan: track 2D. Was: Not met.

#### DIAG-06 · Project configuration respected — **Needs visual confirmation**
- SwiftLint runs from the root with no paths (`ToolCommand.swift:16-17`); a formatter runs only with its configuration
  (`DiagnosticTool.swift:94-100`, `DiagnosticsEngine.swift:109-116`); findings narrow to the changed files under every
  spelling of the root (`DiagnosticsEngine.swift:261-266`).
- Tests: `DiagnosticsEngineRequiredConfigurationTests` (4).
- Missing: criterion 4 was never measured; revision 1's evidence compared no counts. Findings: Core S23 fixed by
  `2342755`. Was: Met.

#### DIAG-07 · Lockwood's SwiftFormat — **Implemented**
- Its own tool, row and bundle entry (`AtelierDiagnostics/DiagnosticTool.swift:5-6`, `Apps/GitDiffViewer/scripts/bundle.sh:33`),
  run as `--lint .` only with a `.swiftformat` (`ToolCommand.swift:20-21`, `DiagnosticTool.swift:97`), its `(rule)`
  prefix read as the rule ID (`XcodeTextParser.swift:43-52`).
- Tests: `XcodeTextParserTests` "a parenthesized rule prefix, as swiftformat emits, is extracted the same way as a
  bracketed one"; `DiagnosticsEngineRequiredConfigurationTests` (the two swiftformat cases). Was: Met.

#### DIAG-08 · Analyzed sides — **Partially implemented**
- Met: a setting with "Newer side" as the default (`DiffComparison/ViewerSettings.swift:52-60`,
  `GitDiffViewer/Views/ToolsSettings.swift:63-67`).
- Missing: "Left only" and "None"; running each side on its own files; exporting a ref side outside the working tree.
  "Both sides" copies the newer side's findings onto removed rows that share an old line number
  (`DiffTextKit/DiagnosticOverlay.swift:85-92`), against criterion 3.
- Plan: none; the modes wait on OQ6. Was: Partially met.

### TOOL: Tool discovery and locations

#### TOOL-01 · Dynamic discovery — **Partially implemented**
- Met: rungs in order (`AtelierDiagnostics/ToolDiscovery.swift:45-84`); the login shell runs
  `$SHELL -l -c "/usr/bin/printenv PATH"` from `$HOME`, keeps the last line and absolute entries only (`:169-198`);
  concurrent first lookups share one probe (`:140-163`); relative values are skipped
  (`AtelierProcess/ExecutableResolver.swift:37`, `:47`); Settings shows origin and version.
- Tests: `ToolDiscoveryLoginShellTests` (8), for example "what the startup files print before the PATH line is
  skipped", "three concurrent first lookups start one login shell".
- Missing: criterion 3. Refresh (`GitDiffViewer/Views/ToolsSettings.swift:229-236`) never calls
  `ToolDiscovery.invalidate()` (`ToolDiscovery.swift:106-111`), so a tool added to `PATH` after launch stays "Not
  found" until the app relaunches. Not verified live under fish.
- Findings: Core B10, S6, S24 and Sec L1 fixed by `bfe8d1d`. Plan: the Refresh gap is in no plan. Was: Partially met.

#### TOOL-02 · Locations in Settings — **Partially implemented**
- Met: every row has Locate… and Reset (`ToolsSettings.swift:130-140`); a pin wins over discovery
  (`ToolDiscovery.swift:64-66`); a diagnostics-tool pin applies on the next run.
- Missing:
  - Criterion 1: the Tools and Language Servers sections are disabled while diagnostics are off (`ToolsSettings.swift:93`,
    `:102`), which is the default, although hover, on by default, runs sourcekit-lsp.
  - Criterion 3: a pin that is not executable falls through to discovery (`ToolDiscovery.swift:64`) and shows green.
  - Criterion 4: a new sourcekit-lsp pin needs a restart (`AtelierLSP/SourceKitLSPRegistry.swift:13-27`,
    `GitDiffViewer/App.swift:182-206`).
- At `ebafb9f`: a project's own sourcekit-lsp setting is honoured (`1ad6cd4`, Sec L2 fixed). The three gaps remain;
  the gate is at `ToolsSettings.swift:95` and `:104` at `ebafb9f`.
- Plan: the three gaps are in no fix-plan track. Was: Regressed.

#### TOOL-03 · Bundling optional — **Implemented**
- The bundle is one rung (`ToolDiscovery.swift:67-70`); `Apps/GitDiffViewer/scripts/bundle.sh:28-79` stages what it
  finds, warns for the rest and signs each helper. The installed app holds `swiftlint`, `swift-format` and
  `swiftformat`.
- Tests: `ToolDiscoveryTests` cases without a bundle. Findings: Sec M5 and GDV N5 open (track 2O). Was: Met.

#### TOOL-04 · Bundle the five analyzers — **Superseded**
- By TOOL-03, TOOL-01 and TOOL-02 (09-21 15:20), after decision D2.

### HOVER: Hover documentation

#### HOVER-01 · Hover from sourcekit-lsp and swift-syntax, toggleable — **Implemented**
- A 300 ms debounce and one lookup at a time (`DiffTextKit/DocHoverController.swift:41`, `:141-171`); tiers in order
  language server, doc index, SDK (`DiffComparison/HoverDocumentation.swift:155-176`); blob sides indexed under
  `atelier-blob://` URIs (`:178-185`); the toggle in Settings and in View options (`ToolsSettings.swift:62`,
  `ViewOptionsMenu.swift:94-96`).
- Tests: `DocHoverControllerTests` "disabling the controller never calls the resolver"; `SourceKitLSPServiceTests`
  "hover performs the initialize handshake once and returns markdown"; `HoverDocumentationTests`
  "theNewSideOnDiskConsultsTheLanguageServerRegistry".
- At `ebafb9f`, the language-server tier waits for the user's trust decision (`f94d3be`, QUAL-07).
- Findings: Sec C1 fixed by track 1A; GDV S20 (dead app copy, track 2E). Was: Met.

#### HOVER-02 · Hover in every pane — **Needs visual confirmation**
- Card panes attach a controller and a resolver (`DiffTextKit/EmbeddedDiffTextView.swift:87`, `:120-121`;
  `GitDiffViewer/Views/CombinedDiffView.swift:320-336`, `:421-428`) for inline and side-by-side cards; the single-file
  pane has its own (`DiffTextView.swift:139`); both sides resolve (`HoverDocumentation.swift:155-168`).
- Tests: `HoverHitTesterTests` "a card pane's hosted text view resolves a mid-identifier hit the same way a scrolling
  pane does". The card container was rebuilt twice after the 09-22 screenshots that were the evidence. Was: Met.

#### HOVER-03 · Project doc comments appear — **Partially implemented**
- Met: tiers merge, so a declaration-only answer no longer hides a doc comment (`AtelierLSP/TieredHoverProviders.swift:16-46`);
  each publish feeds the files landed so far (`DiffComparison/DiffViewerModel+Diagnostics.swift:43-61`); an
  undocumented symbol reads "No documentation" (`DiffTextKit/HoverDocPanel.swift:297-302`).
- Tests: `SDKDocumentationProviderTests` "declaration-only repo LSP, doc index has the doc comment -- merges with
  provenance docIndex"; `DocCommentIndexTests` "a documented computed property inside an extension with an explicit
  get block is indexed".
- Missing: criterion 3 is undermined. Each publish replaces the index with the changeset, then re-reads up to 2,000
  corpus files (`HoverDocumentation.swift:119-139`, `AtelierDocIndex/DocCommentIndex.swift:38-52`), so a hover during
  that pass misses symbols outside the changeset. No test covers criteria 3 and 4.
- Findings: GDV B6, Core S4, S5. Plan: track 2E. Was: Needs visual confirmation.

#### HOVER-04 · System APIs from on-device documentation — **Partially implemented**
- Met: `AtelierLSP/SDKDocumentationProvider.swift:39-107` asks the local toolchain's sourcekit-lsp through a
  synthetic document that copies the file's imports; no network, no apple-docs.
- Missing:
  - Criterion 3: the scratch server gets no SDK or target (`:214-227`) and defaults to Foundation, AppKit and SwiftUI
    (`:31`), so UIKit cannot resolve for the iOS work repositories.
  - Criterion 4: a timeout returns nil (`AtelierLSP/SourceKitLSPService.swift:132-135`), which the provider caches
    until the 256-entry cache evicts it (`SDKDocumentationProvider.swift:46-54`). The test "a nil result is also
    cached" pins the defect.
- At `ebafb9f`: the probe files live in a private `mkdtemp` directory, and one SDK session serves every window
  (`3893897`, `9bc07d1`; Sec M4 and GDV S11 fixed). Neither adds an SDK or a target.
- Findings: Core B9. Plan: criterion 4 in track 2F; criterion 3 in no plan. Was: Partially met.

#### HOVER-05 · Quick Help style panel — **Partially implemented**
- Met: a borderless, non-activating `NSPanel` (`DiffTextKit/HoverDocPanel.swift:175-185`); monospaced inline code
  (`DiffRendering/HoverDocument.swift:173-181`); a body that scrolls past the cap (`HoverDocPanel.swift:311-313`).
- Missing: image 02's structure, criterion 2. No title row; the abstract follows the declaration and merges into the
  discussion with no "Discussion" header (`:275-280`); the only hairline is before the candidates (`:350-353`).
- Plan: none (OQ8). Was: Partially met.

#### HOVER-06 · Colored, legible declarations — **Partially implemented**
- Met: the pane's palette (`DiffRendering/HoverDocument.swift:107-111`) on a chip filled with the theme background
  (`:128-129`).
- Missing: criterion 3. On a row with findings, `GitDiffViewer/Views/DiagnosticDiffTextView.swift:91-94` rebuilds the
  document without `chipBackground`, and the chip turns clear.
- Findings: review §5.2 item 1. Plan: track 2E (`HoverDocument.adding(diagnostics:)`). Was: Partially met.

#### HOVER-07 · Panel fits its content — **Needs visual confirmation**
- The window takes the content stack's fitted height between a 40 pt floor and a 420 pt cap
  (`DiffTextKit/HoverDocPanel.swift:11-19`, `:262-316`).
- Tests: `HoverDocPanelTests` "aDeclarationOnlyDocumentHasNoWastedSpace"; `HoverPanelSizingTests`
  "aShortDocumentHugsItsOwnContentRatherThanPaddingToAFixedFloor".
- Unverified risk: the body never gets less than 60 pt (`:22-24`), so sections above 360 pt would overflow the window.
  Was: Needs visual confirmation.

#### HOVER-08 · Glass clipped by rounded corners — **Partially implemented**
- Met, criterion 3 in code: an `NSVisualEffectView` with the `.popover` material, 8 pt continuous corners and a mask
  image (`DiffTextKit/HoverDocPanel.swift:187-196`, `:491-503`).
- Missing: criterion 1, Liquid Glass (`NSGlassEffectView`) by default, and criterion 2, a Settings option for the
  popover material, both asked for in Q3's answer (09-23 09:37).
- Plan: none (OQ8). Was: Needs visual confirmation.

#### HOVER-09 · Panel follows its line — **Partially implemented**
- Met in the single-file view: the controller follows the pane's own clip view, moves the panel, and closes it when
  the identifier leaves (`DiffTextKit/DocHoverController.swift:65-70`, `:103-121`).
- Missing in the card list, the default view: each card pane's text view sits in its own horizontal `NSScrollView`
  (`DiffTextKit/EmbeddedDiffTextView.swift:56-60`, `:77`), so the controller watches that clip view, and nothing
  moves or closes the panel when the list scrolls.
- Tests: `DocHoverControllerTests` "scrolling the hovered identifier entirely out of view closes the panel" (single-file
  layout only).
- Findings: none; no finding or plan covers it. Was: Met.

#### HOVER-10 · No flash — **Needs visual confirmation**
- A bounds notification without a real scroll is ignored, and moving into the panel keeps it
  (`DiffTextKit/DocHoverController.swift:103-115`, `:133-137`).
- Tests: `DocHoverControllerTests` "a bounds-changed notification with no actual scroll offset is a no-op". Was:
  Needs visual confirmation.

#### HOVER-11 · No duplicates — **Partially implemented**
- Met: a blob entry with a `file://` twin collapses, identical renderings merge, and the hovered revision keeps its
  own entry (`AtelierDocIndex/DocCommentIndex.swift:57-108`).
- Missing: when both sides are refs, or a file was renamed, the old blob has no `file://` twin (`:83-93`), so the old
  declaration is listed beside the new one, as in image 06.
- Tests: `DocCommentIndexTests` (4 dedup tests); none uses two blobs of one path. Plan: none. Was: Met.

#### HOVER-12 · Typography and spacing — **Needs visual confirmation**
- Every prose run gets an explicit system font (`DiffRendering/HoverDocument.swift:173-189`); one spacing scale
  (`DiffTextKit/HoverDocPanel.swift:39-51`); the declaration in an `NSBox` with a 1 pt separator border (`:415-423`).
- Tests: `HoverDocumentTests` "summaryProseAlwaysCarriesAnExplicitSystemFont". Was: Needs visual confirmation.

#### HOVER-13 · No source label — **Implemented**
- No footer slot (`DiffTextKit/HoverDocPanel.swift:225-228`). Test: `HoverDocPanelTests`
  "provenanceStillHasNoFooterFootprint". Leftover: the unused `HoverDocument.Provenance.label`
  (`DiffRendering/HoverDocument.swift:63-71`). Was: Met.

#### HOVER-14 · Documentation and diagnostic in one hover — **Partially implemented**
- Met in the single-file view: the hovered row's findings join the document
  (`GitDiffViewer/Views/DiagnosticDiffTextView.swift:75-97`) as tinted rows (`DiffTextKit/HoverDocPanel.swift:379-398`).
- Missing: matching by the underlined range rather than the row; the card list; the Show Documentation / Show Issue
  menu; the chip background on these rows (HOVER-06). No test.
- Plan: the chip in track 2E; the rest in no plan (OQ8). Was: Partially met.

#### HOVER-15 · Multi-language design — **Implemented**
- `Apps/GitDiffViewer/docs/multi-language-hover-design.md` (`c6d12ea`) covers servers per language, discovery, a
  tree-sitter fallback, tier order and phases. Its "not yet scheduled" contradicts the roadmap. Was: Met.

#### HOVER-16 · Hover for other languages — **Planned**
- `AtelierLSP/LSPHoverProvider.swift:12-14` hard-codes `"swift"`; the language-server tier and the doc index take
  Swift files only (`DiffComparison/HoverDocumentation.swift:104`, `:170-176`); `Language.lspLanguageID` has no
  caller; no descriptor, registry or `AtelierDocComment` target exists.
- The design's fallback needs grammars that fail today (JavaScript and TypeScript do not load; review §3.2).
- Plan: roadmap Phases M1 to M3, after the trust gate (track 1A) and the grammar corpus move (track 4A). Was: Not met.

#### HOVER-17 · The apple-docs tier — **Superseded**
- By HOVER-04. No apple-docs code exists.

#### HOVER-18 · A provenance footer — **Superseded**
- By HOVER-13.

### DUI: Diagnostics UI

#### DUI-01 · A toolbar list of every finding — **Partially implemented**
- Met: a scrollable popover grouped by file and sorted by line (`GitDiffViewer/Views/FindingsNavigator.swift:42-77`,
  `DiffComparison/FindingsNavigatorGrouping.swift:16-22`); a row opens its file (`FindingsNavigator.swift:59-63`).
- Missing: the button shows only when the unobserved `summary` is non-empty (`:12`; GDV B9), so it never appears
  after a run; a row stops at the file instead of the line (GDV S18).
- Tests: `FindingsNavigatorGroupingTests` (2). Plan: GDV B9 in track 2D; the line jump is kept as a default for 2D
  (book, defaults). Was: Not met.

#### DUI-02 · Markers do not change the gutter — **Partially implemented**
- Met in code: the width depends on the digits only (`DiffTextKit/DiffGutterView.swift:78-95`, `:121-124`); a finding
  tints its number over a faint wash (`:269-275`, `:297-311`).
- Missing: a test that the width is the same with and without findings. Plan: none. Was: Met.

#### DUI-03 · A finding opens from its line — **Partially implemented**
- Met in the single-file view: clicking a tinted number opens the finding (`DiffTextKit/DiffGutterView.swift:171-190`,
  `GitDiffViewer/Views/DiagnosticDiffTextView.swift:101-107`).
- Missing: the trailing-edge overlay (optional by its wording), the card list, and a test. Plan: none (OQ8). Was:
  Partially met.

#### DUI-04 · Popover anchored on its line — **Needs visual confirmation**
- The gutter passes the clicked row's rect (`DiffTextKit/DiffGutterView.swift:180-190`), and the popover anchors on it
  (`GitDiffViewer/Views/DiagnosticDiffTextView.swift:101-107`). No test. Was: Met.

### SET: Settings

#### SET-01 · Research-based Settings — **Partially implemented**
- Met: `Apps/GitDiffViewer/docs/settings-design.md` (principles with sources, audit, redesign); four tabs by user
  question (`GitDiffViewer/Views/SettingsView.swift:18-31`); disclosure per tool (`ToolsSettings.swift:114-122`);
  captions and a per-tab Restore Defaults with a deviation count (`SettingsView.swift:247-286`); one label set
  (`DiffComparison/SettingLabels.swift:3-41`).
- Missing: one label per setting on every surface. The toolbar says "Isolate", "Wrap", "Minimap", "Changed only",
  "Ignored" and "Layout" (`GitDiffViewer/Views/ContentView.swift:193-243`) where Settings says "Isolate changes",
  "Wrap long lines", "Show minimap", "Show changed files only", "Show ignored files" and "Diff layout".
- Tests: `SettingLabelTests`; `ViewerSettingsTests` restore-defaults cases. Plan: none. Was: Met.

#### SET-02 · Platform conventions — **Implemented**
- A fixed-size `TabView` in a `Settings` scene (`SettingsView.swift:18-32`, `GitDiffViewer/App.swift:65-70`); the last
  pane restored (`DiffComparison/ViewerSettings.swift:223-225`); view settings in the window's options and toolbar.
- Test: `ViewerSettingsTests` "the settings pane defaults to general and round trips through user defaults". Was: Met.

#### SET-03 · Per-project settings — **Partially implemented**
- Met: criterion 1, a SHA-256 identity of the standardized root (`DiffComparison/ProjectIdentity.swift:13-29`).
  Criterion 2 in part: each window adopts its repository (`ComparisonWindow.swift:55-58`), and overrides persist
  (`ViewerSettings.swift:138-152`, `:255-260`), but only 4 of the 9 scoped settings have a per-window control.
- Missing:
  - Criterion 3: 9 of 27 settings are scoped (`ViewerSettings.swift:131-134`).
  - Criterion 4: no Default-or-project selector; the Settings window edits the app-level instance.
  - Criterion 5: each tab lists projects with overrides (`SettingsView.swift:267-331`), without the settings or their
    values, and cannot edit them.
  - Criterion 6: a broadcast or a project switch writes overrides nobody made (GDV B1); an equal value writes too (S10).
- At `ebafb9f`, a project's own sourcekit-lsp setting applies to its language server (`1ad6cd4`); the SDK tier
  follows the app-wide setting (a default in the book).
- Tests: `ProjectSettingsTests` (11); none asserts that a broadcast writes nothing.
- Plan: criterion 6 and granularity in track 2A; criteria 3 to 5 wait on OQ5. Was: Partially met.

#### SET-04 · Light and dark setting — **Needs visual confirmation**
- System, Light and Dark (`SettingsView.swift:171-176`) set `NSApplication.shared.appearance` (`App.swift:108-147`).
- Tests: `ViewerSettingsTests` "appearance scheme defaults to system and round trips through user defaults". Nothing
  tests the effect on windows. Findings: GDV S4 (the theme is re-parsed on every appearance change). Was: Met.

#### SET-05 · Live settings, no new comparison — **Partially implemented**
- Met: every app-wide write is announced and re-read by every window (`ViewerSettings.swift:261-263`, `:310-317`),
  `reload(key:)` covers all 27 keys including the badge scheme (`ViewerSettings+ProjectOverrides.swift:30-153`), and
  only granularity and heuristics re-diff (`ViewerSettings.swift:181-185`).
- Missing: criterion 2, a theme change relays out with `keepingScroll: false` (`DiffComparison/DiffViewerModel.swift:464`),
  clearing revealed lines and the single-file scroll (`RenderPipeline.swift:144`, `:228`, `:237`). Criterion 1 fails
  for scoped settings once GDV B1 has copied an edit into a project.
- Tests: `ViewerSettingsBroadcastTests` (7). Findings: GDV B1, B7. Plan: tracks 2A and 2B (the scroll reset is named
  only in the fix plan's Wave 0 table). Was: Partially met.

#### SET-06 · Appearance from the theme — **Needs visual confirmation**
- The toggle (`SettingsView.swift:182-183`), off by default; an explicit Light or Dark wins
  (`DiffComparison/BadgeStyle.swift:115-121`); the window follows the theme's luminance (`App.swift:114-125`).
- Tests: `AppearancePrecedenceTests` (7). Was: Met.

#### SET-07 · Badge color scheme — **Needs visual confirmation**
- Classic or Xcode (`SettingsView.swift:205-213`, `BadgeStyle.swift:72-89`), passed to every badge: explorer rows,
  tabs, card headers and their tint (`CombinedDiffView.swift:366`, `:373`), the status bar (`StatusBarView.swift:44-47`)
  and the toolbar's current-file item (`ToolbarItems.swift:75-77`); open windows follow
  (`ViewerSettings+ProjectOverrides.swift:68-70`).
- Tests: `BadgeStyleResolverTests` "xcode scheme reads a modification and a rename both as blue";
  `ViewerSettingsBroadcastTests` "a badge scheme edit on one instance reaches another window's settings".
- Commits: `2d6d788`, `2b3a5c3`, `5a990db`, `510115a`. `ChangeBadge.swift:132-134` still says card headers keep the
  classic look. Was: Partially met.

#### SET-08 · Accent color research — **Planned**
- No research note exists. Plan: roadmap "Accent-color adaptation (research)". Was: Not met.

### CARD: The card list and badges

#### CARD-01 · Sticky headers — **Implemented**
- One AppKit view per card re-places itself on every clip-bounds and host-frame change
  (`DiffTextKit/StickyCardView.swift:159-196`); the header stays on the pin line until only it is left
  (`DiffTextKit/StickyCardGeometry.swift:27-34`); clicks in the pinned header reach the card (`StickyCardView.swift:153-157`),
  and a click folds the file (`GitDiffViewer/Views/CombinedDiffView.swift:377`).
- Tests: `StickyCardViewTests` "a card scrolled past the pin line keeps its header the gap below the bars", "the area
  a pinned header left above it takes no clicks, and the header does". Commits: `840d4e1`, `ce0880c`. Was: Met.

#### CARD-02 · Card look when pinned — **Needs visual confirmation**
- One 16 pt constant for margins, gaps and the sticky gap (`CombinedDiffView.swift:17`, `:141`); the pin line sits
  that gap below the clip view's top content inset (`StickyCardView.swift:202-208`); rounded top corners and one shadow
  layer (`:72-83`, `:218-224`).
- Tests: `StickyCardGeometryTests` "the pin line sits the gap below the top inset whichever way the clip view's axis
  points". The user approved the look on the 09:41 review build (R85). Was: Needs visual confirmation.

#### CARD-03 · Content clipped behind a pinned header — **Needs visual confirmation**
- The top clip starts at the pin line with rounded corners, the body has its own clip at the header's bottom edge,
  and the header is opaque (`StickyCardView.swift:53-56`, `:81-84`, `:214-219`; `CombinedDiffView.swift:372-374`).
- Test: `StickyCardGeometryTests` "past the pin line the visible card starts at the line and the body holds still on
  the card". Was: Not met.

#### CARD-04 · One card at rest — **Needs visual confirmation**
- Header and body touch and share one outline and one shadow (`StickyCardView.swift:72-80`, `:124-125`); one seam
  (`CombinedDiffView.swift:394-397`); the pinned hairline hidden at rest (`StickyCardView.swift:85`, `:225-227`).
- Test: `StickyCardViewTests` "a card below the pin line rests at its own top with no hairline". Was: Partially met.

#### CARD-05 · Nothing clips shadows or the scroll bar — **Needs visual confirmation**
- The list's top edge is the system's soft edge effect (`CombinedDiffView.swift:32-33`); the shadow view is a sibling
  of the card's clips (`StickyCardView.swift:86-88`). No test. Was: Needs visual confirmation.

#### CARD-06 · No square glass, no extra shadow when pinned — **Needs visual confirmation**
- No card surface uses a material (`CombinedDiffView.swift:372-374`; `StickyCardView.swift:36-40`, `:238`); one shadow
  layer per card (`:72-76`). Findings: GDV S5 fixed by `840d4e1`. No test. Was: Not met.

#### CARD-07 · Folding keeps the gap — **Needs visual confirmation**
- The gap is each card's 16 pt top padding, outside the card (`CombinedDiffView.swift:23-27`); a fold changes only
  the card's height. No test: the layout lives in the untestable app target. Was: Met.

#### CARD-08 · Fold symbols with a transition — **Needs visual confirmation**
- `rectangle.expand.vertical` and `rectangle.compress.vertical` with `.contentTransition(.symbolEffect(.replace))`
  (`CombinedDiffView.swift:351-353`). The header now lives in its own hosting controller whose root view a fold
  replaces (`:217-219`), so whether the morph still plays needs a look. No test. Was: Met.

#### CARD-09 · Badge states and Xcode's colors — **Partially implemented**
- Met: staged changes fill, unstaged and untracked ones stroke (`DiffComparison/BadgeStyle.swift:94-105`); in the Xcode
  scheme added is green, deleted red, modified and renamed blue (`:81-87`); the letters are A, D, M and R, and an
  untracked file reads as a stroked A (`GitDiffViewer/Views/ChangeBadge.swift:28-45`); every surface passes scheme and
  state (rows, tabs, card headers, status bar, toolbar).
- Missing: criteria 1 and 4 fail in the ref side's own tree, where unstaged changes draw filled (see CARD-11). The
  `new ← old` row label is unanswered (OQ9).
- Tests: `BadgeStyleResolverTests` "staged, unselected: filled with the scheme's colour and a white letter",
  "untracked reads exactly like unstaged". Plan: the ref-tree fix is in no plan. Was: Partially met.

#### CARD-10 · Badges follow selection and focus — **Needs visual confirmation**
- The resolver inverts on a focused selection (`BadgeStyle.swift:98-104`); the badge reads AppKit's `.emphasized` row
  style (`ChangeBadge.swift:227-233`), which the cell now forwards (`GitDiffViewer/Views/FileOutlineView.swift:471-475`,
  `5a990db`, the fix for R91), in all three explorer placements.
- Tests: `BadgeStyleResolverTests` "unstaged, selected in a focused list: white outline and letter, no fill", "selected
  but unfocused keeps the state's own look, not the inverted one". The forwarding has no test. Was: Needs visual
  confirmation.

#### CARD-11 · Badge state from git — **Partially implemented**
- Met: `git status --porcelain=v2` keeps the staged and unstaged columns (`AtelierGit/GitClient.swift:81-86`,
  `GitParsers.swift:176-184`); the working-tree column decides each file's state, and a path git does not list counts
  as committed, hence filled (`DiffComparison/BadgeChangeStates.swift:36-59`); a ref side is staged throughout
  (`SideState.swift:77-81`); a `git add` refreshes the badges without a reload.
- Missing: each per-side tree uses its own side's states (`GitDiffViewer/Views/FileExplorerView.swift:26-27`). In a
  HEAD-versus-working-tree comparison, the HEAD tree draws every change filled, unstaged edits included, and a test
  pins that (`DiffViewerModelBadgeStatesTests.swift:58` against `:67`).
- The two 11:15 choices are what the code does (kept as defaults in the book).
- Tests: `BadgeChangeStatesTests` "a committed file git's status leaves out is staged", "a folder is unstaged when a
  file anywhere below it is"; `SideStateBadgeStatesTests` "refreshing reads git's status alone, so staging a file
  fills its badge without a reload".
- Findings: Sec C2, which the per-load `git status` widened, is fixed at `ebafb9f` (`ab38879`). Plan: the ref-tree
  fix is in no plan. Was: Not met.

#### CARD-12 · A custom sticky card container — **Needs visual confirmation**
- One AppKit view per card (`CombinedDiffView.swift:122-164`): the pin line 16 pt below the clip view's top inset
  (`StickyCardView.swift:202-208`); the top clip rounds and moves with the pin (`:81-84`, `:214-219`); the card's
  bottom pushes the header out (`StickyCardGeometry.swift:27-34`); one shadow, outline and seam (`StickyCardView.swift:72-85`);
  a scroll moves two view origins and two layer frames with animations off (`:192-196`, `:214-230`).
- Tests: `StickyCardViewTests` "the card's bottom pushes its header out", "scrolling back above the pin line returns
  the card to rest and hides the hairline".
- Missing: a measurement of scrolling, the criterion R85 added (see PERF-05). Not verified: whether the pinned header
  follows a change of top inset alone, such as the tab bar appearing without a scroll. Was: new.

#### CARD-13 · Folding keeps the text and the colors — **Needs visual confirmation**
- A 0.2 s fold progress (`CombinedDiffView.swift:85-118`); the body keeps its height and is clipped by the card's
  shrinking edge (`StickyCardView.swift:116-126`); it stays mounted until none of it shows, and an unfold mounts it
  before the card grows (`DiffTextKit/CardBodyMount.swift:26-45`); the body clip paints the panes' color
  (`StickyCardView.swift:36-40`, `:238`).
- Tests: `CardBodyMountTests` (10), `StickyCardViewTests` "a folding card clips its body at its bottom edge while the
  body keeps its own height", "an unfolding card reveals a body already laid out at its own height". Commit:
  `ce0880c`. Was: new.

#### CARD-14 · Split layouts size cards exactly — **Needs visual confirmation**
- A side-by-side pair is as tall as its taller pane whatever height is offered (`DiffTextKit/SideBySidePanes.swift:3-6`,
  `:31-43`); card heights are memoized (`DiffTextKit/StaticTextLayout.swift:69-72`, `:97-107`); a bad measurement falls
  back to the last good height (`CombinedDiffView.swift:263-270`).
- Tests: `SplitCardHeightTests` "heights stay the same across measures, repeated preparations and a width round trip",
  "a body holding real split panes measures its aligned height whatever height it is offered". Commit: `ce0880c`.
  Was: new.

#### CARD-15 · Cards offer inline and side by side only — **Needs visual confirmation**
- Cards draw Stacked side by side (`DiffComparison/CardLayout.swift:8-10`); while cards show, the Stacked segment and
  ⌘3 are disabled with "Stacked is available for a single file" (`ContentView.swift:246-276`); Settings says "The card
  list shows Stacked side by side." (`SettingsView.swift:220`); a single file keeps all three.
- Tests: `CardLayoutTests` (4). Criterion 2 names a View menu, which has no layout items (kept as a default in the
  book). Commit: `ce0880c`. Was: new.

#### CARD-16 · Card geometry is always finite — **Needs visual confirmation**
- Every measured height must be finite, non-negative and below 10,000,000, else it falls back to the last good one
  with a fault log and a debug assertion (`StickyCardGeometry.swift:10`, `:81-88`; `CombinedDiffView.swift:244-249`,
  `:263-270`); frames use only cleaned geometry (`StickyCardView.swift:119-126`); the unbounded side-by-side height is
  gone (`SideBySidePanes.swift:31-43`).
- Tests: `StickyCardGeometryTests` "a non-finite, negative or unbounded length falls back to the last good one";
  `StickyCardViewTests` "a malformed header or body height never reaches a view frame"; `SplitCardHeightTests` "a
  split body with no width yet measures a finite size".
- Not covered: no test drives SwiftUI's scroll view to the crash's NaN offset. The installed 11:39 build crashed again
  on this NaN at 13:39; the 13:52 build has the fix. Commit: `ce0880c`. Was: new.

### TAB: Window tabs and the in-app tab bar

#### TAB-01 · Native window tabs — **Needs visual confirmation**
- Comparison windows share one tabbing identifier with `tabbingMode = .preferred`
  (`GitDiffViewer/Views/ComparisonWindow.swift:43-50`); the welcome window is `.disallowed` (`App.swift:35-39`); the +
  button opens it (`App.swift:280-284`). No test. Was: Met.

#### TAB-02 · Equal gaps — **Implemented**
- `TabBarLayout.gap` (6 pt, `DiffComparison/TabBarLayout.swift:5-8`) sets the spacing and the bar's padding
  (`GitDiffViewer/Views/TabBarView.swift:36-37`, `:61`). Test: `TabBarLayoutTests` "the bar's gap is six, the one
  constant tying inter-tab spacing to the bar's own insets". Was: Met.

#### TAB-03 · Glass tabs, very light shadow — **Needs visual confirmation**
- `.glassEffect(.regular.interactive(), in: .capsule)` and a 0.12-opacity shadow inside one `GlassEffectContainer`,
  with no bar background (`TabBarView.swift:36`, `:108-113`; `DiffDetailView.swift:17-21`). Tab outlines now draw
  above the glass (`130fa5c`). Was: Needs visual confirmation.

#### TAB-04 · Close button in the badge slot — **Implemented**
- One fixed 18 pt slot shows the close button on hover, else the badge, else the icon (`TabBarView.swift:88-91`,
  `:129-153`; `TabBarLayout.swift:12-21`). Tests: `TabBarLayoutTests` "hovering shows the close button in place of the
  badge" and four more. Was: Met.

#### TAB-05 · Badge instead of the icon; neutral tabs — **Implemented**
- The slot shows the badge in the chosen scheme and git state; tabs carry no tint (`TabBarView.swift:42-44`,
  `:104-112`, `:145-152`). Tests: `TabBarLayoutTests` "unhovered with a change shows the badge". Was: Met.

#### TAB-06 · Restyle native window tabs — **Superseded**
- By TAB-02 to TAB-05.

#### TAB-07 · Native behavior for the in-app file tabs — **Not started**
- Tabs answer click, double-click and a context menu with Reset Revealed Lines, Keep Open and Close Tab
  (`TabBarView.swift:52-57`, `:115-116`). No drag to reorder, no tab commands (⌘W still closes the window), no middle
  click, no Close Other Tabs or Close Tabs to the Right, nothing scrolls the active tab into view, and no accessibility
  actions; the model has no move or next and previous operations (`DiffComparison/DiffTabs.swift:20-88`).
- Conflict: ⌃Tab and ⌃⇧Tab already switch native window tabs (TAB-01). Plan: none (OQ8). Was: new.

#### TAB-08 · Tab hover, close button, capsule and pin — **Needs visual confirmation**
- Capsule shape; a hover wash at 0.03 (`TabBarLayout.swift:45`); a 16 pt disc behind the close button while hovered,
  with the × centered in a fixed frame (`TabBarView.swift:18-20`, `:131-143`); a 14 pt badge centered in the capsule's
  round end (`:13`, `:89-90`, `:105-107`); `pin.fill` after a kept-open tab's name (`:95-101`).
- Tests: `TabBarLayoutTests` "hovering tones the capsule with a faint wash, and resting leaves it clear", "a kept-open
  tab shows a pin after an upright name, active or hovered or not". Commits: `130fa5c`, `bbe50e7`. Was: new.

#### TAB-09 · Native backdrop beneath the tab bar — **Needs user decision**
- Met for the card list: the tab bar is a `safeAreaBar` over the list, which scrolls beneath it with the system edge
  effect (`DiffDetailView.swift:17-21`, `CombinedDiffView.swift:32-33`).
- Missing: the single-file panes are AppKit scroll views that stop at a `Divider` (`DiffDetailView.swift:28-34`);
  AemiSDR was not evaluated. Decision: OQ10 (fix plan §7.3). Was: new.

### GIT: Freshness and reload continuity

#### GIT-01 · Watch and refresh — **Partially implemented**
- Met: one watcher per working-tree comparison routes tree edits to a reload, HEAD to a re-comparison, refs to the
  menus or a reload, and the git directory to a badge refresh (`DiffComparison/RepositoryFreshness.swift:164-177`,
  `DiffViewerModel+Freshness.swift:9-48`); `autoRefresh` turns it off (`ViewerSettings.swift:180`).
- Met after `ce0880c`: `704d7b0` runs one FSEvents stream over every watched directory and each watched file's folder
  (Core B7, B8 fixed). A linked worktree's refs and HEAD should now report with `RepositoryFreshness` unchanged; no
  app test shows it.
- Missing:
  - Criterion 2, the menus: while a side sits on a ref (the default HEAD comparison), a refs change only reloads the
    sources and never re-reads the repository info that feeds the menus (`DiffViewerModel+Freshness.swift:39-43`), so
    new commits, branches and tags do not appear.
  - Criterion 4: every `sourcesChanged` tears the watcher down and re-attaches it (`DiffViewerModel.swift:278`,
    `:290`; `RepositoryFreshness.swift:109-146`), dropping pending debounces (GDV B4).
- Tests: `RepositoryFreshnessTests` (19), for example "staging, reported on the git dir, fires onIndexChanged and
  neither a reload nor a re-comparison"; since `704d7b0`, `FileWatcherTests` "a write under the second of two watched
  directories raises an event", "a watched file keeps reporting after three atomic saves".
- Findings: GDV B4, B5 (app half), the HEAD-watch defect (review §5.1), GDV S2, S3 open. Plan: track 2C; the stale
  menus are in no plan. Was: Partially met.

#### GIT-02 · Fetch, reusable — **Implemented**
- `branches`, `tags`, `remotes`, `aheadBehind` and `fetch` in `AtelierGit/GitClient.swift:134-173`, under `.networking`
  isolation (`GitIsolation.swift:24-28`); both source menus offer Fetch (`SourceToolbarControl.swift:161`, `:201-215`),
  which refreshes the menus and reloads a remote-tracking side (`DiffViewerModel+Freshness.swift:57-74`).
- Tests: `SideStateFetchTests` "fetch refreshes repository info and calls onFetched on success";
  `DiffViewerModelFetchTests` "a fetch on a side parked on a remote-tracking ref reloads the comparison".
- At `ebafb9f`: fetch runs only over `https` or `ssh` with the transports pinned (`protocol.allow=never`,
  `protocol.ext.allow=never`, an empty `credential.helper` and `core.askPass`; `AtelierGit/GitIsolation.swift:66-99`
  at `ebafb9f`), a repository whose own configuration names a program is refused (`ab38879`, Sec H1 fixed), and Fetch
  is off until the user trusts the repository (`2955136`). Was: Met.

#### GIT-03 · A reload never collapses the viewer — **Planned**
- A two-sided reload clears the comparison, the trees and the pipeline when its first side lands
  (`DiffComparison/DiffViewerModel.swift:271-280`; GDV B2). A one-sided reload that changes a file unpublishes it
  first (`RenderPipeline.swift:115-117`), so `detailState` goes `.loading` and the pane shows "Comparing…"
  (`DiffViewerModel.swift:149-157`, `GitDiffViewer/Views/DiffDetailView.swift:35-36`; GDV B3). Options are read
  before the await (`RenderPipeline.swift:418-419`; GDV S1). Folds survive (`DiffViewerModel.swift:286`).
- Doc comments still promise continuity (`DiffViewerModel.swift:147-148`, `RenderPipeline.swift:99-101`).
- Tests: `DiffViewerModelReloadContinuityTests` covers only the listing phase. Plan: track 2B; OQ7 for Swap. Was: Not
  met.

#### GIT-04 · A re-comparison keeps loaded files — **Partially implemented**
- Met: reuse by path and blob, never for unhashed files (`RenderPipeline.swift:266-343`); only missing cards render
  (`:400-468`); a granularity change re-renders all (`:302-305`).
- Missing: a two-sided reload clears the pipeline first (GDV B2), so nothing is reused then. Tests:
  `DiffViewerModelReloadContinuityTests` "a reload keeps an unchanged card's identity and re-renders only the file
  whose blob changed". Plan: track 2B. Was: Partially met.

#### GIT-05 · The watcher never crashes the app — **Implemented**
- At `ebafb9f`, unchanged since `704d7b0`: FSEvents owns the stream controller through the context's retain and
  release callbacks (`AtelierFileTree/AtelierFileWatcher.swift:503-512`); creating, restarting and releasing the
  stream all run on its serial queue (`:437`, `:448`, `:479`, `:494`); `deinit` tears down (`:181-184`); the event
  buffer holds at most 1,024 events (`:93`). The first fix was `8fd26e5`; `704d7b0` kept both rules in its rewrite.
- Test: `FileWatcherTests` "stopping or dropping watchers while their events are in flight never reaches freed state"
  (60 rounds; a survivor must still get events). "Passes repeatedly" rests on the coordinator's "3 of 3" at 11:15; the
  test does not force a callback to run during teardown.
- Findings: Core S15 fixed; Aemi #27 fixed by `704d7b0` (bounded buffer, exclusion paths). Was: new.

### WIN: Window chrome

#### WIN-01 · Toolbar persists — **Needs visual confirmation**
- One customizable toolbar saved under `main.3` (`GitDiffViewer/Views/ContentView.swift:31`, `:303`), built on the
  window's first pass (`ComparisonWindow.swift:20-37`). This machine holds a saved arrangement under that name.
  `ce0880c` changed the layout item's content under the same identifier. No test. Was: Needs visual confirmation.

#### WIN-02 · A saved toolbar never crashes the app — **Needs visual confirmation**
- The only guard is renaming the autosave key when items change (`ContentView.swift:301-303`). One item (Findings,
  `c10d36e`) was added after `main.3` without a rename; none has changed since. The installed app restored the saved
  toolbar and ran from 11:39 to 13:39, when it crashed on CARD-16's NaN, not on the toolbar. No test. Was: Needs visual
  confirmation.

#### WIN-03 · Symmetric source selectors — **Implemented**
- One descriptor gives each side "repository + ref" or "repository + Working Tree" (`AtelierSources/ComparisonSource.swift:47-71`),
  used by both selectors (`SourceToolbarControl.swift:69-103`). Tests: `SourceDescriptorTests` (7). Was: Met.

### PERF: Performance and non-blocking work

#### PERF-01 · Tool runs never block the UI — **Needs visual confirmation**
- Criteria 1 and 2: the analyzers have their own width-2 pool, apart from git's (`GitDiffViewer/App.swift:153`,
  `:158`); one child task per tool (`AtelierDiagnostics/DiagnosticsSession.swift:39-41`); parsing is `@concurrent`
  (`DiagnosticsEngine.swift:241-259`). Test: core `OffMainExecutionTests` "a tool run, called from the main actor,
  executes its runner and parses its output off the main thread".
- At `ebafb9f`, quitting during a lint no longer blocks the main thread: `ShutdownSequence` interrupts diagnostics,
  then git work, then shuts the pools down off the main thread within a limit, and the app answers `.terminateLater`
  (`9a41cf1`; `App.swift:205-234` at `ebafb9f`). Tests: `ShutdownSequenceTests` "diagnostics are interrupted first,
  then git work, and both before anything drains or shuts down", "the sequence ends at its limit when a pool job never
  returns". Aemi #5 fixed on Atelier's side.
- Missing: criterion 3 (the UI stays responsive during a lint of the whole repository) was never checked. Was: Met.

#### PERF-02 · `@concurrent` offload with tests — **Partially implemented**
- Met: criterion 1, the consolidated review covered every package (`11ddbb6`, §3.1 to §3.3, §4.3); six app seams and six
  core seams are `@concurrent` (for example `DiffComparison/DiffPreparer.swift:100`, `RenderPipeline.swift:243`,
  `SideState.swift:278`).
- Missing: KittyCode highlights and searches on the main actor (Kitty B10, S15); relayouts and gap drags re-render
  every card on the main actor (GDV B7); no thread-probe test for `renderOffMain`, `DiffPreparer.load`,
  `SideState.readBadgeStates` or the `SourceLoader` seams.
- Plan: tracks 2B, 3B, 3J, 3H. Was: Partially met.

#### PERF-03 · No feedback loops — **Partially implemented**
- Met: writes under hidden paths such as `.build/index-build` never reach a reload (`RepositoryFreshness.swift:245-251`).
  Since `704d7b0`, suppression also covers directory events (Aemi #26), which protects KittyCode's own saves.
- Missing: criterion 2, no test pins the `.build/index-build` loop. Rename detection writes `.git/index` (see "Gaps
  outside every plan"), which triggers one extra `git status`, not a reload. An in-app fetch reloads twice (GDV S3).
- At `ebafb9f`, sourcekit-lsp starts with background indexing off (`108ccea`), which removes the writer behind the
  09-22 loop. Plan: track 2C for the test. Was: Partially met.

#### PERF-04 · Hovering folded headers is free — **Needs visual confirmation**
- A folded card holds no body once the fold ends (`DiffTextKit/CardBodyMount.swift:26-46`), and the hover controller
  does nothing without content (`DocHoverController.swift:141-145`). Tests: `DocHoverControllerTests` "pointerMoved
  with no rendered content does zero resolver or hit-test work"; `CardBodyMountTests` "a card that starts folded mounts
  nothing". The only measurement predates the new container. Was: Met.

#### PERF-05 · Smooth scrolling — **Needs visual confirmation**
- A scroll moves only view origins and layers (`StickyCardView.swift:192-196`, `:214-230`); gutter drawing is bounded
  by the dirty rect (`DiffGutterView.swift:228-254`); card heights are memoized (`StaticTextLayout.swift:97-107`).
- Missing: a measurement in the repository. The 11:22 figures (median 5.8 to 8.5 ms, p95 7.5 to 32 ms per scroll
  step) exist only in the conversation, and that p95 exceeds a 60 Hz frame. Cursor rects are still invalidated on
  every scroll (GDV N4). Findings: GDV B8 fixed by `840d4e1`. Was: Needs visual confirmation.

#### PERF-06 · Few live materials — **Partially implemented**
- Met: no card surface uses a material since `840d4e1` (`CombinedDiffView.swift:372-374`, `:392-399`;
  `StickyCardView.swift:238`); the live surfaces left do not grow with the file count.
- Missing: the status bar keeps `.ultraThinMaterial` with nothing scrolling beneath it (`StatusBarView.swift:25`,
  `ContentView.swift:33-37`), and no test pins the absence of materials. Findings: GDV S5 fixed. Was: Partially met.

#### PERF-07 · The app does not slow the machine — **Needs visual confirmation**
- The measured cause, one material per header and body, is gone (`840d4e1`). The only numbers are in the conversation:
  38.4% before (09-22 17:02); at 11:34, 25 to 34% with the app open against 28 to 32% with it quit, on a baseline
  already near 30%. Was: Partially met.

#### PERF-08 · No unnecessary work — **Partially implemented**
- Met: reuse by blob, a cache per diagnostics tool, an index that skips unchanged content, memoized card heights.
- Missing:
  - Every publish and finish re-reads the hover corpus, even with hover off
    (`DiffComparison/HoverDocumentation.swift:97-139`; `DiffViewerModel+Diagnostics.swift:43-61` never reads the
    setting).
  - A gap step re-renders every card (`RenderPipeline.swift:142-165`).
  - Each comparison change clears every finding (`DiagnosticsModel.swift:73-90`).
  - Each reload re-hashes the working tree up to 8 MiB per file (`AtelierSources/SourceLoader.swift:220-233`).
  - Any change inside `.git` runs a full `git status` with ignored files (`RepositoryFreshness.swift:172`, `:241`).
  - The prepared-diff cache is capped by count (`DiffPreparer.swift:14`, `:69`), and the doc index has no bound.
- Findings: GDV B6, B7, S2, S8, S9, perf-gui fix 4, Core S4, S5, S21. Plan: tracks 2E, 2B, 2D, 2C; the re-hash and the
  `.git` trigger are in no plan. Was: Partially met.

#### PERF-09 · Text first, then diff and color in parallel — **Planned**
- Text appears only after the whole diff model, the intraline pass, the SwiftSyntax tier and every token are computed
  (`DiffRendering/RenderedDiff.swift:46-55`, from `DiffPreparer.swift:100-119`); no stage, budget or fallback exists.
- At `ebafb9f`, track 1H makes the GLR parser terminate, honour cancellation and cap its depth, and removes its
  per-token stack copies (`d74c4f6`, perf-core G1, which fix plan track 3F had planned). The pipeline itself has not
  started.
- Plan: Wave 3 tracks 3A to 3K, then the text-first pipeline P1 to P3. Was: new.

### JSON: AemiJSON

#### JSON-01 · Benchmark Foundation against AemiJSON — **Planned**
- No JSON benchmark is in the repository; the gated benchmarks cover hashing, lexing and the pipeline. The 09-21
  numbers came from a scratch package, and `6c6ddd8` removed them from `AtelierLSP/JSONRPC.swift`; only "about seven
  times slower" remains (`AtelierDiagnostics/SARIFDecoder.swift:6-7`). The migration's harness sits in
  `/private/tmp/w1json-bench`, uncommitted and not gated.
- Plan: roadmap "In flight"; no fix-plan track. Was: Partially met.

#### JSON-02 · Fast paths to the largest extent — **Partially implemented**
- Met: SARIF walks AemiJSON's tape (`SARIFDecoder.swift:16-37`); JSON-RPC reads `method` and `id` off the tape
  (`AtelierLSP/JSONRPC.swift:156-172`).
- Missing: each response is parsed twice, its `result` copied into a new `Data` (`JSONRPC.swift:180`) and parsed
  again (`AtelierLSP/LSPConnection.swift:62-63`); the `initialize` reply is decoded and discarded
  (`SourceKitLSPService.swift:214-216`); no per-call-site verdicts with numbers. JSON-04 makes "adopt" every verdict.
- Findings: Aemi #16 (needs a decode-from-node API in AemiJSON), #28 (track 2F). Was: Partially met.

#### JSON-03 · AtelierLSP on AemiJSON — **Implemented**
- `AemiJSON.JSONEncoder` for envelopes (`JSONRPC.swift:121-140`), `AemiJSON.parse` for incoming messages (`:156-182`),
  `AemiJSON.JSONDecoder` for results (`LSPConnection.swift:20`, `:62-63`). Tests: `JSONRPCTests` (8),
  `LSPConnectionTests` (9). Was: Met.

#### JSON-04 · All JSON through AemiJSON — **Partially implemented**
- Met at `ebafb9f`, criteria 1, 2 and 4: no production code calls `JSONDecoder`, `JSONEncoder` or
  `JSONSerialization` from Foundation any more. `f06b291`, `4b84c84` and `475fc93` moved the grammar loader, settings,
  project overrides, recents and KittyCode's manifests, compiled-table cache and symbol writer; `da05476` moved
  KittyCode's configuration and symbol catalog; `45dce85` moved the language-server policy's read. Data Foundation wrote
  still loads, and recents keep URLs as Foundation's strings. Decoders of hand-edited and stored JSON cap nesting at
  64 (`DiffComparison/DefaultsJSON.swift:10`, `KittySyntax/SyntaxJSON.swift:10`, KittyCode's configuration).
- Tests: `DefaultsJSONCompatibilityTests` "settings Foundation's encoder wrote load unchanged";
  `GrammarRegistryJSONTests` "tables Foundation's encoder cached decode to the same tables"; `GrammarLoaderJSONShapeTests`
  "nesting at the depth limit loads and one level deeper is invalid JSON".
- Missing: criterion 3, no before and after measurement is committed (the migration's harness is in
  `/private/tmp/w1json-bench`). The LSP decoder, which reads sourcekit-lsp's replies, has no depth cap (Aemi #6,
  track 2F).
- Findings: Core N6 fixed (no `[String: Any]` left in the grammar loader). Was: new.

### MOD: Modularization

#### MOD-01 · Generic parts in the core — **Partially implemented**
- Met: diagnostics, the language-server client, the doc index, file watching and git live in core targets.
- Missing: the dead app `TieredHoverProvider` (`DiffComparison/HoverDocumentation.swift:10-26`), `renderHoverMarkdown`
  called only from tests (`DiffComparison/HoverMarkdownRenderer.swift:6`), hover structuring in the app
  (`DiffRendering/HoverMarkdownStructurer.swift`), KittyCode's `GitStatusProvider` and grammar corpus.
- Findings: GDV S20, Kitty S5, S6. Plan: tracks 2E, 4A, 4B; `renderHoverMarkdown` and hover structuring in no plan.
  Was: Partially met.

#### MOD-02 · Plug and play between terminal and GUI — **Partially implemented**
- Met: both apps share the core watcher and `GitClient`; the watcher's queue label is neutral (`8fd26e5`).
- Missing: `GDV_*` variables (`AtelierDiagnostics/DiagnosticTool.swift:40-45`, `AtelierGit/GitClient.swift:194`,
  `AtelierProcess/PhaseTrace.swift:9`) and the `com.kittytui.search` logger (`AtelierSearch/RegexMatcher.swift:6`);
  KittyCode polls git every 10 s (`KittyWorkspace/GitRefreshManager.swift:33-39`); no module map of tiers and
  consumers (`Apps/GitDiffViewer/docs/gaps-and-modularization.md:22` still says GitDiffViewer watches nothing).
- Findings: Core S16, Kitty S1, S5. Plan: tracks 4C, 4B; the module map in no plan. Was: Partially met.

#### MOD-03 · Tier rules in the core — **Planned**
- Five unstructured tasks remain, unchanged at `ebafb9f`: `AtelierProcess/ProcessSession.swift:82`,
  `AtelierLSP/LSPConnection.swift:38`, `:101`, `:110`, `AtelierLSP/SourceKitLSPService.swift:247` (`:267` at
  `ebafb9f`). No core target uses `TaskProvider`.
- Findings: Core S1, Aemi #29. Plan: track 4E. Was: Not met.

### QUAL: Code quality, reviews and safety

#### QUAL-01 · Latest APIs — **Partially implemented**
- Met: swift-subprocess, typed throws in `LSPFrameCodec` and `SARIFDecoder`, `@concurrent`, `Mutex`, Liquid Glass tabs.
- Missing: SE-0475 `Observations` (the settings keep a hand-written observer list, `ViewerSettings.swift:113-116`);
  untyped throws in `AtelierDiagnostics/DiagnosticsEngine.swift:98` (Core N9); the hover panel is not
  `NSGlassEffectView` (HOVER-08). Plan: none. Was: Partially met.

#### QUAL-02 · Codex review — **Implemented**
- `codex_exec` with `gpt-6-astra`, read-only, effort `xhigh`, 23 findings (`/tmp/codex-review.md`); `c10d36e` answered
  22; finding 15 is track 4E, and finding 10's rest is track 2B. Was: Met.

#### QUAL-03 · Strip verbose comments — **Partially implemented**
- Met: the 13 sweep commits are on `main` and change only comments and blank lines.
- Missing: the four files the sweep excluded (`CombinedDiffView`, `TabBarView`, `ChangeBadge`, `DiffDetailView`) had
  no sweep pass; feature commits have rewritten them since. Plan: track 4F. Was: Partially met.

#### QUAL-04 · Requirements book, plan and audit — **Implemented**
- `c375952`, extended by `d662777` and `5128a14`. This revision is QUAL-10. Was: Met.

#### QUAL-05 · Code review of the codebase and owned dependencies — **Implemented**
- `docs/reviews/2026-09-23-codebase-review.md` (`11ddbb6`): 204 findings over the three packages, aemi, AemiJSON, the
  analyzers and hooks, and security, with four verification passes. Risk: the area reports live only in
  `/tmp/reviews`. Was: Met.

#### QUAL-06 · Definition of Done — **Partially implemented**
- Force unwraps in production code: 1 left, `AtelierProcess/ProcessSession.swift:257` (Core N1, track 4E).
- Forbidden waits: 9 left at `ebafb9f`: `GitDiffViewerTests/SideStateFetchTests.swift:99`, `:157` (track 2C);
  `HoverDocumentationTests.swift:114`, `:149`, `:174`, `:210` (2E); `AtelierLSPTests/SourceKitLSPServiceTests.swift:32`,
  `SDKDocumentationProviderTests.swift:23` (2F); `AtelierProcessTests/ProcessSessionTests.swift:63` (4E).
- Test names: every test added since `10ae905` is a sentence; the 62 camelCase tests revision 1 counted remain.
- Silent catches: 5 left, for example `DiffComparison/HoverDocumentation.swift:20-22` and
  `AtelierLSP/LSPConnection.swift:160-163` (tracks 2E, 2F).
- Documents that contradict the code: the roadmap (PROC-06); `DiffViewerModel.swift:147-148` and
  `RenderPipeline.swift:99-101` (GIT-03); `hover-panel-design.md:7-8`; `gaps-and-modularization.md:22`, `:26`, `:34`;
  `hig-liquid-glass-plan.md:14`, `:20`; `AGENTS.md:49` (PROC-02); `ChangeBadge.swift:132-134`; `GitClient.swift:25`
  ("no optional index locks", which rename detection contradicts).
- One untracked deferral: `AtelierDiagnostics/ToolLocation.swift:9` ("unused today"). Commit titles: PROC-09. Was: Not
  met.

#### QUAL-07 · Untrusted repositories cannot run code — **Needs visual confirmation**
- Criterion 1, at `ebafb9f`: a repository's root reaches sourcekit-lsp only once the user trusts it; the policy admits
  a session per real root (`DiffComparison/LanguageServerPolicy.swift:61` at `ebafb9f`), and every session starts with
  background indexing off (`f94d3be`, `3bdb404`, `108ccea`; Sec C1 fixed). Tests: `LanguageServerTrustGateTests` "an
  untrusted root never reaches the language-server factory, and hover still answers from the doc index", "a declined
  repository neither starts a session nor asks again", "revoking trust stops the running session and every new one".
- Criterion 2, at `ebafb9f`: before git runs in a repository, its own configuration is read and judged against an
  allowlist of inert keys, and any other key refuses the command (`AtelierGit/GitConfigPolicy.swift:112` at
  `ebafb9f`); read commands and fetch carry pins against signatures, filters and transports (`GitIsolation.swift:66-99`
  at `ebafb9f`) (`ab38879`; Sec C2, H1 fixed). Tests: `GitConfigPolicyTests` (12); `GitHostileRepositoryTests`, one
  hostile repository per vector, for example "a filter driver never runs during the working-tree rename diff", "a
  credential helper the repository chose never runs", "an insteadOf rewrite of the fetch URL never runs".
- Criterion 3: hover prose keeps only `https` links, and every text view of the panel refuses the rest
  (`DiffRendering/HoverDocument.swift:147-167`; `DiffTextKit/HoverDocPanel.swift:89-93`, `:440-457`, `:517-532`). Tests:
  `HoverLinkTests` (5). Sec M1 fixed by `bbaf80f`. For KittyCode, every cell writer stores control characters as a
  replacement glyph (`05aaf11`, Sec H2).
- Criterion 4, at `ebafb9f`: the first hover in an unknown repository asks once, in an alert
  (`GitDiffViewer/Views/RepositoryTrustPrompt.swift`); doc comments and SDK documentation answer meanwhile, since the
  SDK tier does not depend on trust (`DiffComparison/HoverDocumentation.swift:174` at `ebafb9f`); Settings ▸ Tools
  lists trusted repositories with a Revoke button (`GitDiffViewer/Views/TrustedRepositoriesSection.swift:23`). Test:
  `LanguageServerTrustGateTests` "a hover in an unknown repository asks the user once".
- To check by eye, on a build of `ebafb9f`: the alert, the Settings list, and SDK documentation in an untrusted
  repository, which no test covers. The installed 13:52 build has none of criteria 1, 2 and 4. Was: Not met.

#### QUAL-08 · A measured rendering-performance review — **Implemented**
- `/tmp/reviews/perf-gui.md`, `perf-tui.md` and `perf-core.md`, consolidated in review §7 and scheduled as Wave 3. Risk:
  the builds and patches behind the numbers (`/tmp/gdv-perf`, `/tmp/kc-src`) were deleted. Was: new.

#### QUAL-09 · A clone cannot get its own hook binary run — **Partially implemented**
- Met: `~/.git-templates/hooks/pre-commit` and `pre-push` try only `~/.local/bin/project-hooks` and `command -v`; the
  31 clones under `~/Developer` were patched at 12:35; `~/project-hooks-ph6-backup.tar.gz` holds the 64 originals.
- Missing: six clones outside `~/Developer` still try `$REPO_ROOT/.build/release/project-hooks` first: under `~/Public`,
  `~/Downloads` (two), `~/.codex`, and two work-repository clones. The installed `~/.local/bin/project-hooks` dates from
  05-12 and has no PH fix. Plan: OQ3; track 1K not started. Was: new.

#### QUAL-10 · Re-gather, re-assess, ask — **In progress**
- This revision of `book.md`, `plan.md` and `audit.md` meets the three criteria; it is uncommitted, and the open
  questions await the user. Was: new.

### DIFF: Diff interaction refinements

#### DIFF-01 · Resizable panes — **Planned**
- The single-file panes sit in a fixed stack with a plain `Divider()` (`GitDiffViewer/Views/DiffDetailView.swift:113-121`);
  no drag, no stored ratio. Plan: roadmap "Diff interaction refinements" item 1, "not scheduled yet" (OQ8). Was: new.

#### DIFF-02 · Predictable gap drags — **Planned**
- `adjustGap` reveals from the change above when dragged down and from the change below when dragged up
  (`DiffComparison/RenderPipeline.swift:156-165`), so dragging back reveals more; one grip per gap
  (`DiffTextKit/DiffGutterView.swift:139-150`); no edge auto-scroll.
- Findings: GDV B7, S1 share `adjustGap`. Plan: roadmap item 2; the fix plan offers it to track 2B (OQ8). Was: new.

#### DIFF-03 · Gutter scope ribbon — **Planned**
- No scope or fold code in the gutter. Reference: images 13 to 18. Plan: roadmap item 3. Was: new.

#### DIFF-04 · Compact inline view — **Planned**
- `ViewMode` has inline, split and stacked only (`DiffComparison/ViewerSettings.swift:9-14`). Plan: roadmap item 4.
  Was: new.

#### DIFF-05 · Xcode as the visual reference — **Implemented**
- The playground at `~/Developer/experimental/010.xcode-diff-playground` holds committed, staged, unstaged,
  untracked, renamed and deleted changes; `Apps/GitDiffViewer/docs/xcode-reference.md` describes images 12 to 21,
  stored under `docs/assets/xcode-reference/` (`fd55a20`); the rename decision is in CARD-09 (`5128a14`).
- Gap: images 22 and 23 are not in the repository, and the reference has no rename section. Was: new.

### REND: A text renderer of our own

#### REND-01 · A measured design — **Implemented**
- `docs/design/text-renderer.md` (`47f2985`) answers "Do the panes use the latest TextKit? Yes", with evidence that
  still holds (`DiffTextKit/DiffTextView.swift:71`, `:78`; the one TextKit 1 object at `DiffRendering/DiffPalette.swift:59`);
  measures TextKit 2 as used, TextKit 2 used correctly and a CoreText prototype on the same inputs (§2); lists what
  a replacement must rebuild (§1.2, §6.1); and gives phases M0 to M3 with gates (§5). The lab is in
  `/tmp/text-renderer-lab`. Was: new.

#### REND-02 · The renderer's qualities — **Designed**
- The design covers each criterion: typed styles (§3.2), UTF-8 with UTF-16 only at boundaries and grapheme-snapped
  hit-testing (§3.2, §3.7, §3.9), fonts in full (§3.7), strict concurrency (§3.10), a diff-free engine (§3.1), Dynamic
  Type where the platform scales text and ⌘+ and ⌘− on the Mac (§3.8), and a prototype 3.4 to 6.7 times faster per new
  document than TextKit used correctly (§2.2). No renderer target exists. Plan: M1, gated by OQ1. Was: new.

#### REND-03 · Pluggable backends — **Needs user decision**
- The seam, the per-window switch and the parity harness exist only in the design (§4). Of M0: items 2 and 3 landed
  in `840d4e1`, item 4 (the wrapped-height memo) in `ce0880c`; item 1 is still open, since `ce0880c` still sets new
  text into the live storage without emptying it first (`DiffTextView.swift:233-237`); items 5 to 13 are open.
- Decision: OQ1 (fix plan §7.4). Was: new.

## Visual confirmation checklist

The installed app (13:52, from `ce0880c`) runs checks 1 to 19; checks 20 and 21 need a build of `ebafb9f`. Three
setups:
- **A, long cards:** `open -n ~/Applications/GitDiffViewer.app --args -repo ~/Developer/Atelier -leftRef 10ae905 -rightRef ce0880c`;
  View options ▸ File explorers ▸ "One merged tree in a sidebar"; Layout Inline (⌘1). The card
  `Apps/GitDiffViewer/Sources/GitDiffViewer/Views/CombinedDiffView.swift` is several screens tall; clicking a folder
  opens a tab and shows the tab bar.
- **B, the Xcode playground:** `open -n ~/Applications/GitDiffViewer.app --args -repo ~/Developer/experimental/010.xcode-diff-playground`
  (HEAD against the working tree); Settings ▸ Appearance ▸ Badge colors: Xcode. It holds a staged `A`, `D`, `M` and
  rename, an unstaged `M` and `D`, an `MM` file and an untracked file.
- **C, diagnostics:** in setup B, Settings ▸ Tools ▸ turn on "Analyze changed Swift files" and wait for the counts.

Cards and badges:
1. **CARD-02, CARD-03, CARD-12 (setup A).** Scroll until the long card's header pins: its top sits 16 pt below the
   toolbar, with rounded top corners and one shadow; no body text shows in the gap or at the corners; body text ends
   at the header's bottom edge under a hairline; the card's end pushes the header out. Click a folder so the tab bar
   shows: the header now rests 16 pt below the tab bar. Repeat in Side by side (⌘2).
2. **CARD-04, CARD-05, CARD-06 (setup A).** At rest each card is one rounded shape with one border, one shadow and one
   light seam; at the top of the list the scroll bar and the shadows draw in full; a pinned header shows no square of
   material and no doubled shadow.
3. **CARD-07, CARD-08, CARD-13 (setup A).** Click the long card's header: the compress glyph morphs into expand; the
   bottom edge rises over about 0.2 s with the text staying in place and cut by the edge; no gray band; the gap to the
   next card stays 16 pt. Click again: the text is there as the edge comes down. Collapse all: equal gaps.
4. **CARD-14, CARD-16 (setup A, ⌘2).** Scroll the whole list, fold and unfold the long card and a short one, with
   Wrap lines on and off, and resize the window: no card changes height while scrolling, the list never blanks, the
   app never quits. Then run `log show --last 10m --predicate 'subsystem == "fr.gcqd.GitDiffViewer" AND category == "cards"'`:
   no "measured" fault.
5. **CARD-15 (setup A).** With the cards showing, press ⌘3: nothing happens, the Stacked segment is gray with "Stacked
   is available for a single file", and the cards stay side by side. Click a file: the picker shows Stacked and the
   file draws stacked.
6. **CARD-10, SET-07 (setup B, merged tree).** Click `SyncEngine.swift`: white outline and white "M", no fill. Click
   `Inventory.swift`: white fill, blue "M". Click `Scratch.swift`: white outline and "A". Click into the diff: gray
   selection, normal badges. Switch Badge colors between Classic and Xcode with the window open: explorer rows, card
   headers and their tint, a tab, the status bar and the toolbar's current-file item change at once.

Hover (setup B):
7. **HOVER-02.** On the `Inventory.swift` card, rest on `itemsMatchingRule3` (line 75): a panel shows its declaration
   and "Returns the items matching rule 3, sorted by name." Rest on the removed line's `itemsMatchingRule20`: the old
   side answers. Repeat in ⌘2, and in a tab opened by double-clicking the header, in ⌘1, ⌘2 and ⌘3.
8. **HOVER-07, HOVER-12.** Rest on `Item` (line 75): the panel is the declaration box plus one line of prose, in the
   system font, the box lightly outlined. Rest on `ItemRow` in `ContentView.swift`: only the box and "No
   documentation".
9. **HOVER-10.** In a tab of `ContentView.swift`, rest on `View` (line 3), slide along it, into the panel and back:
   it stays open; moving to blank space closes it.

Diagnostics (setup C):
10. **DIAG-04.** The status bar shows a spinner, then the warning and error counts; the tooltip lists each tool.
    Save a new violation: the count changes.
11. **DUI-04.** In a tab, click a tinted line number near the top, then one near the bottom: each popover's arrow
    points at its line. The toolbar's Findings button stays hidden, which confirms GDV B9 (DIAG-05, DUI-01).
12. **DIAG-06.** In each of the two work repositories, compare the per-tool counts in the tooltip with
    `swiftlint lint --quiet` and `swiftformat --lint .` run at the root, counting only the changed Swift files.

Settings, tabs and windows:
13. **SET-04, SET-06.** Settings ▸ Appearance: turn off "Match window appearance to theme"; Dark and Light switch
    every window at once; System follows macOS. Turn the toggle on with System and a dark theme: every window turns
    dark; Light pinned wins.
14. **TAB-03, TAB-08.** Double-click a file (a kept tab) and click a folder (an italic preview tab): glass capsules
    with round ends, a barely visible shadow, no bar background; the kept tab ends with a pin; the badge sits centered
    in the round end; hovering tints the tab and swaps the badge for an ×; on the × a disc appears, the × centered.
15. **TAB-01.** Open a second comparison from the welcome window (⇧⌘1): it joins the first window as a native tab;
    the welcome window stays apart; the tab bar's + brings the welcome window forward.
16. **WIN-01, WIN-02.** Customize the toolbar (add Diff totals and the Findings item), quit with ⌘Q, relaunch from
    Finder: no crash, and the arrangement returns.

Measurements, to record in the repository:
17. **PERF-05.** With 33 or more expanded files, including a new file of several thousand lines, record Instruments'
    Animation Hitches while flinging the list end to end, wrapping off then on: no hitches, and main-thread time per
    frame within 8.3 ms at p95 on 120 Hz.
18. **PERF-04.** Collapse all, attach the Time Profiler, and move the pointer over the folded headers for 10 s: no
    main-thread samples in `DocHoverController.pointerMoved`, the hit tester, the resolver or text layout.
19. **PERF-07.** Sample WindowServer for 60 s with the app quit (`top -l 30 -s 2 -stats command,cpu | grep WindowServer`),
    and continue only on a single-digit baseline; then 60 s with the app on the main display idle, and 60 s scrolling.
    WindowServer must stay at its baseline.

Security and quit, on a build of `ebafb9f`:
20. **QUAL-07.** Open a repository never opened before and rest on an identifier: an alert asks once whether to trust
    it, and until you answer, doc comments and Apple SDK documentation (for example on `Int`) still appear. Decline:
    no sourcekit-lsp process starts (`pgrep -fl sourcekit-lsp`), and the source menu offers Trust Repository… instead
    of Fetch. Trust it through that item: hover answers from sourcekit-lsp. Settings ▸ Tools lists the repository;
    Revoke stops its server.
21. **PERF-01.** Turn diagnostics on in a large Swift repository and, while the status bar spinner runs, scroll the
    cards and open Settings: the app stays responsive. Quit with ⌘Q during the run: the app exits within a few
    seconds, with no beachball.

## Defects outside every plan

Found or confirmed in this revision; no review finding and no track covers them.
- **Rename detection writes the user's `.git/index`.** `GitClient.renames` runs porcelain `git diff -M` against the
  working tree on every source change (`AtelierGit/GitClient.swift:122-127`, `:155-160` at `ebafb9f`;
  `AtelierSources/SourceLoader.swift:92-94`). Track 1B added `--no-ext-diff --no-textconv` to it, not the index.
  `GIT_OPTIONAL_LOCKS=0` does not stop `diff.autoRefreshIndex`, which rewrites the index when stat data is stale. Found
  by the coordinator at 11:15, confirmed by mechanism, not reproduced. `GitClient.swift:25` says the opposite.
  Candidate fixes, untested: `-c diff.autoRefreshIndex=false`, or `git diff-index`.
- **The ref menus go stale after a commit** while a side sits on a ref (`DiffComparison/DiffViewerModel+Freshness.swift:39-43`;
  GIT-01).
- **Every reload re-hashes the whole working tree** (`AtelierSources/SourceLoader.swift:220-233`; PERF-08).
- **Any change inside `.git` runs a full `git status`** with ignored files (`DiffComparison/RepositoryFreshness.swift:172`,
  `:241`; PERF-08). Since `704d7b0`, entries inside `.git` arrive under their own paths; whether the directory itself
  is still reported is not verified.
- **The card list's hover panel ignores list scrolling** (`DiffTextKit/DocHoverController.swift:65-70` with
  `EmbeddedDiffTextView.swift:56-60`; HOVER-09).
- **Old declarations are listed beside new ones when both sides are refs or a file was renamed**
  (`AtelierDocIndex/DocCommentIndex.swift:83-108`; HOVER-11).
- **The ref side's tree draws unstaged changes filled** (`GitDiffViewer/Views/FileExplorerView.swift:26-27`,
  `DiffComparison/SideState.swift:77-81`; CARD-11).
- **Refresh keeps the discovery caches**, and a cancelled `PATH` probe hands its waiters an empty `PATH`
  (`AtelierDiagnostics/ToolDiscovery.swift:106-111`, `:154-161`; TOOL-01).
- **A tool missing from saved settings shows as enabled but never runs** (`DiffComparison/ViewerSettings.swift:396-405`,
  `GitDiffViewer/Views/ToolsSettings.swift:185`); latent on this machine.
- **Sidebar visibility is shared by every window:** hiding it in one comparison hides it in all
  (`ViewerSettings.swift:169-171`, `GitDiffViewer/Views/ContentView.swift:49-58`).
- **Not verified:** a pinned header may keep its old line when the tab bar appears without a scroll
  (`DiffTextKit/StickyCardView.swift:159-196`; CARD-12).

## Review findings used

Status at `ebafb9f`; "open" means no commit on `main` fixes it.

| Finding | Requirements | Status | Track |
|---|---|---|---|
| GDV B1, S10, S17 | SET-03, SET-05 | Open | 2A |
| GDV B2, B3, S1 | GIT-03, GIT-04 | Open | 2B |
| GDV B4; B5 app half; HEAD-watch defect | GIT-01 | Open | 2C |
| GDV B5 core half; Core B7, B8; Aemi #4, #26, #27 | GIT-01, GIT-05, PERF-03 | Fixed `704d7b0` | 1D |
| GDV B6; Core S4, S5; perf-gui fix 4 | HOVER-03, PERF-08 | Open | 2E |
| GDV B7 | PERF-02, PERF-08, SET-05, DIFF-02 | Open | 2B |
| GDV B8, S5, S6 | PERF-05, PERF-06, CARD-06 | Fixed `840d4e1` | Wave 0 |
| GDV S7 | CARD-14, PERF-05 | Fixed: the wrapped-height memo landed in `ce0880c`, so track 3H's item is done | 3H |
| GDV B9, S9 | DIAG-04, DIAG-05, DUI-01, PERF-08 | Open | 2D |
| GDV S2, S3 | PERF-03, PERF-08, GIT-02 | Open | 2C |
| GDV S4 | SET-04, SET-06 | Open | Unscheduled |
| GDV S8, S19 | PERF-08, WIN-01 | Open | Unscheduled |
| GDV S11; Sec M4 | HOVER-04 | Fixed `9bc07d1`, `3893897` | 1A |
| GDV S14; Sec M1 | HOVER-05, QUAL-06, QUAL-07 | Fixed `bbaf80f` | 1C |
| GDV S18 | DUI-01 | Open | Unscheduled; the book's default puts it in 2D |
| GDV S20 | MOD-01, HOVER-01 | Open | 2E |
| GDV N4 | PERF-05 | Partial `840d4e1` | Unscheduled |
| GDV N5; Sec M5 | TOOL-03, PROC-03 | Open | 2O |
| Review §5.2 item 1 (hover chip) | HOVER-06, HOVER-14 | Open | 2E |
| Core B9 | HOVER-04 | Open | 2F |
| Core B10, S6, S24; Sec L1 | TOOL-01 | Fixed `bfe8d1d` | 1J |
| Core S1; Aemi #29 | MOD-03 | Open | 4E |
| Core S15 | GIT-05 | Fixed `8fd26e5` | Wave 0 |
| Core S16 | MOD-02 | Partial `8fd26e5` | 4C |
| Core S23; A-1, D-2, W-3, A-5 (Atelier side) | DIAG-01, DIAG-06 | Fixed `2342755` | 1I |
| Core S25 | QUAL-06 | Partial: 9 of 14 waits left | 2C, 2E, 2F, 4E |
| Core N1, N9 | QUAL-06, QUAL-01 | Open | 4E; unscheduled |
| Core N6 | JSON-04 | Fixed `f06b291` | Outside the plan (the JSON migration) |
| Kitty B3 to B6 | PROC-11 | Fixed `2c44008`, `112a632` | 1E |
| Kitty B7 to B9, B11; Sec H2 | PROC-11, QUAL-07 | Fixed `718c75c`, `05aaf11` | 1F, 1G |
| Kitty B10, S15 | PERF-02 | Open | 3B, 3J |
| Kitty S1, S5, S6 | MOD-01, MOD-02 | Open | 4B, 4A |
| Aemi #5 | PERF-01 | Fixed on Atelier's side, `9a41cf1` | 1A |
| Aemi #6, #28 | JSON-04, JSON-02 | Open | 2F |
| Aemi #16 | JSON-02 | Open | Unscheduled; needs AemiJSON (PROC-12) |
| Aemi #24 | PROC-12 | Open | 2O |
| D-1, W-2 | DIAG-01 | Open, external | §7.1 |
| PH-2 | PROC-02 | Open, external | §7.1 |
| PH-5, PH-7 | PROC-04, PROC-05, PROC-10 | Open, external | §7.1 |
| PH-6 | QUAL-09 | Mitigated locally for 31 clones; open in project-hooks | 1K |
| Sec C1, L2 | QUAL-07, HOVER-01, TOOL-02, SET-03 | Fixed `f94d3be`, `1ad6cd4` | 1A |
| Sec C2, H1 | QUAL-07, GIT-02, CARD-11 | Fixed `ab38879` | 1B |
| Review §5.1 parser defects; Core B2 parts 2 and 3, B3 | PERF-09 (engine) | Fixed, track 1H (`47c628c` to `54e5a73`) | 1H |
| Sec L3 | DIAG-08 | Open | Unscheduled |
