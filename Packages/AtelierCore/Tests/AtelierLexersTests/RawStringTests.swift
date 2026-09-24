import AtelierSyntaxModel
import Testing

@testable import AtelierLexers

/// A Swift raw string closes at a quote followed by as many hashes as opened it; a quote with fewer hashes, and an
/// escape written `\#`, stay inside it (perf-core L5: an inner `"""` flipped string and code for the rest of a file).
struct RawStringTests {
    private static func tokens(_ source: String) -> [Token] {
        SyntaxHighlighter.tokens(utf8: Array(source.utf8), language: .swift)
    }

    /// The UTF-8 offset where the first `marker` in `source` ends.
    private static func offset(after marker: String, in source: String) throws -> Int {
        let range = try #require(source.firstRange(of: marker))
        return source.utf8.distance(from: source.utf8.startIndex, to: range.upperBound)
    }

    @Test
    func `a multiline raw string closes at its delimiter and not at an inner triple quote`() throws {
        let source = "let x = #\"\"\"\n    first \"\"\" inner\n    \"\"\"#\nlet y = 1"
        let tokens = Self.tokens(source)
        let start = try Self.offset(after: "let x = ", in: source)
        let end = try Self.offset(after: "\"\"\"#", in: source)
        #expect(tokens.first { $0.kind == .string }?.range == start ..< end)
        #expect(tokens.last == Token(kind: .number, range: source.utf8.count - 1 ..< source.utf8.count))
    }

    @Test(arguments: [
        "let x = ##\"one \"# two\"##",
        "let x = #\"one \\#\" two\"#",
        "let x = #\"say \"hi\" \\#(name)\"#"
    ])
    func `a raw string keeps a quote with fewer hashes and an escaped quote inside`(line: String) throws {
        let source = line + "\nlet y = 1"
        let tokens = Self.tokens(source)
        let start = try Self.offset(after: "let x = ", in: source)
        #expect(tokens.map(\.kind) == [.keyword, .string, .keyword, .number])
        #expect(tokens.dropFirst().first?.range == start ..< line.utf8.count)
    }

    @Test
    func `a run of hashes without a quote leaves the code after it visible`() {
        let source = String(repeating: "#", count: 1_024) + "let value = 1"
        #expect(Self.tokens(source).first == Token(kind: .keyword, range: 1_024 ..< 1_027))
    }
}
