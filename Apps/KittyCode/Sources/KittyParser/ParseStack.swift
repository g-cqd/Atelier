import Synchronization

private let parseStackIDs = ParseStackIDGenerator()

private final class ParseStackIDGenerator: Sendable {
    private let counter = Mutex(0)

    func next() -> Int {
        counter.withLock { counter in
            let current = counter
            counter += 1
            return current
        }
    }
}

struct ParseStack: Sendable {
    let id: Int
    var state: Int
    var stateStack: [Int]
    var nodes: [SyntaxNode]
    var errorCount: Int
    // TODO: Used for future incremental-lexing scanner checkpointing
    var scannerState: [UInt8]

    var stateBeforeTop: Int {
        stateStack.last ?? 0
    }

    init(state: Int) {
        self.id = parseStackIDs.next()
        self.state = state
        self.stateStack = [state]
        self.nodes = []
        self.errorCount = 0
        self.scannerState = []
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
        for _ in 0 ..< min(count, stateStack.count - 1) {
            stateStack.removeLast()
        }
        state = stateStack.last ?? 0
        return popped
    }
}
