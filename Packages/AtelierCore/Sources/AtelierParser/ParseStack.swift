struct ParseStack: Sendable {
    var state: Int
    var stateStack: [Int]
    var nodes: [SyntaxNode]
    var errorCount: Int

    var stateBeforeTop: Int {
        stateStack.last ?? 0
    }

    init(state: Int) {
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
        for _ in 0 ..< min(count, stateStack.count - 1) {
            stateStack.removeLast()
        }
        state = stateStack.last ?? 0
        return popped
    }
}
