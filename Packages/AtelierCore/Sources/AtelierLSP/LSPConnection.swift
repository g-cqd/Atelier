import AemiJSON
import Foundation
import os

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
    /// The deepest nesting a result is decoded to. The decode recurses once per level on this actor's executor, whose
    /// threads have about 512 KiB of stack: a reply 300 levels deep, which the parser's own limit of 512 admits,
    /// overflows it. The results a client reads nest a handful of levels.
    static let maximumResultDepth = 64

    private static let logger = Logger(subsystem: "Atelier.LSP", category: "LSPConnection")

    private let transport: any LSPTransport

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
        return try Self.decodeResult(R.self, from: payload, method: method)
    }

    /// Decodes `payload`, the `result` of a response to `method`, as `R`, at most ``maximumResultDepth`` levels deep.
    /// - Throws: ``LSPConnectionError/malformedResponse(_:)`` when `payload` is not an `R`, or nests deeper.
    static func decodeResult<R: Decodable>(
        _ type: R.Type, from payload: Data, method: String
    ) throws(LSPConnectionError) -> R {
        var decoder = AemiJSON.JSONDecoder()
        // The parser itself is iterative and keeps its own limit; only the decode recurses.
        decoder.maxDecodingDepth = maximumResultDepth
        do {
            return try decoder.decode(R.self, from: payload)
        } catch {
            throw .malformedResponse("\(method): \(error)")
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
                        let reason = String(describing: error)
                        Self.logger.debug("Could not send \(method, privacy: .public): \(reason, privacy: .public)")
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
        do {
            try await notify("$/cancelRequest", CancelParams(id: id))
        } catch {
            // The caller already has its answer; a lost cancel only leaves the server working longer than needed.
            let (request, reason) = (String(describing: id), String(describing: error))
            Self.logger.debug("Could not cancel \(request, privacy: .public): \(reason, privacy: .public)")
        }
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
            // A read that fails after stop() is the teardown itself, not news.
            if !closed { Self.logger.error("The connection ended: \(String(describing: error), privacy: .public)") }
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
            Self.logger.error(
                "Dropped a frame that is not a JSON-RPC message: \(String(describing: error), privacy: .public)")
            // A response that cannot be read still settles its request now, rather than as a timeout later.
            if let id = IncomingMessage.responseID(ofUndecodable: payload) {
                failPending(id, with: LSPConnectionError.malformedResponse("\(error)"))
            }
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
            } else if method == "workspace/semanticTokens/refresh" {
                // The client asks for tokens afresh whenever a text is shown again; the request itself needs only an
                // answer.
                reply = try JSONRPCMessage.response(id: id, result: .null)
            } else {
                reply = try JSONRPCMessage.errorResponse(id: id, code: -32601, message: "method not found")
            }
            try await transport.send(LSPFrameCodec.frame(reply))
        } catch {
            // Best effort: a dead transport surfaces through the read loop.
            let reason = String(describing: error)
            Self.logger.debug("Could not answer the server's \(method, privacy: .public): \(reason, privacy: .public)")
        }
    }
}
