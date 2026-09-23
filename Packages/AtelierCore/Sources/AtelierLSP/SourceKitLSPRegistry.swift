public import Foundation

/// One language-server session per workspace root; sessions start lazily and are shut down together.
public actor SourceKitLSPRegistry {
    private let makeConfiguration: @Sendable (URL) async -> SourceKitLSPService.Configuration?

    /// A root's resolved session, or the callers waiting on its first initialization.
    private enum Entry {
        case ready(SourceKitLSPService?)
        case inProgress([CheckedContinuation<SourceKitLSPService?, Never>])
    }

    /// A `nil` ready entry caches a root with no resolvable server until ``shutdownAll()``.
    private var entries: [URL: Entry] = [:]
    /// Bumped by every ``shutdownAll()``, so an initialization that spans one is stopped rather than published.
    private var generation = 0

    public init(makeConfiguration: @Sendable @escaping (URL) async -> SourceKitLSPService.Configuration?) {
        self.makeConfiguration = makeConfiguration
    }

    /// The session for `root`, created on the first request; `nil`, cached as well, when no server executable
    /// resolves for it. Concurrent first requests share one initialization, so a root never gets two services.
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
                        // Unreachable without a suspension since the switch; resumed rather than leaked all the same.
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

    /// Publishes one initialization's outcome to its waiters, or shuts the new service down when ``shutdownAll()``
    /// ran meanwhile.
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

    /// Shuts down every session this registry started and forgets every root, so the next ``service(forRoot:)``
    /// resolves afresh. Callers waiting on an initialization in flight get `nil` at once.
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
