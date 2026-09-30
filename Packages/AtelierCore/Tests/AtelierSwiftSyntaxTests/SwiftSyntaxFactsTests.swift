import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSwiftSyntax

/// One parse of a Swift side gives the colour, the intraline boundaries and the declarations, each what its own parse
/// gave before (PERF-11 step 3).
struct SwiftSyntaxFactsTests {
    private static let text = """
        /// A point, café 😀.
        struct Point {
            /* a block
               comment */ var x = 1, `y` = "two"
            /** Moves it. */
            func moved(by delta: Int) -> Point { self }
        }
        enum E {
            /// The first.
            case a, b
        }
        let tail = 3
        """

    @Test
    func `the facts hold the tokens, the boundaries and the entries each parse gave on its own`() throws {
        let facts = try #require(SwiftSyntaxFacts.extract(Self.text))

        #expect(facts.highlights == (try SwiftSyntaxHighlights.tokens(in: Self.text)))
        #expect(facts.tokenBoundaries == SwiftSyntaxTokenRanges().tokenRangesByLine(text: Self.text, language: .swift))
        #expect(facts.declarations.map(\.name) == ["Point", "x", "y", "moved", "E", "a", "b", "tail"])
        #expect(facts.declarations.filter { $0.documentation != nil }.map(\.name) == ["Point", "moved", "a", "b"])
        #expect(facts.declarations.first { $0.name == "moved" }?.signature == "func moved(by delta: Int) -> Point")
    }

    @Test
    func `the intraline provider reads a stored side's boundaries, parsing it once`() {
        let store = SyntaxFactsStore()
        let revision = SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob"))
        let provider = SwiftSyntaxTokenRanges(store: store) { text, _ in text == Self.text ? revision : nil }
        let lines = [0, 2, 3, 8]

        let stored = provider.tokenRangesByLine(text: Self.text, language: .swift, lineIndices: lines)
        let whole = provider.tokenRangesByLine(text: Self.text, language: .swift)

        #expect(
            stored == SwiftSyntaxTokenRanges().tokenRangesByLine(text: Self.text, language: .swift, lineIndices: lines))
        #expect(whole == SwiftSyntaxTokenRanges().tokenRangesByLine(text: Self.text, language: .swift))
        #expect(store.extractions == 1)
    }

    @Test
    func `a side past the gate keeps its boundaries and declarations without colour`() throws {
        let json = String(repeating: #"{"a": [1, 2, {"b": true}], "c": null}"# + "\n", count: 20)

        let facts = try #require(SwiftSyntaxFacts.extract(json))

        #expect(facts.highlights == nil)
        #expect(facts.unexpectedShare > SwiftSyntaxHighlights.maximumUnexpectedShare)
        #expect(facts.tokenBoundaries.count == 20)
        #expect(facts.declarations.isEmpty)
    }

    @Test
    func `the tier colours a stored side without parsing it again`() async throws {
        let store = SyntaxFactsStore()
        let revision = SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob"))
        _ = await SwiftSyntaxFacts.facts(for: revision, text: Self.text, in: store)
        var ranges: [Range<Int>] = []
        var start = 0
        for line in Self.text.split(separator: "\n", omittingEmptySubsequences: false) {
            ranges.append(start ..< start + line.utf8.count)
            start += line.utf8.count + 1
        }
        let request = TierRequest(revision: revision, text: Self.text, lineRanges: ranges, visibleLines: 0 ..< 3)
        var updates: [TierUpdate] = []

        try await SwiftSyntaxTier(deadline: nil, store: store).run(request) { updates.append($0) }

        #expect(store.extractions == 1)
        #expect(updates.map(\.lines) == [0 ..< 3, 3 ..< ranges.count])
        let expected = request.lineTokens(
            try await SwiftSyntaxHighlights.tokens(in: Self.text), lines: 0 ..< ranges.count)
        #expect(updates.flatMap { Array($0.tokens) }.map { Array($0) } == expected.map { Array($0) })
    }

    @Test
    func `the walk that finds the declarations finds each brace pair's scope and its kind`() throws {
        let text = """
            struct S {
                var v: Int { 1 }
                func f() {
                    if true { [1].map { $0 } }
                    switch v { default: break }
                }
            }
            """
        let facts = try #require(SwiftSyntaxFacts.extract(text))
        let bytes = Array(text.utf8)

        #expect(facts.scopes.map(\.kind) == [.type, .function, .function, .controlFlow, .closure, .controlFlow])
        #expect(facts.scopes.map { bytes[$0.range.lowerBound] } == Array(repeating: UInt8(ascii: "{"), count: 6))
        #expect(facts.scopes.map { bytes[$0.range.upperBound - 1] } == Array(repeating: UInt8(ascii: "}"), count: 6))
        #expect(facts.scopes.first?.range == 9 ..< bytes.count)
    }
}
