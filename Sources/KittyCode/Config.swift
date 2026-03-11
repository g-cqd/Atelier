import Foundation
import KittyCodecs

struct KittyConfig: Codable, Sendable {
    enum KeybindingMode: String, Codable, Sendable {
        case nano
        case vim
    }

    enum TabRibbonPosition: String, Codable, Sendable {
        case top
        case hidden
    }

    struct ActivityBarConfig: Codable, Sendable {
        var show: Bool = true
        var position: Position = .left
        var items: [String] = ["explorer", "openDocuments"]
        enum Position: String, Codable, Sendable { case left, right }

        init() {}

        init(from decoder: Decoder) throws {
            let d = ActivityBarConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            show = try c.decodeIfPresent(Bool.self, forKey: .show) ?? d.show
            position = try c.decodeIfPresent(Position.self, forKey: .position) ?? d.position
            items = try c.decodeIfPresent([String].self, forKey: .items) ?? d.items
        }
    }

    struct KeybindingsConfig: Codable, Sendable {
        var tabNext: String = "ctrl+pagedown"
        var tabPrev: String = "ctrl+pageup"
        var tabClose: String? = nil
        var toggleSidebar: String = "ctrl+b"

        init() {}

        init(from decoder: Decoder) throws {
            let d = KeybindingsConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tabNext = try c.decodeIfPresent(String.self, forKey: .tabNext) ?? d.tabNext
            tabPrev = try c.decodeIfPresent(String.self, forKey: .tabPrev) ?? d.tabPrev
            tabClose = try c.decodeIfPresent(String.self, forKey: .tabClose) ?? d.tabClose
            toggleSidebar = try c.decodeIfPresent(String.self, forKey: .toggleSidebar) ?? d.toggleSidebar
        }
    }

    struct Theme: Codable, Sendable {
        // GitHub Dark (foreground-focused) defaults.
        // Backgrounds are intentionally omitted so terminal default background is preserved.
        var treePanelForeground = ColorRGB(r: 0xc9, g: 0xd1, b: 0xd9)
        var treeSelectedForeground = ColorRGB(r: 0x58, g: 0xa6, b: 0xff)
        var treeDirectoryForeground = ColorRGB(r: 0x7e, g: 0xe7, b: 0x87)
        var editorForeground = ColorRGB(r: 0xc9, g: 0xd1, b: 0xd9)
        var lineNumberForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        var statusBarForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        var titleBarForeground = ColorRGB(r: 0xf0, g: 0xf6, b: 0xfc)
        var separatorForeground = ColorRGB(r: 0x30, g: 0x36, b: 0x3d)

        var keywordForeground = ColorRGB(r: 0xff, g: 0x7b, b: 0x72)
        var typeForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        var commentForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        var stringForeground = ColorRGB(r: 0xa5, g: 0xd6, b: 0xff)
        var numberForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        var attributeForeground = ColorRGB(r: 0xd2, g: 0xa8, b: 0xff)

        var gitModifiedForeground = ColorRGB(r: 0xe3, g: 0xb3, b: 0x41)
        var gitAddedForeground = ColorRGB(r: 0x3f, g: 0xb9, b: 0x50)
        var gitUntrackedForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        var gitDeletedForeground = ColorRGB(r: 0xf8, g: 0x51, b: 0x49)
        var gitConflictedForeground = ColorRGB(r: 0xff, g: 0x7b, b: 0x72)

        // Tab ribbon
        var tabActiveBackground: ColorRGB?
        var tabActiveForeground: ColorRGB?
        var tabInactiveBackground: ColorRGB?
        var tabInactiveForeground: ColorRGB?
        var tabDirtyIndicator: ColorRGB?

        // Activity bar
        var activityBarBackground: ColorRGB?
        var activityBarForeground: ColorRGB?
        var activityBarActiveForeground: ColorRGB?

        // Open files panel
        var openFilesForeground: ColorRGB?
        var openFilesSelectedForeground: ColorRGB?

        init() {}

        init(from decoder: Decoder) throws {
            let d = Theme()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            treePanelForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .treePanelForeground) ?? d.treePanelForeground
            treeSelectedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .treeSelectedForeground) ?? d.treeSelectedForeground
            treeDirectoryForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .treeDirectoryForeground) ?? d.treeDirectoryForeground
            editorForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .editorForeground) ?? d.editorForeground
            lineNumberForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .lineNumberForeground) ?? d.lineNumberForeground
            statusBarForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .statusBarForeground) ?? d.statusBarForeground
            titleBarForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .titleBarForeground) ?? d.titleBarForeground
            separatorForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .separatorForeground) ?? d.separatorForeground
            keywordForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .keywordForeground) ?? d.keywordForeground
            typeForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .typeForeground) ?? d.typeForeground
            commentForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .commentForeground) ?? d.commentForeground
            stringForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .stringForeground) ?? d.stringForeground
            numberForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .numberForeground) ?? d.numberForeground
            attributeForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .attributeForeground) ?? d.attributeForeground
            gitModifiedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .gitModifiedForeground) ?? d.gitModifiedForeground
            gitAddedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .gitAddedForeground) ?? d.gitAddedForeground
            gitUntrackedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .gitUntrackedForeground) ?? d.gitUntrackedForeground
            gitDeletedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .gitDeletedForeground) ?? d.gitDeletedForeground
            gitConflictedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .gitConflictedForeground) ?? d.gitConflictedForeground
            tabActiveBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .tabActiveBackground)
            tabActiveForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .tabActiveForeground)
            tabInactiveBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .tabInactiveBackground)
            tabInactiveForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .tabInactiveForeground)
            tabDirtyIndicator = try c.decodeIfPresent(ColorRGB.self, forKey: .tabDirtyIndicator)
            activityBarBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .activityBarBackground)
            activityBarForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .activityBarForeground)
            activityBarActiveForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .activityBarActiveForeground)
            openFilesForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .openFilesForeground)
            openFilesSelectedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .openFilesSelectedForeground)
        }
    }

    var keybindingMode: KeybindingMode = .nano
    var wrapLines = false
    var treeWidth = 30
    var useSFSymbolsInTerminal = true
    var theme = Theme()

    // File watching
    var fileWatcherEnabled: Bool = true

    // Auto-save
    var autoSave: Bool = false
    var autoSaveInterval: TimeInterval = 30

    // Git
    var showGitStatus: Bool = true
    var gitRefreshInterval: TimeInterval = 10

    // Syntax
    var syntaxHighlighting: Bool = true
    var disabledLanguages: [String] = []

    // Tab ribbon
    var tabRibbonPosition: TabRibbonPosition = .top

    // Activity bar
    var activityBar: ActivityBarConfig = .init()

    // Keybindings
    var keybindings: KeybindingsConfig = .init()

    init() {}

    init(from decoder: Decoder) throws {
        let d = KittyConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keybindingMode = try c.decodeIfPresent(KeybindingMode.self, forKey: .keybindingMode) ?? d.keybindingMode
        wrapLines = try c.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? d.wrapLines
        treeWidth = try c.decodeIfPresent(Int.self, forKey: .treeWidth) ?? d.treeWidth
        useSFSymbolsInTerminal = try c.decodeIfPresent(Bool.self, forKey: .useSFSymbolsInTerminal) ?? d.useSFSymbolsInTerminal
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? d.theme
        fileWatcherEnabled = try c.decodeIfPresent(Bool.self, forKey: .fileWatcherEnabled) ?? d.fileWatcherEnabled
        autoSave = try c.decodeIfPresent(Bool.self, forKey: .autoSave) ?? d.autoSave
        autoSaveInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .autoSaveInterval) ?? d.autoSaveInterval
        showGitStatus = try c.decodeIfPresent(Bool.self, forKey: .showGitStatus) ?? d.showGitStatus
        gitRefreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .gitRefreshInterval) ?? d.gitRefreshInterval
        syntaxHighlighting = try c.decodeIfPresent(Bool.self, forKey: .syntaxHighlighting) ?? d.syntaxHighlighting
        disabledLanguages = try c.decodeIfPresent([String].self, forKey: .disabledLanguages) ?? d.disabledLanguages
        tabRibbonPosition = try c.decodeIfPresent(TabRibbonPosition.self, forKey: .tabRibbonPosition) ?? d.tabRibbonPosition
        activityBar = try c.decodeIfPresent(ActivityBarConfig.self, forKey: .activityBar) ?? d.activityBar
        keybindings = try c.decodeIfPresent(KeybindingsConfig.self, forKey: .keybindings) ?? d.keybindings
    }

    static func load() -> KittyConfig {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".kittycode.json")
        guard let data = try? Data(contentsOf: configURL) else {
            return KittyConfig()
        }
        do {
            return try JSONDecoder().decode(KittyConfig.self, from: data)
        } catch {
            FileHandle.standardError.write(
                Data("Warning: failed to parse ~/.kittycode.json: \(error). Using defaults.\n".utf8)
            )
            return KittyConfig()
        }
    }
}
