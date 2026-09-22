public import Foundation

/// One language-server session per workspace root; sessions start lazily and are shut down together.
///
/// Hoisted into ``AtelierLSP`` rather than kept app-side so KittyCode -- or any other client that wants one
/// warm sourcekit-lsp session per workspace -- can reuse it verbatim.
public actor SourceKitLSPRegistry {
    private let makeConfiguration: @Sendable (URL) async -> SourceKitLSPService.Configuration?

    /// What ``service(forRoot:)`` knows about one root: a resolved answer, or a first caller's initialization
    /// still running with every other concurrent caller's continuation parked on it.
    private enum Entry {
        case ready(SourceKitLSPService?)
        case inProgress([CheckedContinuation<SourceKitLSPService?, Never>])
    }

    /// `nil` values inside ``Entry/ready(_:)`` are meaningful entries: a root for which no server executable
    /// could be resolved, cached so a later lookup does not re-run discovery. `shutdownAll()` drops the whole
    /// table, so a fresh lookup after it re-resolves from scratch.
    private var entries: [URL: Entry] = [:]
    /// Bumped by every ``shutdownAll()``; an initialization started before a call publishes its result only if
    /// this generation has not moved since, so a session ``shutdownAll()`` already tore the table down for
    /// cannot resurrect itself into it afterward.
    private var generation = 0

    public init(makeConfiguration: @Sendable @escaping (URL) async -> SourceKitLSPService.Configuration?) {
        self.makeConfiguration = makeConfiguration
    }

    /// The session for `root`, creating it on first request. `nil` when no server executable could be resolved
    /// for this root; that failure is cached too, so a repeated lookup does not keep re-running discovery.
    ///
    /// Concurrent first requests for the same root do not each start their own service: the first caller runs
    /// ``makeConfiguration`` and constructs the service, and every other concurrent caller parks until that
    /// result is ready, so a root never ends up with two live services -- only one of which the table (and
    /// therefore ``shutdownAll()``) would ever know about.
    public func service(forRoot root: URL) async -> SourceKitLSPService? {
        switch entries[root] {
            case .ready(let service):
                return service
            case .inProgress:
                typealias Waiter = CheckedContinuation<SourceKitLSPService?, Never>
                return await withCheckedContinuation { (continuation: Waiter) in
                    if case .inProgress(var waiters) = entries[root] {
                        waiters.append(continuation)
                        entries[root] = .inProgress(waiters)
                    } else {
                        // The in-flight attempt finished (and published) between the switch above and this
                        // closure running; both steps are actor-isolated and synchronous, so this cannot
                        // actually happen, but resume rather than leak the continuation if it ever does.
                        continuation.resume(returning: nil)
                    }
                }
            case nil:
                entries[root] = .inProgress([])
                let startedGeneration = generation
                let configuration = await makeConfiguration(root)
                let service = configuration.map { SourceKitLSPService(configuration: $0) }
                return await publish(service, forRoot: root, startedGeneration: startedGeneration)
        }
    }

    /// Publishes the outcome of one initialization, unless ``shutdownAll()`` ran while it was in flight -- in
    /// which case the table has already moved on without it, so this stops the freshly built service (if any)
    /// instead of resurrecting a stale entry or leaving a live connection untracked by any future
    /// ``shutdownAll()``.
    private func publish(
        _ service: SourceKitLSPService?, forRoot root: URL, startedGeneration: Int
    ) async -> SourceKitLSPService? {
        guard generation == startedGeneration else {
            if let service { await service.shutdown() }
            return nil
        }

        guard case .inProgress(let waiters) = entries[root] else {
            entries[root] = .ready(service)
            return service
        }
        entries[root] = .ready(service)
        for waiter in waiters {
            waiter.resume(returning: service)
        }
        return service
    }

    /// Shuts down every session this registry has started, then forgets them: the next ``service(forRoot:)``
    /// re-resolves and starts fresh. Any initialization still in flight is cut loose too -- its waiters are
    /// resumed with `nil` immediately rather than left parked until an initialization racing a now-cleared
    /// table happens to finish.
    public func shutdownAll() async {
        generation += 1
        var readyServices: [SourceKitLSPService] = []
        for entry in entries.values {
            switch entry {
                case .ready(let service):
                    if let service { readyServices.append(service) }
                case .inProgress(let waiters):
                    for waiter in waiters { waiter.resume(returning: nil) }
            }
        }
        entries.removeAll()
        for service in readyServices {
            await service.shutdown()
        }
    }
}
