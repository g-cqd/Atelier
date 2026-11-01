internal import AtelierGrammar
import Synchronization

// Shifting a token onto every live stack; apart from the type's file, to keep its type body within the 300 lines
// SwiftLint allows.
extension GLRParser {
    /// Shifts `token` onto every stack whose state allows it, forking when several shifts do. A stack that cannot
    /// shift it keeps its state and takes the token as an ERROR node: error recovery skips the token for that stack.
    func shift(_ stacks: consuming [ParseStack], token: ParseToken, lookahead: Int) -> [ParseStack] {
        var pending = consume stacks
        pending.reverse()
        var shifted: [ParseStack] = []
        shifted.reserveCapacity(pending.count)
        let leaf = SyntaxNode(
            type: token.type,
            byteRange: token.byteRange,
            pointRange: token.pointRange,
            isNamed: token.isNamed
        )
        while var stack = pending.popLast() {
            let shiftTargets: [Int]
            switch parseTable.actions[stack.state, lookahead] {
                case .shift(let nextState):
                    stack.pushNode(leaf)
                    stack.state = nextState
                    stack.isRecovering = false
                    shifted.append(consume stack)
                    continue
                case .accept:
                    shifted.append(consume stack)
                    continue
                case .conflict(let actions):
                    shiftTargets = actions.compactMap { action -> Int? in
                        if case .shift(let nextState) = action { return nextState }
                        return nil
                    }
                case .reduce:
                    // A reduction left unmade: the shift precedence set against it, if there was one.
                    shiftTargets = lostShift(of: lookahead, in: stack.state).map { [$0] } ?? []
                case .error:
                    shiftTargets = []
            }
            guard let lastTarget = shiftTargets.last else {
                stack.pushNode(
                    SyntaxNode(type: "ERROR", byteRange: token.byteRange, pointRange: token.pointRange, isError: true)
                )
                stack.isRecovering = true
                shifted.append(consume stack)
                continue
            }
            // Forks copy the stack; the last shift takes it over.
            for nextState in shiftTargets.dropLast() {
                var fork = stack
                fork.pushNode(leaf)
                fork.state = nextState
                fork.isRecovering = false
                shifted.append(consume fork)
            }
            stack.pushNode(leaf)
            stack.state = lastTarget
            stack.isRecovering = false
            shifted.append(consume stack)
        }
        return shifted
    }
}
