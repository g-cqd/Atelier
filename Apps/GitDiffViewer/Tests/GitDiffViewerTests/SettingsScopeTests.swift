import DiffCore
import Foundation
import Testing

@testable import DiffComparison

/// ``SettingsScope``: what the Settings window edits, the known projects it lists, and what resetting or removing
/// one does (book SET-03, decision D11).
@MainActor
struct SettingsScopeTests {
    private let app = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
    private let other = ProjectIdentity(root: URL(filePath: "/repos/other", directoryHint: .isDirectory))

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.scope.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func `a project a window opened is listed as using the defaults`() throws {
        let defaults = try makeDefaults()
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(app)

        let sut = SettingsScope(appSettings: ViewerSettings(defaults: defaults))

        #expect(sut.entries == [SettingsScope.Entry(project: app, overrides: [])])
    }

    @Test
    func `a project a window opens while Settings is open joins the list`() throws {
        let defaults = try makeDefaults()
        let sut = SettingsScope(appSettings: ViewerSettings(defaults: defaults))
        let window = ViewerSettings(defaults: defaults)

        window.adoptProject(app)

        #expect(sut.entries.map(\.project) == [app])
    }

    @Test
    func `editing a project changes that project's value and not the default`() throws {
        let defaults = try makeDefaults()
        let appSettings = ViewerSettings(defaults: defaults)
        let sut = SettingsScope(appSettings: appSettings)

        sut.select(.project(app))
        sut.edited.contextLines = 9

        #expect(appSettings.contextLines == 3)
        #expect(defaults.object(forKey: "project.\(app.key).contextLines") as? Int == 9)
    }

    @Test
    func `the defaults scope edits the app's own instance`() throws {
        let appSettings = ViewerSettings(defaults: try makeDefaults())
        let sut = SettingsScope(appSettings: appSettings)
        sut.select(.project(app))

        sut.select(.defaults)

        #expect(sut.edited === appSettings)
    }

    @Test
    func `the list shows what a project overrides, with its value and its default`() throws {
        let defaults = try makeDefaults()
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(app)
        window.granularity = .syntax

        let sut = SettingsScope(appSettings: ViewerSettings(defaults: defaults))

        #expect(
            sut.entries.first?.overrides == [
                SettingOverride(
                    key: "intralineGranularity", label: SettingLabel.granularity, value: "Syntax",
                    defaultValue: "Words")
            ])
    }

    @Test
    func `resetting one override keeps the project's others`() throws {
        let defaults = try makeDefaults()
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(app)
        window.granularity = .syntax
        window.contextLines = 9
        let sut = SettingsScope(appSettings: ViewerSettings(defaults: defaults))

        sut.resetOverride("intralineGranularity", of: app)

        #expect(sut.entries.first?.overrides.map(\.key) == ["contextLines"])
        #expect(window.granularity == .word)
    }

    @Test
    func `resetting a project drops every override and keeps it listed`() throws {
        let defaults = try makeDefaults()
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(app)
        window.granularity = .syntax
        window.diagnosticsEnabled = true
        let sut = SettingsScope(appSettings: ViewerSettings(defaults: defaults))

        sut.resetOverrides(of: app)

        #expect(sut.entries == [SettingsScope.Entry(project: app, overrides: [])])
        #expect(!window.diagnosticsEnabled)
    }

    @Test
    func `removing a project drops it from the list and sends the tabs back to the defaults`() throws {
        let defaults = try makeDefaults()
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(app)
        window.adoptProject(other)
        let sut = SettingsScope(appSettings: ViewerSettings(defaults: defaults))
        sut.select(.project(app))
        sut.edited.contextLines = 9

        sut.remove(app)

        #expect(sut.entries.map(\.project) == [other])
        #expect(sut.selection == .defaults)
        #expect(defaults.object(forKey: "project.\(app.key).contextLines") == nil)
    }
}
