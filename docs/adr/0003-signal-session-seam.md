---
status: accepted
date: 2026-10-18
---

# 0003 — The runtime's signal delivery is injected

## Context

TerminalKit `264f744` carries the keyboard decoder's allocation fix, and Atelier pinned `7a1f22a`.
Between the two, `SignalHandler` changed in ways the runtime must follow:

- `start()` installs delivery synchronously and `throws(SignalHandlerError)`; it no longer returns a
  `Task` to cancel. `stop()` restores the saved dispositions and must be called on every exit.
- One handler owns delivery per process. A second `start()` while one is active throws
  `.alreadyRunning`.
- Callbacks run on a dedicated reader thread, not the main dispatch queue, and the shutdown callback
  receives the signal number.

The runtime's tests run sessions in parallel. Under the one-owner rule, overlapping sessions would fail
setup with `.alreadyRunning`. Every test session also replaced the test runner's SIGINT and SIGTERM
dispositions, which was already wrong before the upgrade.

## Decision

- `ApplicationRuntime` builds its signal delivery through an injected `SignalSessionFactory`. The
  public initializer passes `SignalHandler`, which conforms to the internal `SignalSession` protocol
  unchanged. Tests pass `SignalSessionSpy`.
- A session that cannot start fails setup with `AppError.terminalSetupFailed`; the terminal is still
  restored by the existing teardown. A started session is stopped by `defer` on every exit path.
- The resize and shutdown callbacks only call `InputSource.inject` and `InputSource.stop`, which yield
  to or finish an `AsyncStream` continuation and are safe from the reader thread.

## Consequences

- Two tests pin the lifecycle: a run stops the session it started, and a session that cannot start
  fails setup while restoring the terminal. Removing the `stop()` call and swallowing the start
  error each fail the intended test.
- Signal delivery stops before the terminal teardown writes run, as the old task cancellation did. A
  signal in that window takes its default action. This ordering is unchanged, not introduced here.
- Moving TerminalKit required moving Aemi to `5f0c47c` everywhere and AemiJSON to `a6c2d58`, because
  SwiftPM accepts one revision per package identity in a graph.
