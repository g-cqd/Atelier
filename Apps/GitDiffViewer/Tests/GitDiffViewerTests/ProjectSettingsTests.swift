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
        sut.granularity = .syntax  // documented as global, not in the scoped set

        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        sut.adoptProject(project)
        #expect(sut.granularity == .syntax)

        sut.granularity = .character
        #expect(defaults.string(forKey: "intralineGranularity") == "character")  // wrote straight to the base key

        let other = ViewerSettings(defaults: defaults)
        #expect(other.granularity == .character)  // visible without adopting any project
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
