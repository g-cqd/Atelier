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
    /// The bytes those error nodes span: each is a token the stack could not take, so they never overlap.
    private(set) var errorByteCount = 0
    /// The sum of the dynamic precedences of the productions reduced so far.
    private(set) var dynamicPrecedence = 0
    /// The input position, scanner state, and extras belonging to this GLR branch.
    var cursor = TokenScanner.Cursor.start
    var scannerState: [UInt8] = []
    var extras: [ParseToken] = []
    var tokenIndex = 0
    var zeroWidthCount = 0
    var isRecovering = false

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
        if node.isError {
            errorCount += 1
            errorByteCount += node.byteRange.count
        }
    }

    /// Counts the dynamic precedence of a production just reduced.
    mutating func addDynamicPrecedence(_ value: Int) {
        dynamicPrecedence += value
    }

    /// Whether this stack's parse is better than `other`'s: fewer errors, or as many and a higher dynamic precedence.
    func isPreferred(over other: ParseStack) -> Bool {
        errorCount != other.errorCount
            ? errorCount < other.errorCount : dynamicPrecedence > other.dynamicPrecedence
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

    /// Takes out the preferred stack, the first of them on a tie, and releases the others; nil when `stacks` is empty.
    static func takingBest(from stacks: inout [ParseStack]) -> ParseStack? {
        guard let bestIndex = stacks.indices.min(by: { stacks[$0].isPreferred(over: stacks[$1]) }) else {
            return nil
        }
        let best = stacks.remove(at: bestIndex)
        for index in stacks.indices {
            stacks[index].releaseNodes(sparing: best)
        }
        return best
    }

    /// Empties every stack in `stacks` without recursing into a deep subtree. A stack that shares nodes with the first
    /// spares them, so only the first frees them.
    static func releaseAll(_ stacks: inout [ParseStack]) {
        guard !stacks.isEmpty else { return }
        var first = stacks.removeFirst()
        for index in stacks.indices {
            stacks[index].releaseNodes(sparing: first)
        }
        stacks.removeAll()
        first.releaseNodes()
    }

    /// `stacks` with one stack per state history, in order: stacks with the same history parse the rest of the input
    /// alike, so the first preferred one stands for all of them, and the others are released.
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
            if let twin = candidates.first(where: {
                kept[$0].states == stack.states && kept[$0].cursor == stack.cursor
                    && kept[$0].scannerState == stack.scannerState
                    && kept[$0].isRecovering == stack.isRecovering
                    && kept[$0].zeroWidthCount == stack.zeroWidthCount
                    && kept[$0].tokenIndex == stack.tokenIndex
                    && kept[$0].extras == stack.extras
            }) {
                if stack.isPreferred(over: kept[twin]) {
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
