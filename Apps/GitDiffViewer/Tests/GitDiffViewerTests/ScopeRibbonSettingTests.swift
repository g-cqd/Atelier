import AemiCore
import AemiTesting
import AppKit
import DiffCore
import DiffRendering
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffTextKit

/// The "Show scope ribbon" setting (DIFF-03): off, no scope stays folded; either way the gutter keeps the width the
/// ribbon takes, so turning it back on never shifts the text.
@MainActor
@Suite(.mainActorLane)
struct ScopeRibbonSettingTests {
    private let harness = ModelTestHarness()
    private static let s = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 1)

    /// `a.swift` shown inline, with `s` folded.
    private func showFolded() async throws -> DiffViewerModel {
        let sut = harness.makeSUT()
        sut.settings.mode = .inline
        harness.reader.blobContents["old"] = ScopeFoldRenderingTests.old
        harness.reader.blobContents["new"] = ScopeFoldRenderingTests.new
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "old")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "new")]
        try await harness.load(sut)
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        sut.changeFolds(.fold([Self.s: 3]))
        return sut
    }

    @Test
    func `turning the ribbon off unfolds every scope, since nothing could fold one back`() async throws {
        let sut = try await showFolded()
        try #require(!sut.foldedScopes.isEmpty)

        sut.settings.showsScopeRibbon = false

        #expect(sut.foldedScopes.isEmpty)
    }

    @Test
    func `turning the ribbon back on folds none of the scopes it dropped`() async throws {
        let sut = try await showFolded()
        sut.settings.showsScopeRibbon = false

        sut.settings.showsScopeRibbon = true

        #expect(sut.foldedScopes.isEmpty)
    }

    @Test
    func `an unrelated appearance change while the ribbon is already off folds nothing back`() async throws {
        let sut = try await showFolded()
        sut.settings.showsScopeRibbon = false

        sut.settings.wrapsLines.toggle()

        #expect(sut.foldedScopes.isEmpty)
    }

    /// A gutter with a scope, whose thickness and drawing follow ``DiffGutterView/showsScopeRibbon``.
    private func gutter() throws -> DiffGutterView {
        let text = ScopeLinesTests.text
        let prepared = PreparedDiff(
            FileDiffInput(title: "a.swift", oldText: text, newText: text, language: .swift), granularity: .word)
        let rendered = try #require(
            DiffRenderer.render(prepared: [prepared], options: .init(), layout: .full, withHeaders: false).new)
        let gutter = DiffGutterView(clipView: nil)
        gutter.rendered = rendered
        gutter.decorations = DecorationSnapshot()
        let decorations = DiffDecorations(new: .init(scopes: try ScopeLinesTests.scopes()))
        gutter.decorations?.set(rendered: rendered, decorations: decorations)
        return gutter
    }

    @Test
    func `turning the ribbon off reclaims its width, and back on grows it again (book D43)`() throws {
        let sut = try gutter()
        let withRibbon = sut.thickness

        sut.showsScopeRibbon = false
        let withoutRibbon = sut.thickness

        #expect(withoutRibbon < withRibbon)

        sut.showsScopeRibbon = true

        #expect(sut.thickness == withRibbon)
    }
}
