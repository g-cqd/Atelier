import AemiTestKit
import AtelierSwiftSyntax
import AtelierSyntaxModel
import Foundation
import SwiftParser
import SwiftSyntax
import Synchronization
import Testing

@testable import AtelierDocIndex

/// The stack sizes the recorded work ran on.
private final class StackSizes: Sendable {
    private let sizes = Mutex<[Int]>([])

    var all: [Int] { sizes.withLock { $0 } }

    /// Records the calling thread's stack size.
    func record() {
        let size = pthread_get_stacksize_np(pthread_self())
        sizes.withLock { $0.append(size) }
    }
}

/// swift-syntax recurses once per level of nesting. A file read as the wrong language nests deeply: Python's comments and
/// single-quoted strings are neither to Swift, so every bracket in them opens a level that never closes. Every parse
/// and walk runs on a stack that holds it, whatever thread asks: a 512 KiB worker stack, as a task or a pool thread
/// has, overflowed on the file that crashed the app. A release build's frames are larger than a test build's, so the
/// tests below stand a 128 KiB stack in for a worker's.
struct DeepNestingTests {
    private static let workerStack = 128 * 1024

    /// Levels of closures and conditions, two brackets each: under swift-syntax's cap of 256, so it recurses through
    /// every one, and far deeper than a worker stack holds.
    private static let depth = 120

    /// A documented function, then `depth` closures each holding an `if`, as the crash's stack showed; the deepest
    /// line calls the function: "increment" sits at columns 13..<22 of line ``callLine``.
    private static let nested: String = {
        var text = "/// Adds one.\nfunc increment(_ x: Int) -> Int { x + 1 }\n"
        for level in 0 ..< depth {
            text += "items.forEach { item\(level) in\nif item\(level) > 0 {\n"
        }
        text += "let result = increment(1)\n"
        return text + String(repeating: "}\n}\n", count: depth)
    }()

    private static let callLine = 2 + 2 * depth

    @Test
    func `the identifier under a position is found from a worker stack`() {
        let name = runOnConstrainedStack(stackSize: Self.workerStack) {
            IdentifierLocator.identifier(in: Self.nested, line: Self.callLine, utf16Column: 15)
        }
        #expect(name == "increment")
    }

    @Test
    func `doc comments are extracted from a worker stack`() {
        let entries = runOnConstrainedStack(stackSize: Self.workerStack) {
            DocCommentIndex.extractEntries(uri: "file:///deep.swift", content: Self.nested)
        }
        #expect(entries.map(\.name) == ["increment"])
    }

    @Test
    func `a hover over deeply nested Swift answers from a task`() async throws {
        let index = DocCommentIndex()
        try await index.update(files: [DocIndexFile(uri: "file:///deep.swift", content: Self.nested)])
        let provider = DocIndexHoverProvider(index: index)
        let query = HoverQuery(
            documentURI: "file:///deep.swift", content: Self.nested, line: Self.callLine, utf16Column: 15)

        let content = try await provider.hover(query)

        #expect(content?.markdown.contains("Adds one.") == true)
    }

    @Test
    func `a hover parses the document on the deep stack`() async throws {
        let stacks = StackSizes()
        let sources = ParsedSourceCache { content in
            stacks.record()
            return Parser.parse(source: content)
        }
        let provider = DocIndexHoverProvider(index: DocCommentIndex(), side: .both, sources: sources)

        _ = try await provider.hover(
            HoverQuery(documentURI: "file:///use.swift", content: "let a = load()\n", line: 0, utf16Column: 9))

        #expect(stacks.all.count == 1)
        #expect(stacks.all.allSatisfy { $0 >= SwiftSyntaxStack.stackSize })
    }

    @Test
    func `the index extracts every file on the deep stack`() async throws {
        let stacks = StackSizes()
        let index = DocCommentIndex { _, _ in
            stacks.record()
            return []
        }

        try await index.upsert([
            DocIndexFile(uri: "file:///a.swift", content: "let a = 1"),
            DocIndexFile(uri: "file:///b.swift", content: "let b = 2")
        ])

        #expect(stacks.all.count == 2)
        #expect(stacks.all.allSatisfy { $0 >= SwiftSyntaxStack.stackSize })
    }
}
