import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Instances over the same `UserDefaults`, one per window and one for Settings: a base-default edit through one
/// reaches every other instance's unoverridden keys without a reopen.
@MainActor
struct ViewerSettingsBroadcastTests {
    @Test
    func `a base edit on one instance reflects on another sharing the same defaults`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        a.wrapsLines = false

        #expect(!b.wrapsLines)
    }

    @Test
    func `a base edit does not override a key the receiving instance's own project already overrides`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        b.adoptProject(project)
        b.contextLines = 9  // b's own project-scoped override

        a.contextLines = 15  // a base edit made on a different instance

        #expect(b.contextLines == 9)  // b's own override still wins
        #expect(a.contextLines == 15)
    }

    @Test
    func `a broadcast is applied without re-broadcasting, so it never reaches a third instance twice`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)
        let c = ViewerSettings(defaults: defaults)

        final class Owner {}
        let owner = Owner()
        var cChanges: [ViewerSettings.Change] = []
        c.addObserver(owner) { cChanges.append($0) }

        a.wrapsLines = false

        #expect(!b.wrapsLines)
        #expect(!c.wrapsLines)
        // Exactly once: a re-broadcast of b's own reload would fire it again.
        #expect(cChanges == [.appearance])
    }

    @Test
    func `a theme change on one instance fires the palette category on another, not a re-comparison category`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        final class Owner {}
        let owner = Owner()
        var bChanges: [ViewerSettings.Change] = []
        b.addObserver(owner) { bChanges.append($0) }

        a.themePath = "/themes/a.xccolortheme"

        #expect(b.themePath == "/themes/a.xccolortheme")
        #expect(bChanges == [.palette])
    }

    @Test
    func `a badge scheme edit on one instance reaches another window's settings`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        a.badgeScheme = .xcode

        #expect(b.badgeScheme == .xcode)
    }

    @Test
    func `following the theme's appearance on one instance reaches another window's settings`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        a.matchesThemeAppearance = true

        #expect(b.matchesThemeAppearance)
    }

    @Test
    func `a project-scoped write on one instance does not broadcast to another instance's base value`() throws {
        let defaults = try makeDefaults()
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        a.adoptProject(project)

        a.contextLines = 9  // project-scoped write, not a base write

        #expect(a.contextLines == 9)
        #expect(b.contextLines == 3)  // b never adopted the project and never saw a base broadcast
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
