import Synchronization
import TerminalKitInput

@testable import KittyApp

/// Stands in for process signal delivery: records how a run starts and stops it, and can refuse to start.
///
/// The production delivery owns process-wide state, so runtime tests use this spy instead: parallel runs then
/// neither contend for the one signal handler a process allows nor replace the test runner's dispositions.
final class SignalSessionSpy: SignalSession {
    private struct Counts {
        var starts = 0
        var stops = 0
    }

    private let counts = Mutex(Counts())
    private let startError: SignalHandlerError?

    init(failingWith startError: SignalHandlerError? = nil) {
        self.startError = startError
    }

    var startCount: Int { counts.withLock { $0.starts } }
    var stopCount: Int { counts.withLock { $0.stops } }

    /// A factory handing this spy to the runtime; the callbacks are not invoked.
    var factory: SignalSessionFactory { { _, _ in self } }

    func start() throws(SignalHandlerError) {
        counts.withLock { $0.starts += 1 }
        if let startError { throw startError }
    }

    func stop() {
        counts.withLock { $0.stops += 1 }
    }
}
