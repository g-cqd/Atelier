---
status: done
date: 2026-10-18
---

# 0002 — Adopt TerminalKit's decoder allocation fix

One outcome: KittyCode's keyboard decoder no longer allocates per keystroke, by consuming the
TerminalKit revision `ask` already uses instead of carrying a local patch.

- [x] Move AemiJSON to Aemi `5f0c47c` (AemiJSON `a6c2d58`, 372 tests, exit 0).
- [x] Pin TerminalKit `264f744`, Aemi `5f0c47c` and AemiJSON `a6c2d58` in all three manifests;
      lockfiles change only those three revisions.
- [x] Adapt the runtime to `SignalHandler`'s throwing start, explicit stop and off-main delivery
      behind an injected signal session (ADR-0003), with two lifecycle tests proven by mutation.
- [x] Run all three full release suites on the new pins: KittyCode 968 and GitDiffViewer 1,161
      exit 0. AtelierCore 1,628 with one failure, the contaminated lexer allocation case, which
      passes in isolation on the same build and predates this change (entry 0003).
- [x] Land on main (PR #6, `2535e73`). Superseded pins: TerminalKit `98650f4`, Aemi `a6446f1`,
      AemiJSON `6cbe2ae`, which add the router and flush ceilings and the thread-scoped counter.

Out of scope: the renderer and input-router allocation ceilings, which belong to TerminalKit.
