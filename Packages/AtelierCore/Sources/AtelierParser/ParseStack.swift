/// One stack of a GLR parse: the nodes shifted or reduced so far, and the LR state each was pushed in.
struct ParseStack: Sendable {
    /// Nodes up to this many levels tall are freed by ordinary, recursive release: a 512 KiB thread overflows
    /// between 2,000 and 3,000 levels, and this leaves most of it to the caller.
    static let recursiveReleaseHeight = 512

    /// The state each node of `nodes` was pushed in, then the current state: one entry more than `nodes`.
    private(set) var states: [Int]
    private(set) var nodes: [SyntaxNode]
    /// How many levels tall each node of `nodes` is, 1 for a leaf.
    private(set) var heights: [Int]
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
        self.heights = []
        self.errorCount = 0
    }

    /// The state the stack returns to once its top `count` nodes are popped, all of them if it holds fewer.
    func state(poppingNodes count: Int) -> Int {
        states[nodes.count - min(max(count, 0), nodes.count)]
    }

    /// How many levels tall the tallest of the top `count` nodes is, 0 for none.
    func height(ofTop count: Int) -> Int {
        heights.suffix(max(count, 0)).max() ?? 0
    }

    /// Pushes `node`, `height` levels tall, in the current state, which stays current until the caller sets another.
    mutating func pushNode(_ node: SyntaxNode, height: Int = 1) {
        nodes.append(node)
        heights.append(height)
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
        heights.removeSubrange(start...)
        states.removeSubrange((start + 1)...)
        return popped
    }

    /// Empties the stack without recursing into a deep subtree: a node taller than `recursiveReleaseHeight` is freed
    /// by ``SyntaxTree/releaseIteratively(_:)``, unless `survivor` holds the same node at the same position, which
    /// keeps it alive.
    mutating func releaseNodes(sparing survivor: ParseStack? = nil) {
        var deepNodes: [SyntaxNode] = []
        for index in nodes.indices where heights[index] > Self.recursiveReleaseHeight {
            let node = nodes[index]
            if let survivor, survivor.nodes.indices.contains(index),
                survivor.nodes[index].children.isTriviallyIdentical(to: node.children)
            {
                continue
            }
            deepNodes.append(node)
        }
        nodes = []
        heights = []
        states = [state]
        SyntaxTree.releaseIteratively(consume deepNodes)
    }

    /// `stacks` with one stack per state history, in order: stacks with the same history parse the rest of the input
    /// alike, so the first with the fewest errors stands for all of them, and the others are released.
    ///
    /// - Complexity: O(s · d) for s stacks d states deep, comparing only stacks that share a current state.
    static func mergingIdenticalHistories(_ stacks: consuming [ParseStack]) -> [ParseStack] {
        var pending = consume stacks
        guard pending.count > 1 else { return pending }
        pending.reverse()
        var kept: [ParseStack] = []
        kept.reserveCapacity(pending.count)
        var keptIndicesByState: [Int: [Int]] = [:]
        while var stack = pending.popLast() {
            let candidates = keptIndicesByState[stack.state, default: []]
            if let twin = candidates.first(where: { kept[$0].states == stack.states }) {
                if stack.errorCount < kept[twin].errorCount {
                    swap(&stack, &kept[twin])
                }
                stack.releaseNodes(sparing: kept[twin])
                continue
            }
            keptIndicesByState[stack.state, default: []].append(kept.count)
            kept.append(stack)
        }
        return kept
    }
}
