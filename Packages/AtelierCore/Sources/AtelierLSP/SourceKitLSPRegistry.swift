public import Foundation

/// One language-server session per workspace root; sessions start lazily and are shut down together.
///
/// Hoisted into ``AtelierLSP`` rather than kept app-side so KittyCode -- or any other client that wants one
/// warm sourcekit-lsp session per workspace -- can reuse it verbatim.
public actor SourceKitLSPRegistry {
    private let makeConfiguration: @Sendable (URL) async -> SourceKitLSPService.Configuration?
    /// `nil` values are meaningful entries: a root for which no server executable could be resolved, cached so
    /// a later lookup does not re-run discovery. `shutdownAll()` drops the whole table, so a fresh lookup after
    /// it re-resolves from scratch.
    private var services: [URL: SourceKitLSPService?] = [:]

    public init(makeConfiguration: @Sendable @escaping (URL) async -> SourceKitLSPService.Configuration?) {
        self.makeConfiguration = makeConfiguration
    }

    /// The session for `root`, creating it on first request. `nil` when no server executable could be resolved
    /// for this root; that failure is cached too, so a repeated lookup does not keep re-running discovery.
    public func service(forRoot root: URL) async -> SourceKitLSPService? {
        if let cached = services[root] { return cached }
        guard let configuration = await makeConfiguration(root) else {
            services[root] = .some(nil)
            return nil
        }
        let service = SourceKitLSPService(configuration: configuration)
        services[root] = .some(service)
        return service
    }

    /// Shuts down every session this registry has started, then forgets them: the next ``service(forRoot:)``
    /// re-resolves and starts fresh.
    public func shutdownAll() async {
        let existing = services.values.compactMap { $0 }
        services.removeAll()
        for service in existing {
            await service.shutdown()
        }
    }
}
