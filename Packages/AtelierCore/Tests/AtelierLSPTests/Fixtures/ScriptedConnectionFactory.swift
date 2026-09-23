@testable import AtelierLSP

/// Builds a fresh ``PipeTransport`` on every ``LSPConnection`` a service asks for, as a real server restart would,
/// and remembers each one, so a test can script a whole generation of the conversation.
actor ScriptedConnectionFactory {
    private(set) var transports: [PipeTransport] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func make() -> LSPConnection {
        let transport = PipeTransport()
        transports.append(transport)
        let satisfied = waiters.filter { transports.count >= $0.count }
        waiters.removeAll { transports.count >= $0.count }
        for waiter in satisfied { waiter.continuation.resume() }
        return LSPConnection(transport: transport)
    }

    func transport(at index: Int) -> PipeTransport { transports[index] }
    var generationCount: Int { transports.count }

    /// Returns once at least `count` connections have been made. `make()` resumes the wait on this actor, so a
    /// connection made before the call is counted and one made after it is never missed.
    func waitForGeneration(_ count: Int) async {
        if transports.count >= count { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}
