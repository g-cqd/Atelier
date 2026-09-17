// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable file_length function_body_length type_body_length
public import Foundation
public import KittyCodecs
import KittyTerminal

/// Errors surfaced while loading or decoding the user's `~/.kittycode.json`.
///
/// `load(from:)` always falls back to a default config, but these typed cases
/// let internal callers distinguish "no file" from "bad file" (currently used
/// by the logger to choose log level).
public enum ConfigError: Error {
    case fileUnreadable(URL, any Error)
    case decodeFailed(URL, any Error)
}

public struct KittyConfig: Codable, Sendable {
    public enum KeybindingMode: String, Codable, Sendable {
        case nano
        case vim
        case kittycode
    }

    public enum TabRibbonPosition: String, Codable, Sendable {
        case top
        case hidden
    }

    public enum TabPersistence: String, Codable, Sendable {
        case pinned
        case preview
    }

    public struct ActivityBarConfig: Codable, Sendable {
        public var show: Bool = true
        public var position: Position = .left
        public var items: [String] = ["explorer", "openDocuments", "search"]
        public enum Position: String, Codable, Sendable { case left, right }

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = ActivityBarConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            show = try c.decodeIfPresent(Bool.self, forKey: .show) ?? d.show
            position = try c.decodeIfPresent(Position.self, forKey: .position) ?? d.position
            items = try c.decodeIfPresent([String].self, forKey: .items) ?? d.items
        }
    }

    public struct KeybindingsConfig: Codable, Sendable {
        public enum ShortcutModifier: String, Codable, Sendable {
            case command
            case control
            case both
        }

        public var tabNext: String = "ctrl+pagedown"
        public var tabPrev: String = "ctrl+pageup"
        public var tabClose: String? = nil
        public var toggleSidebar: String = "ctrl+b"
        public var clipboardModifier: ShortcutModifier = .command
        public var historyModifier: ShortcutModifier = .command
        public var overrides: [String: [String]] = [:]
        public var sequenceTimeoutMilliseconds: Int = 500

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = KeybindingsConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tabNext = try c.decodeIfPresent(String.self, forKey: .tabNext) ?? d.tabNext
            tabPrev = try c.decodeIfPresent(String.self, forKey: .tabPrev) ?? d.tabPrev
            tabClose = try c.decodeIfPresent(String.self, forKey: .tabClose) ?? d.tabClose
            toggleSidebar =
                try c.decodeIfPresent(String.self, forKey: .toggleSidebar) ?? d.toggleSidebar
            clipboardModifier =
                try c.decodeIfPresent(ShortcutModifier.self, forKey: .clipboardModifier)
                ?? d.clipboardModifier
            historyModifier =
                try c.decodeIfPresent(ShortcutModifier.self, forKey: .historyModifier)
                ?? d.historyModifier
            overrides =
                try c.decodeIfPresent([String: [String]].self, forKey: .overrides) ?? d.overrides
            sequenceTimeoutMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .sequenceTimeoutMilliseconds)
                ?? d.sequenceTimeoutMilliseconds
        }
    }

    public struct EditorConfig: Codable, Sendable {
        public var highlightCurrentLine: Bool = false
        public var arrowKeysWrapAcrossLines: Bool = true
        public var wrapLines: Bool = false
        public var tabSize: Int = 4
        public var undoCoalescingEnabled: Bool = true
        public var undoCoalescingMilliseconds: Int = 400
        public var scrollLines: Int? = nil
        public var scrollHorizontalStep: Int = 4
        public var scrollMomentumBlockMilliseconds: Int = 5
        public var scrollAccelerationEnabled: Bool = true
        public var scrollAccelerationWindowMilliseconds: Int = 120
        public var scrollAccelerationStepIntervalMilliseconds: Int = 1
        public var scrollAccelerationMaxExtraLines: Int = 8
        public var keyRepeatIntervalMilliseconds: Int = 40
        public var maxUndoSteps: Int = 200
        public var maxTreeUndoSteps: Int = 50
        public var snapshotMaxFiles: Int = 500
        public var snapshotMaxBytes: Int = 10_000_000

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = EditorConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            highlightCurrentLine =
                try c.decodeIfPresent(Bool.self, forKey: .highlightCurrentLine)
                ?? d.highlightCurrentLine
            arrowKeysWrapAcrossLines =
                try c.decodeIfPresent(Bool.self, forKey: .arrowKeysWrapAcrossLines)
                ?? d.arrowKeysWrapAcrossLines
            wrapLines = try c.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? d.wrapLines
            tabSize = try c.decodeIfPresent(Int.self, forKey: .tabSize) ?? d.tabSize
            undoCoalescingEnabled =
                try c.decodeIfPresent(Bool.self, forKey: .undoCoalescingEnabled)
                ?? d.undoCoalescingEnabled
            undoCoalescingMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .undoCoalescingMilliseconds)
                ?? d.undoCoalescingMilliseconds
            scrollLines = try c.decodeIfPresent(Int.self, forKey: .scrollLines)
            scrollHorizontalStep =
                try c.decodeIfPresent(Int.self, forKey: .scrollHorizontalStep)
                ?? d.scrollHorizontalStep
            scrollMomentumBlockMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .scrollMomentumBlockMilliseconds)
                ?? d.scrollMomentumBlockMilliseconds
            scrollAccelerationEnabled =
                try c.decodeIfPresent(Bool.self, forKey: .scrollAccelerationEnabled)
                ?? d.scrollAccelerationEnabled
            scrollAccelerationWindowMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .scrollAccelerationWindowMilliseconds)
                ?? d.scrollAccelerationWindowMilliseconds
            scrollAccelerationStepIntervalMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .scrollAccelerationStepIntervalMilliseconds)
                ?? d.scrollAccelerationStepIntervalMilliseconds
            scrollAccelerationMaxExtraLines =
                try c.decodeIfPresent(Int.self, forKey: .scrollAccelerationMaxExtraLines)
                ?? d.scrollAccelerationMaxExtraLines
            keyRepeatIntervalMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .keyRepeatIntervalMilliseconds)
                ?? d.keyRepeatIntervalMilliseconds
            maxUndoSteps =
                try c.decodeIfPresent(Int.self, forKey: .maxUndoSteps) ?? d.maxUndoSteps
            maxTreeUndoSteps =
                try c.decodeIfPresent(Int.self, forKey: .maxTreeUndoSteps) ?? d.maxTreeUndoSteps
            snapshotMaxFiles =
                try c.decodeIfPresent(Int.self, forKey: .snapshotMaxFiles) ?? d.snapshotMaxFiles
            snapshotMaxBytes =
                try c.decodeIfPresent(Int.self, forKey: .snapshotMaxBytes) ?? d.snapshotMaxBytes
        }
    }

    public struct StatusBarConfig: Codable, Sendable {
        public enum Item: String, Codable, Sendable {
            case path
            case file
            case status
            case language
            case size
            case lineEnding
            case git
            case position
            case visibility
            case undo
        }

        public var show: Bool = true
        public var leftItems: [Item] = [.path, .status]
        public var rightItems: [Item] = [.visibility, .language, .size, .lineEnding, .git, .position]
        public var showContextHints: Bool = true

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = StatusBarConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            show = try c.decodeIfPresent(Bool.self, forKey: .show) ?? d.show
            leftItems = try c.decodeIfPresent([Item].self, forKey: .leftItems) ?? d.leftItems
            rightItems = try c.decodeIfPresent([Item].self, forKey: .rightItems) ?? d.rightItems
            showContextHints =
                try c.decodeIfPresent(Bool.self, forKey: .showContextHints) ?? d.showContextHints
        }
    }

    public struct GitDecorationsConfig: Codable, Sendable {
        public var showLineChanges: Bool = true
        public var showLineBackgrounds: Bool = false
        public var showLineForegrounds: Bool = false
        public var showTabRibbonStatus: Bool = true
        public var showOpenFilesStatus: Bool = true
        public var lineChangeDebounceMilliseconds: UInt64 = 150
        public var maxLineDiffBytes: Int = 1_000_000

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = GitDecorationsConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showLineChanges =
                try c.decodeIfPresent(Bool.self, forKey: .showLineChanges) ?? d.showLineChanges
            showLineBackgrounds =
                try c.decodeIfPresent(Bool.self, forKey: .showLineBackgrounds)
                ?? d.showLineBackgrounds
            showLineForegrounds =
                try c.decodeIfPresent(Bool.self, forKey: .showLineForegrounds)
                ?? d.showLineForegrounds
            showTabRibbonStatus =
                try c.decodeIfPresent(Bool.self, forKey: .showTabRibbonStatus)
                ?? d.showTabRibbonStatus
            showOpenFilesStatus =
                try c.decodeIfPresent(Bool.self, forKey: .showOpenFilesStatus)
                ?? d.showOpenFilesStatus
            lineChangeDebounceMilliseconds =
                try c.decodeIfPresent(UInt64.self, forKey: .lineChangeDebounceMilliseconds)
                ?? d.lineChangeDebounceMilliseconds
            maxLineDiffBytes =
                try c.decodeIfPresent(Int.self, forKey: .maxLineDiffBytes) ?? d.maxLineDiffBytes
        }
    }

    public struct GitConfig: Codable, Sendable {
        public var enabled: Bool = true
        public var refreshInterval: TimeInterval = 10
        public var decorations: GitDecorationsConfig = .init()

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = GitConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            refreshInterval =
                try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval)
                ?? d.refreshInterval
            decorations =
                try c.decodeIfPresent(GitDecorationsConfig.self, forKey: .decorations)
                ?? d.decorations
        }
    }

    public struct TabRibbonConfig: Codable, Sendable {
        public var position: TabRibbonPosition = .top
        public var persistence: TabPersistence = .pinned

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = TabRibbonConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            position =
                try c.decodeIfPresent(TabRibbonPosition.self, forKey: .position) ?? d.position
            persistence =
                try c.decodeIfPresent(TabPersistence.self, forKey: .persistence) ?? d.persistence
        }
    }

    public struct SyntaxConfig: Codable, Sendable {
        public var enabled: Bool = true
        public var disabledLanguages: [String] = []
        /// Path of an Xcode `.xccolortheme` whose syntax colours replace the six `theme.*Foreground` syntax
        /// colours; `~` expands to the home directory. Nil keeps the configured colours.
        public var xcodeTheme: String?
        /// Derive the syntax colours from the terminal's own palette (queried with OSC 10, 11 and 4 at
        /// startup) when no Xcode theme is set, so the editor matches the terminal around it.
        public var themeFromTerminal: Bool = false

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = SyntaxConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            disabledLanguages =
                try c.decodeIfPresent([String].self, forKey: .disabledLanguages)
                ?? d.disabledLanguages
            xcodeTheme = try c.decodeIfPresent(String.self, forKey: .xcodeTheme) ?? d.xcodeTheme
            themeFromTerminal =
                try c.decodeIfPresent(Bool.self, forKey: .themeFromTerminal) ?? d.themeFromTerminal
        }
    }

    public struct AutoSaveConfig: Codable, Sendable {
        public var enabled: Bool = false
        public var interval: TimeInterval = 30

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = AutoSaveConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? d.interval
        }
    }

    public enum WhitespaceVisibility: String, Codable, Sendable {
        /// Show no whitespace in the selection.
        case none
        /// Show only leading indentation (spaces and tabs).
        case indentation
        /// Show indentation + mid-line/trailing spaces.
        case all
        /// Show indentation + spaces + line-break markers.
        case boundary
    }

    public struct SearchConfig: Codable, Sendable {
        public var defaultTarget: String = "currentFile"
        public var includeHiddenByDefault: Bool = false
        public var includeGitIgnoredByDefault: Bool = false
        public var caseSensitiveByDefault: Bool = false
        public var regexByDefault: Bool = false
        public var wholeWordByDefault: Bool = false
        public var excludeGlobs: [String] = ["**/.git/**", "**/build/**", "**/.build/**"]
        public var maxResults: Int = 5000
        public var debounceMilliseconds: Int = 150

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = SearchConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultTarget =
                try c.decodeIfPresent(String.self, forKey: .defaultTarget) ?? d.defaultTarget
            includeHiddenByDefault =
                try c.decodeIfPresent(Bool.self, forKey: .includeHiddenByDefault)
                ?? d.includeHiddenByDefault
            includeGitIgnoredByDefault =
                try c.decodeIfPresent(Bool.self, forKey: .includeGitIgnoredByDefault)
                ?? d.includeGitIgnoredByDefault
            caseSensitiveByDefault =
                try c.decodeIfPresent(Bool.self, forKey: .caseSensitiveByDefault)
                ?? d.caseSensitiveByDefault
            regexByDefault =
                try c.decodeIfPresent(Bool.self, forKey: .regexByDefault) ?? d.regexByDefault
            wholeWordByDefault =
                try c.decodeIfPresent(Bool.self, forKey: .wholeWordByDefault)
                ?? d.wholeWordByDefault
            excludeGlobs =
                try c.decodeIfPresent([String].self, forKey: .excludeGlobs) ?? d.excludeGlobs
            maxResults =
                try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? d.maxResults
            debounceMilliseconds =
                try c.decodeIfPresent(Int.self, forKey: .debounceMilliseconds)
                ?? d.debounceMilliseconds
        }
    }

    public struct WhitespaceConfig: Codable, Sendable {
        public var showIndentation: Bool = false
        public var showSpaces: Bool = false
        public var showLineBreaks: Bool = false
        public var showUnexpected: Bool = true
        public var selectionWhitespace: WhitespaceVisibility = .none

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = WhitespaceConfig()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showIndentation =
                try c.decodeIfPresent(Bool.self, forKey: .showIndentation) ?? d.showIndentation
            showSpaces = try c.decodeIfPresent(Bool.self, forKey: .showSpaces) ?? d.showSpaces
            showLineBreaks =
                try c.decodeIfPresent(Bool.self, forKey: .showLineBreaks) ?? d.showLineBreaks
            showUnexpected =
                try c.decodeIfPresent(Bool.self, forKey: .showUnexpected) ?? d.showUnexpected
            selectionWhitespace =
                try c.decodeIfPresent(WhitespaceVisibility.self, forKey: .selectionWhitespace)
                ?? d.selectionWhitespace
        }
    }

    public struct Theme: Codable, Sendable {
        // GitHub Dark (foreground-focused) defaults.
        // Backgrounds are intentionally omitted so terminal default background is preserved.
        public var treePanelForeground = ColorRGB(r: 0xc9, g: 0xd1, b: 0xd9)
        public var treeSelectedForeground = ColorRGB(r: 0x58, g: 0xa6, b: 0xff)
        public var treeDirectoryForeground = ColorRGB(r: 0x7e, g: 0xe7, b: 0x87)
        public var editorForeground = ColorRGB(r: 0xc9, g: 0xd1, b: 0xd9)
        public var lineNumberForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        public var statusBarForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        public var titleBarForeground = ColorRGB(r: 0xf0, g: 0xf6, b: 0xfc)
        public var separatorForeground = ColorRGB(r: 0x30, g: 0x36, b: 0x3d)

        public var keywordForeground = ColorRGB(r: 0xff, g: 0x7b, b: 0x72)
        public var typeForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        public var commentForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        public var stringForeground = ColorRGB(r: 0xa5, g: 0xd6, b: 0xff)
        public var numberForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        public var attributeForeground = ColorRGB(r: 0xd2, g: 0xa8, b: 0xff)

        public var gitModifiedForeground = ColorRGB(r: 0xe3, g: 0xb3, b: 0x41)
        public var gitAddedForeground = ColorRGB(r: 0x3f, g: 0xb9, b: 0x50)
        public var gitUntrackedForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        public var gitDeletedForeground = ColorRGB(r: 0xf8, g: 0x51, b: 0x49)
        public var gitConflictedForeground = ColorRGB(r: 0xff, g: 0x7b, b: 0x72)

        // Tab ribbon
        public var tabActiveBackground: ColorRGB?
        public var tabActiveForeground: ColorRGB?
        public var tabInactiveBackground: ColorRGB?
        public var tabInactiveForeground: ColorRGB?
        public var tabDirtyIndicator: ColorRGB?

        // Activity bar
        public var activityBarBackground: ColorRGB?
        public var activityBarForeground: ColorRGB?
        public var activityBarActiveForeground: ColorRGB?

        // Open files panel
        public var openFilesForeground: ColorRGB?
        public var openFilesSelectedForeground: ColorRGB?

        // Editor line highlighting
        public var cursorLineBackground: ColorRGB?
        public var cursorLineForeground: ColorRGB?

        // Selection highlighting
        public var selectionBackground: ColorRGB?
        public var selectionForeground: ColorRGB?

        // Whitespace rendering
        public var whitespaceIndentationForeground: ColorRGB?
        public var whitespaceSpaceForeground: ColorRGB?
        public var whitespaceLineBreakForeground: ColorRGB?
        public var whitespaceUnexpectedForeground: ColorRGB?

        // Search highlighting
        public var searchMatchForeground: ColorRGB?
        public var searchMatchBackground: ColorRGB?
        public var activeSearchMatchForeground: ColorRGB?
        public var activeSearchMatchBackground: ColorRGB?

        // Command feedback
        public var commandFeedbackForeground: ColorRGB?
        public var commandFeedbackBackground: ColorRGB?

        // Git line highlighting
        public var gitModifiedLineBackground: ColorOverlayConfig?
        public var gitModifiedLineForeground: ColorOverlayConfig?
        public var gitAddedLineBackground: ColorOverlayConfig?
        public var gitAddedLineForeground: ColorOverlayConfig?
        public var gitUntrackedLineBackground: ColorOverlayConfig?
        public var gitUntrackedLineForeground: ColorOverlayConfig?
        public var gitDeletedLineBackground: ColorOverlayConfig?
        public var gitDeletedLineForeground: ColorOverlayConfig?
        public var gitConflictedLineBackground: ColorOverlayConfig?
        public var gitConflictedLineForeground: ColorOverlayConfig?

        public init() {}

        public init(from decoder: any Decoder) throws {
            let d = Theme()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            treePanelForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .treePanelForeground)
                ?? d.treePanelForeground
            treeSelectedForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .treeSelectedForeground)
                ?? d.treeSelectedForeground
            treeDirectoryForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .treeDirectoryForeground)
                ?? d.treeDirectoryForeground
            editorForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .editorForeground)
                ?? d.editorForeground
            lineNumberForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .lineNumberForeground)
                ?? d.lineNumberForeground
            statusBarForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .statusBarForeground)
                ?? d.statusBarForeground
            titleBarForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .titleBarForeground)
                ?? d.titleBarForeground
            separatorForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .separatorForeground)
                ?? d.separatorForeground
            keywordForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .keywordForeground)
                ?? d.keywordForeground
            typeForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .typeForeground) ?? d.typeForeground
            commentForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .commentForeground)
                ?? d.commentForeground
            stringForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .stringForeground)
                ?? d.stringForeground
            numberForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .numberForeground)
                ?? d.numberForeground
            attributeForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .attributeForeground)
                ?? d.attributeForeground
            gitModifiedForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .gitModifiedForeground)
                ?? d.gitModifiedForeground
            gitAddedForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .gitAddedForeground)
                ?? d.gitAddedForeground
            gitUntrackedForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .gitUntrackedForeground)
                ?? d.gitUntrackedForeground
            gitDeletedForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .gitDeletedForeground)
                ?? d.gitDeletedForeground
            gitConflictedForeground =
                try c.decodeIfPresent(ColorRGB.self, forKey: .gitConflictedForeground)
                ?? d.gitConflictedForeground
            tabActiveBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .tabActiveBackground)
            tabActiveForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .tabActiveForeground)
            tabInactiveBackground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .tabInactiveBackground)
            tabInactiveForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .tabInactiveForeground)
            tabDirtyIndicator = try c.decodeIfPresent(ColorRGB.self, forKey: .tabDirtyIndicator)
            activityBarBackground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .activityBarBackground)
            activityBarForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .activityBarForeground)
            activityBarActiveForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .activityBarActiveForeground)
            openFilesForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .openFilesForeground)
            openFilesSelectedForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .openFilesSelectedForeground)
            cursorLineBackground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .cursorLineBackground)
            cursorLineForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .cursorLineForeground)
            selectionBackground = try c.decodeIfPresent(ColorRGB.self, forKey: .selectionBackground)
            selectionForeground = try c.decodeIfPresent(ColorRGB.self, forKey: .selectionForeground)
            whitespaceIndentationForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .whitespaceIndentationForeground)
            whitespaceSpaceForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .whitespaceSpaceForeground)
            whitespaceLineBreakForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .whitespaceLineBreakForeground)
            whitespaceUnexpectedForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .whitespaceUnexpectedForeground)
            searchMatchForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .searchMatchForeground)
            searchMatchBackground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .searchMatchBackground)
            activeSearchMatchForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .activeSearchMatchForeground)
            activeSearchMatchBackground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .activeSearchMatchBackground)
            commandFeedbackForeground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .commandFeedbackForeground)
            commandFeedbackBackground = try c.decodeIfPresent(
                ColorRGB.self, forKey: .commandFeedbackBackground)
            gitModifiedLineBackground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitModifiedLineBackground)
            gitModifiedLineForeground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitModifiedLineForeground)
            gitAddedLineBackground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitAddedLineBackground)
            gitAddedLineForeground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitAddedLineForeground)
            gitUntrackedLineBackground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitUntrackedLineBackground)
            gitUntrackedLineForeground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitUntrackedLineForeground)
            gitDeletedLineBackground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitDeletedLineBackground)
            gitDeletedLineForeground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitDeletedLineForeground)
            gitConflictedLineBackground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitConflictedLineBackground)
            gitConflictedLineForeground = try c.decodeIfPresent(
                ColorOverlayConfig.self, forKey: .gitConflictedLineForeground)
        }
    }

    public enum SidebarOverflowMode: String, Codable, Sendable {
        case truncateEnd
        case marquee
    }

    public var sidebarOverflowMode: SidebarOverflowMode = .truncateEnd
    public var keybindingMode: KeybindingMode = .nano
    public var treeWidth: Int = 30
    public var useSFSymbolsInTerminal: Bool = true
    public var fileWatcherEnabled: Bool = true
    public var editor: EditorConfig = .init()
    public var theme: Theme = .init()
    public var statusBar: StatusBarConfig = .init()
    public var git: GitConfig = .init()
    public var syntax: SyntaxConfig = .init()
    public var tabRibbon: TabRibbonConfig = .init()
    public var autoSave: AutoSaveConfig = .init()
    public var activityBar: ActivityBarConfig = .init()
    public var keybindings: KeybindingsConfig = .init()
    public var whitespace: WhitespaceConfig = .init()
    public var search: SearchConfig = .init()

    public init() {}

    public init(from decoder: any Decoder) throws {
        let d = KittyConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sidebarOverflowMode =
            try c.decodeIfPresent(SidebarOverflowMode.self, forKey: .sidebarOverflowMode)
            ?? d.sidebarOverflowMode
        keybindingMode =
            try c.decodeIfPresent(KeybindingMode.self, forKey: .keybindingMode) ?? d.keybindingMode
        treeWidth = try c.decodeIfPresent(Int.self, forKey: .treeWidth) ?? d.treeWidth
        useSFSymbolsInTerminal =
            try c.decodeIfPresent(Bool.self, forKey: .useSFSymbolsInTerminal)
            ?? d.useSFSymbolsInTerminal
        fileWatcherEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .fileWatcherEnabled) ?? d.fileWatcherEnabled
        editor = try c.decodeIfPresent(EditorConfig.self, forKey: .editor) ?? d.editor
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? d.theme
        statusBar = try c.decodeIfPresent(StatusBarConfig.self, forKey: .statusBar) ?? d.statusBar
        git = try c.decodeIfPresent(GitConfig.self, forKey: .git) ?? d.git
        syntax = try c.decodeIfPresent(SyntaxConfig.self, forKey: .syntax) ?? d.syntax
        tabRibbon = try c.decodeIfPresent(TabRibbonConfig.self, forKey: .tabRibbon) ?? d.tabRibbon
        autoSave = try c.decodeIfPresent(AutoSaveConfig.self, forKey: .autoSave) ?? d.autoSave
        activityBar =
            try c.decodeIfPresent(ActivityBarConfig.self, forKey: .activityBar) ?? d.activityBar
        keybindings =
            try c.decodeIfPresent(KeybindingsConfig.self, forKey: .keybindings) ?? d.keybindings
        whitespace =
            try c.decodeIfPresent(WhitespaceConfig.self, forKey: .whitespace) ?? d.whitespace
        search =
            try c.decodeIfPresent(SearchConfig.self, forKey: .search) ?? d.search
    }

    public static let configURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".kittycode.json")

    public static func load() -> KittyConfig {
        load(from: configURL)
    }

    public static func load(from url: URL) -> KittyConfig {
        do {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                // Missing file is the common case (no user config) — silent fallback.
                // Other read errors (permission, I/O) warrant a log entry.
                if (error as NSError).code != NSFileReadNoSuchFileError {
                    KittyLogger.warning("config unreadable at \(url.path): \(error). using defaults")
                }
                return KittyConfig()
            }
            return try JSONDecoder().decode(KittyConfig.self, from: data)
        } catch let error as DecodingError {
            KittyLogger.warning("config decode failed at \(url.path): \(error). using defaults")
            return KittyConfig()
        } catch {
            KittyLogger.warning("config load failed at \(url.path): \(error). using defaults")
            return KittyConfig()
        }
    }
}

extension KittyConfig.Theme {
    public func resolvedStyle(_ color: ColorRGB?, bold: Bool = false) -> Style? {
        guard let color else { return nil }
        return Style(fg: color.color, bold: bold)
    }
}
