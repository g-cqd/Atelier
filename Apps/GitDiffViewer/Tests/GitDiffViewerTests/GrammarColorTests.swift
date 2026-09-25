import AemiCore
import AemiTesting
import AtelierHighlighting
import AtelierSyntaxModel
import DiffCore
import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierGrammarCorpus
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// Grammar colour in GitDiffViewer (PERF-11 step 5): a displayed side of a language whose grammar qualifies refines to
/// its grammar's colour after the lexer's, per language and under the tables' limits.
@MainActor
@Suite(.mainActorLane)
struct GrammarColorTests {
    private let harness = ModelTestHarness()

    /// Compiled tables shared by every run of these tests: the registry keys them by the grammar's hash, so a run never
    /// reads another grammar's, and only the first run on a machine compiles.
    private static let sharedCacheDirectory = FileManager.default.temporaryDirectory.appending(
        path: "gdv-test-grammar-tables", directoryHint: .isDirectory)

    /// Services over the bundled corpus, parsing on the tier's own task so the harness's task provider waits for them.
    private static func services(
        cacheDirectory: URL = sharedCacheDirectory, compile: GrammarRegistry? = nil
    ) throws -> GrammarColorServices {
        let corpus = try GrammarCorpus.bundled()
        let manifest = try corpus.manifest()
        let registry = compile ?? GrammarRegistry(cacheDirectory: cacheDirectory, bundledManifest: manifest)
        return GrammarColorServices(
            artifacts: SyntaxArtifactsCache(
                registry: registry, grammarsDirectory: corpus.grammarsDirectory, limits: GrammarColorServices.limits),
            pool: nil)
    }

    /// Shows `path` changed from `old` to `new` in a folder comparison, on a model with `services` attached, and
    /// reports the file displayed.
    private func show(
        _ path: String, old: String, new: String, services: GrammarColorServices?, off: Set<String> = [],
        refinesSwift: Bool = true
    ) async throws -> (model: DiffViewerModel, file: RenderedDiff) {
        let sut = harness.makeSUT()
        sut.settings.grammarColorOff = off
        sut.settings.refinesSwiftColor = refinesSwift
        sut.attachGrammarColor(services)
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry(path, "old-\(path)")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry(path, "new-\(path)")]
        harness.reader.blobContents["old-\(path)"] = old
        harness.reader.blobContents["new-\(path)"] = new
        try await harness.load(sut)
        let file = try #require(sut.renderedFiles.first?.rendered)
        #expect(!Self.hasGrammarColor(sut.decorations(for: file.new)?.new))
        sut.noteDisplayed(file.id)
        return (sut, file)
    }

    /// Whether the new side's first line took the grammar's layer.
    private func newSideHasGrammarColor(_ model: DiffViewerModel, _ file: RenderedDiff) -> Bool {
        Self.hasGrammarColor(model.decorations(for: file.new)?.new)
    }

    /// Whether a side's first line took the grammar's layer; the lexer's colour alone does not count.
    private static func hasGrammarColor(_ side: DiffDecorations.Side?) -> Bool {
        side?.colors?.layers(onLine: 0).contains(.structural) == true
    }

    /// Whether a side's first line took any layer above the lexer's.
    private static func hasRefinedColor(_ side: DiffDecorations.Side?) -> Bool {
        side?.colors?.layers(onLine: 0).contains { $0 != .lexical } == true
    }

    @Test(arguments: [
        ("settings.json", "{\"a\": 1}\n", "{\"a\": 2}\n"),
        ("tool.py", "def run():\n    return 1\n", "def run():\n    return 2\n")
    ])
    func `a JSON or Python side refines to its grammar's colour after the lexer's`(
        path: String, old: String, new: String
    ) async throws {
        let (sut, file) = try await show(path, old: old, new: new, services: Self.services())

        try await harness.taskProvider.waitForAllTasks()

        #expect(newSideHasGrammarColor(sut, file))
    }

    @Test
    func `a grammar not loaded yet leaves the lexer's colour, then refines while its file shows`() async throws {
        let cache = FileManager.default.temporaryDirectory.appending(path: "gdv-grammar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cache) }
        let corpus = try GrammarCorpus.bundled()
        let started = AsyncProbe<Void>()
        let loaded = TaskGate()
        let registry = GrammarRegistry(cacheDirectory: cache, bundledManifest: try corpus.manifest()) {
            grammar throws(GrammarError) in
            started.send(())
            try? await loaded.wait()
            return try ParseTableCompiler.compile(grammar)
        }
        let (sut, file) = try await show(
            "settings.json", old: "{\"a\": 1}\n", new: "{\"a\": 2}\n", services: Self.services(compile: registry))

        _ = try await started.next()
        #expect(!Self.hasGrammarColor(sut.decorations(for: file.new)?.new))
        loaded.open()
        try await harness.taskProvider.waitForAllTasks()

        #expect(newSideHasGrammarColor(sut, file))
    }

    @Test
    func `a side its grammar cannot read keeps the lexer's colour`() async throws {
        let (sut, file) = try await show(
            "settings.json", old: "{\"a\": 1}\n", new: "{ { { nope nope nope ] ] ]\n", services: Self.services())

        try await harness.taskProvider.waitForAllTasks()

        #expect(!Self.hasGrammarColor(sut.decorations(for: file.new)?.new))
        #expect(Self.hasGrammarColor(sut.decorations(for: file.new)?.old))
    }

    @Test
    func `a language turned off keeps the lexer's colour and parses nothing`() async throws {
        let services = try Self.services()
        let parsed = services.record.parsesStarted
        let (sut, file) = try await show(
            "settings.json", old: "{\"a\": 1}\n", new: "{\"a\": 3}\n", services: services, off: ["json"])

        try await harness.taskProvider.waitForAllTasks()

        #expect(!Self.hasGrammarColor(sut.decorations(for: file.new)?.new))
        #expect(!Self.hasGrammarColor(sut.decorations(for: file.new)?.old))
        #expect(services.record.parsesStarted == parsed)
    }

    @Test
    func `with swift-syntax's colour off, Swift keeps the lexer's while JSON takes its grammar's`() async throws {
        let services = try Self.services()
        let (swift, swiftFile) = try await show(
            "a.swift", old: "let a = 1\n", new: "let a = 2\n", services: services, refinesSwift: false)
        try await harness.taskProvider.waitForAllTasks()
        #expect(!Self.hasRefinedColor(swift.decorations(for: swiftFile.new)?.new))

        let (json, jsonFile) = try await show(
            "settings.json", old: "{\"a\": 1}\n", new: "{\"a\": 4}\n", services: services, refinesSwift: false)
        try await harness.taskProvider.waitForAllTasks()

        #expect(newSideHasGrammarColor(json, jsonFile))
    }

    @Test
    func `grammar colour is on for every language by default, app-wide, and restores to on`() {
        let settings = ViewerSettings(defaults: harness.scratchDefaults.defaults)
        #expect(settings.grammarColorOff.isEmpty)
        #expect(!ViewerSettings.isProjectScoped(\ViewerSettings.grammarColorOff))
        #expect(ColorTierGate.settingRows.map(\.id).contains("json"))
        #expect(!ColorTierGate.settingRows.map(\.id).contains("swift"))

        settings.grammarColorOff = ["python"]
        #expect(ViewerSettings(defaults: harness.scratchDefaults.defaults).grammarColorOff == ["python"])
        settings.restoreDefaults(.appearance)
        #expect(settings.grammarColorOff.isEmpty)
    }
}
