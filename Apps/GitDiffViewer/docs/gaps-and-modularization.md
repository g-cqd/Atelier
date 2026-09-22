# Gaps and modularization findings (2026-09)

## Toolbar persistence (bug)
Saving works (both defaults domains carry real `NSToolbar Configuration main.2` payloads); the
failure is re-apply. Causes, by confidence: (1) two defaults domains — bundled
`fr.gcqd.GitDiffViewer` vs unbundled `GitDiffViewer` (swift run) hold different arrangements;
(2) the customizable toolbar is attached only after `model` exists (`ComparisonWindow` shows a
ProgressView first), so NSToolbar restores before `.toolbar(id:)` exists → default set;
(3) latent: `explorerPlacement == .top` mutates the default identifier set (`.toolbar(removing:
.sidebarToggle)`), which invalidates saved configs. Fix: toolbar present on first body
evaluation; stop mutating the default set conditionally.

## Repo selector asymmetry
One symmetric control; the asymmetry is the model's: right side becomes `.directory(root)` for
the working tree, rendered as parent-folder + folder-name + folder icon, while left renders
repo + ref + branch icon. Fix: a `SourceDescriptor` (symbol/context/primary/detail) in
`AtelierSources` next to `displayName`, taking `RepositoryInfo?`, so `.directory(url == repo
root)` reads "<repo>  Working Tree" with the branch icon; toolbar control, status bar, and
window title all map from it.

## Watchers
GitDiffViewer watches nothing; refresh is manual via `reloadSources()`. KittyCode's
`FileWatcher` (FSEvents + per-file DispatchSources, actor, AsyncStream, 0.1 s latency,
self-write suppression) moves to `AtelierFileTree` after stripping its `AemiCore.TaskProvider`
use (2 sites → consumer-driven stream, per the core-tier rule). Wire in `DiffViewerModel`:
working tree → debounced 500 ms `right.reload()` (must exceed DiagnosticsSession's 250 ms);
`.git/HEAD` → branch switch reload; `refs/**` + `packed-refs` → repository-info refresh.
KittyCode's polling `GitRefreshManager` deletes afterwards.

## Git surface
`GitClient` wraps 13 read commands; no fetch/remotes/ahead-behind; `references` is private and
`RepositoryInfo` is read once per comparison (menus go stale). Add `fetch(remote:refspecs:
prune:)` (relaxed isolation case keeping SSH_AUTH_SOCK/HOME + GIT_TERMINAL_PROMPT=0; long
explicit timeout; checked args + --end-of-options; NOT on the width-4 diff pool),
`remotes()`, `aheadBehind(_:_:)` with pure GitParsers; app adds `refreshRepositoryInfo()`.

## Per-project settings
Identity: SHA-256 of the resolved repo-root path (readable path kept in payload); overlay via
`ViewerSettings.projectID` + scoped key fallback (`project.<hash>.<key>` → base key), one
instance per comparison window; Settings window edits base only + "overridden in N projects"
review affordance. Project-scope candidates: diagnosticsEnabled, toolLocations,
lspServerLocations, contextLines, showsChangesOnly, showsIgnoredFiles, diffHeuristics,
treeStyle, analyzed sides. Global-only: theme/fonts/layout chrome.

## Modularization map (cost)
- FileWatcher → AtelierFileTree, strip TaskProvider (S/M). Unblocks watchers.
- DiagnosticsSession: confirmed AGENTS core-tier violation (AemiRuntime TaskProvider). Reshape
  to `analyze(_:) -> AsyncStream<Update>`, caller owns task + debounce; delete
  RuntimeTaskProviderBridge (M).
- TieredHoverProvider → AtelierLSP (S); renderHoverMarkdown → core structure pass +
  app-side font (S).
- Grammars corpus (3 MB) → AtelierGrammar resources; 5 Bundle.module call sites repointed (M).
  Win: syntax-tier intraline granularity for every grammar language in GitDiffViewer.
- ToolIdentity decoupling from the closed DiagnosticTool enum + GDV_ env prefix parameterized
  (M/L, needs defaults migration).
- GitStatusProvider → AtelierGit after FileStatusProvider moves (M); GitRefreshManager deletes.
Move protocol: promotion commit → git mv + manifests per move, each package green after each.
