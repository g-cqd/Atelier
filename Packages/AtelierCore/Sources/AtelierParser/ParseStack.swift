/// One stack of a GLR parse: the nodes shifted or reduced so far, and the LR state each was pushed in.
struct ParseStack: Sendable {
    /// The state each node of `nodes` was pushed in, then the current state: one entry more than `nodes`.
    private(set) var states: [Int]
    private(set) var nodes: [SyntaxNode]
    /// The error nodes pushed so far, including those a reduction has since wrapped.
    private(set) var errorCount: Int

    /// The current LR state.
    var state: Int {
        get { states[states.count - 1] }
        set { states[states.count - 1] = newValue }
    }

    init(state: Int) {
        self.states = [state]
        self.nodes = []
        self.errorCount = 0
    }

    /// The state the stack returns to once its top `count` nodes are popped, all of them if it holds fewer.
    func state(poppingNodes count: Int) -> Int {
        states[nodes.count - min(max(count, 0), nodes.count)]
    }

    /// Pushes `node` in the current state, which stays current until the caller sets another.
    mutating func pushNode(_ node: SyntaxNode) {
        nodes.append(node)
        states.append(state)
        if node.isError { errorCount += 1 }
    }

    /// Pops the top `count` nodes, all of them if it holds fewer, and returns them oldest first; the current state
    /// becomes the one the first of them was pushed in.
    mutating func popNodes(_ count: Int) -> [SyntaxNode] {
        let start = nodes.count - min(max(count, 0), nodes.count)
        guard start < nodes.count else { return [] }
        let popped = Array(nodes[start...])
        nodes.removeSubrange(start...)
        states.removeSubrange((start + 1)...)
        return popped
    }

    /// `stacks` with one stack per state history, in order: stacks with the same history parse the rest of the input
    /// alike, so the first with the fewest errors stands for all of them.
    ///
    /// - Complexity: O(s · d) for s stacks d states deep, comparing only stacks that share a current state.
    static func mergingIdenticalHistories(_ stacks: consuming [ParseStack]) -> [ParseStack] {
        var pending = consume stacks
        guard pending.count > 1 else { return pending }
        pending.reverse()
        var kept: [ParseStack] = []
        kept.reserveCapacity(pending.count)
        var keptIndicesByState: [Int: [Int]] = [:]
        while let stack = pending.popLast() {
            let candidates = keptIndicesByState[stack.state, default: []]
            if let twin = candidates.first(where: { kept[$0].states == stack.states }) {
                if stack.errorCount < kept[twin].errorCount {
                    kept[twin] = stack
                }
                continue
            }
            keptIndicesByState[stack.state, default: []].append(kept.count)
            kept.append(stack)
        }
        return kept
    }
}
