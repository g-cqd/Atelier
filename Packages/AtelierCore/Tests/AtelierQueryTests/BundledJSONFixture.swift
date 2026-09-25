import Foundation

@testable import AtelierGrammar
@testable import AtelierParser
@testable import AtelierQuery

/// KittyCode's bundled JSON grammar and highlight query, read from this checkout and built once per test process.
enum BundledJSONFixture {
    static let artifacts = Result { try load() }

    /// A parser for the JSON grammar and the highlight query KittyCode runs over its trees.
    static func parserAndQuery() throws -> (parser: GLRParser, query: Query) {
        let (compiled, query) = try artifacts.get()
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        return (parser, query)
    }

    private static func load() throws -> (ParseTableCompiler.CompilationResult, Query) {
        // Tests/AtelierQueryTests/ → the repository root, four levels up from this file's directory.
        let directory = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Packages/AtelierCore/Sources/AtelierGrammarCorpus/Grammars/json")
        let grammar = try GrammarLoader.parse(Data(contentsOf: directory.appending(path: "grammar.json")))
        let query = try QueryParser.parse(
            String(contentsOf: directory.appending(path: "highlights.scm"), encoding: .utf8))
        return (try ParseTableCompiler.compile(grammar), query)
    }
}
