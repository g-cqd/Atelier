import AtelierGrammar

/// The order of a grammar's symbols as tree-sitter numbers them, which decides between two parses that tie on errors
/// and dynamic precedence: tokens first, in the order the grammar's rules first use them, then external tokens, then
/// the rules in the grammar's order, repetition helpers last.
struct SymbolRanks: Sendable {
    private let ranks: [String: Int]

    /// Ranks from an explicit table; a type it leaves out sorts after every ranked one.
    init(_ ranks: [String: Int]) {
        self.ranks = ranks
    }

    /// The ranks of the grammar behind `lexTable`, `parseTable` and `productions`. An alias ranks as the symbol it
    /// renames, the lowest of them when it renames several: tree-sitter compares symbols, not aliases.
    init(lexTable: LexTable, parseTable: ParseTable, productions: [ProductionRule]) {
        var ranks: [String: Int] = [:]
        func rank(_ type: String) {
            if ranks[type] == nil { ranks[type] = ranks.count }
        }
        lexTable.tokens.map(\.name).forEach(rank)
        parseTable.externalSymbols.forEach(rank)
        productions.map(\.name).forEach(rank)
        for production in productions {
            for (index, alias) in production.aliases where production.symbols.indices.contains(index) {
                let original = ranks[production.symbols[index]] ?? Int.max
                ranks[alias.type] = min(ranks[alias.type] ?? Int.max, original)
            }
        }
        self.ranks = ranks
    }

    /// The rank of the symbol of nodes of type `type`; an error, or a type the grammar does not name, sorts last.
    func rank(of type: String) -> Int {
        ranks[type] ?? Int.max
    }

    /// Tree-sitter's comparison of two trees (`ts_subtree_compare`), over two sequences of nodes as a root's children:
    /// the shorter first, then, node by node in pre-order, the lower rank, then the node with fewer children.
    /// - Returns: A negative number when `lhs` comes first, a positive one when `rhs` does, 0 when neither does.
    /// - Complexity: O(n) in the nodes the two sequences do not share.
    func compare(_ lhs: [SyntaxNode], _ rhs: [SyntaxNode]) -> Int {
        guard lhs.count == rhs.count else { return lhs.count < rhs.count ? -1 : 1 }
        var pending = Array(zip(lhs, rhs).reversed())
        while let (left, right) = pending.popLast() {
            if left.type == right.type, left.byteRange == right.byteRange,
                left.children.isTriviallyIdentical(to: right.children)
            {
                continue
            }
            let (leftRank, rightRank) = (rank(of: left.type), rank(of: right.type))
            guard leftRank == rightRank else { return leftRank < rightRank ? -1 : 1 }
            guard left.children.count == right.children.count else {
                return left.children.count < right.children.count ? -1 : 1
            }
            pending.append(contentsOf: zip(left.children, right.children).reversed())
        }
        return 0
    }
}
