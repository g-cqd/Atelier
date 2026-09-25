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

/// Failures internal to ``LanguageServerSession``, whose hover reports each as ``HoverOutcome/unavailable``.
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

/// What a semantic tokens request came to.
public enum SemanticTokensOutcome: Sendable, Equatable {
    /// The document's tokens, in the server's relative encoding, and the legend that names their types.
    case tokens(data: [UInt32], legend: SemanticTokensLegend)
    /// The server does not give semantic tokens.
    case unsupported
    /// The document changed while the request was out, so the reply was for an older version and was dropped.
    case superseded
    /// No reply came within the request timeout.
    case timedOut
    /// No answer: the document is not on disk, or the server is unavailable, went away, failed or was cancelled.
    case unavailable
}

/// A long-lived language server session, kept warm across hovers and shut down when idle. Nothing in it is one
/// server's: the executable, its arguments and its options come in through the ``Configuration``, which
/// ``LanguageServerDescriptor`` builds for each server.
///
/// The server is spawned and initialized on first use, keeps at most ``Configuration/openDocumentLimit`` documents
/// open, and is shut down after ``Configuration/idleShutdown`` without a hover. A hover after any shutdown
/// reconnects; only a failed connection attempt spends the restart budget.
public actor LanguageServerSession {
    private static let logger = Logger(subsystem: "Atelier.LSP", category: "LanguageServerSession")

    /// How to reach the server, and the policy for keeping the session alive.
    public struct Configuration: Sendable {
        public var serverExecutable: URL
        public var serverArguments: [String]
        public var workspaceRoot: URL
        /// How long the session stays connected with no hover requests before it shuts down.
        public var idleShutdown: Duration
        /// The cap on how long the `initialize` handshake is allowed to take. A server that loads a whole runtime or
        /// project model before it answers, as a JVM server does, needs far longer here than for any request after.
        public var initializeTimeout: Duration
        /// The cap on how long any single request after the `initialize` handshake is allowed to take.
        public var requestTimeout: Duration
        /// How many times a failed connection attempt is retried before the service gives up for good.
        public var maximumRestarts: Int
        /// How many documents stay open on the server at once; the least-recently-used is closed past this.
        public var openDocumentLimit: Int
        /// The server's options for the session, sent as `initialize`'s `initializationOptions`; nil sends none.
        public var initializationOptions: JSONValue?
        /// The server process's whole environment; nil inherits the app's.
        public var environment: [String: String]?

        public init(
            serverExecutable: URL,
            serverArguments: [String] = [],
            workspaceRoot: URL,
            idleShutdown: Duration = .seconds(180),
            initializeTimeout: Duration = .seconds(2),
            requestTimeout: Duration = .seconds(2),
            maximumRestarts: Int = 2,
            openDocumentLimit: Int = 32,
            initializationOptions: JSONValue? = nil,
            environment: [String: String]? = nil
        ) {
            self.serverExecutable = serverExecutable
            self.serverArguments = serverArguments
            self.workspaceRoot = workspaceRoot
            self.idleShutdown = idleShutdown
            self.initializeTimeout = initializeTimeout
            self.requestTimeout = requestTimeout
            self.maximumRestarts = maximumRestarts
            self.openDocumentLimit = openDocumentLimit
            self.initializationOptions = initializationOptions
            self.environment = environment
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

    /// What the server said of semantic tokens when it initialized; nil when it has none, or before it initialized.
    private var semanticSupport: InitializeResult.SemanticTokensSupport?
    /// Each open document's last semantic tokens, which a delta request names and applies to.
    private var semanticStates: [String: LSPSemanticTokenDecoder.SemanticTokensState] = [:]

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

    /// The server's executable name, which the log names it by.
    private nonisolated var serverName: String { configuration.serverExecutable.lastPathComponent }

    /// How long any request after the handshake may take.
    public nonisolated var requestTimeout: Duration { configuration.requestTimeout }

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
            let server = serverName
            Self.logger.error("\(server, privacy: .public) went away during a hover: \(reason, privacy: .public)")
            await abruptTeardown()
            return .unavailable
        } catch is CancellationError {
            // The caller moved on, as when the pointer leaves the identifier.
            Self.logger.debug("A hover was cancelled")
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
        semanticStates.removeAll()
        semanticSupport = nil
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
            let initialized = try await performHandshake(created)
            guard connectionGeneration == startedGeneration else {
                // A teardown ran meanwhile: stop this connection instead of publishing it.
                await created.stop()
                resumeEstablishingWaiters(with: nil)
                return nil
            }
            connection = created
            semanticSupport = initialized.semanticTokens
            resumeEstablishingWaiters(with: created)
            return created
        } catch {
            let reason = String(describing: error)
            Self.logger.error("\(self.serverName, privacy: .public) did not start: \(reason, privacy: .public)")
            // A created connection has a running process behind it even when `initialize` failed.
            if let newConnection {
                await newConnection.stop()
            }
            restartsUsed += 1
            if restartsUsed > configuration.maximumRestarts {
                let attempts = restartsUsed
                let server = serverName
                Self.logger.error(
                    "\(server, privacy: .public) failed to start \(attempts, privacy: .public) times; no more restarts")
                permanentlyUnavailable = true
            } else {
                do {
                    try await clock.sleep(for: .seconds(1))
                } catch {
                    // Cancelled: the caller no longer waits, and the next hover may restart at once.
                    Self.logger.debug("The restart backoff ended early: \(String(describing: error), privacy: .public)")
                }
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

    /// Starts `connection` and initializes the server: what the server answered, read for its semantic tokens.
    private func performHandshake(_ connection: LSPConnection) async throws -> InitializeResult {
        await connection.start()
        let root = configuration.workspaceRoot
        let params = InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier), rootUri: root.absoluteString,
            initializationOptions: configuration.initializationOptions,
            workspaceFolders: [WorkspaceFolder(uri: root.absoluteString, name: root.lastPathComponent)])
        let result = try await raceAgainstTimeout(clock: clock, timeout: configuration.initializeTimeout) {
            try await connection.request("initialize", params, as: InitializeResult.self)
        }
        try await connection.notify("initialized", InitializedParams())
        return result
    }

    /// Drops a connection whose transport is gone, skipping the `shutdown`/`exit` exchange it cannot answer.
    private func abruptTeardown() async {
        connectionGeneration += 1
        guard let connection else { return }
        self.connection = nil
        openDocuments.removeAll()
        openOrder.removeAll()
        semanticStates.removeAll()
        semanticSupport = nil
        await connection.stop()
    }

    /// Ends a session that may still be listening: `shutdown`, then `exit`, then the transport closes.
    private func gracefulTeardown(_ connection: LSPConnection) async {
        do {
            _ = try await raceAgainstTimeout(clock: clock, timeout: .milliseconds(500)) {
                try await connection.requestOptional("shutdown", JSONValue.null, as: DiscardedResult.self)
            }
        } catch {
            // Stopping the connection below ends the server all the same.
            let reason = String(describing: error)
            let server = serverName
            Self.logger.info("\(server, privacy: .public) did not acknowledge shutdown: \(reason, privacy: .public)")
        }
        await send("exit", JSONValue.null, on: connection)
        await connection.stop()
    }

    /// Sends a notification, logging a failure: a dead transport also fails the next request, which tears the
    /// connection down.
    private func send(_ method: String, _ params: some Encodable & Sendable, on connection: LSPConnection) async {
        do {
            try await connection.notify(method, params)
        } catch {
            let reason = String(describing: error)
            Self.logger.debug("Could not send \(method, privacy: .public): \(reason, privacy: .public)")
        }
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
                Self.logger.debug("Idle timer \(generation, privacy: .public) superseded")
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
        semanticStates.removeAll()
        semanticSupport = nil
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
            // The whole new text, one version on: the server keeps the document, and a semantic tokens delta against
            // its last result stays meaningful.
            let newVersion = existing.version + 1
            openDocuments[uri] = OpenDocument(version: newVersion, contentHash: hash)
            await send(
                "textDocument/didChange",
                DidChangeTextDocumentParams(
                    textDocument: VersionedTextDocumentIdentifier(uri: uri, version: newVersion),
                    contentChanges: [TextDocumentContentChangeEvent(text: content)]),
                on: connection)
            touch(uri)
            return
        }

        if openOrder.count >= configuration.openDocumentLimit {
            await evictOldest(on: connection)
        }

        openDocuments[uri] = OpenDocument(version: 1, contentHash: hash)
        openOrder.append(uri)
        await send(
            "textDocument/didOpen",
            DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(uri: uri, languageId: languageID, version: 1, text: content)),
            on: connection)
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
        semanticStates.removeValue(forKey: oldest)
        await send(
            "textDocument/didClose", DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: oldest)),
            on: connection)
    }

    // MARK: - The real-world factory

    /// The server process `configuration` describes, not yet started: its executable, arguments and environment, run
    /// in the workspace root.
    static func processSession(for configuration: Configuration) -> ProcessSession {
        ProcessSession(
            executable: configuration.serverExecutable, arguments: configuration.serverArguments,
            environment: configuration.environment, workingDirectory: configuration.workspaceRoot)
    }

    private static func defaultConnectionFactory(_ configuration: Configuration) async throws -> LSPConnection {
        let session = processSession(for: configuration)
        try await session.start()
        let transport = ProcessSessionTransport(session: session)
        return LSPConnection(transport: transport)
    }
}

// MARK: - Semantic tokens

extension LanguageServerSession {
    /// The semantic tokens of `uri`, a `file://` document, opened with `content` on the server first: the whole
    /// document's the first time, then a delta against the last result when the server gives deltas. A reply for an
    /// older version of the document, which a change of `content` made meanwhile, is dropped. A URI that is not a
    /// `file://` one, as a git blob's, is never sent. Restarts the idle timer.
    public func semanticTokens(uri: String, languageID: String, content: String) async -> SemanticTokensOutcome {
        guard uri.hasPrefix("file://"), !permanentlyUnavailable else { return .unavailable }
        defer { scheduleIdleShutdown() }
        guard let connection = await ensureConnection() else { return .unavailable }
        guard let support = semanticSupport, support.full else { return .unsupported }
        await ensureOpen(uri: uri, languageID: languageID, content: content, on: connection)
        guard let version = openDocuments[uri]?.version else { return .unavailable }
        let generation = connectionGeneration
        let document = TextDocumentIdentifier(uri: uri)
        let previous = support.delta ? semanticStates[uri] : nil
        do {
            var state = previous ?? LSPSemanticTokenDecoder.SemanticTokensState()
            if let previous, let previousID = previous.resultId {
                let reply = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
                    try await connection.requestOptional(
                        "textDocument/semanticTokens/full/delta",
                        SemanticTokensDeltaParams(textDocument: document, previousResultId: previousID),
                        as: SemanticTokensDeltaResult.self)
                }
                // The delta applies to the result it names, which a concurrent request may have replaced.
                guard isCurrent(uri, version: version, generation: generation),
                    semanticStates[uri]?.resultId == previousID
                else { return .superseded }
                switch reply {
                    case .full(let result): state.applyFull(resultId: result.resultId, data: result.data)
                    case .delta(let resultID, let edits): state.applyDelta(resultId: resultID, edits: edits)
                    case nil: state.applyFull(resultId: nil, data: [])
                }
            } else {
                let reply = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
                    try await connection.requestOptional(
                        "textDocument/semanticTokens/full", SemanticTokensParams(textDocument: document),
                        as: SemanticTokensResult.self)
                }
                guard isCurrent(uri, version: version, generation: generation) else { return .superseded }
                state.applyFull(resultId: reply?.resultId, data: reply?.data ?? [])
            }
            semanticStates[uri] = state
            return .tokens(data: state.data, legend: support.legend)
        } catch LSPServiceError.timedOut {
            Self.logger.info("Semantic tokens timed out for a document")
            return .timedOut
        } catch LSPConnectionError.transportClosed(let reason) {
            let server = serverName
            Self.logger.error(
                "\(server, privacy: .public) went away during semantic tokens: \(reason, privacy: .public)")
            await abruptTeardown()
            return .unavailable
        } catch {
            Self.logger.info("Semantic tokens got no answer: \(String(describing: error), privacy: .public)")
            return .unavailable
        }
    }

    /// Whether `uri` is still open at `version` on the connection of `generation`.
    private func isCurrent(_ uri: String, version: Int, generation: Int) -> Bool {
        connectionGeneration == generation && openDocuments[uri]?.version == version
    }
}

// MARK: - Documentation pages

extension LanguageServerSession {
    /// The page Apple's developer documentation gives the system symbol at the position, where a hover has opened
    /// `uri` with `content`; nil for the workspace's own symbols, when the server does not answer, and when the text
    /// reaches the symbol through a value rather than through its types. Asks `textDocument/symbolInfo` about
    /// the symbol, for its name and labels, and about the type its chain starts with, whose module files the page even
    /// when another module declares the symbol, as Foundation does `String.Encoding.utf8`. Restarts the idle timer.
    public func documentationPage(
        uri: String, languageID: String, content: String, line: Int, utf16Column: Int
    ) async -> HoverContent.DocumentationPage? {
        guard !permanentlyUnavailable,
            let chain = DocumentationChain(content: content, line: line, utf16Column: utf16Column)
        else { return nil }
        defer { scheduleIdleShutdown() }
        guard let connection = await ensureConnection() else { return nil }
        await ensureOpen(uri: uri, languageID: languageID, content: content, on: connection)

        guard let symbol = await systemSymbol(uri: uri, line: line, utf16Column: utf16Column, on: connection) else {
            return nil
        }
        guard chain.segments.count > 1, !chain.startsWith(module: symbol.module) else {
            return chain.page(module: symbol.module, symbolName: symbol.name)
        }
        guard let root = await systemSymbol(uri: uri, line: line, utf16Column: chain.rootColumn, on: connection)
        else { return nil }
        return chain.page(module: root.module, symbolName: symbol.name)
    }

    /// The name and top-level module of the system symbol at the position, as `textDocument/symbolInfo` gives them;
    /// nil for a symbol with sources, or when no answer comes.
    private func systemSymbol(
        uri: String, line: Int, utf16Column: Int, on connection: LSPConnection
    ) async -> (name: String, module: String)? {
        let params = HoverParams(
            textDocument: TextDocumentIdentifier(uri: uri), position: Position(line: line, character: utf16Column))
        do {
            let symbols = try await raceAgainstTimeout(clock: clock, timeout: configuration.requestTimeout) {
                try await connection.requestOptional("textDocument/symbolInfo", params, as: [SymbolDetails].self)
            }
            guard let symbol = symbols?.first(where: { $0.systemModule != nil }), let name = symbol.name,
                let module = symbol.systemModule?.moduleName.split(separator: ".").first
            else { return nil }
            return (name, String(module))
        } catch {
            // A page is extra: whatever went wrong, the hover that asked for it stands, and reports its own failures.
            Self.logger.debug("No symbol info: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
