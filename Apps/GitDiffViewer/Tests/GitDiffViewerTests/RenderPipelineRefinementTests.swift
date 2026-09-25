import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A syntactic tier that counts the sides it is handed and can hold them, and answers a line without a token per line.
final class RefinerSpy: Sendable {
    private let state = Mutex((texts: [String](), isHolding: false))
    let started = AsyncProbe<String>()
    let release = AsyncProbe<Void>()

    var texts: [String] { state.withLock { $0.texts } }

    var isHolding: Bool {
        get { state.withLock { $0.isHolding } }
        set { state.withLock { $0.isHolding = newValue } }
    }

    var refiner: SyntaxRefiner {
        SyntaxRefiner { [self] text, lines in
            let holds = state.withLock { state in
                state.texts.append(text)
                return state.isHolding
            }
            if holds {
                started.send(text)
                _ = try await release.next()
            }
            return LineTokens(emptyLines: lines.count)
        }
    }
}

/// The render pipeline runs swift-syntax on each displayed Swift side after the lexer's first paint, once per content,
/// and hands what lands only to the texts still published (PERF-11 step 1).
@MainActor
struct RenderPipelineRefinementTests {
    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()
    private let spy = RefinerSpy()
    private let sut: RenderPipeline

    init() {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        sut = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: DiffRenderer.Options(sides: [.old, .new]),
            refiner: spy.refiner)
        sut.configure(options: DiffRenderer.Options(sides: [.old, .new]), context: 2, isolatesChanges: false)
        reader.blobContents["old"] = "let set = [1]\nlet b = 2\n"
        reader.blobContents["new"] = "let set = [1]\nlet b = 3\n"
        reader.blobContents["other"] = "let other = 4\n"
    }

    private func pair(_ path: String, old: String = "old", new: String = "new") -> FilePair {
        FilePair(
            path: path, old: SourceEntry(relativePath: path, blobID: old, size: 1),
            new: SourceEntry(relativePath: path, blobID: new, size: 1))
    }

    /// What `text`'s panes colour with; nil for no text.
    private func sides(of text: RenderedText?) -> RefinedSides? {
        text.flatMap { sut.refinedSides(forText: $0.id) }
    }

    /// Renders `pair` as the file shown, taking what showed off screen at once.
    private func render(_ pair: FilePair) {
        sut.render(
            .file(pair), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics(), keepingPublished: false)
    }

    /// Renders `pair` as the file shown and waits until it is published.
    private func show(_ pair: FilePair) async throws -> RenderedDiff {
        render(pair)
        try await taskProvider.waitForAllTasks()
        return try #require(sut.file)
    }

    @Test
    func `a displayed Swift file's sides are refined once each and reach both its panes`() async throws {
        let file = try await show(pair("a.swift"))

        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        #expect(spy.texts.count == 2)
        let old = try #require(sides(of: file.old))
        #expect(old.old?.count == 2 && old.new?.count == 2)
        #expect(sides(of: file.new)?.id == old.id)
    }

    @Test
    func `both sides of one blob are parsed once`() async throws {
        let file = try await show(pair("a.swift", old: "old", new: "old"))

        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        #expect(spy.texts.count == 1)
    }

    @Test
    func `a file that is not Swift never reaches swift-syntax`() async throws {
        let file = try await show(pair("a.json"))

        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        #expect(spy.texts.isEmpty)
        #expect(sut.refinement.byText.isEmpty)
    }

    @Test
    func `with the setting off no parse runs, and turning it on refines what shows`() async throws {
        sut.refinesSwiftColor = false
        let file = try await show(pair("a.swift"))

        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()
        #expect(spy.texts.isEmpty)
        #expect(sut.refinement.byText.isEmpty)

        sut.refinesSwiftColor = true
        try await taskProvider.waitForAllTasks()
        #expect(spy.texts.count == 2)
        #expect(sides(of: file.new) != nil)
    }

    @Test
    func `turning the setting off takes the refined colour away`() async throws {
        let file = try await show(pair("a.swift"))
        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        sut.refinesSwiftColor = false

        #expect(sides(of: file.new) == nil)
    }

    @Test
    func `an update for a superseded render is dropped`() async throws {
        spy.isHolding = true
        let first = try await show(pair("a.swift"))
        sut.refineDisplayed(first.id)
        _ = try await spy.started.expectNext()
        _ = try await spy.started.expectNext()

        render(pair("b.swift", old: "other", new: "other"))
        spy.release.send(())
        spy.release.send(())
        try await taskProvider.waitForAllTasks()

        let second = try #require(sut.file)
        #expect(sut.refinement.byText.isEmpty)
        #expect(sides(of: second.new) == nil)
        #expect(sides(of: first.new) == nil)
        spy.isHolding = false
        sut.refineDisplayed(second.id)
        try await taskProvider.waitForAllTasks()
        #expect(spy.texts.count == 3)
    }

    @Test
    func `a relayout of a refined file takes its colour at once, with no new parse`() async throws {
        let file = try await show(pair("a.swift"))
        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        sut.configure(options: DiffRenderer.Options(sides: [.unified]), context: 2, isolatesChanges: false)
        sut.relayout(keepingScroll: true)
        try await taskProvider.waitForAllTasks()
        let relaid = try #require(sut.file)
        sut.refineDisplayed(relaid.id)

        #expect(relaid.id != file.id)
        #expect(spy.texts.count == 2)
        #expect(sides(of: relaid.unified) != nil)
    }
}

/// The window's setting turns the tier on and off, and is on by default.
@MainActor
struct SwiftColorRefinementSettingTests {
    private let harness = ModelTestHarness()

    @Test
    func `swift-syntax colour is on by default and follows its setting`() {
        let sut = harness.makeSUT()
        #expect(sut.settings.refinesSwiftColor)
        #expect(sut.pipeline.refinesSwiftColor)

        sut.settings.refinesSwiftColor = false

        #expect(!sut.pipeline.refinesSwiftColor)
        #expect(ViewerSettings(defaults: harness.scratchDefaults.defaults).refinesSwiftColor == false)
    }

    @Test
    func `restoring the appearance defaults turns it back on`() {
        let sut = harness.makeSUT()
        sut.settings.refinesSwiftColor = false
        #expect(sut.settings.settingsDiffCount(.appearance) == 1)

        sut.settings.restoreDefaults(.appearance)

        #expect(sut.settings.refinesSwiftColor)
        #expect(!ViewerSettings.isProjectScoped(\ViewerSettings.refinesSwiftColor))
    }
}
