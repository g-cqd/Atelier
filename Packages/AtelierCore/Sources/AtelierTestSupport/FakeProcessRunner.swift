public import AtelierProcess
import Foundation
import Synchronization

/// A ``ProcessRunner`` that never spawns: it answers each spec through `handler` and records every spec it was
/// given, so a test asserts on the exact command a client built and scripts the output or failure it gets back.
public final class FakeProcessRunner: ProcessRunner, Sendable {
    public typealias Handler = @Sendable (ProcessSpec) async throws -> ProcessOutput

    private let handler: Handler
    private let recorded = Mutex<[ProcessSpec]>([])

    /// - Parameter handler: Produces the output for a spec; it may suspend, throw, or observe cancellation.
    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// A runner that answers every spec with `output`.
    public convenience init(always output: ProcessOutput) {
        self.init { _ in output }
    }

    /// Every spec run so far, in order.
    public var specs: [ProcessSpec] { recorded.withLock { $0 } }

    public func run(_ spec: ProcessSpec) async throws -> ProcessOutput {
        recorded.withLock { $0.append(spec) }
        return try await handler(spec)
    }
}

extension ProcessOutput {
    /// A successful run that printed `text`.
    public static func success(_ text: String) -> ProcessOutput {
        ProcessOutput(terminationStatus: 0, standardOutput: Data(text.utf8), standardError: Data())
    }

    /// A failed run with `status` that wrote `error` to standard error.
    public static func failure(_ status: Int32, error: String) -> ProcessOutput {
        ProcessOutput(terminationStatus: status, standardOutput: Data(), standardError: Data(error.utf8))
    }
}
