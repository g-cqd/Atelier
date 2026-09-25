import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// The compact inline view through the window model (book DIFF-04): a marker's click and the keyboard commands
/// disclose and fold changes, rendering only the card they belong to, and the setting is off until turned on.
@MainActor
struct DiffViewerModelCompactInlineTests {
    private let harness = ModelTestHarness()

    /// Cards for a.swift and b.swift in the compact inline view, each thirty lines changed at lines 5 and 25.
    private func loadCompactCards() async throws -> DiffViewerModel {
        let sut = harness.makeSUT()
        sut.settings.mode = .inline
        sut.settings.compactsInlineView = true
        let lines = (1 ... 30).map { "line \($0)" }
        var changed = lines
        changed[4] = "line five"
        changed[24] = "line twenty-five"
        harness.reader.blobContents["old"] = lines.joined(separator: "\n") + "\n"
        harness.reader.blobContents["new"] = changed.joined(separator: "\n") + "\n"
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "old"), harness.entry("b.swift", "old")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "new"), harness.entry("b.swift", "new")
        ]
        try await harness.load(sut)
        return sut
    }

    private func changes(ofCard index: Int, in sut: DiffViewerModel) -> [RenderedChange] {
        sut.renderedFiles[index].rendered.unified?.changes ?? []
    }

    @Test
    func `the compact inline view is off until turned on`() {
        let sut = harness.makeSUT()
        sut.settings.mode = .inline

        #expect(!sut.settings.compactsInlineView)
        #expect(!sut.showsCompactInline)
    }

    @Test
    func `restoring the appearance defaults turns the compact inline view off`() {
        let sut = harness.makeSUT()
        sut.settings.compactsInlineView = true
        #expect(sut.settings.settingsDiffCount(.appearance) >= 1)

        sut.settings.restoreDefaults(.appearance)

        #expect(!sut.settings.compactsInlineView)
    }

    @Test
    func `a marker's click discloses its change and renders its card alone`() async throws {
        let sut = try await loadCompactCards()
        let before = sut.renderedFiles.map(\.rendered.id)
        let key = try #require(changes(ofCard: 1, in: sut).first).key

        sut.toggleChange(key)

        #expect(changes(ofCard: 1, in: sut).map(\.isDisclosed) == [true, false])
        #expect(sut.renderedFiles[0].rendered.id == before[0])
        #expect(sut.renderedFiles[1].rendered.id != before[1])
    }

    @Test
    func `a second click folds the change again`() async throws {
        let sut = try await loadCompactCards()
        let key = try #require(changes(ofCard: 0, in: sut).first).key

        sut.toggleChange(key)
        sut.toggleChange(key)

        #expect(changes(ofCard: 0, in: sut).allSatisfy { !$0.isDisclosed })
        #expect(sut.disclosedChanges.isEmpty)
    }

    @Test
    func `the keyboard discloses the current card's changes together, then folds them`() async throws {
        let sut = try await loadCompactCards()
        sut.goToNextChange()
        sut.goToNextChange()

        sut.toggleCurrentChange()
        #expect(changes(ofCard: 1, in: sut).allSatisfy { $0.isDisclosed })
        #expect(changes(ofCard: 0, in: sut).allSatisfy { !$0.isDisclosed })

        sut.toggleCurrentChange()
        #expect(sut.disclosedChanges.isEmpty)
    }

    @Test
    func `the keyboard discloses every change, then folds them all`() async throws {
        let sut = try await loadCompactCards()

        sut.toggleAllChanges()
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.unified?.changes.allSatisfy { $0.isDisclosed } == true })

        sut.toggleAllChanges()
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.unified?.changes.allSatisfy { !$0.isDisclosed } == true })
    }

    @Test
    func `changing the layout folds every change back`() async throws {
        let sut = try await loadCompactCards()
        sut.toggleAllChanges()
        try await harness.taskProvider.waitForAllTasks()

        sut.settings.mode = .split
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.disclosedChanges.isEmpty)
    }

    @Test
    func `outside the compact view the commands disclose nothing`() async throws {
        let sut = try await loadCompactCards()
        sut.settings.compactsInlineView = false
        try await harness.taskProvider.waitForAllTasks()

        sut.toggleAllChanges()
        sut.toggleCurrentChange()
        sut.toggleChange(ChangeKey(fileIndex: 0, changeIndex: 0))

        #expect(sut.disclosedChanges.isEmpty)
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.unified?.changes.isEmpty == true })
    }
}
