import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

@MainActor
struct ProjectSettingsTests {
    // MARK: - ProjectIdentity

    @Test
    func `identity is deterministic for the same standardized root and its key is a 16-character hex string`() throws {
        let a = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        let b = ProjectIdentity(root: URL(filePath: "/repos/app/", directoryHint: .isDirectory))

        #expect(a.key == b.key)
        #expect(a.key.count == 16)
        #expect(a.key.allSatisfy { $0.isHexDigit })
        #expect(a.displayPath == b.displayPath)
    }

    @Test
    func `different roots produce different keys`() throws {
        let a = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        let b = ProjectIdentity(root: URL(filePath: "/repos/other", directoryHint: .isDirectory))
        #expect(a.key != b.key)
    }

    // MARK: - Scoped read/write and fallback

    @Test
    func `a project-scoped key falls back to the base value until the project writes its own`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        sut.contextLines = 8  // base edit, before any project is adopted

        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)
        #expect(sut.contextLines == 8)  // inherits the base value, nothing overridden yet

        sut.contextLines = 12  // now writes to the project scope
        #expect(sut.contextLines == 12)
        #expect(defaults.object(forKey: "contextLines") as? Int == 8)  // base untouched

        let reopened = ViewerSettings(defaults: defaults)
        #expect(reopened.contextLines == 8)  // a fresh, unadopted instance still sees the base
        reopened.adoptProject(project)
        #expect(reopened.contextLines == 12)  // adopting the same project picks the override back up
    }

    @Test
    func `a scoped override in one project does not affect another`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        let projectA = ProjectIdentity(root: URL(filePath: "/repos/a", directoryHint: .isDirectory))
        let projectB = ProjectIdentity(root: URL(filePath: "/repos/b", directoryHint: .isDirectory))

        sut.adoptProject(projectA)
        sut.showsChangesOnly = true

        sut.adoptProject(projectB)
        #expect(!sut.showsChangesOnly)  // project B never overrode it, base default is false

        sut.adoptProject(projectA)
        #expect(sut.showsChangesOnly)  // project A's own override is still there
    }

    @Test
    func `a non-scoped key stays global across adoption`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        sut.badgeScheme = .xcode  // app-wide by decision D11, not in the scoped set

        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)
        #expect(sut.badgeScheme == .xcode)

        sut.badgeScheme = .classic
        #expect(defaults.string(forKey: "badgeScheme") == "classic")  // wrote straight to the base key

        let other = ViewerSettings(defaults: defaults)
        #expect(other.badgeScheme == .classic)  // visible without adopting any project
    }

    @Test
    func `granularity round trips per project`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        let projectA = ProjectIdentity(root: URL(filePath: "/repos/a", directoryHint: .isDirectory))
        let projectB = ProjectIdentity(root: URL(filePath: "/repos/b", directoryHint: .isDirectory))
        sut.adoptProject(projectA)
        sut.granularity = .syntax

        sut.adoptProject(projectB)
        #expect(sut.granularity == .word)  // project B never overrode it
        sut.adoptProject(projectA)
        #expect(sut.granularity == .syntax)
        #expect(defaults.string(forKey: "intralineGranularity") == nil)  // the base was never written
    }

    // MARK: - Overrides only the user makes

    @Test
    func `switching a window from one project to another writes nothing for the second`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        let first = ProjectIdentity(root: URL(filePath: "/repos/first", directoryHint: .isDirectory))
        let second = ProjectIdentity(root: URL(filePath: "/repos/second", directoryHint: .isDirectory))
        sut.adoptProject(first)
        sut.contextLines = 10  // the first project's own override

        sut.adoptProject(second)

        #expect(sut.contextLines == 3)  // the second project inherits the base
        #expect(defaults.object(forKey: "project.\(second.key).contextLines") == nil)
        #expect(sut.projectsWithOverrides(in: .diff).map(\.key) == [first.key])
    }

    @Test
    func `re-selecting the current value writes no override`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)

        sut.diffHeuristics.whitespace = sut.diffHeuristics.whitespace

        #expect(defaults.object(forKey: "project.\(project.key).diffHeuristics") == nil)
        #expect(sut.projectsWithOverrides(in: .diff).isEmpty)
    }

    @Test
    func `restoring the appearance defaults with no theme fires no palette change`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        final class Owner {}
        let owner = Owner()
        var changes: [ViewerSettings.Change] = []
        sut.addObserver(owner) { changes.append($0) }

        sut.restoreDefaults(.appearance)

        #expect(!changes.contains(.palette))
    }

    @Test
    func `adoptProject fires Change only for keys that actually differ`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        sut.contextLines = 8  // base edit shared by every project until overridden

        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        final class Owner {}
        let owner = Owner()
        var changes: [ViewerSettings.Change] = []
        sut.addObserver(owner) { changes.append($0) }

        sut.adoptProject(project)

        #expect(changes.isEmpty)  // nothing differs: this instance already reads the base for every scoped key
    }

    @Test
    func `adoptProject fires Change for a scoped key that differs from what this instance already holds`() throws {
        let defaults = try makeDefaults()
        let writer = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        writer.adoptProject(project)
        writer.diagnosticsEnabled = true  // writes the override for `project`

        let sut = ViewerSettings(defaults: defaults)  // fresh instance, still reading the (false) base
        #expect(!sut.diagnosticsEnabled)
        final class Owner {}
        let owner = Owner()
        var changes: [ViewerSettings.Change] = []
        sut.addObserver(owner) { changes.append($0) }

        sut.adoptProject(project)

        #expect(sut.diagnosticsEnabled)
        #expect(changes == [.diagnostics])
    }

    // MARK: - Registry

    @Test
    func `a scoped write registers the project, and clearing removes it once nothing is left overridden`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)

        #expect(sut.projectsWithOverrides(in: .tools).isEmpty)

        sut.diagnosticsEnabled = true
        let overrides = sut.projectsWithOverrides(in: .tools)
        #expect(overrides.map(\.key) == [project.key])
        #expect(overrides.first?.displayPath == project.displayPath)

        sut.clearOverrides(projectKey: project.key, category: .tools)
        #expect(sut.projectsWithOverrides(in: .tools).isEmpty)
        #expect(!sut.diagnosticsEnabled)  // fell back to the base
    }

    @Test
    func `clearAllOverrides removes every category's overrides for a project`() throws {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)
        sut.diagnosticsEnabled = true
        sut.contextLines = 9
        sut.showsChangesOnly = true

        sut.clearAllOverrides(projectKey: project.key)

        #expect(sut.projectsWithOverrides(in: .tools).isEmpty)
        #expect(sut.projectsWithOverrides(in: .diff).isEmpty)
        #expect(sut.projectsWithOverrides(in: .general).isEmpty)
    }

    // MARK: - restoreDefaults under adoption

    @Test
    func
        `restoreDefaults under adoption clears the project override and falls back to the base, not the coded default`()
        throws
    {
        let defaults = try makeDefaults()
        let sut = ViewerSettings(defaults: defaults)
        sut.contextLines = 11  // base edit, made before any project is adopted

        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)
        sut.contextLines = 20  // project override

        sut.restoreDefaults(.diff)

        #expect(sut.contextLines == 11)  // falls back to the base value, not the coded default of 3
        #expect(sut.projectsWithOverrides(in: .diff).isEmpty)
    }

    @Test
    func `restoreDefaults with no project adopted still resets to the coded default`() throws {
        let sut = ViewerSettings(defaults: try makeDefaults())
        sut.contextLines = 11
        sut.restoreDefaults(.diff)
        #expect(sut.contextLines == 3)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
