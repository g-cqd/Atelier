import Testing

@testable import AtelierParser

/// A stack whose errors cost more than those of a stack as far along or further is dropped, as tree-sitter drops a
/// version once a better one exists; errors cost what they skip, so one long skip outweighs a few short ones.
@Suite
struct OutdoneStackTests {
    @Test
    func `a stack with a costlier error than one as far along is dropped`() {
        let clean = Self.stack(at: 10, skipping: [])
        let faulty = Self.stack(at: 10, skipping: [4 ..< 5])

        let kept = ParseStack.droppingOutdone([faulty, clean], finished: [])

        #expect(kept.map(\.errorCost) == [0])
    }

    @Test
    func `a stack further along with a costlier error does not drop one behind with a cheaper one`() {
        let behind = Self.stack(at: 10, skipping: [4 ..< 5])
        let ahead = Self.stack(at: 90, skipping: [12 ..< 90])

        let kept = ParseStack.droppingOutdone([behind, ahead], finished: [])

        #expect(kept.map(\.cursor.offset) == [10, 90])
    }

    @Test
    func `a finished stack drops the stacks whose errors cost more`() {
        let finished = Self.stack(at: 100, skipping: [])
        let faulty = Self.stack(at: 10, skipping: [4 ..< 5])

        let kept = ParseStack.droppingOutdone([faulty], finished: [finished])

        #expect(kept.isEmpty)
    }

    /// A stack whose cursor is at `offset`, having skipped a token over each of `skipped`.
    private static func stack(at offset: Int, skipping skipped: [Range<Int>]) -> ParseStack {
        var stack = ParseStack(state: 0)
        for range in skipped {
            stack.pushNode(
                SyntaxNode(
                    type: "ERROR", byteRange: range,
                    pointRange: Point(row: 0, column: range.lowerBound) ..< Point(row: 0, column: range.upperBound),
                    isError: true))
            stack.isRecovering = true
        }
        stack.cursor = TokenScanner.Cursor(offset: offset, point: Point(row: 0, column: offset))
        return stack
    }
}
