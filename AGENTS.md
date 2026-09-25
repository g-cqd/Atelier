# Working in Atelier

## Packages and tiers

| Tier | Packages / targets | Runtime | Tests |
|---|---|---|---|
| Core (kernel) | every library in `Packages/AtelierCore` | `AemiRuntime` (`BlockingOffloadPool`, `LiveClock`, `mapConcurrently`); an injected `any Clock<Duration>`; **no unstructured tasks and no `TaskProvider`**: a core service exposes `async` functions, task groups and `AsyncStream`s the caller drives | `AemiTestKit` |
| App models | `Apps/GitDiffViewer` (`DiffComparison`, `DiffTextKit`, `DiffRendering`, app), `Apps/KittyCode` (`KittyWorkspace`, `KittyEditor`, `KittyApp`, `KittyWidgets`) | `AemiCore` (`TaskProvider`, `DefaultTaskProvider`) plus an injected clock | `AemiTesting` (`TaskProviderSpy`, `TestClock`, `AsyncProbe`, `CountProbe`) |
| Terminal kernel | `KittyTerminal`, `KittyCodecs`, `KittyInput`, `KittyRenderer`, `KittyStyle` | none, or `AemiRuntime` | `AemiTestKit` |

`AemiCore` and `AemiRuntime` both define `TaskProvider` and `TaskRole`; `AemiTesting` and `AemiTestKit` both
define `TestClock`, `TaskProviderSpy` and `AsyncProbe`. Never import both families unqualified in one file. An
app-tier file that needs a runtime helper imports it scoped: `import func AemiRuntime.mapConcurrently`.

One `BlockingOffloadPool` per app, created in the composition root and injected; the core never creates a global one.

## Shared building blocks

- Diffing goes through `AtelierDiff`: `LineDiff.diffLines(old:new:pipeline:)` over any `DiffSource` (a rope, a
  mapped file, `SubstringLines`, `ByteLines`); `LineChangeMarkers` turns an edit script into gutter marks. No other
  diff code lives in the umbrella.
- Highlighting goes through `HighlightEngine` (`AtelierSyntaxModel`): the scanners are `LexicalHighlightEngine`
  (`AtelierLexers`, UTF-8 or UTF-16 units, `.lexical` layer), the grammar stack is the `.structural` layer. Tokens
  are `HighlightToken`s with `HighlightRole`s; `LineTokens` splits them per line into one flat buffer; themes are
  `SyntaxTheme`s keyed by role (`AtelierTheme`), bridged to `NSColor`/`Style` only in the apps.
- Subprocesses go through `AtelierProcess.ProcessRunner`; git through `AtelierGit.GitClient` and the pure
  `GitParsers`; tests script them with `AtelierTestSupport.FakeProcessRunner`.

## Tests

- Swift Testing only. One behaviour per test; names in backticks read as sentences.
- Waiting is event-driven: `TestClock.waitForSleepers` then `advance`, `TaskProviderSpy.waitForAllTasks`,
  `AsyncProbe`, `CountProbe`, observation tracking. No `Task.sleep`, `Task.yield`, polling or wall-clock assertions.
- Benchmarks are env-gated (`GDV_BENCH`, ordo-one suites) and never run in the default `swift test`.
- A GitDiffViewer suite on the main actor carries `@Suite(.mainActorLane)` (`MainActorLane.swift`): it lets two
  main-actor test cases run at once, so a test's waits measure its own work rather than the queue of every other
  test's main-thread work, which at a load of 50 and more failed hundreds of bounded waits together.
- Main-actor tests share the one main thread, so a run lasts at least as long as their main-thread time added up,
  and under load their bounded waits fail together. A GitDiffViewer suite takes at most 1 s of it on an idle
  machine: compare pixels by their bytes before making colours, put pure sweeps in a suite that is not a main-actor
  one, and read the file system off the main actor. After adding a test that draws, lays out, sweeps or reads files
  on the main actor, make your final GitDiffViewer suite run the budget run:
  `Apps/GitDiffViewer/scripts/main-actor-budget.sh` runs the whole suite with the main thread sampled, ranks the
  suites by their main-thread time and fails past the budget. Run it once, after rebasing onto `main`, with
  `work run --weight 8`: an exclusive job now waits at most a minute and then holds only new heavy jobs, for three
  minutes at most, so two lanes' budget runs no longer overlap and inflate each other. The coordinator does not run
  it again. A suite over the 1 s budget only under load: rerun once, and report both runs if it is over twice. It exits 2 with "no usable sample" when
  `sample` fails to attach to the test process; that says nothing of the suites, so run it again.

## Builds, hand-back and worktrees

The global rules apply (`engineering-practices` §5, `planner` Orchestration Mode): build once per completed step,
in one configuration, and never check a change against a matrix of configurations; build release once per task.
Here that means:
- **While you work,** build the debug tests of the one package you changed (`swift build --build-tests` in
  `Packages/AtelierCore`, `Apps/GitDiffViewer` or `Apps/KittyCode`), and run filtered tests with `--skip-build`.
- **Before handing back,** rebase onto `main`, build once, and run the full suite of each package you changed. If
  you changed a core target's API, also run the suite of each app whose `Package.swift` links that target. The
  coordinator lands your branch on that run without rebuilding, and asks you to run again, from your warm build,
  only when `main` has since changed the same packages.
- **Worktrees:** at most three, one per lane (GitDiffViewer, core highlighting, parser and grammar), long-lived
  and reused from task to task. Work in the worktree you are given and never create one. Read-only agents
  work in the main checkout without writing to it.

## Moving code between packages

- One move per commit: `git mv` plus the manifest edits, every package green afterwards.
- Promote `package` declarations to `public` in a separate no-op commit *before* the move.
- Shared core targets carry the `Atelier` prefix; targets that stay inside an app keep their names.

## Style and gates

`.swift-format` and `.swiftlint.yml` are aemi's canonical files (`scripts/sync-config.sh` in aemi); they are
copied into every package directory because the CI gate checks them per package. Every target compiles in Swift 6
language mode with warnings as errors and the `ExistentialAny`, `InferIsolatedConformances`,
`InternalImportsByDefault` and `MemberImportVisibility` features on.

Use `xcrun swift` when the `swift` on PATH is a swiftly shim without a selected toolchain.

## Work order and waiting

- The work runs first in, first out, validity first (book PROC-13). A regression that breaks validity is fixed
  before its work lands. One that costs only performance joins the work queue, section 9 of
  `docs/reviews/2026-09-23-fix-plan.md`, with its measurement and origin, and the work lands.
- `planner`'s `scripts/order_tasks.py` orders a task list by that rule, and plans several agents' work so that no two
  run on overlapping files at once.
- Never wait on a build, a test run or an agent with a fixed sleep. Start long commands in the background and let
  the harness report their end, or use `engineering-practices`' `scripts/wait-for.sh`, which returns the moment the
  work ends. The suites here take minutes; a fixed sleep either wastes them or checks too early.
