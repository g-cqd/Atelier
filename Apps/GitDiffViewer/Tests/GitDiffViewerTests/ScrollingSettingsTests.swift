import DiffCore
import Foundation
import Testing

@testable import DiffComparison

/// The three scrolling settings of the code panes (book SET-09): bouncing at the edges, scrolling past the last line,
/// and scrolling to the first change when a file opens. Each is stored, reaches every window at once, and can differ
/// per project, as the other settings of the Diff tab do.
@MainActor
struct ScrollingSettingsTests {
    private let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
    private let scratchDefaults = ScratchDefaults(tag: "scrolling")

    @Test(arguments: ScrollingSetting.allCases)
    func `a scrolling setting starts at its default`(setting: ScrollingSetting) {
        let sut = ViewerSettings(defaults: scratchDefaults.defaults)

        #expect(setting.value(in: sut) == setting.appDefault)
    }

    @Test(arguments: ScrollingSetting.allCases)
    func `a scrolling setting round trips through user defaults`(setting: ScrollingSetting) {
        let defaults = scratchDefaults.defaults
        setting.set(!setting.appDefault, in: ViewerSettings(defaults: defaults))

        let reloaded = ViewerSettings(defaults: defaults)

        #expect(setting.value(in: reloaded) == !setting.appDefault)
    }

    /// The panes read the setting as they update: the window hears an appearance change, and redoes no diff.
    @Test(arguments: ScrollingSetting.allCases)
    func `a scrolling setting changed in one window reaches another at once, as an appearance change`(
        setting: ScrollingSetting
    ) {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        let window = ViewerSettings(defaults: defaults)
        var changes: [ViewerSettings.Change] = []
        window.addObserver(self.scratchDefaults) { changes.append($0) }

        setting.set(!setting.appDefault, in: settingsWindow)

        #expect(setting.value(in: window) == !setting.appDefault)
        #expect(changes == [.appearance])
    }

    @Test(arguments: ScrollingSetting.allCases)
    func `a scrolling setting edited for a project holds in its windows and nowhere else`(setting: ScrollingSetting) {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        settingsWindow.adoptProject(project)
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(project)
        let otherWindow = ViewerSettings(defaults: defaults)

        setting.set(!setting.appDefault, in: settingsWindow)

        #expect(setting.value(in: window) == !setting.appDefault)
        #expect(setting.value(in: otherWindow) == setting.appDefault)
        #expect(setting.value(in: ViewerSettings(defaults: defaults)) == setting.appDefault)
        #expect(defaults.object(forKey: "project.\(project.key).\(setting.key)") as? Bool == !setting.appDefault)
    }

    @Test
    func `restoring the diff tab's defaults resets the scrolling settings`() {
        let sut = ViewerSettings(defaults: scratchDefaults.defaults)
        for setting in ScrollingSetting.allCases { setting.set(!setting.appDefault, in: sut) }
        #expect(sut.settingsDiffCount(.diff) == ScrollingSetting.allCases.count)

        sut.restoreDefaults(.diff)

        for setting in ScrollingSetting.allCases { #expect(setting.value(in: sut) == setting.appDefault) }
    }

    @Test
    func `a project's scrolling overrides are listed under their labels`() {
        let defaults = scratchDefaults.defaults
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(project)
        for setting in ScrollingSetting.allCases { setting.set(!setting.appDefault, in: window) }

        let overrides = SettingOverride.list(for: project, over: ViewerSettings(defaults: defaults))

        #expect(
            Set(overrides.map(\.label))
                == [SettingLabel.bouncesAtEdges, SettingLabel.scrollsPastEnd, SettingLabel.scrollsToFirstChange])
        for override in overrides { #expect(override.value != override.defaultValue) }
    }
}

/// One of the scrolling settings, by its defaults key.
enum ScrollingSetting: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case bouncesAtEdges
    case scrollsPastEnd
    case scrollsToFirstChange

    var testDescription: String { rawValue }
    var key: String { rawValue }
    /// Off for the two CARD-18 and CARD-19 left off, on for the scroll to the first change (DIFF-08).
    var appDefault: Bool { self == .scrollsToFirstChange }

    @MainActor
    func value(in settings: ViewerSettings) -> Bool {
        switch self {
            case .bouncesAtEdges: settings.bouncesAtEdges
            case .scrollsPastEnd: settings.scrollsPastEnd
            case .scrollsToFirstChange: settings.scrollsToFirstChange
        }
    }

    @MainActor
    func set(_ value: Bool, in settings: ViewerSettings) {
        switch self {
            case .bouncesAtEdges: settings.bouncesAtEdges = value
            case .scrollsPastEnd: settings.scrollsPastEnd = value
            case .scrollsToFirstChange: settings.scrollsToFirstChange = value
        }
    }
}
