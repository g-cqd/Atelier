import Darwin
import Dispatch
import Synchronization

/// Installs signal handlers for SIGWINCH (resize), SIGINT, and SIGTERM.
public final class SignalHandler: Sendable {
    private let onResize: @Sendable () -> Void
    private let onShutdown: @Sendable () -> Void

    public init(
        onResize: @escaping @Sendable () -> Void,
        onShutdown: @escaping @Sendable () -> Void
    ) {
        self.onResize = onResize
        self.onShutdown = onShutdown
    }

    /// Starts monitoring signals using dispatch sources.
    @discardableResult
    public func start() -> Task<Void, Never> {
        let onResize = self.onResize
        let onShutdown = self.onShutdown

        return Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in Self.signalStream(SIGWINCH) {
                        onResize()
                    }
                }
                group.addTask {
                    for await _ in Self.signalStream(SIGINT) {
                        onShutdown()
                        break
                    }
                }
                group.addTask {
                    for await _ in Self.signalStream(SIGTERM) {
                        onShutdown()
                        break
                    }
                }
            }
        }
    }

    private static func signalStream(_ sig: Int32) -> AsyncStream<Void> {
        AsyncStream { continuation in
            // Save the previous disposition so we can restore it on stream termination.
            let previous = PreviousDisposition(signal: sig)
            previous.install(handler: SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                continuation.yield()
            }
            continuation.onTermination = { _ in
                source.cancel()
                previous.restore()
            }
            source.resume()
        }
    }

    /// A POSIX signal disposition, saved in a `Mutex` when a handler is installed and restored on stream termination.
    private final class PreviousDisposition: Sendable {
        private let signal: Int32
        private let saved = Mutex<sigaction>(sigaction())

        init(signal: Int32) {
            self.signal = signal
        }

        func install(handler: @escaping @convention(c) (Int32) -> Void) {
            let sig = signal
            saved.withLock { stored in
                var new = sigaction()
                new.__sigaction_u.__sa_handler = handler
                sigemptyset(&new.sa_mask)
                new.sa_flags = 0
                _ = sigaction(sig, &new, &stored)
            }
        }

        func restore() {
            let sig = signal
            saved.withLock { stored in
                _ = sigaction(sig, &stored, nil)
            }
        }
    }
}
