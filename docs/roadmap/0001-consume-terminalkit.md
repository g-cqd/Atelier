---
status: in-progress
date: 2026-10-18
---

# 0001 — Switch the terminal and text compatibility modules to TerminalKit

One outcome: Atelier uses the same implementation as TerminalKit consumers, without a second
copy of the terminal/text code or its owning tests.

- [x] Verify TerminalKit's inherited owning suites before deleting any originals.
- [x] Pin TerminalKit `7a1f22a` in KittyCode and AtelierCore.
- [x] Replace 43 implementation files with six compatibility re-export files.
- [x] Remove the 56 duplicate owning test files now verified in TerminalKit.
- [x] Keep app integration assertions; import the owning module for internal tests.
- [x] Rename old sequence/logger symbols at consumer call sites.
- [x] Add four canonical-type/frame compatibility tests and prove a duplicate-style mutation fails.
- [x] Run KittyCode's full optimized suite: exit 0, 970 tests across eight targets.
- [x] Run AtelierCore's full suite (1,628 tests, 22 targets) and GitDiffViewer's (1,161 tests,
      215 suites): both exit 0.
- [x] Review the diff, verify dependency locks, lint every changed file, and check the binary runs.
- [ ] Publish the migration commit to main.

ADR: `docs/adr/0001-consume-terminalkit.md`.
Owning library tests: TerminalKit, not the compatibility modules.
Do not close this entry based only on a successful KittyCode build.
