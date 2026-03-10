import Foundation
import KittyCodecs

@MainActor
final class EditorState {
    struct ColorScheme {
        var bg: Style
        var treeBg: Style
        var treeSelected: Style
        var treeDir: Style
        var lineNumber: Style
        var editorText: Style
        var editorCursorLine: Style
        var statusBar: Style
        var titleBar: Style
        var separator: Style
        var syntaxKeyword: Style
        var syntaxType: Style
        var syntaxComment: Style
        var syntaxString: Style
        var syntaxNumber: Style
        var syntaxAttribute: Style
    }

    enum Mode {
        case tree
        case editor
    }

    enum VimMode {
        case normal
        case insert
    }

    var config: KittyConfig
    var colorScheme: ColorScheme
    var rootPath: String
    var fileTree: [FileEntry] = []
    var flatTree: [(depth: Int, entry: FileEntry)] = []
    var selectedTreeIndex = 0
    var treeScrollOffset = 0
    var fileContent: [String] = []
    var fileName = ""
    var filePath = ""
    var scrollOffset = 0
    var hScrollOffset = 0
    var cursorRow = 0
    var cursorCol = 0
    var treePanelWidth = 30
    var statusMessage = ""
    var mode: Mode = .tree
    var vimMode: VimMode = .normal
    var lastClickTime: Date = .distantPast
    var lastClickIndex = -1
    var isScrolling = false

    init(rootPath: String, config: KittyConfig) {
        self.rootPath = rootPath
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        self.fileTree = Self.scanDirectory(rootPath, maxDepth: 1)
        self.flatTree = Self.flatten(fileTree)
        self.statusMessage = "Opened: \(rootPath) | ^O: Save, ^X: Quit"
    }
}