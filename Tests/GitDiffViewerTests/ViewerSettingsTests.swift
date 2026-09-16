import DiffCore
import Foundation
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
import Testing

@MainActor
struct ViewerSettingsTests {
    @Test
    func `defaults are split layout, wrapped lines, word emphasis, minimap on and compaction off`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        #expect(sut.mode == .split)
        #expect(sut.wrapsLines)
        #expect(sut.syncsScrolling)
        #expect(!sut.showsChangesOnly)
        #expect(!sut.showsIgnoredFiles)
        #expect(sut.granularity == .word)
        #expect(sut.showsMinimap)
        #expect(sut.treeStyle == .hierarchy)
        #expect(sut.explorerPlacement == .top)
        #expect(sut.sidebarVisibility == .all)
        #expect(sut.wrapColumn == 0)
        #expect(sut.themePath == nil)
        #expect(sut.lineHeightMultiple == 0)
        #expect(!sut.isolatesChanges)
        #expect(sut.contextLines == 3)
    }

    @Test
    func `every setting round trips through user defaults`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        sut.mode = .inline
        sut.wrapsLines = false
        sut.syncsScrolling = false
        sut.showsChangesOnly = true
        sut.showsIgnoredFiles = true
        sut.granularity = .syntax
        sut.showsMinimap = false
        sut.treeStyle = .flat
        sut.explorerPlacement = .unifiedSidebar
        sut.sidebarVisibility = .detailOnly
        sut.wrapColumn = 100
        sut.themePath = "/themes/a.xccolortheme"
        sut.lineHeightMultiple = 1.4
        sut.isolatesChanges = true
        sut.contextLines = 5

        let reloaded = ViewerSettings(defaults: defaults)

        #expect(reloaded.mode == .inline)
        #expect(!reloaded.wrapsLines)
        #expect(!reloaded.syncsScrolling)
        #expect(reloaded.showsChangesOnly)
        #expect(reloaded.showsIgnoredFiles)
        #expect(reloaded.granularity == .syntax)
        #expect(!reloaded.showsMinimap)
        #expect(reloaded.treeStyle == .flat)
        #expect(reloaded.explorerPlacement == .unifiedSidebar)
        #expect(reloaded.sidebarVisibility == .detailOnly)
        #expect(reloaded.wrapColumn == 100)
        #expect(reloaded.themePath == "/themes/a.xccolortheme")
        #expect(reloaded.lineHeightMultiple == 1.4)
        #expect(reloaded.isolatesChanges)
        #expect(reloaded.contextLines == 5)
    }

    @Test
    func `a stored compact folders flag migrates to the compact tree style`() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "compactsFolders")
        #expect(ViewerSettings(defaults: defaults).treeStyle == .compact)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
