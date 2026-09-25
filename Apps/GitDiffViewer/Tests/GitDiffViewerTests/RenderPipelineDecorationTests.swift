import AemiCore
import AemiTesting
import AppKit
import AtelierHighlighting
import AtelierSwiftSyntax
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A syntactic tier that counts the sides it is handed and can hold them, and answers a line without a token per line.
final class TierSpy: Sendable {
    private let state = Mutex((requests: [TierRequest](), isHolding: false))
    let started = AsyncProbe<String>()
    let release = AsyncProbe<Void>()

    var texts: [String] { state.withLock { $0.requests.map(\.text) } }
    var requests: [TierRequest] { state.withLock { $0.requests } }

    var isHolding: Bool {
        get { state.withLock { $0.isHolding } }
        set { state.withLock { $0.isHolding = newValue } }
    }

    var tier: Tier { Tier(spy: self) }

    /// Records the request, holds when asked to, then emits every line at once.
    fileprivate func run(_ request: TierRequest) async throws -> TierUpdate {
        let holds = state.withLock { state in
            state.requests.append(request)
            return state.isHolding
        }
        if holds {
            started.send(request.text)
            _ = try await release.next()
        }
        let lines = 0 ..< request.lineRanges.count
        return TierUpdate(
            layer: .syntactic, coverage: .complete, revision: request.revision, lines: lines,
            tokens: LineTokens(emptyLines: lines.count))
    }

    struct Tier: AtelierHighlighting.HighlightTier {
        let spy: TierSpy

        var layer: HighlightLayer { .syntactic }
        var coverage: TierCoverage { .complete }

        func supports(_ language: Language) -> Bool { language == .swift }

        func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
            await emit(try await spy.run(request))
        }
    }
}

/// What a test records from a closure it hands on.
private final class Recorded<Element: Sendable>: Sendable {
    private let values = Mutex([Element]())

    func append(_ value: Element) { values.withLock { $0.append(value) } }

    var all: [Element] { values.withLock { $0 } }
}

/// The events a pipeline sent, in order.
@MainActor
private final class EventLog {
    var all: [RenderPipeline.Event] = []
}

/// A structural tier that always fails, for a stage that fails beside the others.
private struct FailingTier: AtelierHighlighting.HighlightTier {
    var layer: HighlightLayer { .structural }
    var coverage: TierCoverage { .complete }

    func supports(_ language: Language) -> Bool { true }

    func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        throw TierFailure.gate("error nodes")
    }
}

/// The stages after the text (PERF-09): a published file is plain until a pane shows it; then its sides are coloured,
/// the lexer's first and swift-syntax's over it on Swift sides, once per content, and its changes emphasized, the rows
/// a pane shows first; what lands reaches only the texts still published, and a stage that fails leaves the others.
@MainActor
@Suite(.mainActorLane)
struct RenderPipelineDecorationTests {
    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()
    private let spy = TierSpy()
    private let sut: RenderPipeline
    private let events = EventLog()

    init() {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        sut = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: DiffRenderer.Options(sides: [.old, .new]),
            decorator: DiffDecorator(tiers: [LexicalTier(), spy.tier], clock: TestClock()))
        sut.configure(options: DiffRenderer.Options(sides: [.old, .new]), context: 2, isolatesChanges: false)
        let events = events
        sut.onEvent = { event in events.all.append(event) }
        reader.blobContents["old"] = "let set = [1]\nlet b = 2\n"
        reader.blobContents["new"] = "let set = [1]\nlet b = 3\n"
        reader.blobContents["other"] = "let other = 4\n"
        reader.blobContents["long-old"] = (0 ..< 200).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        reader.blobContents["long-new"] =
            (0 ..< 200).map { $0 % 50 == 0 ? "let value\($0) = -\($0)" : "let value\($0) = \($0)" }
            .joined(separator: "\n") + "\n"
    }

    private func pair(_ path: String, old: String = "old", new: String = "new") -> FilePair {
        FilePair(
            path: path, old: SourceEntry(relativePath: path, blobID: old, size: 1),
            new: SourceEntry(relativePath: path, blobID: new, size: 1))
    }

    /// What `text`'s panes draw over it; nil for no text, or none landed.
    private func decorations(of text: RenderedText?) -> DiffDecorations? {
        text.flatMap { sut.decorations(forText: $0.id) }
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

    /// Shows `pair`, as a pane does, and waits for its stages to land.
    private func decorate(_ pair: FilePair) async throws -> RenderedDiff {
        let file = try await show(pair)
        sut.decorateDisplayed(file.id)
        try await taskProvider.waitForAllTasks()
        return file
    }

    @Test
    func `a published file is plain text, and nothing colours or emphasizes it before a pane shows it`() async throws {
        let file = try await show(pair("a.swift"))

        let new = try #require(file.new)
        var colors: [NSColor] = []
        new.attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: new.attributed.length)) {
            value, _, _ in
            if let color = value as? NSColor { colors.append(color) }
        }
        #expect(colors == [new.palette.textColor])
        #expect(sut.decorations(forText: new.id) == nil)
        #expect(sut.decorator.started == 0 && sut.decorator.marksStarted == 0)
        #expect(spy.texts.isEmpty)
    }

    @Test
    func `a shown file's sides are coloured once each and its changes emphasized, on both its panes`() async throws {
        let file = try await decorate(pair("a.swift"))

        #expect(spy.texts.count == 2)
        let old = try #require(decorations(of: file.old))
        #expect(old.old.colors?.layers(onLine: 0) == [.lexical, .syntactic])
        #expect(old.new.colors?.lineCount == 2)
        // `let b = 2` became `let b = 3`: the digits are the change.
        #expect(old.new.emphasis[1] == [8 ..< 9])
        #expect(old.old.emphasis[1] == [8 ..< 9])
        #expect(decorations(of: file.new)?.colorVersion == old.colorVersion)
        let published = events.all.firstIndex { if case .published = $0 { true } else { false } }
        let decorated = events.all.enumerated()
            .compactMap { index, event -> (Int, RenderPipeline.DecorationLayer)? in
                guard case .decorated(let id, let layer) = event, id == file.id else { return nil }
                return (index, layer)
            }
        #expect(Set(decorated.map(\.1)) == [.color(.lexical), .color(.syntactic), .marks])
        #expect(decorated.allSatisfy { $0.0 > (published ?? .max) })
    }

    @Test
    func `both sides of one blob are coloured once`() async throws {
        _ = try await decorate(pair("a.swift", old: "old", new: "old"))

        #expect(spy.texts.count == 1)
        #expect(sut.decorator.started == 1)
    }

    @Test
    func `a Swift tier never sees another language, and a language no tier knows is emphasized but not coloured`()
        async throws
    {
        let json = try await decorate(pair("a.json"))
        #expect(spy.texts.isEmpty)
        #expect(decorations(of: json.new)?.new.colors?.layers(onLine: 0) == [.lexical])

        let plain = try await decorate(pair("a.txt"))
        #expect(decorations(of: plain.new)?.new.colors == nil)
        #expect(decorations(of: plain.new)?.new.emphasis[1] == [8 ..< 9])
    }

    @Test
    func `with swift-syntax off the lexer alone colours, and turning it on refines what shows`() async throws {
        sut.refinesSwiftColor = false
        let file = try await decorate(pair("a.swift"))
        #expect(spy.texts.isEmpty)
        #expect(decorations(of: file.new)?.new.colors?.layers(onLine: 0) == [.lexical])

        sut.refinesSwiftColor = true
        try await taskProvider.waitForAllTasks()

        #expect(spy.texts.count == 2)
        #expect(decorations(of: file.new)?.new.colors?.layers(onLine: 0) == [.lexical, .syntactic])
    }

    @Test
    func `turning swift-syntax off takes its colour away and keeps the lexer's and the emphasis`() async throws {
        let file = try await decorate(pair("a.swift"))

        sut.refinesSwiftColor = false
        try await taskProvider.waitForAllTasks()

        let decorations = try #require(decorations(of: file.new))
        #expect(decorations.new.colors?.layers(onLine: 0) == [.lexical])
        #expect(decorations.new.emphasis[1] == [8 ..< 9])
    }

    @Test
    func `an update for a superseded render is dropped`() async throws {
        spy.isHolding = true
        let first = try await show(pair("a.swift"))
        sut.decorateDisplayed(first.id)
        _ = try await spy.started.expectNext()
        _ = try await spy.started.expectNext()

        render(pair("b.swift", old: "other", new: "other"))
        spy.release.send(())
        spy.release.send(())
        try await taskProvider.waitForAllTasks()

        let second = try #require(sut.file)
        #expect(decorations(of: second.new) == nil)
        #expect(decorations(of: first.new) == nil)
        spy.isHolding = false
        sut.decorateDisplayed(second.id)
        try await taskProvider.waitForAllTasks()
        #expect(spy.texts.count == 3)
    }

    @Test
    func `clearing the pipeline stops the stages in flight, and nothing they find lands`() async throws {
        spy.isHolding = true
        let file = try await show(pair("a.swift"))
        sut.decorateDisplayed(file.id)
        _ = try await spy.started.expectNext()

        sut.clear()
        spy.release.send(())
        spy.release.send(())
        try await taskProvider.waitForAllTasks()

        #expect(sut.decorator.byText.isEmpty)
    }

    @Test
    func `a tier that fails leaves the others' colour, and plain text where it failed`() async throws {
        let taskProvider = TaskProviderSpy.tolerant()
        let sut = RenderPipeline(
            preparer: DiffPreparer(reader: reader, taskProvider: taskProvider), taskProvider: taskProvider,
            options: DiffRenderer.Options(sides: [.old, .new]),
            decorator: DiffDecorator(tiers: [LexicalTier(), FailingTier()], clock: TestClock()))
        sut.render(
            .file(pair("a.swift")), left: .directory(ModelTestHarness.leftURL),
            right: .directory(ModelTestHarness.rightURL), granularity: .word, heuristics: DiffHeuristics(),
            keepingPublished: false)
        try await taskProvider.waitForAllTasks()
        let file = try #require(sut.file)

        sut.decorateDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        let decorations = try #require(file.new.flatMap { sut.decorations(forText: $0.id) })
        #expect(decorations.new.colors?.layers(onLine: 0) == [.lexical])
        #expect(decorations.new.emphasis[1] == [8 ..< 9])
    }

    @Test
    func `a stage past its deadline is cancelled and keeps what it handed on`() async throws {
        let clock = TestClock()
        let handed = Recorded<Int>()
        let gate = TaskGate()

        async let run: Void = RenderPipeline.withinDeadline(.milliseconds(250), on: clock) {
            handed.append(1)
            do {
                try await gate.wait()
                handed.append(2)
            } catch {
                handed.append(-1)
            }
        }
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .milliseconds(250))
        await run
        gate.open()

        #expect(handed.all == [1, -1])
    }

    @Test
    func `the rows a pane shows are coloured and emphasized first`() async throws {
        let file = try await show(pair("long.swift", old: "long-old", new: "long-new"))
        let new = try #require(file.new)
        sut.decorationViewport.register(new.id) { 120 ..< 160 }

        sut.decorateDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        let lines = spy.requests.map(\.visibleLines)
        #expect(lines.allSatisfy { $0 == 120 ..< 160 })
        let shown = try #require(sut.publishedFiles().first)
        #expect(sut.visibleChanges(of: shown) == [3])
    }

    @Test
    func `a relayout of a decorated file takes its decorations at once, with no new parse`() async throws {
        let file = try await decorate(pair("a.swift"))

        sut.configure(options: DiffRenderer.Options(sides: [.unified]), context: 2, isolatesChanges: false)
        sut.relayout(keepingScroll: true)
        try await taskProvider.waitForAllTasks()
        let relaid = try #require(sut.file)
        sut.decorateDisplayed(relaid.id)

        #expect(relaid.id != file.id)
        #expect(spy.texts.count == 2)
        #expect(decorations(of: relaid.unified)?.new.colors != nil)
    }
}

/// Through the core tier job, a side takes the colour step 1's direct parse gave it, line for line (PERF-11 step 2).
@MainActor
@Suite(.mainActorLane)
struct RenderPipelineTierJobTests {
    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()
    private let sut: RenderPipeline

    /// Non-ASCII text, a CRLF line and a block comment across lines: what the cutting into UTF-16 lines must keep.
    private static let text = "let café = \"😀\" // naïve\r\n/* a\n   b */ struct Set { var set = [1] }\n"

    init() {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        sut = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: DiffRenderer.Options(sides: [.old, .new]),
            decorator: DiffDecorator(clock: TestClock()))
        reader.blobContents["old"] = Self.text
        reader.blobContents["new"] = Self.text + "let tail = 2\n"
    }

    @Test
    func `each line takes the tokens a direct parse gives it`() async throws {
        let pair = FilePair(
            path: "a.swift", old: SourceEntry(relativePath: "a.swift", blobID: "old", size: 1),
            new: SourceEntry(relativePath: "a.swift", blobID: "new", size: 1))
        sut.render(
            .file(pair), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics(), keepingPublished: false)
        try await taskProvider.waitForAllTasks()
        let file = try #require(sut.file)

        sut.decorateDisplayed(file.id)
        try await taskProvider.waitForAllTasks()

        let new = try #require(file.new)
        let sides = try #require(sut.decorations(forText: new.id))
        let text = Self.text + "let tail = 2\n"
        let direct = DecorationFixtures.byLine(
            try await SwiftSyntaxHighlights.tokens(in: text), text: text, lines: DiffModel.lines(of: text))
        for (row, meta) in new.rows.enumerated() {
            guard let number = meta.newNumber else { continue }
            #expect(sides.tokens(of: meta, on: .new) == Array(direct[number - 1]), "row \(row)")
        }
    }
}

/// The window's setting turns the tier on and off, and is on by default.
@MainActor
@Suite(.mainActorLane)
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
