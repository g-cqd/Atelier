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
@Suite(.mainActorLane)
struct ViewerSettingsBroadcastTests {
    private let scratchDefaults = ScratchDefaults(tag: "broadcast")

    @Test
    func `a base edit on one instance reflects on another sharing the same defaults`() throws {
        let defaults = scratchDefaults.defaults
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        a.wrapsLines = false

        #expect(!b.wrapsLines)
    }

    @Test
    func `a base edit does not override a key the receiving instance's own project already overrides`() throws {
        let defaults = scratchDefaults.defaults
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
        let defaults = scratchDefaults.defaults
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
        let defaults = scratchDefaults.defaults
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
        let defaults = scratchDefaults.defaults
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        a.badgeScheme = .xcode

        #expect(b.badgeScheme == .xcode)
    }

    @Test
    func `following the theme's appearance on one instance reaches another window's settings`() throws {
        let defaults = scratchDefaults.defaults
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)

        a.matchesThemeAppearance = true

        #expect(b.matchesThemeAppearance)
    }

    @Test
    func `a base edit broadcast to a window on a project writes no override and registers no project`() throws {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        let window = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        window.adoptProject(project)

        settingsWindow.contextLines = 5

        #expect(window.contextLines == 5)
        #expect(defaults.object(forKey: "project.\(project.key).contextLines") == nil)
        #expect(defaults.dictionary(forKey: "projectRegistry") == nil)
    }

    @Test
    func `base edits keep reaching a window whose project overrides nothing`() throws {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory)))

        settingsWindow.contextLines = 5
        settingsWindow.contextLines = 7

        #expect(window.contextLines == 7)
    }

    @Test
    func `overridden in N projects counts only the projects the user edited`() throws {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        let edited = ProjectIdentity(root: URL(filePath: "/repos/edited", directoryHint: .isDirectory))
        let untouched = ProjectIdentity(root: URL(filePath: "/repos/untouched", directoryHint: .isDirectory))
        let editedWindow = ViewerSettings(defaults: defaults)
        editedWindow.adoptProject(edited)
        let untouchedWindow = ViewerSettings(defaults: defaults)
        untouchedWindow.adoptProject(untouched)
        editedWindow.contextLines = 9  // the one override the user made

        settingsWindow.contextLines = 5
        settingsWindow.diagnosticsEnabled = true
        settingsWindow.showsChangesOnly = true

        #expect(settingsWindow.projectsWithOverrides(in: .diff).map(\.key) == [edited.key])
        #expect(settingsWindow.projectsWithOverrides(in: .tools).isEmpty)
        #expect(settingsWindow.projectsWithOverrides(in: .general).isEmpty)
    }

    @Test
    func `a project's own value edited on one instance reaches another window on that project`() throws {
        let defaults = scratchDefaults.defaults
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        let settingsWindow = ViewerSettings(defaults: defaults)
        settingsWindow.adoptProject(project)
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(project)

        settingsWindow.contextLines = 9

        #expect(window.contextLines == 9)
    }

    @Test
    func `clearing a project's override falls a window on that project back to the default`() throws {
        let defaults = scratchDefaults.defaults
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(project)
        window.contextLines = 9
        let settingsWindow = ViewerSettings(defaults: defaults)

        settingsWindow.clearOverride("contextLines", projectKey: project.key)

        #expect(window.contextLines == 3)
    }

    @Test
    func `hiding the sidebar in one window leaves another window's sidebar alone`() throws {
        let defaults = scratchDefaults.defaults
        let window = ViewerSettings(defaults: defaults)
        let other = ViewerSettings(defaults: defaults)

        window.sidebarVisibility = .detailOnly

        #expect(other.sidebarVisibility == .all)
    }

    @Test
    func `a new window opens with the sidebar as the last window left it`() throws {
        let defaults = scratchDefaults.defaults
        ViewerSettings(defaults: defaults).sidebarVisibility = .detailOnly

        #expect(ViewerSettings(defaults: defaults).sidebarVisibility == .detailOnly)
    }

    @Test
    func `a project-scoped write on one instance does not broadcast to another instance's base value`() throws {
        let defaults = scratchDefaults.defaults
        let a = ViewerSettings(defaults: defaults)
        let b = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        a.adoptProject(project)

        a.contextLines = 9  // project-scoped write, not a base write

        #expect(a.contextLines == 9)
        #expect(b.contextLines == 3)  // b never adopted the project and never saw a base broadcast
    }
}
