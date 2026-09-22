import AtelierProcess
public import AtelierSyntaxModel
public import Foundation

/// Races `operation` against a timeout, whichever finishes first; the loser is cancelled when the task group
/// scope exits.
private func raceAgainstTimeout<T: Sendable>(
    clock: any Clock<Duration>,
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await clock.sleep(for: timeout)
            throw LSPServiceError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw LSPServiceError.timedOut
        }
        return result
    }
}

/// Internal failure modes that never escape ``SourceKitLSPService``'s public API; every public entry point
/// turns them (and everything else) into `nil`.
private enum LSPServiceError: Error, Sendable {
    case timedOut
}

/// A long-lived sourcekit-lsp session, kept warm across hovers and shut down when idle.
///
/// One actor owns the whole lifecycle: it lazily spawns the server and performs the `initialize` handshake on
/// first use, tracks which documents it has told the server about (opening, reopening on content changes, and
/// closing the least-recently-used past a cap), times out and recovers from a server that stops answering, and
/// shuts itself down -- gracefully, and after a period with no hovers -- so nothing keeps sourcekit-lsp alive
/// forever. A hover after either kind of shutdown reconnects lazily; only a *failed* connection attempt spends
/// the restart budget.
public actor SourceKitLSPService {
    /// How to reach the server, and the policy for keeping the session alive.
    public struct Configuration: Sendable {
        public var serverExecutable: URL
        public var serverArguments: [String]
        public var workspaceRoot: URL
        /// How long the session stays connected with no hover requests before it shuts down.
        public var idleShutdown: Duration
        /// The cap on how long any single request (including the `initialize` handshake) is allowed to take.
        public var requestTimeout: Duration
        /// How many times a failed connection attempt is retried before the service gives up for good.
        public var maximumRestarts: Int
        /// How many documents stay open on the server at once; the least-recently-used is closed past this.
        public var openDocumentLimit: Int

        public init(
            serverExecutable: URL,
            serverArguments: [String] = [],
            workspaceRoot: URL,
            idleShutdown: Duration = .seconds(180),
            requestTimeout: Duration = .seconds(2),
            maximumRestarts: Int = 2,
            openDocumentLimit: Int = 32
        ) {
            self.serverExecutable = serverExecutable
            self.serverArguments = serverArguments
            self.workspaceRoot = workspaceRoot
            self.idleShutdown = idleShutdown
            self.requestTimeout = requestTimeout
            self.maximumRestarts = maximumRestarts
            self.openDocumentLimit = openDocumentLimit
        }
    }

    /// Builds an unstarted connection for a session. ``SourceKitLSPService`` calls ``LSPConnection/start()`` and
    /// performs the `initialize` handshake itself, so a test factory only needs to hand back a connection over
    /// whatever transport it likes -- a real child process, or a scripted double.
    public typealias ConnectionFactory = @Sendable (Configuration) async throws -> LSPConnection

    private struct OpenDocument {
        var version: Int
        var contentHash: Int
    }

    private let configuration: Configuration
    private nonisolated let clock: any Clock<Duration>
    private let connectionFactory: ConnectionFactory

    private var connection: LSPConnection?
    /// Non-nil while a connection is being created and handshaken: a first caller does the work, every other
    /// concurrent caller for the same session parks its continuation here instead of racing its own
    /// ``connectionFactory``/`initialize` and clobbering the stored ``connection``.
    private var establishingWaiters: [CheckedContinuation<LSPConnection?, Never>]?
    /// Bumped by every teardown path (``shutdown()``, the abrupt teardown on a dead transport, an idle
    /// timeout). An in-flight ``ensureConnection()`` that started before the bump must not publish its result
    /// (or leave a connection nobody will stop) once the session has moved on without it.
    private var connectionGeneration = 0
    private var restartsUsed = 0
    private var permanentlyUnavailable = false

    private var openDocuments: [String: OpenDocument] = [:]
    /// Least-recently-used order, oldest first.
    private var openOrder: [String] = []

    /// Bumped on every ``hover(uri:languageID:content:line:utf16Column:)`` call; an idle-shutdown task that
    /// fires after the generation has moved on knows a later hover kept the session alive and does nothing.
    private var idleGeneration = 0
    private var idleTask: Task<Void, Never>?

    public init(
        configuration: Configuration,
        clock: any Clock<Duration> = ContinuousClock(),
        connectionFactory: ConnectionFactory? = nil
    ) {
        self.configuration = configuration
        self.clock = clock
        self.connectionFactory = connectionFactory ?? Self.defaultConnectionFactory
    }

    /// Answers a hover query, or `nil` when the server is unavailable, times out, or has nothing to show.
    /// Never throws: every failure mode this session can hit collapses to `nil`.
    public func hover(
        uri: String, languageID: String, content: String, line: Int, utf16Column: Int
    ) async -> HoverContent? {
        guard !permanentlyUnavailable else { return nil }
        defer { scheduleIdleShutdown() }

        guard let connection = await ensureConnection() else { return nil }
        await ensureOpen(uri: uri, languageID: languageID, content: content, on: connection)

        let params = HoverParams(
            textDocument: TextDocumentIdentifier(uri: uri), position: Position(line: line, character: utf16Column))

        do {
            let hover = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
                try await connection.requestOptional("textDocument/hover", params, as: Hover.self)
            }
            guard let hover, !hover.markdown.isEmpty else { return nil }
            return HoverContent(markdown: hover.markdown, source: .languageServer)
        } catch LSPConnectionError.transportClosed {
            // The connection actually died; drop it so the next hover reconnects from scratch.
            await abruptTeardown()
            return nil
        } catch {
            // A timeout, a server error response, or a malformed response: the connection itself may still be
            // fine, so leave it up for the next hover.
            return nil
        }
    }

    /// Gracefully shuts the session down: `shutdown`, then `exit`, then closes the transport. Safe to call when
    /// no session is running. Idempotent.
    public func shutdown() async {
        idleTask?.cancel()
        idleTask = nil
        connectionGeneration += 1
        guard let connection else { return }
        self.connection = nil
        openDocuments.removeAll()
        openOrder.removeAll()
        await gracefulTeardown(connection)
    }

    // MARK: - Connection lifecycle

    private func ensureConnection() async -> LSPConnection? {
        if let connection { return connection }

        if establishingWaiters != nil {
            return await withCheckedContinuation { (continuation: CheckedContinuation<LSPConnection?, Never>) in
                if establishingWaiters != nil {
                    establishingWaiters?.append(continuation)
                } else {
                    // The in-flight attempt finished (and cleared the waiters list) between the check above and
                    // this closure running; both steps are actor-isolated and synchronous, so this cannot
                    // actually happen, but resume rather than leak the continuation if it ever does.
                    continuation.resume(returning: connection)
                }
            }
        }

        guard !permanentlyUnavailable else { return nil }

        establishingWaiters = []
        let startedGeneration = connectionGeneration
        var newConnection: LSPConnection?
        do {
            let created = try await connectionFactory(configuration)
            newConnection = created
            try await performHandshake(created)
            guard connectionGeneration == startedGeneration else {
                // A teardown ran while this was establishing: the session has already moved on without it, so
                // this connection must not become the stored one -- stop it instead of leaking it.
                await created.stop()
                resumeEstablishingWaiters(with: nil)
                return nil
            }
            connection = created
            resumeEstablishingWaiters(with: created)
            return created
        } catch {
            // A connection that was created but never finished (or never started) `initialize` still has a
            // running reader/process behind it; stop it before giving up so a failed attempt does not leak.
            if let newConnection {
                await newConnection.stop()
            }
            restartsUsed += 1
            if restartsUsed > configuration.maximumRestarts {
                permanentlyUnavailable = true
            } else {
                try? await clock.sleep(for: .seconds(1))
            }
            resumeEstablishingWaiters(with: nil)
            return nil
        }
    }

    private func resumeEstablishingWaiters(with connection: LSPConnection?) {
        let waiters = establishingWaiters ?? []
        establishingWaiters = nil
        for waiter in waiters {
            waiter.resume(returning: connection)
        }
    }

    private func performHandshake(_ connection: LSPConnection) async throws {
        await connection.start()
        let params = InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            rootUri: configuration.workspaceRoot.absoluteString)
        _ = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
            try await connection.request("initialize", params, as: JSONValue.self)
        }
        try await connection.notify("initialized", InitializedParams())
    }

    /// The transport is already gone (or as good as); drop it without wasting time on the `shutdown`/`exit`
    /// protocol over a connection that cannot answer.
    private func abruptTeardown() async {
        connectionGeneration += 1
        guard let connection else { return }
        self.connection = nil
        openDocuments.removeAll()
        openOrder.removeAll()
        await connection.stop()
    }

    /// `shutdown`, then `exit`, then close the transport -- the well-behaved way to end a session that might
    /// still be listening. Used by both the public ``shutdown()`` and an idle timeout.
    private func gracefulTeardown(_ connection: LSPConnection) async {
        _ = try? await raceAgainstTimeout(clock: clock, timeout: .milliseconds(500)) {
            try await connection.requestOptional("shutdown", JSONValue.null, as: JSONValue.self)
        }
        try? await connection.notify("exit", JSONValue.null)
        await connection.stop()
    }

    // MARK: - Idle shutdown

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        // Each scheduling call gets its own, strictly increasing generation, distinct from every earlier one:
        // an older timer's generation can then never match the latest one, even if two overlapping hovers both
        // reach here between the same pair of awaits.
        idleGeneration += 1
        let generation = idleGeneration
        let duration = configuration.idleShutdown
        let sessionClock = clock
        idleTask = Task { [weak self] in
            do {
                try await sessionClock.sleep(for: duration)
            } catch {
                // Cancelled by a later call to scheduleIdleShutdown (or by shutdown()/deinit): the session is
                // either still alive under a newer timer or already being torn down some other way. Firing
                // idleFire here regardless of cancellation is exactly what let a fresher timer's cancellation
                // of a stale one still shut the live connection down; must return without touching it.
                return
            }
            await self?.idleFire(generation: generation)
        }
    }

    private func idleFire(generation: Int) async {
        guard generation == idleGeneration, let connection else { return }
        self.connection = nil
        openDocuments.removeAll()
        openOrder.removeAll()
        await gracefulTeardown(connection)
    }

    // MARK: - Open document tracking

    private func ensureOpen(uri: String, languageID: String, content: String, on connection: LSPConnection) async {
        let hash = content.hashValue

        if let existing = openDocuments[uri] {
            guard existing.contentHash != hash else {
                touch(uri)
                return
            }
            try? await connection.notify(
                "textDocument/didClose", DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: uri)))
            let newVersion = existing.version + 1
            try? await connection.notify(
                "textDocument/didOpen",
                DidOpenTextDocumentParams(
                    textDocument: TextDocumentItem(
                        uri: uri, languageId: languageID, version: newVersion, text: content)))
            openDocuments[uri] = OpenDocument(version: newVersion, contentHash: hash)
            touch(uri)
            return
        }

        if openOrder.count >= configuration.openDocumentLimit {
            await evictOldest(on: connection)
        }

        try? await connection.notify(
            "textDocument/didOpen",
            DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(uri: uri, languageId: languageID, version: 1, text: content)))
        openDocuments[uri] = OpenDocument(version: 1, contentHash: hash)
        openOrder.append(uri)
    }

    private func touch(_ uri: String) {
        guard let index = openOrder.firstIndex(of: uri) else { return }
        openOrder.remove(at: index)
        openOrder.append(uri)
    }

    private func evictOldest(on connection: LSPConnection) async {
        guard !openOrder.isEmpty else { return }
        let oldest = openOrder.removeFirst()
        openDocuments.removeValue(forKey: oldest)
        try? await connection.notify(
            "textDocument/didClose", DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: oldest)))
    }

    // MARK: - The real-world factory

    private static func defaultConnectionFactory(_ configuration: Configuration) async throws -> LSPConnection {
        let session = ProcessSession(
            executable: configuration.serverExecutable,
            arguments: configuration.serverArguments,
            workingDirectory: configuration.workspaceRoot)
        try await session.start()
        let transport = ProcessSessionTransport(session: session)
        return LSPConnection(transport: transport)
    }
}
