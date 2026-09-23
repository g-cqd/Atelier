import class AemiRuntime.BlockingOffloadPool

/// Runs a blocking directory read on a thread that may block, never on a cooperative one, which the whole process
/// shares with about one thread per core. ``BlockingOffloadPool`` is the one real conformer; a test substitutes a spy.
protocol BlockingOffload: Sendable {
    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T
}

extension BlockingOffloadPool: BlockingOffload {}
