import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Tables read back from their table file parse every input into the same tree as the tables compiled.
@Suite
struct TableFileParseTests {
    private static let jsonInputs = [
        #"{"a": [1, 2.5e3, true, null, "x\né"], "b": {}, "c": [[], [{}]]}"#,
        #"{"a": [1,, }"#,
        "[\"unterminated"
    ]
    private static let cssInputs = [
        "a > b:hover, .x::before { color: #fff; margin: 0 auto !important; }",
        "@media screen and (min-width: 10px) { .x { display: none } } /* note */",
        "a { color: ; } }"
    ]

    @Test(arguments: [("json", jsonInputs), ("css", cssInputs)])
    func `tables read from their file parse as the compiled tables do`(language: String, inputs: [String]) throws {
        let compiled = try (language == "json" ? BundledGrammarFixture.json : BundledGrammarFixture.css).get()
        let read = try ParseTableCompiler.CompilationResult(tableFile: compiled.tableFile())
        let compiledParser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let readParser = GLRParser(parseTable: read.parseTable, lexTable: read.lexTable, productions: read.productions)

        for input in inputs {
            let expected = try compiledParser.parse(input)
            let actual = try readParser.parse(input)
            #expect(actual == expected, "\(language): \(input)")
        }
    }
}
