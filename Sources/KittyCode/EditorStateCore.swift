import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittySymbols
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
        var gitModified: Style
        var gitAdded: Style
        var gitUntracked: Style
        var gitDeleted: Style
        var gitConflicted: Style

        func gitStatusStyle(for color: FileStatusColor) -> Style {
            switch color {
            case .modified: return gitModified
            case .added: return gitAdded
            case .untracked: return gitUntracked
            case .deleted: return gitDeleted
            case .conflicted: return gitConflicted
            case .clean: return treeBg
            }
        }
    }

    enum Mode {
        case tree
        case editor
    }

    enum VimMode {
        case normal
        case insert
    }

    enum ScrollDragTarget: Equatable {
        case tree
        case editor
    }

    struct ScrollDragState: Equatable {
        var target: ScrollDragTarget
        var gripOffset: Int
    }

    var config: KittyConfig
    var fileStatusProvider: (any FileStatusProvider)?
    var colorScheme: ColorScheme {
        didSet {
            highlightSession = nil
        }
    }
    var rootPath: String
    var currentLanguage: String? {
        didSet {
            if currentLanguage != oldValue {
                highlightSession = nil
            }
        }
    }
    var highlightedLines: [[StyledSpan]] = [[StyledSpan(text: "", style: .default)]]

    // MARK: - Text buffer (backed by KittyText)

    var textBuffer = TextBuffer()
    var textCursor = TextCursor()
    private var cachedFileLines: [String]?
    private var cachedDocumentText: String?
    private var highlightSession: LanguageHighlighter.Session?

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
            cachedDocumentText = normalizedLines.joined(separator: "\n")
            highlightSession = nil
        }
    }

    var documentText: String {
        if let cachedDocumentText {
            return cachedDocumentText
        }

        let text = textBuffer.text
        cachedDocumentText = text
        return text
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
        cachedDocumentText = nil
    }

    func invalidateHighlightSession() {
        highlightSession = nil
    }

    func textDidChange() {
        invalidateTextSnapshotCache()
        refreshHighlights()
    }

    func textDidChange(_ mutation: TextMutation) {
        invalidateTextSnapshotCache()
        refreshHighlights(after: mutation)
    }

    func replaceDocumentText(with content: String) {
        textBuffer = TextBuffer(content)
        cachedFileLines = nil
        cachedDocumentText = content
        highlightSession = nil
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
        theme.setStyle(colorScheme.syntaxKeyword, for: "operator")
        theme.setStyle(colorScheme.syntaxKeyword, for: "keyword.operator")
        theme.setStyle(colorScheme.editorText, for: "variable")
        theme.setStyle(colorScheme.editorText, for: "variable.parameter")
        theme.setStyle(colorScheme.editorText, for: "delimiter")
        theme.setStyle(colorScheme.editorText, for: "punctuation")
        theme.setStyle(colorScheme.editorText, for: "punctuation.delimiter")
        theme.setStyle(colorScheme.editorText, for: "punctuation.bracket")
        theme.setStyle(colorScheme.syntaxString, for: "escape")
        theme.setStyle(colorScheme.syntaxAttribute, for: "property")
        theme.setStyle(colorScheme.syntaxAttribute, for: "function")
        theme.setStyle(colorScheme.syntaxAttribute, for: "label")
        theme.setStyle(colorScheme.syntaxType, for: "module")
        theme.setStyle(colorScheme.syntaxType, for: "namespace")
        theme.setStyle(colorScheme.syntaxKeyword, for: "tag")
        theme.setStyle(colorScheme.syntaxAttribute, for: "constructor")
        return theme
    }

    func refreshHighlights() {
        let session = currentHighlightSession()
        if session.prefersLineInput {
            highlightedLines = session.highlightLines(fileContent)
        } else {
            highlightedLines = session.highlightDocument(source: documentText)
        }
    }

    private func currentHighlightSession() -> LanguageHighlighter.Session {
        if let highlightSession {
            return highlightSession
        }

        let newSession = LanguageHighlighter.makeSession(
            language: currentLanguage,
            theme: syntaxTheme
        )
        highlightSession = newSession
        return newSession
    }

    private func refreshHighlights(after mutation: TextMutation) {
        let session = currentHighlightSession()
        guard session.prefersLineInput else {
            refreshHighlights()
            return
        }

        let lines = fileContent
        guard mutation.originalLineRange.lowerBound >= 0,
              mutation.originalLineRange.upperBound <= highlightedLines.count,
              mutation.updatedLineRange.lowerBound >= 0,
              mutation.updatedLineRange.upperBound <= lines.count
        else {
            refreshHighlights()
            return
        }

        let updatedHighlights = session.highlightLines(lines[mutation.updatedLineRange])
        highlightedLines.replaceSubrange(mutation.originalLineRange, with: updatedHighlights)
    }

    var fileName = ""
    var filePath = ""
    var treePanelWidth = 30
    var statusMessage = ""
    var mode: Mode = .tree
    var vimMode: VimMode = .normal
    var symbolTheme: TerminalSymbolTheme
    var lastClickTime: Date = .distantPast
    var lastClickIndex = -1
    var isScrolling = false
    var scrollDragState: ScrollDragState?

    init(rootPath: String, config: KittyConfig) {
        self.rootPath = rootPath
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        let catalog = try? SymbolCatalog.load(from: SymbolCatalogLocator.defaultMappingURL())
        self.symbolTheme = TerminalSymbolTheme.make(symbolsEnabled: config.useSFSymbolsInTerminal, catalog: catalog)
        self.treeNodes = DirectoryScanner.scan(rootPath, maxDepth: 1)
        self.cachedFlatTree = FileTreeNavigator.flatten(treeNodes)
        self.statusMessage = "Opened \(rootPath) | ^O Save | ^X Quit"
        refreshHighlights()
    }
}
