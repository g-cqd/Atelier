import Darwin
public import Foundation

/// One session per workspace root and language server; sessions start lazily and are shut down together.
///
/// Sessions are keyed by their root's canonical path (``canonicalRoot(_:)``) and their server's
/// ``LanguageServerDescriptor/id``, so every spelling of one directory, with or without a trailing slash or through a
/// symbolic link, shares one session per server, and one root can run several servers side by side. A document's root
/// is found by walking up to its server's root markers (``workspaceRoot(forDocumentAt:within:markers:)``). Every
/// request asks the admission check first, so a root it refuses gets no session, neither a running one nor a new one.
public actor LanguageServerRegistry {
    /// Whether a session of a server may run at a canonical root.
    public typealias Admission = @Sendable (URL, LanguageServerDescriptor) async -> Bool
    /// A server's session configuration at a canonical root; nil when the server does not resolve there.
    public typealias ConfigurationFactory =
        @Sendable (URL, LanguageServerDescriptor) async -> LanguageServerSession.Configuration?

    private let admits: Admission
    private let makeConfiguration: ConfigurationFactory

    /// A session's table key: its root's canonical path and its server's id.
    private struct Key: Hashable {
        let root: String
        let serverID: String
    }

    private typealias Waiter = CheckedContinuation<LanguageServerSession?, Never>

    /// A root's resolved session, or the callers waiting on its first initialization.
    private enum Entry {
        case ready(LanguageServerSession?)
        /// `token` names the initialization, so one whose entry was removed meanwhile stops instead of publishing.
        case inProgress(token: Int, waiters: [Waiter])
    }

    /// A `nil` ready entry caches a root where the server does not resolve until ``shutdown(root:)`` or
    /// ``shutdownAll()``.
    private var entries: [Key: Entry] = [:]
    private var nextToken = 0

    /// - Parameters:
    ///   - admits: Whether a session of the server may run at a canonical root. Asked on every request, and again
    ///     before a new session is published; its answer is never cached.
    ///   - makeConfiguration: The session's configuration for the server at an admitted canonical root, or nil when
    ///     the server does not resolve there, which is cached.
    public init(admits: @escaping Admission, makeConfiguration: @escaping ConfigurationFactory) {
        self.admits = admits
        self.makeConfiguration = makeConfiguration
    }

    /// `server`'s session for the document at `document`, a file URL, rooted at the nearest directory holding one of
    /// the server's root markers between the document and `ceiling`, or at `ceiling` when none does
    /// (``workspaceRoot(forDocumentAt:within:markers:)``); nil as ``session(forRoot:server:)`` answers it.
    public func session(
        forDocumentAt document: URL, within ceiling: URL, server: LanguageServerDescriptor
    ) async -> LanguageServerSession? {
        guard let canonicalCeiling = Self.canonicalRoot(ceiling) else { return nil }
        let root = Self.workspaceRoot(forDocumentAt: document, within: canonicalCeiling, markers: server.rootMarkers)
        return await session(forRoot: root, server: server)
    }

    /// `server`'s session for `root`, created on the first admitted request; `nil` when `root` names no existing
    /// directory, when the admission check refuses it, or when the server does not resolve for it (cached). Concurrent
    /// first requests share one initialization, so a root never gets two sessions of one server.
    public func session(forRoot root: URL, server: LanguageServerDescriptor) async -> LanguageServerSession? {
        guard let canonical = Self.canonicalRoot(root) else { return nil }
        guard await admits(canonical, server) else { return nil }
        let key = Key(root: Self.key(of: canonical), serverID: server.id)
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
                let configuration = await makeConfiguration(canonical, server)
                let service = configuration.map { LanguageServerSession(configuration: $0) }
                let stillAdmitted = await admits(canonical, server)
                return await publish(service, key: key, token: token, admitted: stillAdmitted)
        }
    }

    /// Publishes one initialization's outcome to its waiters. The new service is shut down instead when its entry
    /// was removed meanwhile, and dropped uncached when the root lost its admission during the initialization.
    private func publish(
        _ service: LanguageServerSession?, key: Key, token: Int, admitted: Bool
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

    /// Shuts down every server's session at `root`, if any, and forgets them, so the root's next request resolves
    /// afresh. Callers waiting on an initialization there get `nil` at once. A root that no longer resolves is looked
    /// up by its path as given, which matches when `root` is already canonical.
    public func shutdown(root: URL) async {
        let path = Self.canonicalRoot(root).map(Self.key(of:)) ?? Self.key(of: root)
        let keys = entries.keys.filter { $0.root == path }
        var services: [LanguageServerSession] = []
        for key in keys {
            switch entries.removeValue(forKey: key) {
                case .ready(let service?):
                    services.append(service)
                case .inProgress(_, let waiters):
                    for waiter in waiters { waiter.resume(returning: nil) }
                default:
                    break
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { await service.shutdown() }
            }
        }
    }

    /// Shuts down every session this registry started, concurrently, and forgets every root, so the next
    /// ``session(forRoot:server:)`` resolves afresh. Callers waiting on an initialization in flight get `nil` at once.
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

    /// The nearest directory from `document`'s own up to `ceiling` that holds `markers`' first marker found there,
    /// trying each marker in turn, strongest first; `ceiling` when none holds one, when `markers` is empty, or when
    /// `document` does not lie under `ceiling`. `ceiling` is canonical, and `document` a file URL under its spelling.
    /// - Complexity: One `stat(2)` per marker and directory between `document` and `ceiling`, at most.
    public static func workspaceRoot(forDocumentAt document: URL, within ceiling: URL, markers: [String]) -> URL {
        let ceilingPath = key(of: ceiling)
        let documentPath = document.path(percentEncoded: false)
        let prefix = ceilingPath == "/" ? "/" : ceilingPath + "/"
        guard !markers.isEmpty, documentPath.hasPrefix(prefix) else { return ceiling }
        // The document's directories from its own up to the ceiling's child, then the ceiling itself.
        var components = documentPath.dropFirst(prefix.count).split(separator: "/").map(String.init)
        components.removeLast()
        var directories: [String] = []
        while !components.isEmpty {
            directories.append(prefix + components.joined(separator: "/"))
            components.removeLast()
        }
        directories.append(ceilingPath)
        let fileManager = FileManager.default
        for marker in markers {
            for directory in directories
            where fileManager.fileExists(atPath: (directory as NSString).appendingPathComponent(marker)) {
                return URL(filePath: directory, directoryHint: .isDirectory)
            }
        }
        return ceiling
    }

    /// The table key of a root: its path without a trailing slash, except for the file system root itself.
    private static func key(of root: URL) -> String {
        let path = root.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
