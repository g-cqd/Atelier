import Testing
import Foundation
@testable import KittyParser
@testable import KittyGrammar

@Suite("SyntaxNode")
struct SyntaxNodeTests {
    @Test("Node text extraction")
    func nodeText() {
        let source = "hello world"
        let node = SyntaxNode(type: "word", byteRange: 0..<5)
        #expect(node.text(from: source) == "hello")
    }

    @Test("Named children filter")
    func namedChildren() {
        let child1 = SyntaxNode(type: "name", isNamed: true)
        let child2 = SyntaxNode(type: ",", isNamed: false)
        let parent = SyntaxNode(type: "list", children: [child1, child2])
        #expect(parent.namedChildren.count == 1)
        #expect(parent.namedChildren[0].type == "name")
    }
}

@Suite("SyntaxTree")
struct SyntaxTreeTests {
    @Test("Walk visits all nodes")
    func walkTree() {
        let leaf = SyntaxNode(type: "leaf", byteRange: 0..<3)
        let root = SyntaxNode(type: "root", children: [leaf], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")

        var visited: [String] = []
        tree.walk { node, _ in
            visited.append(node.type)
            return true
        }
        #expect(visited == ["root", "leaf"])
    }

    @Test("Node at byte offset")
    func nodeAtOffset() {
        let child1 = SyntaxNode(type: "a", byteRange: 0..<3)
        let child2 = SyntaxNode(type: "b", byteRange: 3..<6)
        let root = SyntaxNode(type: "root", children: [child1, child2], byteRange: 0..<6)
        let tree = SyntaxTree(root: root, source: "abcdef")

        let found = tree.nodeAt(byteOffset: 4)
        #expect(found?.type == "b")
    }
}

@Suite("TextEdit")
struct TextEditTests {
    @Test("Apply edit shifts byte ranges")
    func applyEdit() {
        let child1 = SyntaxNode(type: "a", byteRange: 0..<3)
        let child2 = SyntaxNode(type: "b", byteRange: 3..<6)
        let root = SyntaxNode(type: "root", children: [child1, child2], byteRange: 0..<6)
        let tree = SyntaxTree(root: root, source: "abcdef")

        // Insert 2 bytes at position 3
        let edit = TextEdit(startByte: 3, oldEndByte: 3, newEndByte: 5)
        let edited = tree.applying(edit: edit)

        // child2 should have shifted by 2
        #expect(edited.root.children[1].byteRange.lowerBound == 5)
    }
}

@Suite("Lexer")
struct LexerTests {
    @Test("Tokenize with keywords")
    func tokenizeKeywords() {
        let lexTable = LexTable(
            states: [
                LexState(transitions: [
                    (UInt32(Character("i").asciiValue!)...UInt32(Character("i").asciiValue!), 1)
                ]),
                LexState(transitions: [
                    (UInt32(Character("f").asciiValue!)...UInt32(Character("f").asciiValue!), 2)
                ]),
                LexState(accepting: 0),
            ],
            keywords: ["if": 0]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("if")
        #expect(tokens.contains(where: { $0.text == "if" }))
    }

    @Test("Tokenize skips whitespace")
    func tokenizeWhitespace() {
        let lexer = Lexer(lexTable: LexTable())
        let tokens = lexer.tokenize("a b")
        #expect(tokens.count == 3) // 'a', whitespace, 'b'
        #expect(tokens[1].isExtra)
    }
}

@Suite("GLRParser")
struct GLRParserTests {
    @Test("Parse produces syntax tree")
    func parseSimple() throws {
        // Build a minimal grammar and parse table
        let json = """
        {
            "name": "minimal",
            "rules": {
                "source": {"type": "STRING", "value": "hello"}
            }
        }
        """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let parser = GLRParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree = try parser.parse("hello")
        #expect(tree.root.type != "")
    }
}

@Suite("IncrementalParser")
struct IncrementalParserTests {
    @Test("Incremental parse produces tree")
    func incrementalParse() throws {
        let json = """
        {
            "name": "inc_test",
            "rules": {
                "source": {"type": "STRING", "value": "x"}
            }
        }
        """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let parser = IncrementalParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree1 = try parser.parse("x")
        let tree2 = try parser.parse("x", oldTree: tree1)
        #expect(tree2.root.type != "")
    }
}
