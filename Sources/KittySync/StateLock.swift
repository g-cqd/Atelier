import Foundation
#if canImport(os)
import os
#endif
#if canImport(Synchronization)
import Synchronization
#endif

public final class StateLock<State: Sendable>: @unchecked Sendable {
    #if canImport(Synchronization)
    private let mutexBox: AnyObject?
    #endif
    #if canImport(os)
    private let unfairLock: OSAllocatedUnfairLock<State>
    #else
    private let nsLock = NSLock()
    private var state: State
    #endif

    public init(initialState: sending State) {
        #if canImport(Synchronization)
        if #available(macOS 15, *) {
            mutexBox = MutexBox(initialState)
        } else {
            mutexBox = nil
        }
        #endif
        #if canImport(os)
        unfairLock = OSAllocatedUnfairLock(initialState: initialState)
        #else
        state = initialState
        #endif
    }

    public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
        #if canImport(Synchronization)
        if #available(macOS 15, *), let mutexBox = mutexBox as? MutexBox<State> {
            return try mutexBox.withLock(body)
        }
        #endif
        #if canImport(os)
        return try unfairLock.withLock(body)
        #else
        nsLock.lock()
        defer { nsLock.unlock() }
        return try body(&state)
        #endif
    }
}

#if canImport(Synchronization)
@available(macOS 15, *)
private final class MutexBox<State>: @unchecked Sendable {
    private let mutex: Mutex<State>

    init(_ initialState: sending State) {
        mutex = Mutex(initialState)
    }

    func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
        try mutex.withLock { state in
            try body(&state)
        }
    }
}
#endif
