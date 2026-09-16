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

## Tests

- Swift Testing only. One behaviour per test; names in backticks read as sentences.
- Waiting is event-driven: `TestClock.waitForSleepers` then `advance`, `TaskProviderSpy.waitForAllTasks`,
  `AsyncProbe`, `CountProbe`, observation tracking. No `Task.sleep`, `Task.yield`, polling or wall-clock assertions.
- Benchmarks are env-gated (`GDV_BENCH`, ordo-one suites) and never run in the default `swift test`.

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
