import AemiTestKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSwiftSyntax

/// swift-syntax work runs on a stack deep enough for it, whichever thread asks, and in place when that thread's own
/// stack is deep enough. A release build's frames are larger than a test build's, so the deep-text tests stand a
/// 128 KiB stack in for a worker's 512 KiB.
struct SwiftSyntaxStackTests {
    private static let workerStack = 128 * 1024

    /// The stack of the thread that runs the calling code, guard pages included.
    private static func currentStackSize() -> Int {
        pthread_get_stacksize_np(pthread_self())
    }

    /// `levels` closures each holding an `if`, nested: two brackets a level, as in the file that crashed the app.
    private static func nested(_ levels: Int) -> String {
        (0 ..< levels).map { "items.forEach { item\($0) in\nif item\($0) > 0 {\n" }.joined()
            + String(repeating: "}\n}\n", count: levels)
    }

    @Test
    func `a worker thread's work moves to a deep stack`() {
        let stack = runOnConstrainedStack { SwiftSyntaxStack.run { Self.currentStackSize() } }
        #expect(stack >= SwiftSyntaxStack.stackSize)
    }

    @Test
    func `a thread with a deep enough stack runs the work in place`() {
        let stack = runOnConstrainedStack(stackSize: 8 << 20) { SwiftSyntaxStack.run { Self.currentStackSize() } }
        #expect(stack >= 8 << 20 && stack < SwiftSyntaxStack.stackSize)
    }

    @Test
    func `a task awaits the work on a deep stack`() async {
        let stack = await SwiftSyntaxStack.run { Self.currentStackSize() }
        #expect(stack >= SwiftSyntaxStack.stackSize)
    }

    @Test
    func `the syntax tier tokenizes deeply nested text from a worker stack`() {
        let text = Self.nested(120)
        let ranges = runOnConstrainedStack(stackSize: Self.workerStack) {
            SwiftSyntaxTokenRanges().tokenRangesByLine(text: text, language: .swift)
        }
        #expect(ranges.count == 480)
        // "items" on the first line.
        #expect(ranges.first?.contains(0 ..< 5) == true)
    }

    /// Nesting past swift-syntax's cap of 256 brackets: the parser stops descending there, and the rest of the file
    /// comes back as unexpected text rather than overflowing the stack.
    @Test
    func `nesting past the parser's cap still parses`() {
        let text = Self.nested(1_000)
        let ranges = runOnConstrainedStack(stackSize: Self.workerStack) {
            SwiftSyntaxTokenRanges().tokenRangesByLine(text: text, language: .swift)
        }
        #expect(ranges.count == 4_000)
    }
}
