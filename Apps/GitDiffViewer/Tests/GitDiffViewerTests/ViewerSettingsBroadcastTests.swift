import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Two windows, and the Settings window, each hold their own ``ViewerSettings`` instance over the same
/// `UserDefaults` suite (see `ComparisonWindow`'s own doc comment on why). A base-default edit made through one of
/// them now live-propagates to every other one's unoverridden keys, in-process, without any of them having to
/// reopen -- these tests are the other half of the contract ``ProjectSettingsTests`` already covers for adopting a
/// project in the first place.
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
        // c reacts to a's one base edit exactly once: were b's own reload (itself triggered by a's broadcast) to
        // re-broadcast in turn, c would see this fire a second time.
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
