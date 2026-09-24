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

    /// The state the stack returns to once its top `count` symbols are popped, all of them if it holds fewer.
    func state(poppingSymbols count: Int) -> Int {
        states[symbolRange(ofTop: count).lowerBound]
    }

    /// How many levels tall the tallest of the stack's nodes is, 0 for none.
    var tallestHeight: Int { heights.max() ?? 0 }

    /// How many levels tall the tallest node among the top `count` symbols is, 0 for none.
    func height(ofTopSymbols count: Int) -> Int {
        heights[symbolRange(ofTop: count)].max() ?? 0
    }

    /// The nodes a reduction of `count` symbols takes: from the first of the top `count` symbols, all of them if the
    /// stack holds fewer, to the last symbol. The ERROR nodes of the tokens error recovery skipped are no symbols, as
    /// tree-sitter's are extras: a reduction takes those between its symbols as children and leaves those above them.
    private func symbolRange(ofTop count: Int) -> Range<Int> {
        var end = nodes.count
        guard count > 0 else { return end ..< end }
        while end > 0, nodes[end - 1].isError { end -= 1 }
        var start = end
        var remaining = count
        while start > 0, remaining > 0 {
            start -= 1
            if !nodes[start].isError { remaining -= 1 }
        }
        return start ..< end
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

    /// Whether this stack's parse is better than `other`'s, as tree-sitter chooses between two parses: fewer errors,
    /// then a higher dynamic precedence, then the nodes that come first by `ranks` (see ``SymbolRanks/compare(_:_:)``).
    func isPreferred(over other: ParseStack, ranks: SymbolRanks) -> Bool {
        guard errorCount == other.errorCount, dynamicPrecedence == other.dynamicPrecedence else {
            return isPreferred(over: other)
        }
        return ranks.compare(nodes, other.nodes) < 0
    }

    /// Pops the top `count` symbols, all of them if it holds fewer, with the skipped tokens' ERROR nodes between and
    /// above them. Returns the nodes from the first symbol to the last, oldest first, which a reduction takes as
    /// children, and the ERROR nodes above the last, for ``restoreSkipped(_:)`` to push back over the reduction's node.
    /// The current state becomes the one the first symbol was pushed in.
    mutating func popSymbols(_ count: Int) -> (symbols: [SyntaxNode], skippedAbove: [SyntaxNode]) {
        let range = symbolRange(ofTop: count)
        let popped = (Array(nodes[range]), Array(nodes[range.upperBound...]))
        nodes.removeSubrange(range.lowerBound...)
        heights.removeSubrange(range.lowerBound...)
        states.removeSubrange((range.lowerBound + 1)...)
        return popped
    }

    /// Pushes back, in the current state, the ERROR nodes ``popSymbols(_:)`` popped above a reduction's symbols; they
    /// are counted already.
    mutating func restoreSkipped(_ skipped: [SyntaxNode]) {
        for node in skipped {
            nodes.append(node)
            heights.append(1)
            states.append(state)
        }
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

    /// Takes out the stack `ranks` prefers, the first of them on a tie, and releases the others; nil when `stacks` is
    /// empty.
    static func takingBest(from stacks: inout [ParseStack], ranks: SymbolRanks) -> ParseStack? {
        guard let bestIndex = stacks.indices.min(by: { stacks[$0].isPreferred(over: stacks[$1], ranks: ranks) }) else {
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
    /// alike, so the first one `ranks` prefers stands for all of them, and the others are released.
    ///
    /// - Complexity: O(s · d) for s stacks d states deep, comparing only stacks that share a current state, plus the
    ///   nodes two stacks that tie on errors and dynamic precedence do not share.
    static func mergingIdenticalHistories(
        _ stacks: consuming [ParseStack], ranks: SymbolRanks = SymbolRanks([:])
    ) -> [ParseStack] {
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
                if stack.isPreferred(over: kept[twin], ranks: ranks) {
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
