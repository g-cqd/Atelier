import KittyTerminal
import KittyCodecs

/// Async stream of input events from a terminal connection.
public final class InputSource: Sendable {
    private let connection: any TerminalConnection
    private let _events: AsyncStream<InputEvent>
    private let continuation: AsyncStream<InputEvent>.Continuation

    public var events: AsyncStream<InputEvent> { _events }

    public init(connection: any TerminalConnection) {
        self.connection = connection
        let (stream, cont) = AsyncStream<InputEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        self._events = stream
        self.continuation = cont
    }

    /// Starts the read loop in a new Task. Returns the task for cancellation.
    @discardableResult
    public func start() -> Task<Void, Never> {
        Task { [connection, continuation] in
            var router = SequenceRouter()
            let bufferSize = 4096
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 1)
            defer { buffer.deallocate() }

            while !Task.isCancelled {
                do {
                    let count = try connection.read(into: buffer)
                    let bytes = Array(UnsafeRawBufferPointer(start: buffer.baseAddress, count: count))
                    let events = router.feedAll(bytes)
                    for event in events {
                        continuation.yield(event)
                    }
                } catch {
                    break
                }
            }
            continuation.finish()
        }
    }

    /// Inject an event into the stream from outside the read loop (e.g., from a signal handler).
    public func inject(_ event: InputEvent) {
        continuation.yield(event)
    }

    public func stop() {
        continuation.finish()
    }
}
