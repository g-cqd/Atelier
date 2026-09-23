import AtelierProcess
public import AtelierSyntaxModel
public import Foundation
import os

/// `operation`'s result, or `LSPServiceError.timedOut` when `timeout` elapses first; the loser is cancelled.
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

/// Failures internal to ``SourceKitLSPService``, whose hover reports each as ``HoverOutcome/unavailable``.
private enum LSPServiceError: Error, Sendable {
    case timedOut
}

/// What a hover request came to: the server's answer, or none.
public enum HoverOutcome: Sendable, Equatable {
    /// The server answered, with content or with nothing to show (nil).
    case answered(HoverContent?)
    /// The server gave no answer: it is unavailable or restarting, it timed out or closed the connection, it replied
    /// with an error or with a result that could not be read, or the request was cancelled. Asking again may answer.
    case unavailable

    /// The answer's content; nil when the server has nothing to show, or gave no answer.
    public var content: HoverContent? {
        if case .answered(let content) = self { content } else { nil }
    }
}

/// `initialize`'s parameters with sourcekit-lsp's `initializationOptions`, which ``InitializeParams`` does not carry.
private struct SessionInitializeParams: Encodable, Sendable {
    let processId: Int?
    let rootUri: String?
    let capabilities: ClientCapabilities
    let initializationOptions: JSONValue?
}

/// A long-lived sourcekit-lsp session, kept warm across hovers and shut down when idle.
///
/// The server is spawned and initialized on first use, keeps at most ``Configuration/openDocumentLimit`` documents
/// open, and is shut down after ``Configuration/idleShutdown`` without a hover. A hover after any shutdown
/// reconnects; only a failed connection attempt spends the restart budget.
public actor SourceKitLSPService {
    private static let logger = Logger(subsystem: "Atelier.LSP", category: "SourceKitLSPService")

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
        /// sourcekit-lsp's options for the session, sent as `initialize`'s `initializationOptions`; nil sends none.
        public var initializationOptions: JSONValue?

        /// The options a hover session starts with: no background indexing, since a hover needs no index of the
        /// workspace and indexing builds the project.
        public static let hoverInitializationOptions: JSONValue = .object(["backgroundIndexing": .bool(false)])

        public init(
            serverExecutable: URL,
            serverArguments: [String] = [],
            workspaceRoot: URL,
            idleShutdown: Duration = .seconds(180),
            requestTimeout: Duration = .seconds(2),
            maximumRestarts: Int = 2,
            openDocumentLimit: Int = 32,
            initializationOptions: JSONValue? = Configuration.hoverInitializationOptions
        ) {
            self.serverExecutable = serverExecutable
            self.serverArguments = serverArguments
            self.workspaceRoot = workspaceRoot
            self.idleShutdown = idleShutdown
            self.requestTimeout = requestTimeout
            self.maximumRestarts = maximumRestarts
            self.openDocumentLimit = openDocumentLimit
            self.initializationOptions = initializationOptions
        }
    }

    /// Builds an unstarted connection for a session; the service starts it and performs the `initialize` handshake.
    public typealias ConnectionFactory = @Sendable (Configuration) async throws -> LSPConnection

    private struct OpenDocument {
        var version: Int
        var contentHash: Int
    }

    private let configuration: Configuration
    private nonisolated let clock: any Clock<Duration>
    private let connectionFactory: ConnectionFactory

    private var connection: LSPConnection?
    /// Non-nil while a connection is being established; concurrent callers wait here for the first caller's result.
    private var establishingWaiters: [CheckedContinuation<LSPConnection?, Never>]?
    /// Bumped by ``shutdown()`` and by the teardown after a dead transport, so a connection established across either
    /// is stopped rather than published.
    private var connectionGeneration = 0
    private var restartsUsed = 0
    private var permanentlyUnavailable = false

    private var openDocuments: [String: OpenDocument] = [:]
    /// Least-recently-used order, oldest first.
    private var openOrder: [String] = []

    /// Bumped per scheduled idle shutdown; a timer that fires with a stale generation does nothing.
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

    /// The directory the server runs in and takes as its workspace (`rootUri`).
    public nonisolated var workspaceRoot: URL { configuration.workspaceRoot }

    /// The server's hover at the position: its answer, which may have nothing to show, or ``HoverOutcome/unavailable``
    /// when no answer came, so that a caller caches answers alone. Opens `uri` with `content` on the server first, and
    /// restarts the idle timer.
    public func hover(
        uri: String, languageID: String, content: String, line: Int, utf16Column: Int
    ) async -> HoverOutcome {
        guard !permanentlyUnavailable else { return .unavailable }
        defer { scheduleIdleShutdown() }

        guard let connection = await ensureConnection() else { return .unavailable }
        await ensureOpen(uri: uri, languageID: languageID, content: content, on: connection)

        let params = HoverParams(
            textDocument: TextDocumentIdentifier(uri: uri), position: Position(line: line, character: utf16Column))

        do {
            let hover = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
                try await connection.requestOptional("textDocument/hover", params, as: Hover.self)
            }
            guard let hover, !hover.markdown.isEmpty else { return .answered(nil) }
            return .answered(HoverContent(markdown: hover.markdown, source: .languageServer))
        } catch LSPConnectionError.transportClosed(let reason) {
            // A dead connection is dropped so the next hover reconnects.
            Self.logger.error("sourcekit-lsp went away during a hover: \(reason, privacy: .public)")
            await abruptTeardown()
            return .unavailable
        } catch {
            // A timeout, a server error or an unreadable reply leaves a connection that may still be fine.
            Self.logger.info("A hover got no answer: \(String(describing: error), privacy: .public)")
            return .unavailable
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
                    // Unreachable without a suspension since the check above; resumed rather than leaked all the same.
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
                // A teardown ran meanwhile: stop this connection instead of publishing it.
                await created.stop()
                resumeEstablishingWaiters(with: nil)
                return nil
            }
            connection = created
            resumeEstablishingWaiters(with: created)
            return created
        } catch {
            // A created connection has a running process behind it even when `initialize` failed.
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
        let params = SessionInitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            rootUri: configuration.workspaceRoot.absoluteString, capabilities: ClientCapabilities(),
            initializationOptions: configuration.initializationOptions)
        _ = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
            try await connection.request("initialize", params, as: DiscardedResult.self)
        }
        try await connection.notify("initialized", InitializedParams())
    }

    /// Drops a connection whose transport is gone, skipping the `shutdown`/`exit` exchange it cannot answer.
    private func abruptTeardown() async {
        connectionGeneration += 1
        guard let connection else { return }
        self.connection = nil
        openDocuments.removeAll()
        openOrder.removeAll()
        await connection.stop()
    }

    /// Ends a session that may still be listening: `shutdown`, then `exit`, then the transport closes.
    private func gracefulTeardown(_ connection: LSPConnection) async {
        _ = try? await raceAgainstTimeout(clock: clock, timeout: .milliseconds(500)) {
            try await connection.requestOptional("shutdown", JSONValue.null, as: DiscardedResult.self)
        }
        try? await connection.notify("exit", JSONValue.null)
        await connection.stop()
    }

    // MARK: - Idle shutdown

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleGeneration += 1
        let generation = idleGeneration
        let duration = configuration.idleShutdown
        let sessionClock = clock
        idleTask = Task { [weak self] in
            do {
                try await sessionClock.sleep(for: duration)
            } catch {
                // Cancelled: a newer timer or a teardown owns the session now.
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
