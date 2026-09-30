import Synchronization
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct ExternalScannerIntegrationTests {
    @Test
    func `external token is scanned before an internal token in its valid state`() throws {
        let grammar = GrammarDefinition(
            name: "scanner_priority",
            rules: [("source", .seq([.symbol("OPEN"), .symbol("CLOSE")]))],
            extras: [],
            externals: [.symbol("OPEN"), .symbol("CLOSE")]
        )
        let result = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: result.parseTable, lexTable: result.lexTable, productions: result.productions)

        let tree = try parser.parse("{}", externalScanner: BraceScanner())

        #expect(tree.root.children.map(\.type) == ["OPEN", "CLOSE"])
        #expect(tree.root.children.allSatisfy { !$0.isError })
        #expect(result.parseTable.externalNames == ["OPEN", "CLOSE"])
        #expect(result.parseTable.validExternals[0] == [true, false])
    }

    @Test
    func `a literal external takes priority over its internal token`() throws {
        let grammar = GrammarDefinition(
            name: "literal_external", rules: [("source", .string("x"))],
            extras: [], externals: [.string("x")])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable,
            productions: compiled.productions)

        let tree = try parser.parse("xy", externalScanner: LongLiteralScanner())

        #expect(!tree.root.containsError)
        #expect(tree.root.byteRange == 0 ..< 2)
    }

    @Test
    func `internal lexer reads a token when the external scanner declines`() throws {
        let grammar = GrammarDefinition(
            name: "scanner_declines",
            rules: [("source", .choice([.symbol("EXTERNAL"), .string("x")]))],
            extras: [],
            externals: [.symbol("EXTERNAL")]
        )
        let result = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: result.parseTable, lexTable: result.lexTable, productions: result.productions)

        let tree = try parser.parse("x", externalScanner: DecliningScanner())

        #expect(tree.root.children.map(\.type) == ["\"x\""])
        #expect(tree.root.children.allSatisfy { !$0.isError })
    }

    @Test
    func `internal lexer restarts at the original position after a scanner advances and declines`() throws {
        let grammar = GrammarDefinition(
            name: "scanner_backtracks",
            rules: [("source", .choice([.symbol("EXTERNAL"), .seq([.string("x"), .string("z")])]))],
            extras: [], externals: [.symbol("EXTERNAL")])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("xz", externalScanner: AdvancingDecliningScanner())

        #expect(!tree.root.containsError)
        #expect(tree.root.children.map(\.type) == ["\"x\"", "\"z\""])
    }

    @Test
    func `an in-range unoffered external token enters error recovery`() throws {
        let grammar = GrammarDefinition(
            name: "unoffered_external", rules: [("source", .seq([.symbol("A"), .string("x")]))],
            extras: [], externals: [.symbol("A"), .symbol("B")])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("bx", externalScanner: UnofferedScanner())

        #expect(tree.root.containsError)
        #expect(tree.root.byteRange == 0 ..< 2)
    }

    @Test(arguments: [0, 1, 2])
    func `malformed external table dimensions throw before scanning`(damage: Int) throws {
        let grammar = GrammarDefinition(
            name: "malformed_externals", rules: [("source", .symbol("A"))],
            extras: [], externals: [.symbol("A")])
        let compiled = try ParseTableCompiler.compile(grammar)
        var table = compiled.parseTable
        switch damage {
            case 0: table.validExternals = ExternalValidity()
            case 1: table.externalSymbols = []
            default: table.externalIsExtra = []
        }
        let parser = GLRParser(
            parseTable: table, lexTable: compiled.lexTable, productions: compiled.productions)

        #expect(throws: ParseError.parsingFailed("External scanner table is inconsistent")) {
            try parser.parse("a", externalScanner: TableScanner())
        }
    }

    @Test
    func `markEnd fixes the token extent before scanner lookahead`() throws {
        let grammar = GrammarDefinition(
            name: "marked_extent",
            rules: [("source", .seq([.symbol("EXTERNAL"), .string("b")]))],
            extras: [], externals: [.symbol("EXTERNAL")])
        let result = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: result.parseTable, lexTable: result.lexTable, productions: result.productions)

        let tree = try parser.parse("ab", externalScanner: MarkingScanner())

        #expect(tree.root.children.map(\.byteRange) == [0 ..< 1, 1 ..< 2])
        #expect(tree.root.children.allSatisfy { !$0.isError })
    }

    @Test
    func `zero width external token advances the parse state`() throws {
        let grammar = GrammarDefinition(
            name: "automatic_semicolon",
            rules: [("source", .seq([.string("a"), .symbol("SEMI"), .string("b")]))],
            extras: [],
            externals: [.symbol("SEMI")]
        )
        let result = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: result.parseTable, lexTable: result.lexTable, productions: result.productions)

        let tree = try parser.parse("ab", externalScanner: AutomaticSemicolonScanner())

        #expect(tree.root.children.map(\.type) == ["\"a\"", "SEMI", "\"b\""])
        #expect(tree.root.children[1].byteRange == 1 ..< 1)
        #expect(tree.root.children.allSatisfy { !$0.isError })
    }

    @Test
    func `indentation scanner emits indent and dedent at line boundaries`() throws {
        let grammar = GrammarDefinition(
            name: "indentation",
            rules: [
                (
                    "source",
                    .seq([
                        .string("a"), .symbol("INDENT"), .string("b"), .symbol("DEDENT"), .string("c")
                    ])
                )
            ],
            externals: [.symbol("INDENT"), .symbol("DEDENT")])
        let result = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: result.parseTable, lexTable: result.lexTable, productions: result.productions)

        let tree = try parser.parse("a\n  b\nc", externalScanner: IndentationScanner())

        #expect(tree.root.children.map(\.type) == ["\"a\"", "INDENT", "\"b\"", "DEDENT", "\"c\""])
        #expect(tree.root.children.allSatisfy { !$0.isError })
        #expect(tree.root.children[1].byteRange == 4 ..< 4)
        #expect(tree.root.children[3].byteRange == 6 ..< 6)
    }

    @Test
    func `scanner state follows its own GLR branch after a fork`() throws {
        let grammar = GrammarDefinition(name: "fork", rules: [("source", .string("a"))], extras: [])
        let lexTable = try ParseTableCompiler.compile(grammar).lexTable
        let terminals = ["\"a\"", "X", "Y", "Z", "$end"]
        let table = ParseTable(
            stateCount: 5, symbols: terminals, terminals: terminals, nonTerminals: [],
            actions: [
                [.conflict([.shift(1), .shift(2)]), .error, .error, .error, .error],
                [.error, .shift(3), .error, .error, .error],
                [.error, .error, .shift(3), .error, .error],
                [.error, .error, .error, .shift(4), .error],
                [.error, .error, .error, .error, .accept]
            ],
            gotos: [[], [], [], [], []],
            externalNames: ["X", "Y", "Z"], externalSymbols: ["X", "Y", "Z"],
            validExternals: [
                [false, false, false], [true, false, false],
                [false, true, false], [false, false, true], [false, false, false]
            ],
            externalIsExtra: [false, false, false])
        let parser = GLRParser(
            parseTable: table, lexTable: lexTable,
            productions: [ProductionRule(name: "source", symbolCount: 0)])

        let tree = try parser.parse("ab!", externalScanner: ForkStateScanner())

        #expect(tree.root.children.map(\.type) == ["\"a\"", "Y", "Z"])
        #expect(tree.root.children.allSatisfy { !$0.isError })
    }

    @Test
    func `error recovery offers every external symbol to the scanner`() throws {
        let grammar = GrammarDefinition(
            name: "recovery", rules: [("source", .string("a"))],
            extras: [], externals: [.symbol("EXTERNAL")])
        let result = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: result.parseTable, lexTable: result.lexTable, productions: result.productions)
        let scanner = RecoveryScanner()

        _ = try parser.parse("?a", externalScanner: scanner)

        #expect(result.parseTable.validExternals[0] == [false])
        #expect(scanner.sawAllValid)
    }
}

private struct BraceScanner: GrammarExternalScanner {
    static let externalNames = ["OPEN", "CLOSE"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        if validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "{")) {
            lexer.resultSymbol = 0
            lexer.advance(skip: false)
            return true
        }
        if validSymbols[1], lexer.lookahead == UInt32(UInt8(ascii: "}")) {
            lexer.resultSymbol = 1
            lexer.advance(skip: false)
            return true
        }
        return false
    }

    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct DecliningScanner: GrammarExternalScanner {
    static let externalNames = ["EXTERNAL"]
    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool { false }
    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct AdvancingDecliningScanner: GrammarExternalScanner {
    static let externalNames = ["EXTERNAL"]
    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "x")) else { return false }
        lexer.advance(skip: false)
        return false
    }
    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct UnofferedScanner: GrammarExternalScanner {
    static let externalNames = ["A", "B"]
    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "b")) else { return false }
        lexer.advance(skip: false)
        lexer.resultSymbol = 1
        return true
    }
    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct TableScanner: GrammarExternalScanner {
    static let externalNames = ["A"]
    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool { false }
    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct AutomaticSemicolonScanner: GrammarExternalScanner {
    static let externalNames = ["SEMI"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "b")) else { return false }
        lexer.resultSymbol = 0
        lexer.markEnd()
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct MarkingScanner: GrammarExternalScanner {
    static let externalNames = ["EXTERNAL"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "a")) else { return false }
        lexer.advance(skip: false)
        lexer.markEnd()
        lexer.advance(skip: false)
        lexer.resultSymbol = 0
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct IndentationScanner: GrammarExternalScanner {
    static let externalNames = ["INDENT", "DEDENT"]
    private var indentation: UInt8 = 0
    init() {}

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard lexer.lookahead == UInt32(UInt8(ascii: "\n")) else { return false }
        lexer.advance(skip: true)
        while lexer.lookahead == UInt32(UInt8(ascii: " ")) { lexer.advance(skip: true) }
        let column = lexer.column()
        if validSymbols[0], column > indentation {
            indentation = UInt8(clamping: column)
            lexer.resultSymbol = 0
            lexer.markEnd()
            return true
        }
        if validSymbols[1], column < indentation {
            indentation = UInt8(clamping: column)
            lexer.resultSymbol = 1
            lexer.markEnd()
            return true
        }
        return false
    }

    func serialize(into buffer: inout [UInt8]) { buffer.append(indentation) }
    mutating func deserialize(_ state: ArraySlice<UInt8>) { indentation = state.first ?? 0 }
}

private struct ForkStateScanner: GrammarExternalScanner {
    static let externalNames = ["X", "Y", "Z"]
    private var previous = 0
    init() {}

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        if validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "b")) {
            previous = 1
            lexer.resultSymbol = 0
            lexer.advance(skip: false)
            return true
        }
        if validSymbols[1], lexer.lookahead == UInt32(UInt8(ascii: "b")) {
            previous = 2
            lexer.resultSymbol = 1
            lexer.advance(skip: false)
            return true
        }
        if validSymbols[2], previous == 2, lexer.lookahead == UInt32(UInt8(ascii: "!")) {
            lexer.resultSymbol = 2
            lexer.advance(skip: false)
            return true
        }
        return false
    }

    func serialize(into buffer: inout [UInt8]) { buffer.append(UInt8(previous)) }
    mutating func deserialize(_ state: ArraySlice<UInt8>) { previous = Int(state.first ?? 0) }
}

private final class RecoveryScanner: GrammarExternalScanner {
    static let externalNames = ["EXTERNAL"]
    private let observed = Mutex(false)
    var sawAllValid: Bool { observed.withLock { $0 } }
    init() {}

    func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        if lexer.lookahead == UInt32(UInt8(ascii: "a")), validSymbols == [true] {
            observed.withLock { $0 = true }
        }
        return false
    }

    func serialize(into buffer: inout [UInt8]) {}
    func deserialize(_ state: ArraySlice<UInt8>) {}
}

private struct LongLiteralScanner: GrammarExternalScanner {
    static let externalNames = ["x"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "x")) else { return false }
        lexer.advance(skip: false)
        guard lexer.lookahead == UInt32(UInt8(ascii: "y")) else { return false }
        lexer.advance(skip: false)
        lexer.resultSymbol = 0
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}
