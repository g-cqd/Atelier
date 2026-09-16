import Testing

@testable import DiffCore

struct IntralineGranularityTests {
    @Test
    func `character tier marks only the differing units`() {
        let emphasis = IntralineDiff.emphasis(old: "let x = foo(bar)", new: "let x = foo(baz)", granularity: .character)
        #expect(emphasis?.old == [14 ..< 15])
        #expect(emphasis?.new == [14 ..< 15])
    }

    @Test
    func `word tier marks the whole changed word`() {
        let emphasis = IntralineDiff.emphasis(old: "let value = count", new: "let value = total", granularity: .word)
        #expect(emphasis?.old == [12 ..< 17])
        #expect(emphasis?.new == [12 ..< 17])
    }

    @Test
    func `word tier treats identifiers with digits and underscores as one word`() {
        #expect(IntralineTokenizer.words(Array("a1_b + 42".utf16)) == [0 ..< 4, 4 ..< 5, 5 ..< 6, 6 ..< 7, 7 ..< 9])
    }

    @Test
    func `syntax tier marks a whole string segment as one token`() {
        let old = "print(\"hello world\", terminator: \"\")"
        let new = "print(\"hello there\", terminator: \"\")"
        let oldTokens = SyntaxTokenizer.tokenRangesByLine(text: old, language: .swift)
        let newTokens = SyntaxTokenizer.tokenRangesByLine(text: new, language: .swift)
        let emphasis = IntralineDiff.emphasis(
            old: old[...], new: new[...], granularity: .syntax, oldTokens: oldTokens[0], newTokens: newTokens[0]
        )
        #expect(emphasis?.old == [7 ..< 18])
        #expect(emphasis?.new == [7 ..< 18])
    }

    @Test
    func `swift tokens are split per line with comments broken into words`() {
        let text = "let a = 1\n// hi there\n"
        let byLine = SyntaxTokenizer.tokenRangesByLine(text: text, language: .swift)
        #expect(byLine.count == 2)
        #expect(byLine[0] == [0 ..< 3, 3 ..< 4, 4 ..< 5, 5 ..< 6, 6 ..< 7, 7 ..< 8, 8 ..< 9])
        #expect(byLine[1] == [0 ..< 1, 1 ..< 2, 2 ..< 3, 3 ..< 5, 5 ..< 6, 6 ..< 11])
    }

    @Test
    func `swift tokens use utf16 offsets after non ascii characters`() {
        let byLine = SyntaxTokenizer.tokenRangesByLine(text: "let é = \"😀\" + x", language: .swift)
        #expect(byLine[0].last == 15 ..< 16)
    }

    @Test
    func `objective c syntax tier keeps directives and strings whole`() {
        let byLine = SyntaxTokenizer.tokenRangesByLine(
            text: "@interface Foo : NSObject @\"a b\"", language: .objectiveC)
        #expect(
            byLine[0] == [
                0 ..< 10, 10 ..< 11, 11 ..< 14, 14 ..< 15, 15 ..< 16, 16 ..< 17, 17 ..< 25, 25 ..< 26, 26 ..< 32
            ])
    }

    @Test
    func `emphasis falls back to nil when tokens differ everywhere`() {
        let emphasis = IntralineDiff.emphasis(old: "one two three", new: "four five six", granularity: .word)
        #expect(emphasis == nil)
    }
}
