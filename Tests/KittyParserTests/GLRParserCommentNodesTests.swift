import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct GLRParserCommentNodesTests {
    @Test
    func `Comment tokens appear as extra nodes in the tree`() throws {
        let json = """
            {
                "name": "comment_tree_test",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "PATTERN",
                            "value": "\\\\/\\\\/[^\\\\n]*"
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let parser = GLRParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree = try parser.parse("// a comment\nx")
        let commentNodes = tree.root.children.filter { $0.type == "comment" }
        #expect(commentNodes.count == 1)
        #expect(commentNodes[0].isExtra)
        #expect(commentNodes[0].isNamed)
        #expect(commentNodes[0].text(from: tree.source) == "// a comment")
    }

    @Test
    func `Multiple comments produce multiple extra nodes`() throws {
        let json = """
            {
                "name": "multi_comment_test",
                "rules": {
                    "source": {
                        "type": "SEQ",
                        "members": [
                            {"type": "STRING", "value": "x"},
                            {"type": "STRING", "value": "x"}
                        ]
                    },
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "PATTERN",
                            "value": "\\\\/\\\\/[^\\\\n]*"
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let parser = GLRParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree = try parser.parse("// first\nx\n// second\nx")
        let commentNodes = tree.root.children.filter { $0.type == "comment" }
        #expect(commentNodes.count == 2)
    }
}
