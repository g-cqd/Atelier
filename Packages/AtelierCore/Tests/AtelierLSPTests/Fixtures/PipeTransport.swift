import Foundation

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
/// `deliver`/`endIncoming` feed the client side of the conversation. No child process involved.
final class PipeTransport: LSPTransport, Sendable {
    let incoming: AsyncThrowingStream<Data, any Error>
    private let incomingContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    let sink = FrameSink()

    init() {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        self.incoming = stream
        self.incomingContinuation = continuation
    }

    func send(_ data: Data) async throws {
        await sink.append(data)
    }

    func close() async {
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
