import AtelierScanners
import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Opt-in parse measurements against the pinned Swift 0.7.3 grammar.
@Suite
struct SwiftGrammarAcceptanceTests {
    /// Tree-sitter reads `@Test` as the class's modifier. Offered `_implicit_semi` after `Test`, which only another
    /// context of the merged state could take, the scanner ended the attribute there and the parse left five ERROR
    /// nodes.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_SWIFT_GRAMMAR"] != nil))
    func `the pinned annotation corpus case reads its attribute as the class's modifier`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["ATELIER_SWIFT_GRAMMAR"])
        let grammar = try GrammarLoader.load(from: path)
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable,
            productions: compiled.productions)

        let tree = try parser.parse("@Test\nclass Empty { }\n", externalScanner: SwiftExternalScanner())

        #expect(!tree.root.containsError)
        #expect(Self.nodes("class_declaration", in: tree.root).map(\.byteRange) == [0 ..< 21])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_SWIFT_GRAMMAR"] != nil))
    func `parses repository Swift files with the bundled external scanner`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["ATELIER_SWIFT_GRAMMAR"])
        let grammar = try GrammarLoader.load(from: path)
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable,
            productions: compiled.productions)
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let seven = [
            "Packages/AtelierCore/Sources/AtelierGrammar/LexAutomaton.swift",
            "Packages/AtelierCore/Sources/AtelierParser/ScannerLexer.swift",
            "Packages/AtelierCore/Sources/AtelierGrammar/GrammarDefinition.swift",
            "Apps/KittyCode/Sources/KittyStyle/Style.swift",
            "Packages/AtelierCore/Sources/AtelierSyntaxModel/HighlightToken.swift",
            "Packages/AtelierCore/Sources/AtelierSyntaxModel/HighlightRole.swift",
            "Packages/AtelierCore/Sources/AtelierSyntaxModel/SemanticTokenProvider.swift"
        ]
        let extra = try samplePaths(in: repository).filter { !seven.contains($0) }.prefix(21)
        var totalNodes = 0
        var totalErrors = 0
        var totalBytes = 0
        var totalErrorBytes = 0
        let clock = ContinuousClock()
        for relative in seven + Array(extra) {
            let source = try String(contentsOf: repository.appending(path: relative), encoding: .utf8)
            let start = clock.now
            let tree = try parser.parse(source, externalScanner: SwiftExternalScanner())
            let elapsed = start.duration(to: clock.now)
            let counts = countErrors(in: tree)
            totalNodes += counts.nodes
            totalErrors += counts.errors
            totalBytes += source.utf8.count
            totalErrorBytes += counts.errorBytes
            print(
                "SWIFT PARSE \(relative): \(counts.errors) ERROR nodes / \(counts.nodes) nodes, "
                    + "\(counts.errorBytes) ERROR bytes / \(source.utf8.count) bytes in \(elapsed)")
            if counts.errors > 0, seven.contains(relative) {
                var pending = [tree.root]
                while let node = pending.popLast() {
                    if node.isError || node.type == "ERROR" {
                        let preview = node.text(from: source).prefix(100)
                            .replacingOccurrences(of: "\n", with: "\\n")
                        print("SWIFT ERROR \(relative): \(node.byteRange) \(preview)")
                        break
                    }
                    pending.append(contentsOf: node.children)
                }
            }
            #expect(counts.nodes > 1)
            if seven.contains(relative) { #expect(counts.errors * 10 <= counts.nodes) }
        }
        print(
            "SWIFT TOTAL: \(totalErrors) ERROR nodes / \(totalNodes) nodes, "
                + "\(totalErrorBytes) ERROR bytes / \(totalBytes) bytes")
    }

    private func samplePaths(in repository: URL) throws -> [String] {
        let root = repository.appending(path: "Packages/AtelierCore/Sources")
        var pending = [root]
        var paths: [String] = []
        while let directory = pending.popLast() {
            for url in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            {
                if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    pending.append(url)
                } else if url.pathExtension == "swift" {
                    paths.append(String(url.path.dropFirst(repository.path.count + 1)))
                }
            }
        }
        return paths.sorted()
    }

    private func countErrors(in tree: SyntaxTree) -> (nodes: Int, errors: Int, errorBytes: Int) {
        var pending = [tree.root]
        var nodes = 0
        var errors = 0
        var ranges: [Range<Int>] = []
        while let node = pending.popLast() {
            nodes += 1
            if node.isError || node.type == "ERROR" {
                errors += 1
                ranges.append(node.byteRange)
            }
            pending.append(contentsOf: node.children)
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var covered = 0
        var end = 0
        for range in ranges {
            covered += max(0, range.upperBound - max(end, range.lowerBound))
            end = max(end, range.upperBound)
        }
        return (nodes, errors, covered)
    }

    /// The nodes of type `type` in the tree of `root`, in source order.
    private static func nodes(_ type: String, in root: SyntaxNode) -> [SyntaxNode] {
        var found: [SyntaxNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            if node.type == type { found.append(node) }
            pending.append(contentsOf: node.children.reversed())
        }
        return found
    }
}
