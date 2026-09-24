import Foundation

/// Runs swift-syntax work on a stack deep enough for it. The parser and a walk over its tree recurse once per level of
/// nesting and stop descending only at 256 levels of brackets, while a Swift concurrency or pool thread's 512 KiB stack
/// overflows at about 80 in a release build. Text in another language gets there easily: its comments and single-quoted
/// strings are neither to Swift, so each bracket in them opens a level that never closes. Work sent here runs on a
/// thread with a 64 MiB stack, or in place on a thread that already has 4 MiB, such as the main thread.
public enum SwiftSyntaxStack {
    /// The stack of the threads this starts: address space reserved up front, committed only as deep as the work goes.
    public static let stackSize = 64 << 20
    /// The smallest stack the work runs on in place.
    static let inPlaceStackSize = 4 << 20

    /// Whether the calling thread's stack holds swift-syntax's deepest recursion.
    static var callerIsDeepEnough: Bool {
        pthread_get_stacksize_np(pthread_self()) >= inPlaceStackSize
    }

    /// `body`'s result, computed on a deep enough stack. The calling thread waits while another thread runs `body`, so
    /// call this from synchronous code only; a task awaits the asynchronous `run` instead.
    public static func run<T>(_ body: @escaping () -> T) -> T {
        if callerIsDeepEnough { return body() }
        let handoff = Handoff(body)
        start { handoff.run() }
        return handoff.wait()
    }

    /// `body`'s result, computed on a thread with a deep enough stack while the calling task is suspended.
    public static func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            start { continuation.resume(returning: body()) }
        }
    }

    /// Starts a thread with a ``stackSize`` stack, at the caller's quality of service, that runs `work` and exits.
    private static func start(_ work: @escaping @Sendable () -> Void) {
        let thread = Thread(block: work)
        thread.stackSize = stackSize
        thread.qualityOfService = Thread.current.qualityOfService
        thread.name = "SwiftSyntaxStack"
        thread.start()
    }
}

/// A body handed to another thread and its result handed back. The semaphore orders the result's write before its
/// read, and the waiting thread touches nothing else, which is why the unchecked sendability holds.
private final class Handoff<T>: @unchecked Sendable {
    private let body: () -> T
    private var result: T?
    private let done = DispatchSemaphore(value: 0)

    init(_ body: @escaping () -> T) {
        self.body = body
    }

    /// Runs the body on the calling thread and hands its result over.
    func run() {
        result = body()
        done.signal()
    }

    /// Waits for ``run()`` on the other thread, then returns what it produced.
    func wait() -> T {
        done.wait()
        guard let result else { preconditionFailure("the other thread signalled before it stored a result") }
        return result
    }
}
