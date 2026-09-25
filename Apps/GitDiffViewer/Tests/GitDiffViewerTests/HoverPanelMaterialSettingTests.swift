import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffRendering

/// The hover panel's material (book HOVER-08): Liquid Glass unless the user picks the popover material, stored,
/// reaching every window at once, and overridable per project as the other hover setting is.
@MainActor
@Suite(.mainActorLane)
struct HoverPanelMaterialSettingTests {
    private let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
    private let scratchDefaults = ScratchDefaults(tag: "hoverMaterial")

    @Test
    func `the hover panel is made of liquid glass by default`() {
        let sut = ViewerSettings(defaults: scratchDefaults.defaults)

        #expect(sut.hoverPanelMaterial == .liquidGlass)
    }

    @Test
    func `the popover material round trips through user defaults`() {
        let defaults = scratchDefaults.defaults
        ViewerSettings(defaults: defaults).hoverPanelMaterial = .popover

        #expect(ViewerSettings(defaults: defaults).hoverPanelMaterial == .popover)
    }

    /// The next panel reads the setting as its document resolves: the window hears an appearance change only.
    @Test
    func `the material changed in one window reaches another at once, as an appearance change`() {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        let window = ViewerSettings(defaults: defaults)
        var changes: [ViewerSettings.Change] = []
        window.addObserver(scratchDefaults) { changes.append($0) }

        settingsWindow.hoverPanelMaterial = .popover

        #expect(window.hoverPanelMaterial == .popover)
        #expect(changes == [.appearance])
    }

    @Test
    func `the material edited for a project holds in its windows and nowhere else`() {
        let defaults = scratchDefaults.defaults
        let settingsWindow = ViewerSettings(defaults: defaults)
        settingsWindow.adoptProject(project)
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(project)
        let otherWindow = ViewerSettings(defaults: defaults)

        settingsWindow.hoverPanelMaterial = .popover

        #expect(window.hoverPanelMaterial == .popover)
        #expect(otherWindow.hoverPanelMaterial == .liquidGlass)
        #expect(defaults.string(forKey: "project.\(project.key).hoverPanelMaterial") == "popover")
        #expect(ViewerSettings.isProjectScoped(\ViewerSettings.hoverPanelMaterial))
    }

    @Test
    func `restoring the tools tab's defaults brings the glass back`() {
        let sut = ViewerSettings(defaults: scratchDefaults.defaults)
        sut.hoverPanelMaterial = .popover
        #expect(sut.settingsDiffCount(.tools) == 1)

        sut.restoreDefaults(.tools)

        #expect(sut.hoverPanelMaterial == .liquidGlass)
    }

    @Test
    func `a project's material override is listed under its label`() {
        let defaults = scratchDefaults.defaults
        let window = ViewerSettings(defaults: defaults)
        window.adoptProject(project)
        window.hoverPanelMaterial = .popover

        let overrides = SettingOverride.list(for: project, over: ViewerSettings(defaults: defaults))

        let override = overrides.first { $0.label == SettingLabel.hoverPanelMaterial }
        #expect(override?.value == "Popover")
        #expect(override?.defaultValue == "Liquid Glass")
    }
}
