import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// KittyCode's JSON grammar lexed through its own tokens: numbers and string contents as single tokens, read in the
/// lex mode of the parser's state.
@Suite
struct GLRParserJSONLexingTests {
    @Test
    func `An object with a string key and a number parses without an error`() throws {
        let tree = try Self.parse(#"{"a": 1}"#)

        #expect(tree.root.type == "document")
        #expect(!tree.root.containsError)
    }

    @Test
    func `A number is one named leaf`() throws {
        let tree = try Self.parse("[-12.5e-3, 0, 42]")

        #expect(Self.leaves(of: "number", in: tree) == ["-12.5e-3", "0", "42"])
        #expect(!tree.root.containsError)
    }

    @Test
    func `A string's text between escapes is one leaf each`() throws {
        let tree = try Self.parse(#"["say \"hi\" to all", "true false null"]"#)

        #expect(Self.leaves(of: "string_content", in: tree) == ["say ", "hi", " to all", "true false null"])
        #expect(Self.leaves(of: "escape_sequence", in: tree) == [#"\""#, #"\""#])
        #expect(!tree.root.containsError)
    }

    @Test
    func `Comment and whitespace text inside a string stays string content`() throws {
        let tree = try Self.parse(#"{"url": "http://example.com/*path*/", "pad": "  // "}"#)

        #expect(Self.leaves(of: "string_content", in: tree) == ["url", "http://example.com/*path*/", "pad", "  // "])
        #expect(Self.leaves(of: "comment", in: tree).isEmpty)
        #expect(!tree.root.containsError)
    }

    @Test
    func `A comment between values is an extra node of the tree`() throws {
        let tree = try Self.parse("[1, // one\n2]")

        let comments = tree.root.children.filter { $0.type == "comment" }
        #expect(comments.map { $0.text(from: tree.source) } == ["// one"])
        #expect(comments.map(\.isExtra) == [true])
        #expect(!tree.root.containsError)
    }

    @Test
    func `A 206 KB JSON file stays under the token limit and parses without an error`() throws {
        let source = Self.records(bytes: 206 * 1_024)

        let tree = try Self.parse(source)

        #expect(source.utf8.count >= 206 * 1_024)
        #expect(tree.root.type == "document")
        #expect(!tree.root.containsError)
    }

    private static func parse(_ source: String) throws -> SyntaxTree {
        try BundledGrammarFixture.parser(for: BundledGrammarFixture.json).parse(source)
    }

    /// The text of every leaf of type `type`, in source order.
    private static func leaves(of type: String, in tree: SyntaxTree) -> [String] {
        var texts: [String] = []
        tree.walk { node, _ in
            if node.type == type, node.children.isEmpty {
                texts.append(node.text(from: tree.source))
            }
            return true
        }
        return texts
    }

    /// A pretty-printed array of records of at least `bytes` bytes, with the strings, escapes, numbers, booleans,
    /// nulls and nested containers of an ordinary data file: its string contents alone once lexed a token a
    /// character, past the parser's 100,000-token limit.
    private static func records(bytes: Int) -> String {
        var records: [String] = []
        var size = 2
        var index = 0
        while size < bytes {
            let record = """
                  {
                    "id": \(index),
                    "name": "record number \(index) of the \\"sample\\" set",
                    "path": "src/module-\(index % 7)/file-\(index).swift",
                    "score": \(Double(index) * 1.25 - 300.5),
                    "ratio": 1.5e-\(index % 9 + 1),
                    "enabled": \(index.isMultiple(of: 2)),
                    "owner": null,
                    "tags": ["alpha", "beta", "gamma"],
                    "nested": {"depth": \(index % 5), "values": [\(index), \(index * 2), \(index * 3)]}
                  }
                """
            records.append(record)
            size += record.utf8.count + 2
            index += 1
        }
        return "[\n" + records.joined(separator: ",\n") + "\n]\n"
    }
}
