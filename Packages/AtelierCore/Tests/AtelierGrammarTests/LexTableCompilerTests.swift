import Foundation
import Testing

@testable import AtelierGrammar

@Suite
struct LexTableCompilerTests {
    @Test
    func `Extract keywords from grammar`() throws {
        let json = """
            {
                "name": "kw_test",
                "rules": {
                    "source": {
                        "type": "CHOICE",
                        "members": [
                            {"type": "STRING", "value": "if"},
                            {"type": "STRING", "value": "else"},
                            {"type": "STRING", "value": "while"}
                        ]
                    }
                }
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.keywords.count == 3)
        #expect(lexTable.keywords["if"] != nil)
        #expect(lexTable.keywords["else"] != nil)
        #expect(lexTable.keywords["while"] != nil)
    }
}
