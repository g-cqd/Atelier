import Testing

@testable import AtelierGrammar

@Suite
struct ParseTableTerminalVariantsTests {
    /// The bare `"}"`, its numbered variant, and terminals that only look like one: a longer string, and a suffix that
    /// is not a number.
    private static let table = ParseTable(
        stateCount: 0, symbols: [], terminals: ["\"}\"", "\"}\"_7", "\"}}\"", "\"}\"_x", "word"], nonTerminals: [],
        actions: [], gotos: [])

    @Test
    func `a quoted string external's variants are its bare terminal and its numbered variants`() {
        #expect(Self.table.terminalVariants(ofExternalSymbol: "\"}\"") == [0, 1])
    }

    @Test
    func `a symbol external's variants are its own terminal alone`() {
        #expect(Self.table.terminalVariants(ofExternalSymbol: "word") == [4])
    }
}
