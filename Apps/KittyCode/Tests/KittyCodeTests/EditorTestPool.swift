import class AemiRuntime.BlockingOffloadPool

/// The pool every test's ``EditorState`` runs its blocking file work on. A state built without one starts a one-worker
/// pool of its own, whose thread lives until `shutdown()`, which the tests don't call; one shared pool keeps a run from
/// starting a thread per state. The process exits with the test run, so it is never shut down.
enum EditorTestPool {
    static let shared = BlockingOffloadPool(width: 4)
}
