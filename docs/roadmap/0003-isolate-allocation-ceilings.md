---
status: not-started
date: 2026-10-18
---

# 0003 — Isolate the lexer allocation ceiling from concurrent suites

One outcome: `LexerCorpusTests.Allocations` fails only when a scan allocates, never because another
suite allocated during its measurement window.

## Evidence

- Failed in two full AtelierCore runs: once on Aemi `d0f8108` (minimum 7) and once on `5f0c47c`
  (minimum **191** over 64 samples). The bound is 4.
- Passed 5 of 5 times in isolation on the same `5f0c47c` build (`--skip-build --filter`).
- Aemi's C counter is unchanged between those revisions; only its comment and a Swift helper changed.
- The counter counts allocations on threads that first allocate inside the window. Parallel suites
  allocate on such threads. The minimum over more samples cannot exclude a run where every sample is
  contaminated, so raising the sample count is not a fix.

## Options

1. Count only the thread that opened the window, in Aemi's `CAemiTestKitMalloc`: deterministic for
   single-threaded code, and consistent with the header's finding that cross-thread counts are
   unreliable in both directions. Needs a coordinated Aemi pin move across TerminalKit, AemiJSON and
   Atelier.
2. Gate the test behind an environment variable and run it in a separate CI job, as TerminalKit does
   for its decoder ceiling. Needs an Atelier CI job with its own toolchain setup.

Do not loosen the bound or delete the test.
