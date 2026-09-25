import Foundation
import Testing

@testable import AtelierGrammar

/// Tables read back from a cache are checked before a parser indexes into them: one out-of-range index would trap on
/// every launch that reads the file.
@Suite
struct CompilationResultConsistencyTests {
    @Test
    func `Tables the compiler builds are consistent`() throws {
        #expect(try Self.compiled().isConsistent)
    }

    @Test
    func `A shift out of the table is inconsistent`() throws {
        var tables = try Self.compiled()
        tables.parseTable.actions[0][0] = .shift(tables.parseTable.stateCount)

        #expect(!tables.isConsistent)
    }

    @Test
    func `A lexer move on an inverted range is inconsistent`() throws {
        var tables = try Self.compiled()
        tables.lexTable.automaton[0].transitions[0].lower = 0x80
        tables.lexTable.automaton[0].transitions[0].upper = 0x7F

        #expect(!tables.isConsistent)
    }

    @Test
    func `A field on a step before the first is inconsistent`() throws {
        var tables = try Self.compiled()
        tables.productions[1].fields = [ProductionField(step: -1, name: "left")]

        #expect(!tables.isConsistent)
    }

    @Test
    func `Fields out of step order are inconsistent`() throws {
        var tables = try Self.compiled()
        tables.productions[1].fields = [ProductionField(step: 1, name: "right"), ProductionField(step: 0, name: "left")]

        #expect(!tables.isConsistent)
    }

    @Test
    func `A cached keyword-trie move on an inverted range fails to decode`() {
        let json = #"{"transitions": [{"lower": 5, "upper": 3, "target": 0}]}"#

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LexState.self, from: Data(json.utf8)) }
    }

    /// `source: seq("a", "b")`, whose compiled tables have a state, a lexer move and a production to damage.
    private static func compiled() throws -> ParseTableCompiler.CompilationResult {
        let json = """
            {
                "name": "pair",
                "rules": {
                    "source": {
                        "type": "SEQ",
                        "members": [{"type": "STRING", "value": "a"}, {"type": "STRING", "value": "b"}]
                    }
                }
            }
            """
        return try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
    }
}
