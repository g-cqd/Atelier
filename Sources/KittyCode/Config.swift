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

    enum TabPersistence: String, Codable, Sendable {
        case pinned
        case preview
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
        enum ShortcutModifier: String, Codable, Sendable {
            case command
            case control
            case both
        }

        var tabNext: String = "ctrl+pagedown"
        var tabPrev: String = "ctrl+pageup"
        var tabClose: String? = nil
        var toggleSidebar: String = "ctrl+b"
        var clipboardModifier: ShortcutModifier = .command
        var historyModifier: ShortcutModifier = .command

        init() {}

        init(from decoder: Decoder) throws {
            let d = KeybindingsConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tabNext = try c.decodeIfPresent(String.self, forKey: .tabNext) ?? d.tabNext
            tabPrev = try c.decodeIfPresent(String.self, forKey: .tabPrev) ?? d.tabPrev
            tabClose = try c.decodeIfPresent(String.self, forKey: .tabClose) ?? d.tabClose
            toggleSidebar = try c.decodeIfPresent(String.self, forKey: .toggleSidebar) ?? d.toggleSidebar
            clipboardModifier = try c.decodeIfPresent(ShortcutModifier.self, forKey: .clipboardModifier) ?? d.clipboardModifier
            historyModifier = try c.decodeIfPresent(ShortcutModifier.self, forKey: .historyModifier) ?? d.historyModifier
        }
    }

    struct EditorConfig: Codable, Sendable {
        var highlightCurrentLine: Bool = false
        var arrowKeysWrapAcrossLines: Bool = true
        var wrapLines: Bool = false
        var tabSize: Int = 4
        var undoCoalescingEnabled: Bool = true
        var undoCoalescingMilliseconds: Int = 400
        var scrollLines: Int? = nil
        var scrollHorizontalStep: Int = 4
        var scrollMomentumBlockMilliseconds: Int = 5
        var scrollAccelerationEnabled: Bool = true
        var scrollAccelerationWindowMilliseconds: Int = 120
        var scrollAccelerationStepIntervalMilliseconds: Int = 1
        var scrollAccelerationMaxExtraLines: Int = 8

        init() {}

        init(from decoder: Decoder) throws {
            let d = EditorConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            highlightCurrentLine = try c.decodeIfPresent(Bool.self, forKey: .highlightCurrentLine) ?? d.highlightCurrentLine
            arrowKeysWrapAcrossLines = try c.decodeIfPresent(Bool.self, forKey: .arrowKeysWrapAcrossLines) ?? d.arrowKeysWrapAcrossLines
            wrapLines = try c.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? d.wrapLines
            tabSize = try c.decodeIfPresent(Int.self, forKey: .tabSize) ?? d.tabSize
            undoCoalescingEnabled = try c.decodeIfPresent(Bool.self, forKey: .undoCoalescingEnabled) ?? d.undoCoalescingEnabled
            undoCoalescingMilliseconds = try c.decodeIfPresent(Int.self, forKey: .undoCoalescingMilliseconds) ?? d.undoCoalescingMilliseconds
            scrollLines = try c.decodeIfPresent(Int.self, forKey: .scrollLines)
            scrollHorizontalStep = try c.decodeIfPresent(Int.self, forKey: .scrollHorizontalStep) ?? d.scrollHorizontalStep
            scrollMomentumBlockMilliseconds = try c.decodeIfPresent(Int.self, forKey: .scrollMomentumBlockMilliseconds) ?? d.scrollMomentumBlockMilliseconds
            scrollAccelerationEnabled = try c.decodeIfPresent(Bool.self, forKey: .scrollAccelerationEnabled) ?? d.scrollAccelerationEnabled
            scrollAccelerationWindowMilliseconds = try c.decodeIfPresent(Int.self, forKey: .scrollAccelerationWindowMilliseconds) ?? d.scrollAccelerationWindowMilliseconds
            scrollAccelerationStepIntervalMilliseconds = try c.decodeIfPresent(Int.self, forKey: .scrollAccelerationStepIntervalMilliseconds) ?? d.scrollAccelerationStepIntervalMilliseconds
            scrollAccelerationMaxExtraLines = try c.decodeIfPresent(Int.self, forKey: .scrollAccelerationMaxExtraLines) ?? d.scrollAccelerationMaxExtraLines
        }
    }

    struct StatusBarConfig: Codable, Sendable {
        enum Item: String, Codable, Sendable {
            case path
            case file
            case status
            case language
            case size
            case lineEnding
            case git
            case position
            case visibility
        }

        var show: Bool = true
        var leftItems: [Item] = [.path, .status]
        var rightItems: [Item] = [.visibility, .language, .size, .lineEnding, .git, .position]
        var showContextHints: Bool = true

        init() {}

        init(from decoder: Decoder) throws {
            let d = StatusBarConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            show = try c.decodeIfPresent(Bool.self, forKey: .show) ?? d.show
            leftItems = try c.decodeIfPresent([Item].self, forKey: .leftItems) ?? d.leftItems
            rightItems = try c.decodeIfPresent([Item].self, forKey: .rightItems) ?? d.rightItems
            showContextHints = try c.decodeIfPresent(Bool.self, forKey: .showContextHints) ?? d.showContextHints
        }
    }

    struct GitDecorationsConfig: Codable, Sendable {
        var showLineChanges: Bool = true
        var showLineBackgrounds: Bool = false
        var showLineForegrounds: Bool = false
        var showTabRibbonStatus: Bool = true
        var showOpenFilesStatus: Bool = true
        var lineChangeDebounceMilliseconds: UInt64 = 150
        var maxLineDiffBytes: Int = 1_000_000

        init() {}

        init(from decoder: Decoder) throws {
            let d = GitDecorationsConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showLineChanges = try c.decodeIfPresent(Bool.self, forKey: .showLineChanges) ?? d.showLineChanges
            showLineBackgrounds = try c.decodeIfPresent(Bool.self, forKey: .showLineBackgrounds) ?? d.showLineBackgrounds
            showLineForegrounds = try c.decodeIfPresent(Bool.self, forKey: .showLineForegrounds) ?? d.showLineForegrounds
            showTabRibbonStatus = try c.decodeIfPresent(Bool.self, forKey: .showTabRibbonStatus) ?? d.showTabRibbonStatus
            showOpenFilesStatus = try c.decodeIfPresent(Bool.self, forKey: .showOpenFilesStatus) ?? d.showOpenFilesStatus
            lineChangeDebounceMilliseconds = try c.decodeIfPresent(UInt64.self, forKey: .lineChangeDebounceMilliseconds) ?? d.lineChangeDebounceMilliseconds
            maxLineDiffBytes = try c.decodeIfPresent(Int.self, forKey: .maxLineDiffBytes) ?? d.maxLineDiffBytes
        }
    }

    struct GitConfig: Codable, Sendable {
        var enabled: Bool = true
        var refreshInterval: TimeInterval = 10
        var decorations: GitDecorationsConfig = .init()

        init() {}

        init(from decoder: Decoder) throws {
            let d = GitConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? d.refreshInterval
            decorations = try c.decodeIfPresent(GitDecorationsConfig.self, forKey: .decorations) ?? d.decorations
        }
    }

    struct TabRibbonConfig: Codable, Sendable {
        var position: TabRibbonPosition = .top
        var persistence: TabPersistence = .pinned

        init() {}

        init(from decoder: Decoder) throws {
            let d = TabRibbonConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            position = try c.decodeIfPresent(TabRibbonPosition.self, forKey: .position) ?? d.position
            persistence = try c.decodeIfPresent(TabPersistence.self, forKey: .persistence) ?? d.persistence
        }
    }

    struct SyntaxConfig: Codable, Sendable {
        var enabled: Bool = true
        var disabledLanguages: [String] = []

        init() {}

        init(from decoder: Decoder) throws {
            let d = SyntaxConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            disabledLanguages = try c.decodeIfPresent([String].self, forKey: .disabledLanguages) ?? d.disabledLanguages
        }
    }

    struct AutoSaveConfig: Codable, Sendable {
        var enabled: Bool = false
        var interval: TimeInterval = 30

        init() {}

        init(from decoder: Decoder) throws {
            let d = AutoSaveConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? d.interval
        }
    }

    enum WhitespaceVisibility: String, Codable, Sendable {
        /// Show no whitespace in the selection.
        case none
        /// Show only leading indentation (spaces and tabs).
        case indentation
        /// Show indentation + mid-line/trailing spaces.
        case all
        /// Show indentation + spaces + line-break markers.
        case boundary
    }

    struct WhitespaceConfig: Codable, Sendable {
        var showIndentation: Bool = false
        var showSpaces: Bool = false
        var showLineBreaks: Bool = false
        var showUnexpected: Bool = true
        var selectionWhitespace: WhitespaceVisibility = .none

        init() {}

        init(from decoder: Decoder) throws {
            let d = WhitespaceConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showIndentation = try c.decodeIfPresent(Bool.self, forKey: .showIndentation) ?? d.showIndentation
            showSpaces = try c.decodeIfPresent(Bool.self, forKey: .showSpaces) ?? d.showSpaces
            showLineBreaks = try c.decodeIfPresent(Bool.self, forKey: .showLineBreaks) ?? d.showLineBreaks
            showUnexpected = try c.decodeIfPresent(Bool.self, forKey: .showUnexpected) ?? d.showUnexpected
            selectionWhitespace = try c.decodeIfPresent(WhitespaceVisibility.self, forKey: .selectionWhitespace) ?? d.selectionWhitespace
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

        // Editor line highlighting
        var cursorLineBackground: ColorRGB?
        var cursorLineForeground: ColorRGB?

        // Selection highlighting
        var selectionBackground: ColorRGB?
        var selectionForeground: ColorRGB?

        // Whitespace rendering
        var whitespaceIndentationForeground: ColorRGB?
        var whitespaceSpaceForeground: ColorRGB?
        var whitespaceLineBreakForeground: ColorRGB?
        var whitespaceUnexpectedForeground: ColorRGB?

        // Git line highlighting
        var gitModifiedLineBackground: ColorOverlayConfig?
        var gitModifiedLineForeground: ColorOverlayConfig?
        var gitAddedLineBackground: ColorOverlayConfig?
        var gitAddedLineForeground: ColorOverlayConfig?
        var gitUntrackedLineBackground: ColorOverlayConfig?
        var gitUntrackedLineForeground: ColorOverlayConfig?
        var gitDeletedLineBackground: ColorOverlayConfig?
        var gitDeletedLineForeground: ColorOverlayConfig?
        var gitConflictedLineBackground: ColorOverlayConfig?
        var gitConflictedLineForeground: ColorOverlayConfig?

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
            cursorLineBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .cursorLineBackground)
            cursorLineForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .cursorLineForeground)
            selectionBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .selectionBackground)
            selectionForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .selectionForeground)
            whitespaceIndentationForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .whitespaceIndentationForeground)
            whitespaceSpaceForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .whitespaceSpaceForeground)
            whitespaceLineBreakForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .whitespaceLineBreakForeground)
            whitespaceUnexpectedForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .whitespaceUnexpectedForeground)
            gitModifiedLineBackground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitModifiedLineBackground)
            gitModifiedLineForeground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitModifiedLineForeground)
            gitAddedLineBackground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitAddedLineBackground)
            gitAddedLineForeground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitAddedLineForeground)
            gitUntrackedLineBackground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitUntrackedLineBackground)
            gitUntrackedLineForeground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitUntrackedLineForeground)
            gitDeletedLineBackground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitDeletedLineBackground)
            gitDeletedLineForeground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitDeletedLineForeground)
            gitConflictedLineBackground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitConflictedLineBackground)
            gitConflictedLineForeground = try c.decodeIfPresent(ColorOverlayConfig.self, forKey: .gitConflictedLineForeground)
        }
    }

    var keybindingMode: KeybindingMode = .nano
    var treeWidth: Int = 30
    var useSFSymbolsInTerminal: Bool = true
    var fileWatcherEnabled: Bool = true
    var editor: EditorConfig = .init()
    var theme: Theme = .init()
    var statusBar: StatusBarConfig = .init()
    var git: GitConfig = .init()
    var syntax: SyntaxConfig = .init()
    var tabRibbon: TabRibbonConfig = .init()
    var autoSave: AutoSaveConfig = .init()
    var activityBar: ActivityBarConfig = .init()
    var keybindings: KeybindingsConfig = .init()
    var whitespace: WhitespaceConfig = .init()

    init() {}

    init(from decoder: Decoder) throws {
        let d = KittyConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keybindingMode = try c.decodeIfPresent(KeybindingMode.self, forKey: .keybindingMode) ?? d.keybindingMode
        treeWidth = try c.decodeIfPresent(Int.self, forKey: .treeWidth) ?? d.treeWidth
        useSFSymbolsInTerminal = try c.decodeIfPresent(Bool.self, forKey: .useSFSymbolsInTerminal) ?? d.useSFSymbolsInTerminal
        fileWatcherEnabled = try c.decodeIfPresent(Bool.self, forKey: .fileWatcherEnabled) ?? d.fileWatcherEnabled
        editor = try c.decodeIfPresent(EditorConfig.self, forKey: .editor) ?? d.editor
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? d.theme
        statusBar = try c.decodeIfPresent(StatusBarConfig.self, forKey: .statusBar) ?? d.statusBar
        git = try c.decodeIfPresent(GitConfig.self, forKey: .git) ?? d.git
        syntax = try c.decodeIfPresent(SyntaxConfig.self, forKey: .syntax) ?? d.syntax
        tabRibbon = try c.decodeIfPresent(TabRibbonConfig.self, forKey: .tabRibbon) ?? d.tabRibbon
        autoSave = try c.decodeIfPresent(AutoSaveConfig.self, forKey: .autoSave) ?? d.autoSave
        activityBar = try c.decodeIfPresent(ActivityBarConfig.self, forKey: .activityBar) ?? d.activityBar
        keybindings = try c.decodeIfPresent(KeybindingsConfig.self, forKey: .keybindings) ?? d.keybindings
        whitespace = try c.decodeIfPresent(WhitespaceConfig.self, forKey: .whitespace) ?? d.whitespace
    }

    static let configURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".kittycode.json")

    static func load() -> KittyConfig {
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

extension KittyConfig.Theme {
    func resolvedStyle(_ color: ColorRGB?, bold: Bool = false) -> Style? {
        guard let color else { return nil }
        return Style(fg: color.color, bold: bold)
    }
}
