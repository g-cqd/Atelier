import Testing

@testable import AtelierParser

@Suite
struct ParseStackTests {
    @Test(arguments: [(1, 7), (2, 3), (3, 0)])
    func `Popping nodes restores the state the first of them was pushed in`(count: Int, restoredState: Int) {
        var stack = ParseStack(state: 0)
        for (type, nextState) in [("a", 3), ("b", 7), ("c", 9)] {
            stack.pushNode(SyntaxNode(type: type))
            stack.state = nextState
        }

        let popped = stack.popNodes(count)

        #expect(popped.map(\.type) == Array(["a", "b", "c"].suffix(count)))
        #expect(stack.state == restoredState)
    }

    @Test
    func `Stacks with the same state history merge into the one with fewer errors`() {
        var clean = ParseStack(state: 0)
        clean.pushNode(SyntaxNode(type: "x", children: [SyntaxNode(type: "a")]))
        clean.state = 4
        var faulty = ParseStack(state: 0)
        faulty.pushNode(SyntaxNode(type: "ERROR", isError: true))
        _ = faulty.popNodes(1)
        faulty.pushNode(SyntaxNode(type: "x", children: [SyntaxNode(type: "b")]))
        faulty.state = 4

        let merged = ParseStack.mergingIdenticalHistories([faulty, clean])

        #expect(merged.count == 1)
        #expect(merged.first?.errorCount == 0)
        #expect(merged.first?.nodes.first?.children.first?.type == "a")
    }

    @Test
    func `Stacks with different state histories stay apart, in order`() {
        var first = ParseStack(state: 0)
        first.pushNode(SyntaxNode(type: "x"))
        first.state = 4
        var second = ParseStack(state: 0)
        second.pushNode(SyntaxNode(type: "y"))
        second.state = 5
        var third = ParseStack(state: 0)
        third.pushNode(SyntaxNode(type: "z"))
        third.pushNode(SyntaxNode(type: "w"))
        third.state = 4

        let merged = ParseStack.mergingIdenticalHistories([first, second, third])

        #expect(merged.map { $0.nodes.map(\.type) } == [["x"], ["y"], ["z", "w"]])
    }
}
