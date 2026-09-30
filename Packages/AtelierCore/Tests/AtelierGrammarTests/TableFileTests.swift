import Foundation
import Testing

@testable import AtelierGrammar

/// A table file reads back the tables it was written from, and a damaged, truncated or foreign one throws a
/// `TableFileError`, never traps.
@Suite
struct TableFileTests {
    @Test
    func `a compiled grammar's tables read back equal`() throws {
        let compiled = try Self.compiled()

        let read = try ParseTableCompiler.CompilationResult(tableFile: compiled.tableFile())

        #expect(read.parseTable == compiled.parseTable)
        #expect(read.lexTable == compiled.lexTable)
        #expect(read.productions == compiled.productions)
        #expect(read.lexTable.modeSource != nil)
        #expect(read.isConsistent)
    }

    @Test
    func `tables built by hand read back equal, with what no cell holds`() throws {
        let table = ParseTable(
            stateCount: 3, symbols: ["a", "\"é\"", "s"], terminals: ["a", "\"é\""], nonTerminals: ["s"],
            actions: [
                [.shift(1 << 31), .conflict([.reduce(ruleIndex: 0, count: 2, nonTerminal: "s"), .shift(2)])],
                [.accept, .error], [.shift(-4), .reduce(ruleIndex: 1, count: 0, nonTerminal: "s")]
            ],
            gotos: [[2], [nil], [-7]], externalNames: ["x"], externalSymbols: ["\"x\""],
            validExternals: [[true], [false], [true]], externalIsExtra: [false], lostShifts: [0: [1: 2], 2: [0: 1]])
        let lexTable = LexTable(
            states: [LexState(transitions: [(0x61 ... 0x7A, 1)], accepting: nil), LexState(accepting: 0)],
            keywords: ["if": 0, "else": 1], commentPatterns: [.line(prefix: "//"), .block(open: "/*", close: "*/")],
            tokens: [LexToken(name: "a", isNamed: true, isExtra: false)],
            automaton: [LexAutomatonState(transitions: [], accept: 0)], modeStarts: [0], stateModes: [0, 0, 0],
            errorMode: 0, wordToken: nil, keywordTokens: ["if": 0], modeValidTokens: [[0]], modeEmptyTokens: [nil],
            modeEmptyAfterSeparator: [0])
        let productions = [
            ProductionRule(
                name: "s", symbolCount: 2, symbols: ["a", "s"], fields: [ProductionField(step: 1, name: "rest")],
                aliases: [0: SymbolAlias(type: "head", isNamed: true)], dynamicPrecedence: -3)
        ]
        let tables = ParseTableCompiler.CompilationResult(
            parseTable: table, lexTable: lexTable, productions: productions)

        let read = try ParseTableCompiler.CompilationResult(tableFile: tables.tableFile())

        #expect(read.parseTable == table)
        #expect(read.lexTable == lexTable)
        #expect(read.productions == productions)
    }

    @Test
    func `a file cut short is a length mismatch`() throws {
        let file = try Self.compiled().tableFile()

        #expect(throws: TableFileError.lengthMismatch(declared: file.count - 32, actual: file.count / 2 - 32)) {
            try ParseTableCompiler.CompilationResult(tableFile: file.prefix(file.count / 2))
        }
    }

    @Test
    func `a payload cut short under a header that agrees with it is truncated`() throws {
        let file = try Self.compiled().tableFile()

        #expect(throws: TableFileError.truncated) {
            try ParseTableCompiler.CompilationResult(tableFile: Self.file(payload: Self.payload(of: file).dropLast(9)))
        }
    }

    @Test
    func `a file of another version is unsupported`() throws {
        var file = try Self.compiled().tableFile()
        file[TableFile.versionOffset] &+= 1

        #expect(throws: TableFileError.unsupportedVersion(ParseTableCompiler.formatVersion + 1)) {
            try ParseTableCompiler.CompilationResult(tableFile: file)
        }
    }

    @Test
    func `a count past the bytes left is truncated, before anything is allocated`() throws {
        var payload = Self.payload(of: try Self.compiled().tableFile())
        // The payload starts with the number of strings.
        payload.replaceSubrange(0 ..< 4, with: [0xFF, 0xFF, 0xFF, 0x7F])

        #expect(throws: TableFileError.truncated) {
            try ParseTableCompiler.CompilationResult(tableFile: Self.file(payload: payload))
        }
    }

    @Test
    func `a changed byte fails the checksum`() throws {
        var file = try Self.compiled().tableFile()
        file[file.count - 5] ^= 0x40

        #expect(throws: TableFileError.checksumMismatch) {
            try ParseTableCompiler.CompilationResult(tableFile: file)
        }
    }

    @Test(arguments: [Data(), Data("{\"parseTable\": {}}".utf8), Data(repeating: 0, count: 64)])
    func `bytes that are not a table file are not one`(bytes: Data) {
        #expect(throws: TableFileError.notATableFile) { try ParseTableCompiler.CompilationResult(tableFile: bytes) }
    }

    @Test
    func `every cut and every changed byte under a header that agrees with them throws or reads, never traps`() throws {
        // ASCII identifiers keep the file a few kilobytes, so reading it once per byte stays quick.
        let payload = Self.payload(of: try Self.compiled(identifier: "[a-z_][a-z0-9_]*").tableFile())
        for length in 0 ..< payload.count {
            #expect(throws: TableFileError.self) {
                try ParseTableCompiler.CompilationResult(tableFile: Self.file(payload: payload.prefix(length)))
            }
        }
        for offset in payload.indices {
            var damaged = payload
            damaged[offset] ^= 0xA5
            // What reads back is checked as a cache checks it; neither may trap.
            _ = (try? ParseTableCompiler.CompilationResult(tableFile: Self.file(payload: damaged)))?.isConsistent
        }
    }

    /// `payload` under a header of the current version that agrees with it.
    private static func file(payload: Data) -> Data {
        var file = Data(TableFile.magic)
        for value in [UInt32(ParseTableCompiler.formatVersion), 0] {
            withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) }
        }
        let checksum = Data(payload).withUnsafeBytes(TableFile.checksum(of:))
        for value in [UInt64(payload.count), checksum] {
            withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) }
        }
        return file + payload
    }

    private static func payload(of file: Data) -> Data {
        Data(file.dropFirst(TableFile.headerSize))
    }

    /// A grammar with an external, a word token, fields and aliases, so every part of the tables has content; its
    /// identifiers read `identifier`, a pattern as JSON writes it, Unicode letters by default.
    private static func compiled(
        identifier: String = #"[\\p{L}_][\\p{L}\\d_]*"#
    ) throws -> ParseTableCompiler.CompilationResult {
        let json = #"""
            {
                "name": "sample",
                "word": "identifier",
                "externals": [{"type": "SYMBOL", "name": "indent"}],
                "extras": [{"type": "PATTERN", "value": "\\s"}],
                "rules": {
                    "source": {"type": "REPEAT", "content": {"type": "SYMBOL", "name": "statement"}},
                    "statement": {"type": "CHOICE", "members": [
                        {"type": "SEQ", "members": [
                            {"type": "STRING", "value": "let"},
                            {"type": "FIELD", "name": "name", "content": {"type": "SYMBOL", "name": "identifier"}},
                            {"type": "STRING", "value": "="},
                            {"type": "FIELD", "name": "value", "content": {"type": "SYMBOL", "name": "expression"}}
                        ]},
                        {"type": "SEQ", "members": [{"type": "SYMBOL", "name": "indent"},
                            {"type": "ALIAS", "named": true, "value": "block",
                             "content": {"type": "SYMBOL", "name": "expression"}}]}
                    ]},
                    "expression": {"type": "CHOICE", "members": [
                        {"type": "SYMBOL", "name": "identifier"},
                        {"type": "PREC_LEFT", "value": 1, "content": {"type": "SEQ", "members": [
                            {"type": "SYMBOL", "name": "expression"}, {"type": "STRING", "value": "+"},
                            {"type": "SYMBOL", "name": "expression"}]}}
                    ]},
                    "identifier": {"type": "PATTERN", "value": "\#(identifier)"}
                }
            }
            """#
        return try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
    }
}
