import Foundation
import KittyCodecs
import KittyFileTree
import KittySyntax
import KittyText
import KittyWidgets

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
    var currentLanguage: String?
    var highlightedLines: [[StyledSpan]] = [[StyledSpan(text: "", style: .default)]]

    // MARK: - Text buffer (backed by KittyText)

    var textBuffer = TextBuffer()
    var textCursor = TextCursor()
    private var cachedFileLines: [String]?

    /// Backward-compatible computed access to file content lines.
    var fileContent: [String] {
        get {
            if let cachedFileLines {
                return cachedFileLines
            }

            let lines = textBuffer.lines
            cachedFileLines = lines
            return lines
        }
        set {
            let normalizedLines = newValue.isEmpty ? [""] : newValue
            textBuffer = TextBuffer(lines: normalizedLines)
            cachedFileLines = normalizedLines
        }
    }

    var fileLineCount: Int {
        textBuffer.lineCount
    }

    var isFileEmpty: Bool {
        textBuffer.isEmpty
    }

    func fileLine(at index: Int) -> String {
        textBuffer.line(at: index)
    }

    func invalidateTextSnapshotCache() {
        cachedFileLines = nil
    }

    /// Backward-compatible cursor row.
    var cursorRow: Int {
        get { textCursor.row }
        set { textCursor.row = newValue }
    }

    /// Backward-compatible cursor column.
    var cursorCol: Int {
        get { textCursor.col }
        set { textCursor.col = newValue }
    }

    /// Backward-compatible vertical scroll offset.
    var scrollOffset: Int {
        get { textCursor.scrollRow }
        set { textCursor.scrollRow = newValue }
    }

    /// Backward-compatible horizontal scroll offset.
    var hScrollOffset: Int {
        get { textCursor.scrollCol }
        set { textCursor.scrollCol = newValue }
    }

    // MARK: - File tree (backed by KittyFileTree)

    var treeNodes: [FileNode] = []
    var cachedFlatTree: [(depth: Int, node: FileNode)] = []
    var selectedTreeIndex = 0
    var treeScrollOffset = 0

    // MARK: - Highlighted document

    func highlightedLine(at index: Int) -> [StyledSpan] {
        guard index >= 0 && index < highlightedLines.count else {
            return [StyledSpan(text: "", style: syntaxTheme.defaultStyle)]
        }
        return highlightedLines[index]
    }

    var syntaxTheme: Theme {
        var theme = Theme(defaultStyle: colorScheme.editorText)
        theme.setStyle(colorScheme.syntaxKeyword, for: "keyword")
        theme.setStyle(colorScheme.syntaxType, for: "type")
        theme.setStyle(colorScheme.syntaxComment, for: "comment")
        theme.setStyle(colorScheme.syntaxString, for: "string")
        theme.setStyle(colorScheme.syntaxNumber, for: "number")
        theme.setStyle(colorScheme.syntaxAttribute, for: "attribute")
        theme.setStyle(colorScheme.syntaxAttribute, for: "string.special")
        theme.setStyle(colorScheme.syntaxKeyword, for: "constant")
        theme.setStyle(colorScheme.syntaxKeyword, for: "constant.builtin")
        theme.setStyle(colorScheme.editorText, for: "variable")
        theme.setStyle(colorScheme.editorText, for: "variable.parameter")
        theme.setStyle(colorScheme.syntaxAttribute, for: "property")
        theme.setStyle(colorScheme.syntaxAttribute, for: "function")
        return theme
    }

    func refreshHighlights() {
        highlightedLines = LanguageHighlighter.highlightDocument(
            source: textBuffer.text,
            language: currentLanguage,
            theme: syntaxTheme
        )
    }

    var fileName = ""
    var filePath = ""
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
        self.treeNodes = DirectoryScanner.scan(rootPath, maxDepth: 1)
        self.cachedFlatTree = FileTreeNavigator.flatten(treeNodes)
        self.statusMessage = "Opened: \(rootPath) | ^O: Save, ^X: Quit"
        refreshHighlights()
    }
}
