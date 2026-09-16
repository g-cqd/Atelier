import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
struct KittyConfigExtensionTests {
    @Test
    func `old JSON without new fields decodes with defaults`() throws {
        let json = """
            {"keybindingMode": "vim", "treeWidth": 25}
            """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.keybindingMode == .vim)
        #expect(config.treeWidth == 25)
        #expect(config.fileWatcherEnabled == true)
        #expect(config.autoSave.enabled == false)
        #expect(config.autoSave.interval == 30)
        #expect(config.git.enabled == true)
        #expect(config.git.refreshInterval == 10)
        #expect(config.git.decorations.showLineChanges == true)
        #expect(config.git.decorations.showTabRibbonStatus == true)
        #expect(config.git.decorations.showOpenFilesStatus == true)
        #expect(config.syntax.enabled == true)
        #expect(config.syntax.disabledLanguages.isEmpty)
        #expect(config.tabRibbon.position == .top)
        #expect(config.activityBar.show == true)
        #expect(config.activityBar.position == .left)
        #expect(config.keybindings.tabNext == "ctrl+pagedown")
        #expect(config.keybindings.toggleSidebar == "ctrl+b")
        #expect(config.editor.scrollAccelerationEnabled == true)
        #expect(config.editor.scrollAccelerationWindowMilliseconds == 120)
        #expect(config.editor.scrollAccelerationStepIntervalMilliseconds == 1)
        #expect(config.editor.scrollAccelerationMaxExtraLines == 8)
    }

    @Test
    func `status bar and editor config decode custom values`() throws {
        let json = """
            {
              "editor": {
                "arrowKeysWrapAcrossLines": false,
                "scrollMomentumBlockMilliseconds": 9,
                "scrollAccelerationEnabled": false,
                "scrollAccelerationWindowMilliseconds": 80,
                "scrollAccelerationStepIntervalMilliseconds": 3,
                "scrollAccelerationMaxExtraLines": 4
              },
              "statusBar": {
                "show": false,
                "leftItems": ["file"],
                "rightItems": ["language", "lineEnding", "git"],
                "showContextHints": false
              }
            }
            """

        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))

        #expect(config.editor.arrowKeysWrapAcrossLines == false)
        #expect(config.editor.scrollMomentumBlockMilliseconds == 9)
        #expect(config.editor.scrollAccelerationEnabled == false)
        #expect(config.editor.scrollAccelerationWindowMilliseconds == 80)
        #expect(config.editor.scrollAccelerationStepIntervalMilliseconds == 3)
        #expect(config.editor.scrollAccelerationMaxExtraLines == 4)
        #expect(config.statusBar.show == false)
        #expect(config.statusBar.leftItems == [.file])
        #expect(config.statusBar.rightItems == [.language, .lineEnding, .git])
        #expect(config.statusBar.showContextHints == false)
    }

    @Test
    func `new JSON fields roundtrip correctly`() throws {
        var config = KittyConfig()
        config.autoSave.enabled = true
        config.autoSave.interval = 60
        config.tabRibbon.position = .hidden
        config.editor.scrollMomentumBlockMilliseconds = 7
        config.editor.scrollAccelerationEnabled = false
        config.editor.scrollAccelerationWindowMilliseconds = 70
        config.editor.scrollAccelerationStepIntervalMilliseconds = 4
        config.editor.scrollAccelerationMaxExtraLines = 3
        config.activityBar.show = false
        config.git.decorations.showTabRibbonStatus = false
        config.git.decorations.maxLineDiffBytes = 2048
        config.syntax.disabledLanguages = ["python", "ruby"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(KittyConfig.self, from: data)
        #expect(decoded.autoSave.enabled == true)
        #expect(decoded.autoSave.interval == 60)
        #expect(decoded.tabRibbon.position == .hidden)
        #expect(decoded.editor.scrollMomentumBlockMilliseconds == 7)
        #expect(decoded.editor.scrollAccelerationEnabled == false)
        #expect(decoded.editor.scrollAccelerationWindowMilliseconds == 70)
        #expect(decoded.editor.scrollAccelerationStepIntervalMilliseconds == 4)
        #expect(decoded.editor.scrollAccelerationMaxExtraLines == 3)
        #expect(decoded.activityBar.show == false)
        #expect(decoded.git.decorations.showTabRibbonStatus == false)
        #expect(decoded.git.decorations.maxLineDiffBytes == 2048)
        #expect(decoded.syntax.disabledLanguages == ["python", "ruby"])
    }

    @Test
    func `theme new optional fields default to nil`() {
        let theme = KittyConfig.Theme()
        #expect(theme.tabActiveBackground == nil)
        #expect(theme.tabActiveForeground == nil)
        #expect(theme.activityBarBackground == nil)
        #expect(theme.openFilesForeground == nil)
    }
}
