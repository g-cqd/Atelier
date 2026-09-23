import Foundation
import Synchronization

@testable import AtelierLSP

/// Collects frames a test's `PipeTransport` was asked to send, letting a test await until a given number
/// have arrived instead of racing a fixed sleep.
actor FrameSink {
    private var frames: [Data] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ frame: Data) {
        frames.append(frame)
        let satisfied = waiters.filter { frames.count >= $0.count }
        waiters.removeAll { frames.count >= $0.count }
        for waiter in satisfied { waiter.continuation.resume() }
    }

    func waitForCount(_ count: Int) async {
        if frames.count >= count { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    var all: [Data] { frames }
}

/// An in-process ``LSPTransport`` double: `send` is captured into a ``FrameSink`` a test inspects, and
/// `deliver`/`endIncoming` feed the client side of the conversation, or ``answer(_:with:)`` answers requests as
/// they are sent. No child process involved.
final class PipeTransport: LSPTransport, Sendable {
    let incoming: AsyncThrowingStream<Data, any Error>
    private let incomingContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    let sink = FrameSink()
    /// How many times ``close()`` ran.
    let closeCount = CloseCounter()
    /// The result each method's requests get as soon as they are sent, keyed by method.
    private let standingAnswers = Mutex<[String: JSONValue]>([:])

    init() {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        self.incoming = stream
        self.incomingContinuation = continuation
    }

    func send(_ data: Data) async throws {
        await sink.append(data)
        guard case .serverRequest(let id, let method) = try IncomingMessage.decode(unframe(data)),
            let result = standingAnswers.withLock({ $0[method] })
        else { return }
        // A client request reads as a request to its receiver; its answer arrives after the frame is recorded.
        deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: result)))
    }

    /// From now on, answers every request for `method` with `result` as soon as it is sent, as a warm server would.
    func answer(_ method: String, with result: JSONValue) {
        standingAnswers.withLock { $0[method] = result }
    }

    func close() async {
        await closeCount.increment()
        incomingContinuation.finish()
    }

    /// Delivers one already-framed chunk to the client, as if the server had written it.
    func deliver(_ data: Data) {
        incomingContinuation.yield(data)
    }

    /// Ends the server side of the conversation, optionally with an error.
    func endIncoming(throwing error: (any Error)? = nil) {
        if let error {
            incomingContinuation.finish(throwing: error)
        } else {
            incomingContinuation.finish()
        }
    }
}

/// A simple counter a test can await-read, for actions (like `close()`) that have no other observable trace.
actor CloseCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Strips the `Content-Length` header off one framed chunk, for a test that wants the raw JSON.
func unframe(_ data: Data) throws -> Data {
    var codec = LSPFrameCodec()
    let payloads = try codec.feed(data)
    guard let payload = payloads.first else {
        struct NoPayload: Error {}
        throw NoPayload()
    }
    return payload
}
