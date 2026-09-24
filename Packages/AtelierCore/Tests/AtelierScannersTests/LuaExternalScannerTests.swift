import AtelierParser
import AtelierScanners
import Testing

struct LuaBlockCase: Sendable {
    let start: String
    let content: String
    let wrongEnd: String
    let end: String
    let isComment: Bool

    var startName: String { isComment ? "_block_comment_start" : "_block_string_start" }
    var contentName: String { isComment ? "_block_comment_content" : "_block_string_content" }
    var endName: String { isComment ? "_block_comment_end" : "_block_string_end" }
}

private let blockCases: [LuaBlockCase] = [
    .init(start: "--[[", content: "print(\"block comment\")", wrongEnd: "]=]", end: "]]", isComment: true),
    .init(start: "--[==[", content: "print(\"level 2 block comment\")", wrongEnd: "]]", end: "]==]", isComment: true),
    .init(start: "[[", content: " string ", wrongEnd: "]=]", end: "]]", isComment: false),
    .init(start: "[=[", content: "string", wrongEnd: "]]", end: "]=]", isComment: false)
]

struct LuaOracleCase: Sendable {
    let input: String
    let mask: Int
    let level: UInt8
    let found: Bool
    let symbol: Int
    let end: Int
    let position: Int
    let state: [UInt8]
}

// Results from the pinned C scanner compiled with a minimal ASCII TSLexer shim.
private let oracleCases: [LuaOracleCase] = [
    .init(input: "--[[body]]", mask: 1, level: 0, found: true, symbol: 0, end: 4, position: 4, state: [0, 0]),
    .init(input: "--[==[body]==]", mask: 1, level: 0, found: true, symbol: 0, end: 6, position: 6, state: [0, 2]),
    .init(input: "-- [==[", mask: 1, level: 0, found: false, symbol: 0, end: 2, position: 2, state: [0, 0]),
    .init(input: "--[==", mask: 1, level: 0, found: false, symbol: 0, end: 2, position: 5, state: [0, 0]),
    .init(input: "[[body]]", mask: 8, level: 0, found: true, symbol: 3, end: 2, position: 2, state: [0, 0]),
    .init(input: "[=[body]=]", mask: 8, level: 0, found: true, symbol: 3, end: 3, position: 3, state: [0, 1]),
    .init(input: "[==body", mask: 8, level: 0, found: false, symbol: 0, end: 3, position: 3, state: [0, 0]),
    .init(input: " \n[=[", mask: 8, level: 0, found: true, symbol: 3, end: 5, position: 5, state: [0, 1]),
    .init(input: "body]=] tail]]", mask: 2, level: 0, found: true, symbol: 1, end: 12, position: 14, state: [0, 0]),
    .init(input: "body]] tail]==]", mask: 2, level: 2, found: true, symbol: 1, end: 11, position: 15, state: [0, 2]),
    .init(input: "body]]", mask: 2, level: 2, found: false, symbol: 0, end: 5, position: 6, state: [0, 2]),
    .init(input: "body", mask: 2, level: 0, found: false, symbol: 0, end: 4, position: 4, state: [0, 0]),
    .init(input: "string]=] tail]]", mask: 16, level: 0, found: true, symbol: 4, end: 14, position: 16, state: [0, 0]),
    .init(input: "string]] tail]=]", mask: 16, level: 1, found: true, symbol: 4, end: 13, position: 16, state: [0, 1]),
    .init(input: "string]]", mask: 16, level: 1, found: false, symbol: 0, end: 7, position: 8, state: [0, 1]),
    .init(input: "string", mask: 16, level: 0, found: false, symbol: 0, end: 6, position: 6, state: [0, 0]),
    .init(input: "]] more", mask: 4, level: 0, found: true, symbol: 2, end: 2, position: 2, state: [0, 0]),
    .init(input: "]==] more", mask: 4, level: 2, found: true, symbol: 2, end: 4, position: 4, state: [0, 0]),
    .init(input: "]]", mask: 4, level: 2, found: false, symbol: 0, end: 1, position: 1, state: [0, 2]),
    .init(input: "]=]", mask: 4, level: 0, found: false, symbol: 0, end: 2, position: 2, state: [0, 0]),
    .init(input: "]] more", mask: 32, level: 0, found: true, symbol: 5, end: 2, position: 2, state: [0, 0]),
    .init(input: "]=] more", mask: 32, level: 1, found: true, symbol: 5, end: 3, position: 3, state: [0, 0]),
    .init(input: "]]", mask: 32, level: 1, found: false, symbol: 0, end: 1, position: 1, state: [0, 1]),
    .init(input: "]=]", mask: 32, level: 0, found: false, symbol: 0, end: 2, position: 2, state: [0, 0]),
    .init(input: "--[[body]]", mask: 0, level: 0, found: false, symbol: 0, end: 0, position: 0, state: [0, 0]),
    .init(input: "--[[body]]", mask: 2, level: 0, found: true, symbol: 1, end: 8, position: 10, state: [0, 0]),
    .init(input: "--[[body]]", mask: 8, level: 0, found: false, symbol: 0, end: 0, position: 0, state: [0, 0]),
    .init(input: "--[[body]]", mask: 16, level: 0, found: true, symbol: 4, end: 8, position: 10, state: [0, 0]),
    .init(input: "]]", mask: 63, level: 0, found: true, symbol: 5, end: 2, position: 2, state: [0, 0]),
    .init(input: "--[[body]]", mask: 63, level: 0, found: true, symbol: 4, end: 8, position: 10, state: [0, 0]),
    .init(input: "[=[body]=]", mask: 63, level: 0, found: false, symbol: 0, end: 9, position: 10, state: [0, 0]),
    .init(input: "  [[body]]", mask: 63, level: 0, found: true, symbol: 4, end: 8, position: 10, state: [0, 0]),
    .init(input: "]==]", mask: 0, level: 2, found: false, symbol: 0, end: 0, position: 0, state: [0, 2]),
    .init(input: "]==]", mask: 5, level: 2, found: true, symbol: 2, end: 4, position: 4, state: [0, 0]),
    .init(input: "]==]", mask: 36, level: 2, found: true, symbol: 5, end: 4, position: 4, state: [0, 0]),
    .init(input: "]==]", mask: 33, level: 2, found: true, symbol: 5, end: 4, position: 4, state: [0, 0]),
    .init(input: "--[[]]", mask: 1, level: 0, found: true, symbol: 0, end: 4, position: 4, state: [0, 0]),
    .init(input: "]]", mask: 2, level: 0, found: true, symbol: 1, end: 0, position: 2, state: [0, 0]),
    .init(input: "]]", mask: 16, level: 0, found: true, symbol: 4, end: 0, position: 2, state: [0, 0]),
    .init(input: "", mask: 4, level: 0, found: false, symbol: 0, end: 0, position: 0, state: [0, 0])
]

struct LuaExternalScannerTests {
    private func scan(
        _ input: String, at offset: Int = 0, allowing names: [String], scanner: inout LuaExternalScanner
    ) -> (name: String?, lexer: StringScannerLexer) {
        var lexer = StringScannerLexer(input, at: offset)
        let valid = LuaExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? LuaExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `external names match the pinned Lua grammar order`() {
        #expect(
            LuaExternalScanner.externalNames == [
                "_block_comment_start", "_block_comment_content", "_block_comment_end",
                "_block_string_start", "_block_string_content", "_block_string_end"
            ])
        #expect(BundledScanners.byGrammarName["lua"] != nil)
    }

    @Test(arguments: blockCases)
    func `each block start accepts its corpus delimiter and rejects an incomplete opener`(_ block: LuaBlockCase) {
        var scanner = LuaExternalScanner()
        let positive = scan(block.start + block.content + block.end, allowing: [block.startName], scanner: &scanner)
        #expect(positive.name == block.startName)
        #expect(positive.lexer.tokenEnd == block.start.utf8.count)

        scanner = LuaExternalScanner()
        let incomplete = String(block.start.dropLast())
        let negative = scan(incomplete, allowing: [block.startName], scanner: &scanner)
        #expect(negative.name == nil)
    }

    @Test(arguments: blockCases)
    func `each block content includes a different closing level and stops before its own closer`(_ block: LuaBlockCase)
    {
        var scanner = LuaExternalScanner()
        let input = block.start + block.content + block.wrongEnd + " tail" + block.end
        #expect(scan(input, allowing: [block.startName], scanner: &scanner).name == block.startName)
        let content = scan(input, at: block.start.utf8.count, allowing: [block.contentName], scanner: &scanner)
        #expect(content.name == block.contentName)
        #expect(content.lexer.tokenEnd == (block.start + block.content + block.wrongEnd + " tail").utf8.count)

        scanner = LuaExternalScanner()
        #expect(scan(block.start, allowing: [block.startName], scanner: &scanner).name == block.startName)
        let unterminated = scan(block.content + block.wrongEnd, allowing: [block.contentName], scanner: &scanner)
        #expect(unterminated.name == nil)
    }

    @Test(arguments: blockCases)
    func `each block end accepts its level and rejects another level`(_ block: LuaBlockCase) {
        var scanner = LuaExternalScanner()
        #expect(scan(block.start, allowing: [block.startName], scanner: &scanner).name == block.startName)
        let positive = scan(block.end + " tail", allowing: [block.endName], scanner: &scanner)
        #expect(positive.name == block.endName)
        #expect(positive.lexer.tokenEnd == block.end.utf8.count)

        scanner = LuaExternalScanner()
        #expect(scan(block.start, allowing: [block.startName], scanner: &scanner).name == block.startName)
        #expect(scan(block.wrongEnd, allowing: [block.endName], scanner: &scanner).name == nil)
        #expect(scan("", allowing: [block.endName], scanner: &scanner).name == nil)
    }

    @Test(arguments: blockCases)
    func `a token is not produced when its symbol is not offered`(_ block: LuaBlockCase) {
        var scanner = LuaExternalScanner()
        #expect(scan(block.start, allowing: [], scanner: &scanner).name == nil)
        #expect(scan(block.start, allowing: [block.startName], scanner: &scanner).name == block.startName)
        #expect(scan(block.content + block.end, allowing: [], scanner: &scanner).name == nil)
        #expect(scan(block.end, allowing: [], scanner: &scanner).name == nil)
    }

    @Test
    func `all valid symbols follow the C scanner recovery order`() {
        let all = LuaExternalScanner.externalNames
        var scanner = LuaExternalScanner()
        #expect(scan("]]", allowing: all, scanner: &scanner).name == "_block_string_end")
        scanner = LuaExternalScanner()
        #expect(scan("--[[text]]", allowing: all, scanner: &scanner).name == "_block_string_content")
        scanner = LuaExternalScanner()
        #expect(scan("[=[text]=]", allowing: all, scanner: &scanner).name == nil)
    }

    @Test
    func `serialization restores level and empty state resets it`() {
        var scanner = LuaExternalScanner()
        #expect(scan("--[==[", allowing: ["_block_comment_start"], scanner: &scanner).name == "_block_comment_start")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 2])
        #expect(state.count <= maximumSerializedScannerStateSize)

        var restored = LuaExternalScanner()
        restored.deserialize(state[...])
        #expect(scan("]==]", allowing: ["_block_comment_end"], scanner: &restored).name == "_block_comment_end")
        restored.deserialize(state[...])
        restored.deserialize([])
        #expect(scan("]==]", allowing: ["_block_comment_end"], scanner: &restored).name == nil)
        #expect(scan("]]", allowing: ["_block_comment_end"], scanner: &restored).name == "_block_comment_end")
    }

    @Test
    func `delimiter level follows the C unsigned byte wraparound`() {
        let start = "[" + String(repeating: "=", count: 256) + "["
        var scanner = LuaExternalScanner()
        #expect(scan(start, allowing: ["_block_string_start"], scanner: &scanner).name == "_block_string_start")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 0])
        #expect(scan("]]", allowing: ["_block_string_end"], scanner: &scanner).name == "_block_string_end")
    }

    @Test
    func `deserialized comment ending character resets after content`() {
        var scanner = LuaExternalScanner()
        scanner.deserialize([UInt8(ascii: "x"), 0][...])
        let result = scan("abcx", allowing: ["_block_comment_content"], scanner: &scanner)
        #expect(result.name == "_block_comment_content")
        #expect(result.lexer.tokenEnd == 3)
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 0])
    }

    @Test
    func `a signed C ending byte does not match a Unicode scalar`() {
        var scanner = LuaExternalScanner()
        scanner.deserialize([0xFF, 0][...])
        let result = scan("ÿ", allowing: ["_block_comment_content"], scanner: &scanner)
        #expect(result.name == nil)
    }

    @Test(arguments: oracleCases)
    func `scanner matches the pinned C scanner on ASCII inputs`(_ testCase: LuaOracleCase) {
        var scanner = LuaExternalScanner()
        scanner.deserialize([0, testCase.level][...])
        var lexer = StringScannerLexer(testCase.input)
        let valid = (0 ..< LuaExternalScanner.externalNames.count).map { testCase.mask & (1 << $0) != 0 }
        let found = scanner.scan(&lexer, validSymbols: valid)
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(found == testCase.found)
        #expect(lexer.resultSymbol == testCase.symbol)
        #expect(lexer.tokenEnd == testCase.end)
        #expect(lexer.position == testCase.position)
        #expect(state == testCase.state)
    }
}
