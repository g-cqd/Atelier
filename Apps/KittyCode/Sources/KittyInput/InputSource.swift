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
        // Unbounded: every keystroke must arrive in order, even from a fast paste under load.
        let (stream, cont) = AsyncStream<InputEvent>
            .makeStream(
                bufferingPolicy: .unbounded)
        self._events = stream
        self.continuation = cont
    }

    /// Starts the read loop in a new task and returns it. The stream finishes however the loop ends, and a consumer
    /// that stops iterating cancels the loop; a blocked read can't be interrupted, so cancellation lands when the read
    /// returns.
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
