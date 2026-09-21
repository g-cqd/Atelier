public import AtelierProcess
public import Foundation

/// Where ``LSPConnection`` reads and writes raw bytes. The base protocol's `Content-Length` framing sits
/// above this; a transport only moves bytes.
public protocol LSPTransport: Sendable {
    /// Raw byte chunks from the server, in arrival order. The stream finishes, without an error, once the
    /// server goes away cleanly, and throws if reading it fails.
    var incoming: AsyncThrowingStream<Data, any Error> { get }

    /// Writes `data` to the server. Callers already frame the payload with `Content-Length`.
    func send(_ data: Data) async throws

    /// Tears the transport down. Idempotent.
    func close() async
}

/// An ``LSPTransport`` over a ``ProcessSession``, for a language server run as a child process.
public struct ProcessSessionTransport: LSPTransport {
    private let session: ProcessSession

    public init(session: ProcessSession) {
        self.session = session
    }

    public var incoming: AsyncThrowingStream<Data, any Error> { session.output }

    public func send(_ data: Data) async throws {
        try await session.send(data)
    }

    public func close() async {
        await session.terminate()
    }
}
