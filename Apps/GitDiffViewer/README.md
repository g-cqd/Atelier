# GitDiffViewer

A macOS diff viewer for Swift, Objective-C, text and HTML files, built on TextKit 2. Requires macOS 26.1.

Each side of the comparison is an independent target with its own file explorer:

- a single file
- a folder
- the working tree of a git repository
- a branch, tag or commit of a repository (type any ref in the text field)

Files with the same relative path are compared across the two sides; two single files are compared with each other. The
explorers badge files like the file cards do: A added, D deleted, M modified, R renamed; a folder carries a lighter badge
for the aggregate of its files.

Options bar:

- **Changed files only** keeps just the folders leading to files that differ.
- **Ignored files** lists the files git ignores in a section of their own, below the compared files, so a build
  output or a lock file can be looked at on demand; they never count as changes. A working tree is listed the way
  git sees it: tracked and untracked files, dotfiles included, nothing ignored.
- **Wrap lines** wraps long lines; in the side-by-side layout, paired rows keep the same height on both sides.
- **Highlight changes by** picks the intraline emphasis tier: characters, words, or syntax. The syntax tier uses
  swift-syntax tokens for Swift and a code-aware lexer elsewhere, so renaming `count` to `total` marks the whole
  identifier instead of the two letters that differ.

## Welcome window

Launched from the Finder or the Dock, the app opens with a welcome window: open a repository and pick the two refs
to compare (or one ref and the working tree), compare two folders or two files, open a patch, or pick one of the
recent comparisons. Every comparison gets a window of its own; closing the last one brings the welcome window
back, as does File ▸ Welcome to Git Diff Viewer (⇧⌘1). A launch with paths on the command line skips the welcome.

## Requirements and dependencies

Xcode 27 (Swift 6.4) and macOS 26.1. Every target compiles in Swift 6 language mode with warnings as errors and
the `ExistentialAny`, `InferIsolatedConformances`, `InternalImportsByDefault` and `MemberImportVisibility`
features on.

| Package | Used for |
|---|---|
| [aemi](https://github.com/Aemi-Studio/aemi) (`main`) | `AemiCore` task provider behind every spawned task; `AemiRuntime` blocking pool for git and clock seam for timings; `AemiIO` memory-mapped blob hashing; `AemiTesting` test clock, probes and task-provider spy |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) (604) | The syntax tier of the intraline emphasis for Swift |

Formatting and the size and complexity gates follow aemi's canonical `.swift-format` and `.swiftlint.yml`
(`scripts/sync-config.sh` in aemi copies them); CI is aemi's reusable `swift-quality` workflow.

## Run

```sh
./scripts/bundle.sh                                     # release build with its helpers in .build/GitDiffViewer.app
open .build/GitDiffViewer.app                           # HEAD vs working tree of the current directory's repository
open .build/GitDiffViewer.app --args -repo path/to/repo
open .build/GitDiffViewer.app --args -repo path/to/repo -leftRef main -rightRef feature/x
open .build/GitDiffViewer.app --args -left a.swift -right b.swift
open .build/GitDiffViewer.app --args -left folderA -right folderB
open .build/GitDiffViewer.app --args -patch changes.patch     # a unified diff or git patch file
swift run GitDiffViewer -repo path/to/repo              # debug build, same flags
```

Paths are passed as `-key value` flags: AppKit opens positional arguments as documents, and SwiftUI then skips
the main window.

In the explorers, the arrow keys move the selection and open the file in the temporary tab, return pins it, space folds
or unfolds a folder, and typing a name jumps to it. `⌃⌘S` shows or hides the sidebar in the sidebar placements.

`⌘1` inline layout, `⌘2` side by side, `⌘⇧↓` / `⌘⇧↑` next / previous change. `⌘O` opens a `.patch` / `.diff`
file, as does dropping one on the window: every file of the patch becomes a card, with the old side on the left and
the new side on the right. A patch only carries the hunks, so lines outside them are shown blank when a gap is
expanded; line numbers are the real ones.

## Bundle

`scripts/bundle.sh` builds the release app into `.build/GitDiffViewer.app` and puts the diagnostic tools in
`Contents/Helpers`, where the app looks for them before `PATH`. Each helper comes from one known source; the script
never falls back to `PATH` and installs nothing.

| Helper | Source | Checked |
|---|---|---|
| arcleak, dolly, deadwood | the commit `scripts/helpers.lock` pins, built in a private checkout in `~/Library/Caches/fr.gcqd.GitDiffViewer.build/tools/<tool>` | HEAD is the pinned commit and the tree is clean, before and after the build; the build resolves only the tool's committed `Package.resolved` |
| swift-format | the Swift 6.4 toolchain that builds the app | signed by Apple or by Swift Open Source |
| swiftlint, swiftformat | Homebrew's prefix, `$(brew --prefix)/bin` | a Mach-O executable |

Each helper is signed with the hardened runtime, then run once for its version; `Contents/Resources/helpers.txt`
records the version and source of each. The app is signed last.

`helpers.lock` has one line per analyzer: its name, repository URL and full 40-character commit SHA. To move an
analyzer to another commit, change its SHA in a commit of its own; the next run fetches that commit by its SHA and
builds it.

One command builds the app and the analyzers: `$SWIFT` when it is set, otherwise `xcrun swift`, and it must be Swift
6.4. When `TOOLCHAINS` is unset and Xcode's Swift is not 6.4, the script selects the first installed Swift 6.4
toolchain (swiftly and `scripts/bootstrap-toolchain.sh` both install one) and says which. Every build, the app's
included, uses `--force-resolved-versions`, so a dependency's moving `main` reaches a bundle only through a committed
`Package.resolved`.

```sh
./scripts/bundle.sh --dry-run                           # each helper, its source and checks; fetches and builds nothing
CODESIGN_IDENTITY="Apple Development: …" ./scripts/bundle.sh   # sign with this identity instead of ad-hoc
GDV_ALLOW_MISSING_HELPERS=1 ./scripts/bundle.sh         # leave out a helper that fails, with a warning
GDV_BUNDLE_ARCLEAK=/path/to/arcleak ./scripts/bundle.sh # bundle this binary instead, reported as an override
GDV_BUILD_JOBS=8 ./scripts/bundle.sh                    # parallel build jobs (default 2)
```

A helper that fails to build or fails a check stops the script unless `GDV_ALLOW_MISSING_HELPERS=1` is set, and a
failed run leaves the previous bundle in place. The dry run lists every failure it can find without building, and
exits non-zero when one would stop the real run. The analyzers pull swift-syntax, and arcleak and deadwood also
indexstore-db, so the first run takes a while; later runs reuse the checkouts and their `.build`. Delete a tool's
directory from the cache to fetch it again.

## Diff algorithm

The diff is a pipeline of stages the settings wire in or out (Settings ▸ Diff algorithm, or the view-options menu):

| Stage | What it does | Comes from |
|---|---|---|
| Line diff | shortest edit script (Myers, linear space) by default, or the rarest common lines matched first as anchors with Myers between them | git's `myers` / `histogram` |
| Indent heuristic | slides each run of inserted or deleted lines to the position that starts on the shallowest indentation after blank lines | git `diff.indentHeuristic` |
| Similarity pairing | in a changed block, pairs removed and added lines by shared character bigrams (order kept, threshold 50%) so emphasis compares real counterparts; leftovers still zip by position | IntelliJ's fine-grained line matching, git's rename threshold |
| Emphasis cleanup | folds equalities shorter than the changes around them into the change, so `foo` to `bar` is one replacement rather than scattered letters | diff-match-patch `cleanupSemantic` |
| Moved blocks | runs of at least three lines removed in one place and added unchanged in another are drawn in a calm blue | git `--color-moved`, BDiff |
| Whitespace | compare exactly, or ignore trailing, leading and trailing, or all whitespace | git `-w` family |

The three emphasis tiers (characters, words, syntax tokens) sit on top of the same pipeline. Structural, tree-based
differencing (difftastic, GumTree) was considered and not adopted: it needs a full parser per language and produces
edits that no longer map to lines, which is what a review diff is read by.

## Languages

Syntax colouring and the syntax-aware intraline tier cover Swift, Objective-C, Kotlin, Java, JavaScript,
TypeScript, C, C++, Python, shell (bash, zsh), fish, HTML/XML, CSS (and SCSS, Less), JSON, YAML and TOML;
Any other file opens as plain text, except known binary extensions; a binary file that slips through is shown as one line naming its size. Every language is scanned by hand-written scanners in
`DiffCore/Scanners`: `CodeScanner` is driven by a `LanguageSyntax` (keywords, comment and string spellings,
annotations, preprocessor and variable prefixes), `DataScanner` handles JSON/YAML/TOML keys and literals,
`CSSScanner` and `HTMLScanner` their own grammars. Swift additionally uses swift-syntax for the syntax-level
intraline diff. Adding a language is a `LanguageSyntax` value and an extension mapping in `Language.byExtension`.

Why not a language server or tree-sitter: LSP semantic tokens need a running server per language with a
workspace on disk, while the viewer mostly shows blobs from git refs and patches; tree-sitter would give exact
grammars but means compiling a C grammar per language into the app. The scanners are a few hundred lines,
allocation-free over UTF-16, and run in microseconds per file; tree-sitter remains the upgrade path if exact
nesting (JSX, template literals with embedded code) is ever needed.

## Design

Targets, bottom up:

| Target | Holds | Depends on |
|---|---|---|
| `DiffCore` | Myers line diff over interned lines, intraline emphasis tiers (character, word, syntax), hand-written syntax scanners per language, `DiffModel`, hunk layout, row alignment, the unified patch parser | swift-syntax |
| `DiffConcurrency` | the `TaskProvider` seam and `mapConcurrently` | – |
| `DiffIO` | read-only POSIX file and memory mapping, used for hashing folders | – |
| `DiffGit` | `GitClient` (one process per command on a dedicated thread, `cat-file --batch`, pure output parsers), `SourceLoader` with one provider per kind of source (file, folder, git ref, patch side), `ComparisonSource`, `PhaseTrace` | DiffCore, DiffConcurrency, DiffIO |
| `DiffRendering` | `DiffRenderer` turning prepared diffs into attributed text with row metadata, `DiffPalette` (system or Xcode theme), `RenderLayout` | DiffCore, DiffGit |
| `DiffTextKit` | the TextKit 2 panes: scrolling and embedded text views sharing a fragment provider and row spacing, gutter, minimap, split-pane scroll sync, detached measuring layouts for cards | DiffRendering |
| `DiffComparison` | the window model: a pure `Comparison` (statuses, renames, counterparts), `ExplorerTrees`, `DiffPreparer` (content-keyed cache and prefetch), a generation-tagged `RenderPipeline`, `OperationTimer`, `ChangeNavigator`, `CardFolding`, `ViewerSettings`, and `DiffViewerModel` composing them behind one API | DiffCore, DiffGit, DiffRendering |
| `GitDiffViewer` | the app: SwiftUI scenes and views, native toolbar choosers | everything |

Rules the code follows: every value the views read is derived from one source of truth in the model (no
parallel dictionaries or lists to keep in sync); off-actor work is structured (`@concurrent` helpers awaited
from main-actor tasks), so cancelling a task stops its diffing and the caller's priority is the work's
priority; every asynchronous publish carries the generation it belongs to and is dropped when superseded, so a
re-layout during a streaming load never loses cards; settings report what they affect (trees, diff, layout,
palette) and the model reacts itself, so the views carry no wiring.

## Tests

```sh
swift test                      # DiffCore and model tests
GDV_BENCH=1 swift test --filter BlobHashingBenchmark   # timing of Data-based vs memory-mapped hashing
```

## License

MIT. See [LICENSE](LICENSE).
