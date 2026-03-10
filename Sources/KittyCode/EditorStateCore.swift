import Foundation
import KittyCodecs
import KittyFileTree
import KittySyntax
import KittyText

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

    // MARK: - Text buffer (backed by KittyText)

    var textBuffer = TextBuffer()
    var textCursor = TextCursor()

    /// Backward-compatible computed access to file content lines.
    var fileContent: [String] {
        get { textBuffer.lines }
        set { textBuffer = TextBuffer(lines: newValue) }
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

    // MARK: - Highlight cache

    /// Per-line highlight cache: maps line index to (content at time of highlight, styled spans).
    var highlightCache: [Int: (content: String, spans: [StyledSpan])] = [:]

    /// Returns cached highlight spans for a line, re-highlighting only when content changed.
    func cachedHighlightLine(_ lineIndex: Int) -> [StyledSpan] {
        let content = fileContent[lineIndex]
        if let cached = highlightCache[lineIndex], cached.content == content {
            return cached.spans
        }
        let spans = highlightLine(content, language: currentLanguage, colorScheme: colorScheme)
        highlightCache[lineIndex] = (content: content, spans: spans)
        return spans
    }

    /// Invalidates the highlight cache for a specific line.
    func invalidateHighlightCache(line: Int) {
        highlightCache.removeValue(forKey: line)
    }

    /// Clears the entire highlight cache (e.g. on file open or language change).
    func clearHighlightCache() {
        highlightCache.removeAll()
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
    }
}