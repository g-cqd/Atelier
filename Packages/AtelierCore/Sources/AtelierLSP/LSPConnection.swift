import AemiJSON
import Foundation

/// Why an ``LSPConnection`` request or notification failed.
public enum LSPConnectionError: Error, Sendable, Equatable {
    /// The server went away or ``LSPConnection/stop()`` was called; the string describes why, when known.
    case transportClosed(String)
    /// The server replied with a JSON-RPC error object.
    case serverError(JSONRPCError)
    /// A response could not be turned into the caller's expected type: a result was required but absent, or
    /// decoding it failed.
    case malformedResponse(String)
}

/// A JSON-RPC connection to a language server over an ``LSPTransport``: requests matched to their responses by id,
/// notifications, and answers to the server's own requests. A request whose task is cancelled throws
/// `CancellationError` and sends `$/cancelRequest`. Nothing is read until ``start()`` runs the read loop.
public actor LSPConnection {
    private let transport: any LSPTransport
    private let decoder = AemiJSON.JSONDecoder()

    private var nextRequestID = 0
    private var pending: [JSONRPCID: CheckedContinuation<Data?, any Error>] = [:]
    private var readTask: Task<Void, Never>?
    /// Set once ``stop()`` runs or the read loop ends; new requests and notifications are refused from then on.
    private var closed = false
    /// Set once ``LSPTransport/close()`` has run. Only ``stop()`` sets it, so a read loop that ended on its own
    /// still leaves the transport for ``stop()`` to close.
    private var transportDisposed = false

    public init(transport: any LSPTransport) {
        self.transport = transport
    }

    /// Starts the read loop. Call once; later calls are a no-op.
    public func start() {
        guard readTask == nil else { return }
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    /// Sends a request and decodes its result as `R`.
    /// - Throws: ``LSPConnectionError/malformedResponse(_:)`` when the server's result was absent or null;
    ///   use ``requestOptional(_:_:as:)`` when a null/absent result is a meaningful answer (e.g. hover).
    public func request<P: Encodable & Sendable, R: Decodable & Sendable>(
        _ method: String, _ params: P, as type: R.Type
    ) async throws -> R {
        guard let result = try await requestOptional(method, params, as: R.self) else {
            throw LSPConnectionError.malformedResponse("\(method): expected a result, got null/absent")
        }
        return result
    }

    /// Sends a request and decodes its result as `R`, or `nil` when the result is `null` or absent, which is how
    /// LSP says there is nothing to show.
    public func requestOptional<P: Encodable & Sendable, R: Decodable & Sendable>(
        _ method: String, _ params: P, as type: R.Type
    ) async throws -> R? {
        let payload = try await performRequest(method: method, params: params)
        guard let payload, payload != Self.jsonNull else { return nil }
        do {
            return try decoder.decode(R.self, from: payload)
        } catch {
            throw LSPConnectionError.malformedResponse("\(method): \(error)")
        }
    }

    /// Sends a notification; no response is expected.
    public func notify<P: Encodable & Sendable>(_ method: String, _ params: P) async throws {
        guard !closed else { throw LSPConnectionError.transportClosed("connection stopped") }
        let frame = LSPFrameCodec.frame(try JSONRPCMessage.notification(method: method, params: params))
        try await transport.send(frame)
    }

    /// Ends the read loop, closes the transport once, and fails every pending request with
    /// ``LSPConnectionError/transportClosed(_:)``. Idempotent.
    public func stop() async {
        closed = true
        readTask?.cancel()
        readTask = nil
        failAllPending(with: LSPConnectionError.transportClosed("connection stopped"))
        guard !transportDisposed else { return }
        transportDisposed = true
        await transport.close()
    }

    // MARK: - Sending requests

    private static let jsonNull = Data("null".utf8)

    private func performRequest<P: Encodable & Sendable>(method: String, params: P) async throws -> Data? {
        guard !closed else { throw LSPConnectionError.transportClosed("connection stopped") }
        nextRequestID += 1
        let id = JSONRPCID.number(nextRequestID)
        let frame = LSPFrameCodec.frame(try JSONRPCMessage.request(id: id, method: method, params: params))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, any Error>) in
                pending[id] = continuation
                Task { [weak self] in
                    do {
                        try await self?.transport.send(frame)
                    } catch {
                        await self?.failPending(id, with: error)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelPending(id) }
        }
    }

    private func failPending(_ id: JSONRPCID, with error: any Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    private func cancelPending(_ id: JSONRPCID) async {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        try? await notify("$/cancelRequest", CancelParams(id: id))
    }

    private func failAllPending(with error: any Error) {
        let waiters = pending
        pending.removeAll()
        for continuation in waiters.values {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - The read loop

    private func readLoop() async {
        var codec = LSPFrameCodec()
        do {
            for try await chunk in transport.incoming {
                let payloads = try codec.feed(chunk)
                for payload in payloads {
                    await route(payload)
                }
            }
            endedByTransport(description: "server closed the connection")
        } catch {
            endedByTransport(description: String(describing: error))
        }
    }

    private func endedByTransport(description: String) {
        guard !closed else { return }
        closed = true
        failAllPending(with: LSPConnectionError.transportClosed(description))
    }

    private func route(_ payload: Data) async {
        let message: IncomingMessage
        do {
            message = try IncomingMessage.decode(payload)
        } catch {
            // Not a valid JSON-RPC envelope; nothing sensible to do but drop it.
            return
        }

        switch message {
            case .response(let id, let result, let error):
                guard let continuation = pending.removeValue(forKey: id) else { return }
                if let error {
                    continuation.resume(throwing: LSPConnectionError.serverError(error))
                } else {
                    continuation.resume(returning: result)
                }
            case .serverRequest(let id, let method):
                await replyToServerRequest(id: id, method: method)
            case .notification:
                break
        }
    }

    private func replyToServerRequest(id: JSONRPCID, method: String) async {
        do {
            let reply: Data
            if method == "workspace/configuration" {
                reply = try JSONRPCMessage.response(id: id, result: .array([.null]))
            } else {
                reply = try JSONRPCMessage.errorResponse(id: id, code: -32601, message: "method not found")
            }
            try await transport.send(LSPFrameCodec.frame(reply))
        } catch {
            // Best effort: a dead transport surfaces through the read loop.
        }
    }
}
