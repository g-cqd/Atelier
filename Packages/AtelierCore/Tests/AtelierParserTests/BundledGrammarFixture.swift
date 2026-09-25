import Foundation

@testable import AtelierGrammar
@testable import AtelierParser

/// A grammar KittyCode bundles, read from this checkout and compiled once per test process.
enum BundledGrammarFixture {
    static let json = Result { try compile(language: "json") }
    static let css = Result { try compile(language: "css") }

    /// A parser for the grammar `result` compiled.
    static func parser(for result: Result<ParseTableCompiler.CompilationResult, any Error>) throws -> GLRParser {
        let compiled = try result.get()
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }

    /// The `grammar.json` KittyCode bundles for `language`.
    static func grammarURL(language: String) -> URL {
        // Tests/AtelierParserTests/ → the repository root, four levels up from this file's directory.
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Packages/AtelierCore/Sources/AtelierGrammarCorpus/Grammars/\(language)/grammar.json")
    }

    private static func compile(language: String) throws -> ParseTableCompiler.CompilationResult {
        let grammar = try GrammarLoader.parse(Data(contentsOf: grammarURL(language: language)))
        return try ParseTableCompiler.compile(grammar)
    }
}

extension SyntaxNode {
    /// Whether this node or any node below it is an error.
    var containsError: Bool {
        var pending = [self]
        while let node = pending.popLast() {
            if node.isError || node.type == "ERROR" { return true }
            pending.append(contentsOf: node.children)
        }
        return false
    }
}
