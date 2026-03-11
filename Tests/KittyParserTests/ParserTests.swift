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

    @Test("Node text extraction returns empty string for out-of-bounds lower bound")
    func nodeTextOutOfBoundsLowerBound() {
        let source = "hello"
        let node = SyntaxNode(type: "word", byteRange: 20..<25)
        #expect(node.text(from: source).isEmpty)
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

    @Test("Apply edit shifts point ranges and field nodes")
    func applyEditShiftsPointRangesAndFields() {
        let left = SyntaxNode(
            type: "left",
            byteRange: 0..<3,
            pointRange: Point(row: 0, column: 0)..<Point(row: 0, column: 3)
        )
        let right = SyntaxNode(
            type: "right",
            byteRange: 3..<6,
            pointRange: Point(row: 0, column: 3)..<Point(row: 0, column: 6)
        )
        let root = SyntaxNode(
            type: "root",
            children: [left, right],
            byteRange: 0..<6,
            pointRange: Point(row: 0, column: 0)..<Point(row: 0, column: 6),
            fields: ["rhs": [right]]
        )
        let tree = SyntaxTree(root: root, source: "abcdef")

        let edit = TextEdit(
            startByte: 3,
            oldEndByte: 3,
            newEndByte: 4,
            startPoint: Point(row: 0, column: 3),
            oldEndPoint: Point(row: 0, column: 3),
            newEndPoint: Point(row: 1, column: 0)
        )
        let edited = tree.applying(edit: edit)

        #expect(edited.root.children[1].byteRange == 4..<7)
        #expect(edited.root.children[1].pointRange == Point(row: 1, column: 0)..<Point(row: 1, column: 3))
        #expect(edited.root.fields["rhs"]?.first?.byteRange == 4..<7)
        #expect(edited.root.fields["rhs"]?.first?.pointRange == Point(row: 1, column: 0)..<Point(row: 1, column: 3))
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

@Suite("Lexer comment tokenization")
struct LexerCommentTests {
    private func makeLexTable(comments: [CommentPattern], keywords: [String: Int] = [:]) -> LexTable {
        var states: [LexState] = []
        if !keywords.isEmpty {
            states = buildTrieStates(keywords: keywords)
        }
        return LexTable(states: states, keywords: keywords, commentPatterns: comments)
    }

    private func buildTrieStates(keywords: [String: Int]) -> [LexState] {
        // Minimal trie for testing
        LexTableCompiler.compile(
            GrammarDefinition(
                name: "test",
                rules: keywords.map { ($0.key, Rule.string($0.key)) }
            )
        ).states
    }

    @Test("Line comment is tokenized as a single extra token")
    func lineCommentSingleToken() {
        let lexTable = makeLexTable(comments: [.line(prefix: "//")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// this is a comment")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "// this is a comment")
        #expect(commentTokens[0].isExtra)
    }

    @Test("Line comment stops at newline")
    func lineCommentStopsAtNewline() {
        let lexTable = makeLexTable(comments: [.line(prefix: "//")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// comment\ncode")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "// comment")
    }

    @Test("Doc comment (///) is captured by // prefix")
    func docCommentCapturedByLinePrefix() {
        let lexTable = makeLexTable(comments: [.line(prefix: "//")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/// doc comment with if keyword")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "/// doc comment with if keyword")
    }

    @Test("Keywords inside line comments are NOT tokenized separately")
    func keywordsInsideLineCommentNotTokenized() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .string("if"))])
            ).states,
            keywords: ["if": 0],
            commentPatterns: [.line(prefix: "//")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// if something")
        let keywordTokens = tokens.filter { $0.type == "\"if\"" }
        #expect(keywordTokens.isEmpty, "Keywords inside comments should not be tokenized")
    }

    @Test("Block comment is tokenized as a single extra token")
    func blockCommentSingleToken() {
        let lexTable = makeLexTable(comments: [.block(open: "/*", close: "*/")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/* block comment */")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "/* block comment */")
        #expect(commentTokens[0].isExtra)
    }

    @Test("Block comment spans multiple lines")
    func blockCommentMultiline() {
        let lexTable = makeLexTable(comments: [.block(open: "/*", close: "*/")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/* line1\nline2 */")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "/* line1\nline2 */")
    }

    @Test("Keywords inside block comments are NOT tokenized separately")
    func keywordsInsideBlockCommentNotTokenized() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .string("if"))])
            ).states,
            keywords: ["if": 0],
            commentPatterns: [.block(open: "/*", close: "*/")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/* if else for */")
        let keywordTokens = tokens.filter { $0.type == "\"if\"" }
        #expect(keywordTokens.isEmpty, "Keywords inside block comments should not be tokenized")
    }

    @Test("Comment is matched before keyword when at same position")
    func commentMatchedBeforeKeyword() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .choice([.string("if"), .string("//")]))])
            ).states,
            keywords: ["if": 0, "//": 1],
            commentPatterns: [.line(prefix: "//")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// if")
        #expect(tokens.first?.type == "comment")
    }

    @Test("Hash comment prefix works for Python-style comments")
    func hashCommentPrefix() {
        let lexTable = makeLexTable(comments: [.line(prefix: "#")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("# this is a comment")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "# this is a comment")
    }

    @Test("Code after line comment on next line is tokenized normally")
    func codeAfterCommentTokenizedNormally() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .string("if"))])
            ).states,
            keywords: ["if": 0],
            commentPatterns: [.line(prefix: "//")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// comment\nif")
        let commentTokens = tokens.filter { $0.type == "comment" }
        let keywordTokens = tokens.filter { $0.type == "\"if\"" }
        #expect(commentTokens.count == 1)
        #expect(keywordTokens.count == 1, "Keyword after comment line should be tokenized")
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

    @Test("Parse continues reducing later stacks after an earlier conflict")
    func parseProcessesAllStacksAfterConflict() throws {
        let parser = GLRParser(
            parseTable: makeConflictParseTable(),
            lexTable: LexTable(),
            productions: [
                ProductionRule(name: "_start", symbolCount: 1, symbols: ["Good"]),
                ProductionRule(name: "Bad", symbolCount: 2, symbols: ["a", "ERROR"]),
                ProductionRule(name: "BadSingle", symbolCount: 1, symbols: ["ERROR"]),
                ProductionRule(name: "Good", symbolCount: 2, symbols: ["a", "b"], fields: [1: "rhs"]),
            ]
        )

        let tree = try parser.parse("ab")

        #expect(tree.root.type == "Good")
        #expect(tree.root.children.map(\.type) == ["a", "b"])
        #expect(tree.root.child(forField: "rhs")?.type == "b")
    }
}

@Suite("GLRParser comment nodes")
struct GLRParserCommentNodeTests {
    @Test("Comment tokens appear as extra nodes in the tree")
    func commentNodesInTree() throws {
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

    @Test("Multiple comments produce multiple extra nodes")
    func multipleCommentNodes() throws {
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

private func makeConflictParseTable() -> ParseTable {
    let terminals = ["a", "b", "$end"]
    let nonTerminals = ["Bad", "BadSingle", "Good"]
    let errorRow: [Action] = [.error, .error, .error]

    return ParseTable(
        stateCount: 6,
        symbols: terminals + nonTerminals,
        terminals: terminals,
        nonTerminals: nonTerminals,
        actions: [
            [
                .conflict([.shift(1), .shift(2)]),
                .error,
                .error,
            ],
            [
                .error,
                .error,
                .conflict([
                    .reduce(ruleIndex: 1, count: 2, nonTerminal: "Bad"),
                    .reduce(ruleIndex: 2, count: 1, nonTerminal: "BadSingle"),
                ]),
            ],
            [
                .error,
                .shift(3),
                .error,
            ],
            [
                .error,
                .error,
                .reduce(ruleIndex: 3, count: 2, nonTerminal: "Good"),
            ],
            errorRow,
            [
                .error,
                .error,
                .accept,
            ],
        ],
        gotos: [
            [4, 4, 5],
            [nil, nil, nil],
            [nil, nil, nil],
            [nil, nil, nil],
            [nil, nil, nil],
            [nil, nil, nil],
        ]
    )
}
