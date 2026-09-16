import Darwin
import KittyCodecs
public import KittyTerminal

/// Async stream of input events from a terminal connection.
public final class InputSource: Sendable {
    private let connection: any TerminalConnection
    private let _events: AsyncStream<InputEvent>
    private let continuation: AsyncStream<InputEvent>.Continuation

    public var events: AsyncStream<InputEvent> { _events }

    public init(connection: any TerminalConnection) {
        self.connection = connection
        // Unbounded buffering: an editor must deliver every keystroke in
        // arrival order. The prior `.bufferingNewest(256)` dropped the OLDEST
        // events on overflow, which means a fast paste under load could lose
        // leading characters. The consumer is the main-actor event loop;
        // back-pressure cannot meaningfully constrain a human's typing speed,
        // and realistic queue depth during one main-actor hop is far below
        // any pathological growth.
        let (stream, cont) = AsyncStream<InputEvent>.makeStream(
            bufferingPolicy: .unbounded)
        self._events = stream
        self.continuation = cont
    }

    /// Starts the read loop in a new Task. Returns the task for cancellation.
    ///
    /// Lifecycle guarantees:
    /// - `continuation.finish()` is called via `defer` whether the loop exits
    ///   cleanly, throws, or is cancelled at a check point.
    /// - `onTermination` on the continuation cancels the read task so that if
    ///   the consumer stops iterating first, the producer doesn't keep spinning.
    /// - A blocked `connection.read(2)` cannot be unblocked from Swift today;
    ///   that requires migrating to `FileDescriptor` + `poll(2)`/`select(2)`
    ///   (tracked as the EINTR/FileDescriptor migration). Until then,
    ///   cooperative cancellation lands on the next read return (EINTR or
    ///   incoming byte).
    @discardableResult
    public func start() -> Task<Void, Never> {
        let task = Task { [connection, continuation] in
            var router = SequenceRouter()
            var routedEvents: [InputEvent] = []
            let bufferSize = 4096
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 1)
            defer {
                buffer.deallocate()
                continuation.finish()
            }

            while !Task.isCancelled {
                do {
                    let count = try connection.read(into: buffer)
                    if Task.isCancelled { return }
                    // Borrow a `Span<UInt8>` view of the bytes actually read.
                    // `~Escapable` means the span can't outlive `buffer`, so
                    // the producer keeps the lifetime invariant the consumer
                    // already relies on.
                    let raw = UnsafeRawBufferPointer(start: buffer.baseAddress, count: count)
                    let span: Span<UInt8> = raw.bytes._unsafeView(as: UInt8.self)
                    router.feedAll(span, into: &routedEvents)
                    for event in routedEvents {
                        if Task.isCancelled { return }
                        continuation.yield(event)
                    }
                } catch TerminalError.readFailed(let code) where code == EINTR {
                    continue
                } catch {
                    break
                }
            }
        }
        // If the consumer drops the stream's iterator (e.g. early break), the
        // continuation fires its termination hook — wake the producer so it
        // doesn't sit in a stale read.
        let producerTask = task
        continuation.onTermination = { @Sendable _ in
            producerTask.cancel()
        }
        return task
    }

    /// Inject an event into the stream from outside the read loop (e.g., from a signal handler).
    public func inject(_ event: InputEvent) {
        continuation.yield(event)
    }

    public func stop() {
        continuation.finish()
    }
}
