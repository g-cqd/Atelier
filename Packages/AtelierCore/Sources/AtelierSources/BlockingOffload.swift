import Synchronization

import class AemiRuntime.BlockingOffloadPool

/// Runs a blocking call on a thread that may block: the loader's file reads, hashing, `stat` passes and folder scans.
/// The process shares about one cooperative thread per core, so a read parked on one starves unrelated tasks, and a
/// hashing limit above the core count buys nothing. ``BlockingOffloadPool`` is the one real conformer; a test
/// substitutes a spy.
protocol BlockingOffload: Sendable {
    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T
}

extension BlockingOffloadPool: BlockingOffload {}

/// Carries a task's cancellation into a blocking call on a pool thread, where `Task.isCancelled` has no task to read.
final class CancellationFlag: Sendable {
    private let raised = Atomic(false)

    var isRaised: Bool { raised.load(ordering: .relaxed) }

    func raise() {
        raised.store(true, ordering: .relaxed)
    }
}
