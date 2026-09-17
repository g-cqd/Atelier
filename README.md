# Atelier

One workshop for two source tools that share a core:

| Path | What |
|---|---|
| `Apps/GitDiffViewer` | macOS diff viewer on SwiftUI and TextKit 2 |
| `Apps/KittyCode` | terminal code editor; on kitty-protocol terminals its chrome and editor decorations are drawn in pixels under the cells |
| `Packages/AtelierCore` | the building blocks both apps are made of, one product per target: `AtelierText` (rope, cursors, display metrics), `AtelierDiff` (line and intraline diffing, moved blocks, hunks, unified patches, byte-level `DiffSource`), `AtelierSyntaxModel` (languages, roles, tokens, the `HighlightEngine` interface), `AtelierLexers` (allocation-light scanners over UTF-8 or UTF-16, the lexical engine), `AtelierGrammar` / `AtelierParser` / `AtelierQuery` (tree-sitter grammars, GLR parsing, queries), `AtelierSwiftSyntax` (swift-syntax token ranges), `AtelierTheme` (role-keyed themes, Xcode theme import), `AtelierProcess` (subprocess runner on aemi's blocking pool), `AtelierGit` (git client, pure parsers, status vocabulary), `AtelierSources` (files, folders, refs and patches as comparison sources), `AtelierFileTree` (scanned directory trees, secure paths, path trees with chain compaction), `AtelierSearch` (workspace search over mapped files), `AtelierTestSupport` (scripted process runner) |

Every package builds on [aemi](https://github.com/Aemi-Studio/aemi) for its runtime seams (task providers,
clocks, blocking pools), byte kernels, POSIX file access and deterministic test kits.

## Layout

There is no root `Package.swift`: SwiftPM cannot aggregate executables from path dependencies, and the three
packages legitimately differ in what they link. Each directory under `Apps/` and `Packages/` is a package of its
own; the apps depend on the core by path (`../../Packages/AtelierCore`). `Atelier.xcworkspace` opens all three.

## Build and test

Requires Xcode 27 (Swift 6.4).

```sh
scripts/build-all.sh          # swift build in every package
scripts/test-all.sh           # swift test in every package
swift build --package-path Apps/GitDiffViewer
swift test --package-path Packages/AtelierCore
```

`scripts/bootstrap-toolchain.sh` installs the Swift 6.4 snapshot toolchain aemi's CI uses, for a machine without
Xcode 27.

## Conventions

See `AGENTS.md`: which aemi family each tier uses, how tests wait (test clocks, task-provider spies and probes,
never `Task.sleep` or `Task.yield`), and how code moves between packages.

## License

MIT. See [LICENSE](LICENSE).
