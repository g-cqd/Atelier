import Foundation

/// A Swift concurrency pool thread's stack, rounded down: an ``LSPConnection`` decodes every result on such a thread.
let poolThreadStackSize = 512 * 1_024

/// Runs `body` on a new thread with a `stackSize`-byte stack and returns its result once `body` has returned and
/// released everything it created.
func onThread<Result: Sendable>(
    stackSize: Int = poolThreadStackSize,
    _ body: @escaping @Sendable () -> Result
) async -> Result {
    await withCheckedContinuation { continuation in
        let thread = Thread { continuation.resume(returning: body()) }
        thread.stackSize = stackSize
        thread.start()
    }
}
