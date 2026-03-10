#if canImport(os)
import os
private let parseStackCounter = OSAllocatedUnfairLock(initialState: 0)
#else
import Foundation
private let _parseStackLock = NSLock()
private var _parseStackCounterValue = 0
#endif

struct ParseStack: Sendable {
    let id: Int
    var state: Int
    var stateStack: [Int]
    var nodes: [SyntaxNode]
    var errorCount: Int

    var stateBeforeTop: Int {
        stateStack.last ?? 0
    }

    init(state: Int) {
        #if canImport(os)
        self.id = parseStackCounter.withLock { val in
            let current = val
            val += 1
            return current
        }
        #else
        _parseStackLock.lock()
        self.id = _parseStackCounterValue
        _parseStackCounterValue += 1
        _parseStackLock.unlock()
        #endif
        self.state = state
        self.stateStack = [state]
        self.nodes = []
        self.errorCount = 0
    }

    mutating func pushNode(_ node: SyntaxNode) {
        stateStack.append(state)
        nodes.append(node)
        if node.isError { errorCount += 1 }
    }

    mutating func popNodes(_ count: Int) -> [SyntaxNode] {
        guard count > 0 else { return [] }
        let popped = Array(nodes.suffix(count))
        nodes.removeLast(min(count, nodes.count))
        for _ in 0..<min(count, stateStack.count - 1) {
            stateStack.removeLast()
        }
        state = stateStack.last ?? 0
        return popped
    }
}
