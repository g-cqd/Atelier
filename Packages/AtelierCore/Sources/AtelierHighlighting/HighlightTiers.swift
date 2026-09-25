public import AtelierSyntaxModel
import Synchronization

/// What a tier job reports, tier by tier.
public enum TierEvent: Sendable {
    /// A tier's tokens for some lines.
    case update(TierUpdate)
    /// A tier emitted everything it had.
    case finished(HighlightLayer)
    /// A tier gave up; what it emitted before stands, and the lines it did not reach keep the layers below.
    case failed(HighlightLayer, TierFailure)
}

/// The tier job (PERF-11): every tier that supports a text's language starts at once, one child task each, and none
/// waits for another, so a slow or failing tier never delays the others.
///
/// The job is caller-driven, as the core requires: `run` is an async function whose child tasks live in a task group,
/// and it starts no unstructured task. Cancelling the caller's task cancels every tier.
public enum HighlightTiers {
    /// Runs every tier of `tiers` that supports the request's language, each against its own deadline on `clock`,
    /// and hands `emit` each event as it happens, from the tier's own task. Returns once every tier has finished,
    /// failed or timed out, or at once when the calling task is cancelled.
    /// - Parameters:
    ///   - request: The text, its revision, its lines and which of them show.
    ///   - tiers: The tiers the app composes; those that do not support the language are left out.
    ///   - clock: The clock deadlines are measured on.
    ///   - emit: Called with each event, concurrently from several tiers.
    public static func run(
        _ request: TierRequest, tiers: [any HighlightTier], clock: any Clock<Duration>,
        emit: @escaping @Sendable (TierEvent) async -> Void
    ) async {
        let supported = tiers.filter { $0.supports(request.revision.language) }
        await withTaskGroup(of: Void.self) { group in
            for tier in supported {
                group.addTask { await run(tier, request, clock: clock, emit: emit) }
            }
        }
    }

    /// The same job as a stream: iterate `events` while `run` runs in a task of the caller's, a child of a task group
    /// or an `async let`. The stream finishes when `run` returns.
    public static func events(
        _ request: TierRequest, tiers: [any HighlightTier], clock: any Clock<Duration>
    ) -> (events: AsyncStream<TierEvent>, run: @Sendable () async -> Void) {
        let (events, continuation) = AsyncStream.makeStream(of: TierEvent.self)
        return (
            events,
            {
                await run(request, tiers: tiers, clock: clock) { continuation.yield($0) }
                continuation.finish()
            }
        )
    }

    /// One tier, raced against its deadline. Once the deadline passes, the tier is cancelled and nothing more it emits
    /// is passed on.
    private static func run(
        _ tier: any HighlightTier, _ request: TierRequest, clock: any Clock<Duration>,
        emit: @escaping @Sendable (TierEvent) async -> Void
    ) async {
        let gate = EmitGate()
        let layer = tier.layer
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await tier.run(request) { update in
                        if gate.isOpen { await emit(.update(update)) }
                    }
                    if gate.close() { await emit(.finished(layer)) }
                } catch is CancellationError {
                    gate.close()
                } catch let failure as TierFailure {
                    if gate.close() { await emit(.failed(layer, failure)) }
                } catch {
                    if gate.close() { await emit(.failed(layer, .failed(String(describing: error)))) }
                }
                return true
            }
            if let deadline = tier.deadline {
                group.addTask {
                    do {
                        try await clock.sleep(for: deadline)
                    } catch {
                        return false
                    }
                    if gate.close() { await emit(.failed(layer, .deadline(deadline))) }
                    return true
                }
            }
            // The first child to end, the tier or its deadline, ends the other.
            for await ended in group where ended {
                group.cancelAll()
                break
            }
        }
    }
}

/// Whether a tier may still emit: open until it finishes, fails or times out, whichever comes first.
private final class EmitGate: Sendable {
    private let open = Mutex(true)

    var isOpen: Bool { open.withLock { $0 } }

    /// Closes the gate; true for the caller that closed it.
    @discardableResult
    func close() -> Bool {
        open.withLock { isOpen in
            defer { isOpen = false }
            return isOpen
        }
    }
}
