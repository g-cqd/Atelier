import AemiCore
import AemiTesting
import AtelierSyntaxModel
import DiffCore
import Foundation
import Testing

@testable import AtelierGrammarCorpus
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// Which colour each displayed side takes through the window model (PERF-11): the lexer's on every language it knows,
/// whatever the refinement settings, then swift-syntax's on Swift while it is on, and a grammar's where one qualifies.
@MainActor
@Suite(.mainActorLane)
struct ColourTierCoverageTests {
    private let harness = ModelTestHarness()

    private static let cacheDirectory = FileManager.default.temporaryDirectory.appending(
        path: "gdv-test-grammar-tables", directoryHint: .isDirectory)

    private static func services() throws -> GrammarColorServices {
        let corpus = try GrammarCorpus.bundled()
        let registry = GrammarRegistry(cacheDirectory: cacheDirectory, bundledManifest: try corpus.manifest())
        return GrammarColorServices(
            artifacts: SyntaxArtifactsCache(
                registry: registry, grammarsDirectory: corpus.grammarsDirectory, limits: GrammarColorServices.limits),
            pool: nil)
    }

    /// The colour layers the new side's first line took once `path`, changed from `old` to `new`, showed and every
    /// stage ended, on a window with `services`, or the bundled ones when `grammar` holds.
    private func layers(
        _ path: String, old: String, new: String, refinesSwift: Bool, grammar: Bool,
        services: GrammarColorServices? = nil
    ) async throws -> [HighlightLayer] {
        let sut = harness.makeSUT()
        sut.settings.refinesSwiftColor = refinesSwift
        sut.attachGrammarColor(try services ?? (grammar ? Self.services() : nil))
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry(path, "old-\(path)")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry(path, "new-\(path)")]
        harness.reader.blobContents["old-\(path)"] = old
        harness.reader.blobContents["new-\(path)"] = new
        try await harness.load(sut)
        let file = try #require(sut.renderedFiles.first?.rendered)
        sut.noteDisplayed(file.id)
        try await harness.taskProvider.waitForAllTasks()
        return sut.decorations(for: file.new)?.new.colors?.layers(onLine: 0) ?? []
    }

    @Test(arguments: [true, false], [true, false])
    func `a Swift side keeps the lexer's colour, and takes swift-syntax's while it is on`(
        refinesSwift: Bool, grammar: Bool
    ) async throws {
        let layers = try await layers(
            "a.swift", old: "let a = 1\n", new: "let a = 2\n", refinesSwift: refinesSwift, grammar: grammar)

        #expect(layers.contains(.lexical))
        #expect(layers.contains(.syntactic) == refinesSwift)
    }

    @Test(arguments: [true, false])
    func `a language without a grammar keeps the lexer's colour whatever Swift's setting`(refinesSwift: Bool)
        async throws
    {
        let layers = try await layers(
            "a.m", old: "int a = 1;\n", new: "int a = 2;\n", refinesSwift: refinesSwift, grammar: true)

        #expect(layers == [.lexical])
    }

    @Test(arguments: [("settings.json", "{\"a\": 1}\n", "{\"a\": 2}\n"), ("tool.py", "x = 1\n", "x = 2\n")])
    func `JSON and Python take their grammar's colour over the lexer's, with Swift's refinement off`(
        path: String, old: String, new: String
    ) async throws {
        let layers = try await layers(path, old: old, new: new, refinesSwift: false, grammar: true)

        #expect(layers.contains(.lexical))
        #expect(layers.contains(.structural))
    }

    @Test
    func `a language whose table is known too large starts no grammar job and keeps the lexer's colour`()
        async throws
    {
        let cache = FileManager.default.temporaryDirectory.appending(path: "gdv-grammar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cache) }
        let corpus = try GrammarCorpus.bundled()
        let registry = GrammarRegistry(cacheDirectory: cache, bundledManifest: try corpus.manifest())
        // Every table is too large under a limit of one byte, as TypeScript's is under the app's.
        let services = GrammarColorServices(
            artifacts: SyntaxArtifactsCache(
                registry: registry, grammarsDirectory: corpus.grammarsDirectory,
                limits: SyntaxArtifactsCache.Limits(maxTableBytes: 1, budgetBytes: 1 << 20)),
            pool: nil)
        // The first side compiles JSON's table once, which tells its size.
        _ = try await layers(
            "a.json", old: "{\"a\": 1}\n", new: "{\"a\": 2}\n", refinesSwift: true, grammar: true, services: services)
        let parses = services.record.parsesStarted

        let layers = try await layers(
            "b.json", old: "{\"b\": 1}\n", new: "{\"b\": 2}\n", refinesSwift: true, grammar: true, services: services)

        #expect(layers == [.lexical])
        #expect(services.record.parsesStarted == parses)
        // The gate leaves the grammar tier out of JSON's tiers, so no job starts for it.
        let gate = ColorTierGate()
        _ = gate.update(services: services, grammarOff: [], refinesSwift: true)
        #expect(!gate.grammarColors(.json))
        #expect(gate.grammarColors(.python))
    }
}
