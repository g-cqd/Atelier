import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

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
        #expect(!sut.diagnosticsEnabled)
        #expect(sut.showsHoverDocumentation)
        #expect(sut.toolLocations.count == DiagnosticTool.allCases.count)
        #expect(DiagnosticTool.allCases.allSatisfy { sut.toolLocations[$0]?.isEnabled == true })
        #expect(sut.lspServerLocations == ["sourcekit-lsp": ToolLocation()])
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
        sut.diagnosticsEnabled = true
        sut.showsHoverDocumentation = false
        sut.toolLocations = [.swiftlint: ToolLocation(isEnabled: false, customPath: "/usr/local/bin/swiftlint")]
        sut.lspServerLocations = ["sourcekit-lsp": ToolLocation(customPath: "/usr/bin/sourcekit-lsp")]

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
        #expect(reloaded.diagnosticsEnabled)
        #expect(!reloaded.showsHoverDocumentation)
        #expect(
            reloaded.toolLocations == [
                .swiftlint: ToolLocation(isEnabled: false, customPath: "/usr/local/bin/swiftlint")
            ])
        #expect(reloaded.lspServerLocations == ["sourcekit-lsp": ToolLocation(customPath: "/usr/bin/sourcekit-lsp")])
    }

    @Test
    func `toggling the diagnostics master switch fires the diagnostics change category`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        final class Owner {}
        let owner = Owner()
        var changes: [ViewerSettings.Change] = []
        sut.addObserver(owner) { changes.append($0) }

        sut.diagnosticsEnabled = true
        sut.toolLocations = [:]
        sut.lspServerLocations = [:]

        #expect(changes == [.diagnostics, .diagnostics, .diagnostics])
    }

    @Test
    func `a stored compact folders flag migrates to the compact tree style`() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "compactsFolders")
        #expect(ViewerSettings(defaults: defaults).treeStyle == .compact)
    }

    @Test
    func `analyzed sides defaults to the newer side and round trips through user defaults`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        #expect(sut.analyzedSides == .newer)

        sut.analyzedSides = .both
        let reloaded = ViewerSettings(defaults: defaults)
        #expect(reloaded.analyzedSides == .both)
    }

    @Test
    func `the settings pane defaults to general and round trips through user defaults`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        #expect(sut.settingsPane == .general)

        sut.settingsPane = .tools
        let reloaded = ViewerSettings(defaults: defaults)
        #expect(reloaded.settingsPane == .tools)
    }

    @Test
    func `restoring general defaults resets its settings and fires observers`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        sut.explorerPlacement = .sidebar
        sut.treeStyle = .flat
        sut.showsChangesOnly = true
        sut.showsIgnoredFiles = true
        sut.syncsScrolling = false
        sut.showsMinimap = false
        sut.showsStatusBar = false
        #expect(sut.settingsDiffCount(.general) == 7)

        final class Owner {}
        let owner = Owner()
        var changes: [ViewerSettings.Change] = []
        sut.addObserver(owner) { changes.append($0) }

        sut.restoreDefaults(.general)

        #expect(sut.explorerPlacement == .top)
        #expect(sut.treeStyle == .hierarchy)
        #expect(!sut.showsChangesOnly)
        #expect(!sut.showsIgnoredFiles)
        #expect(sut.syncsScrolling)
        #expect(sut.showsMinimap)
        #expect(sut.showsStatusBar)
        #expect(sut.settingsDiffCount(.general) == 0)
        #expect(!changes.isEmpty)
    }

    @Test
    func `restoring diff defaults resets isolation, context, granularity and heuristics`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        sut.isolatesChanges = true
        sut.contextLines = 10
        sut.granularity = .syntax
        sut.diffHeuristics.anchorsRareLines = true
        #expect(sut.settingsDiffCount(.diff) == 4)

        sut.restoreDefaults(.diff)

        #expect(!sut.isolatesChanges)
        #expect(sut.contextLines == 3)
        #expect(sut.granularity == .word)
        #expect(sut.diffHeuristics == DiffHeuristics())
        #expect(sut.settingsDiffCount(.diff) == 0)
    }

    @Test
    func `restoring appearance defaults resets theme, line height, mode and wrapping`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        sut.themePath = "/themes/a.xccolortheme"
        sut.lineHeightMultiple = 1.4
        sut.mode = .inline
        sut.wrapsLines = false
        sut.wrapColumn = 100
        #expect(sut.settingsDiffCount(.appearance) == 5)

        sut.restoreDefaults(.appearance)

        #expect(sut.themePath == nil)
        #expect(sut.lineHeightMultiple == 0)
        #expect(sut.mode == .split)
        #expect(sut.wrapsLines)
        #expect(sut.wrapColumn == 0)
        #expect(sut.settingsDiffCount(.appearance) == 0)
    }

    @Test
    func `restoring tools defaults resets diagnostics, hover, analyzed sides and tool locations`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        sut.diagnosticsEnabled = true
        sut.showsHoverDocumentation = false
        sut.analyzedSides = .both
        sut.toolLocations = [.swiftlint: ToolLocation(isEnabled: false)]
        sut.lspServerLocations = [:]
        #expect(sut.settingsDiffCount(.tools) == 5)

        sut.restoreDefaults(.tools)

        #expect(!sut.diagnosticsEnabled)
        #expect(sut.showsHoverDocumentation)
        #expect(sut.analyzedSides == .newer)
        #expect(DiagnosticTool.allCases.allSatisfy { sut.toolLocations[$0]?.isEnabled == true })
        #expect(sut.lspServerLocations == ["sourcekit-lsp": ToolLocation()])
        #expect(sut.settingsDiffCount(.tools) == 0)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
