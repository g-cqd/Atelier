---
status: proposed
date: 2026-10-18
---

# 0001 — Consume TerminalKit instead of duplicating the terminal stack

## Context

TerminalKit has the terminal implementation formerly owned here and its owning suites. Its
revision `7a1f22a6d78e63df717e9f5fb0a7968a15a3f38b` is published and verified: seven test targets
report 368 tests, with opt-in benchmarks skipped. The previous consumer move was blocked by a
misdiagnosed testability failure; TerminalKit ADR-0012 resolves that with an explicit test command.

## Decision

- Pin that same TerminalKit revision in KittyCode and AtelierCore. Do not combine this move with
  an Aemi/AemiJSON upgrade; all three packages already agree on their existing pins.
- Replace the implementations in `KittyTerminal`, `KittyStyle`, `KittyCodecs`, `KittyInput`,
  `KittyRenderer` and `AtelierText` with re-exports of their owning TerminalKit products.
- Keep the old module names for source import compatibility. This is not a binary ABI guarantee.
  The two renamed symbols (`EscapeSequences`, `TerminalLogger`) are updated at their call sites.
- Remove 56 duplicate owning test files only after their imported copies pass in TerminalKit.
  App integration tests remain here, including tests that inspect the shared implementation.
- Such white-box integration tests import the owning TerminalKit module and declare its product
  dependency directly. Do not make implementation internals public for the migration.

## Why one coupled change

The renderer accepts TerminalKit text/style/connection types. Keeping a second nominal text or
style implementation in this graph creates incompatible types despite identical source spelling.
All six re-exports therefore switch together, without rewriting algorithms or changing signatures.

A dedicated compatibility suite checks canonical type identity for codec events, input events,
text, connections, styles and rendering across the old/new module names. Its renderer test also
checks synchronized output around a real frame written to an in-memory connection.

Negative control: temporarily restore the original local `KittyStyle.Style` implementation.
The compatibility suite fails compilation on conversion to `TerminalKitStyle.Style`. Remove the
control and it passes. This detects the duplicate implementation this move is meant to eliminate.

## Verification

- KittyCode: optimized tests with explicit testability pass; 970 reported tests in eight targets,
  including four compatibility tests. No integration assertions were removed.
- AtelierCore: optimized suite exits 0, 1,628 reported tests across 22 targets.
- GitDiffViewer: optimized suite exits 0, 1,161 tests in 215 suites. Its 291 known issues are the
  suite's declared `withKnownIssue` expectations.
- The KittyCode binary runs: `--help` exits 0 and prints its usage.
- All three lockfiles gain only the TerminalKit pin; no other dependency version moved.
- Every changed file passes swift-format and SwiftLint `--strict`; a 54-file audit shows no
  differences beyond the two renames, the import adaptation and formatting.
- No new UI layout or drawing algorithm is introduced. No performance improvement is claimed.

## Consequences

Future terminal fixes belong in TerminalKit and reach both apps and `ask` through a dependency
pin update. The six compatibility modules contain no implementation state or nominal types.
Removing their module names is a separate source-breaking cleanup, not hidden inside this move.
