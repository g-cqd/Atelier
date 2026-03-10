#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Dispatch

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
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                continuation.yield()
            }
            continuation.onTermination = { _ in
                source.cancel()
            }
            source.resume()
        }
    }
}
