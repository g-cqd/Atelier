import Darwin
public import Foundation

/// One language-server session per workspace root; sessions start lazily and are shut down together.
///
/// Roots are keyed by their canonical path (``canonicalRoot(_:)``), so every spelling of one directory, with or
/// without a trailing slash or through a symbolic link, shares one session. Every request asks the admission check
/// first, so a root it refuses gets no session, neither a running one nor a new one.
public actor SourceKitLSPRegistry {
    private let admits: @Sendable (URL) async -> Bool
    private let makeConfiguration: @Sendable (URL) async -> LanguageServerSession.Configuration?

    private typealias Waiter = CheckedContinuation<LanguageServerSession?, Never>

    /// A root's resolved session, or the callers waiting on its first initialization.
    private enum Entry {
        case ready(LanguageServerSession?)
        /// `token` names the initialization, so one whose entry was removed meanwhile stops instead of publishing.
        case inProgress(token: Int, waiters: [Waiter])
    }

    /// Keyed by canonical path. A `nil` ready entry caches a root with no resolvable server until
    /// ``shutdown(root:)`` or ``shutdownAll()``.
    private var entries: [String: Entry] = [:]
    private var nextToken = 0

    /// - Parameters:
    ///   - admits: Whether a session may run at a canonical root. Asked on every request, and again before a new
    ///     session is published; its answer is never cached.
    ///   - makeConfiguration: The session's configuration for an admitted canonical root, or nil when no server
    ///     resolves there, which is cached.
    public init(
        admits: @Sendable @escaping (URL) async -> Bool,
        makeConfiguration: @Sendable @escaping (URL) async -> LanguageServerSession.Configuration?
    ) {
        self.admits = admits
        self.makeConfiguration = makeConfiguration
    }

    /// The session for `root`, created on the first admitted request; `nil` when `root` names no existing directory,
    /// when the admission check refuses it, or when no server executable resolves for it (cached). Concurrent first
    /// requests share one initialization, so a root never gets two services.
    public func service(forRoot root: URL) async -> LanguageServerSession? {
        guard let canonical = Self.canonicalRoot(root) else { return nil }
        guard await admits(canonical) else { return nil }
        let key = Self.key(of: canonical)
        switch entries[key] {
            case .ready(let service):
                return service
            case .inProgress:
                return await withCheckedContinuation { (continuation: Waiter) in
                    if case .inProgress(let token, var waiters) = entries[key] {
                        waiters.append(continuation)
                        entries[key] = .inProgress(token: token, waiters: waiters)
                    } else {
                        // Unreachable without a suspension since the switch; resumed rather than leaked all the same.
                        continuation.resume(returning: nil)
                    }
                }
            case nil:
                nextToken += 1
                let token = nextToken
                entries[key] = .inProgress(token: token, waiters: [])
                let configuration = await makeConfiguration(canonical)
                let service = configuration.map { LanguageServerSession(configuration: $0) }
                let stillAdmitted = await admits(canonical)
                return await publish(service, key: key, token: token, admitted: stillAdmitted)
        }
    }

    /// Publishes one initialization's outcome to its waiters. The new service is shut down instead when its entry
    /// was removed meanwhile, and dropped uncached when the root lost its admission during the initialization.
    private func publish(
        _ service: LanguageServerSession?, key: String, token: Int, admitted: Bool
    ) async -> LanguageServerSession? {
        guard case .inProgress(let current, let waiters) = entries[key], current == token else {
            // `shutdown(root:)` or `shutdownAll()` removed the entry and already answered its waiters.
            if let service { await service.shutdown() }
            return nil
        }
        guard admitted else {
            entries[key] = nil
            for waiter in waiters { waiter.resume(returning: nil) }
            if let service { await service.shutdown() }
            return nil
        }
        entries[key] = .ready(service)
        for waiter in waiters { waiter.resume(returning: service) }
        return service
    }

    /// Shuts down `root`'s session, if any, and forgets the root, so its next request resolves afresh. Callers
    /// waiting on its initialization get `nil` at once. A root that no longer resolves is looked up by its path as
    /// given, which matches when `root` is already canonical.
    public func shutdown(root: URL) async {
        let key = Self.canonicalRoot(root).map(Self.key(of:)) ?? Self.key(of: root)
        guard let entry = entries.removeValue(forKey: key) else { return }
        switch entry {
            case .ready(let service):
                await service?.shutdown()
            case .inProgress(_, let waiters):
                for waiter in waiters { waiter.resume(returning: nil) }
        }
    }

    /// Shuts down every session this registry started, concurrently, and forgets every root, so the next
    /// ``service(forRoot:)`` resolves afresh. Callers waiting on an initialization in flight get `nil` at once.
    public func shutdownAll() async {
        let removed = entries
        entries.removeAll()
        var readyServices: [LanguageServerSession] = []
        for entry in removed.values {
            switch entry {
                case .ready(let service):
                    if let service { readyServices.append(service) }
                case .inProgress(_, let waiters):
                    for waiter in waiters { waiter.resume(returning: nil) }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for service in readyServices {
                group.addTask { await service.shutdown() }
            }
        }
    }

    // MARK: - Canonical roots

    /// `url`'s real path, with every symbolic link, `.` and `..` resolved and no trailing slash, as a directory URL;
    /// nil when `url` is not a file URL or does not name an existing directory.
    /// - Complexity: One `realpath(3)` call, which reads the file system once per path component, and one `stat(2)`.
    public static func canonicalRoot(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let path = url.path(percentEncoded: false)
        guard !path.isEmpty, let resolved = realpath(path, nil) else { return nil }
        // `realpath` hands back a NUL-terminated buffer it allocated with `malloc`, which the caller owns.
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDirectory), isDirectory.boolValue
        else { return nil }
        return URL(filePath: canonical, directoryHint: .isDirectory)
    }

    /// The table key of a root: its path without a trailing slash, except for the file system root itself.
    private static func key(of root: URL) -> String {
        let path = root.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
