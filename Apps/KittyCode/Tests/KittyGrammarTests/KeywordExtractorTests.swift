import Foundation
import Testing

@testable import KittyGrammar

@Suite
struct KeywordExtractorTests {
    @Test
    func `Extracts word-like keywords`() throws {
        let json = """
            {
                "name": "extract_test",
                "word": "identifier",
                "rules": {
                    "source": {
                        "type": "CHOICE",
                        "members": [
                            {"type": "STRING", "value": "let"},
                            {"type": "STRING", "value": "var"},
                            {"type": "STRING", "value": "+"},
                            {"type": "SYMBOL", "name": "identifier"}
                        ]
                    },
                    "identifier": {"type": "PATTERN", "value": "[a-zA-Z_]\\\\w*"}
                }
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let keywords = KeywordExtractor.extract(from: grammar)
        #expect(keywords["let"] != nil)
        #expect(keywords["var"] != nil)
        #expect(keywords["+"] == nil)  // Not word-like
    }
}
