@testable import AtelierLSP

/// Builds a fresh ``PipeTransport`` on every ``LSPConnection`` a service asks for, as a real server restart would,
/// and remembers each one, so a test can script a whole generation of the conversation.
actor ScriptedConnectionFactory {
    private(set) var transports: [PipeTransport] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    /// The standing answers every new transport starts with (``PipeTransport/answer(_:with:)``).
    private let answers: [String: JSONValue]

    init(answering answers: [String: JSONValue] = [:]) {
        self.answers = answers
    }

    func make() -> LSPConnection {
        let transport = PipeTransport()
        for (method, result) in answers { transport.answer(method, with: result) }
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
