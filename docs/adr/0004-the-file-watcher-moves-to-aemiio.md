---
status: accepted
date: 2026-10-29
---

# 0004 — The file watcher moves to AemiIO

## Context

`AtelierFileTree.FileWatcher` (FSEvents) was general: nothing in it was Atelier's. ask needed the same thing for its
configuration files and had its own kqueue watcher. The owner asked for both to become one reusable surface in aemi's
AemiIO, used by both (aemi ADR 0016).

## Decision

- The watcher and its tests move to AemiIO, ported without Foundation; the behaviour is the same (one stream, files
  followed by path, history replayed across restarts, suppression, exclusions, overflow rescan). Its refusals, which
  went to `os.Logger`, now go to an `onFailure` closure, unused here as before nothing read the log.
- `AtelierFileTree` keeps the names: `FileWatcher` and `FileWatching` are type aliases of AemiIO's. KittyCode's own
  `FileWatching` protocol is AemiIO's now, with the same requirements. Files that name `FileWatcher.FileWatchEvent` or
  `FileWatcher.canonicalPaths` import AemiIO, which `MemberImportVisibility` requires, and their targets declare it.
- The pins move together, as SwiftPM requires one revision per package: aemi `dcad319`, TerminalKit `30b0fcc` (from
  `cc0c60c`; ten TerminalKit commits come along), AemiJSON `8db07fb`.

## Verified

Full suites after the move: AtelierCore 22 runs passed; KittyCode 7 runs passed; GitDiffViewer 1,161 tests in 215
suites passed with 291 known issues (the suite's expected-failure markers; not compared with the count before).
