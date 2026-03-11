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
        var gitModifiedLine: TextStyleOverlay
        var gitAddedLine: TextStyleOverlay
        var gitUntrackedLine: TextStyleOverlay
        var gitDeletedLine: TextStyleOverlay
        var gitConflictedLine: TextStyleOverlay
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
        var whitespaceIndentation: Style
        var whitespaceSpace: Style
        var whitespaceLineBreak: Style
        var whitespaceUnexpected: Style
        var verticalScrollIndicator: VerticalScrollIndicatorStyle
        var horizontalScrollIndicator: HorizontalScrollIndicatorStyle
        var emptyEditorMessage: Style

        func gitStatusStyle(for color: FileStatusColor) -> Style {
            switch color {
            case .modified:
                return gitModified
            case .added:
                return gitAdded
            case .untracked:
                return gitUntracked
            case .deleted:
                return gitDeleted
            case .conflicted:
                return gitConflicted
            case .clean:
                return treeBg
            }
        }

        func gitLineOverlay(for color: FileStatusColor) -> TextStyleOverlay {
            switch color {
            case .modified:
                return gitModifiedLine
            case .added:
                return gitAddedLine
            case .untracked:
                return gitUntrackedLine
            case .deleted:
                return gitDeletedLine
            case .conflicted:
                return gitConflictedLine
            case .clean:
                return TextStyleOverlay()
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

    enum ContextMenuTarget: Equatable {
        case editor
        case treeNode(index: Int)
    }

    enum ContextMenuAction: Equatable {
        case openSelected
        case openSelectedPinned
        case toggleSelectedDirectory
        case beginNewFile(inDirectory: String)
        case beginSavePrompt(inDirectory: String)
        case saveFile
        case focusTree
        case closeTab
    }

    struct ContextMenuItem: Equatable {
        var title: String
        var shortcut: String
        var action: ContextMenuAction
    }

    struct ContextMenuState: Equatable {
        var title: String
        var subtitle: String?
        var target: ContextMenuTarget
        var items: [ContextMenuItem]
        var selectedIndex: Int = 0
    }

    enum ScrollDragTarget: Equatable {
        case tree
        case editor
        case editorHorizontal
    }

    struct ScrollDragState: Equatable {
        var target: ScrollDragTarget
        var gripOffset: Int
    }

    var config: KittyConfig
    var fileStatusProvider: (any FileStatusProvider)?
    var gitLineDecorationProvider: (any GitLineDecorationProvider)?
    var gitDecorationManager: GitDecorationManager?
    var renderRefreshSource: RenderRefreshSource?
    weak var fileWatcherIntegration: FileWatcherIntegration?
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

    // MARK: - Multi-buffer management

    let bufferManager = BufferManager()
    var tabScrollOffset: Int = 0

    // MARK: - Text buffer (backed by KittyText)

    var textBuffer = TextBuffer()
    var textCursor = TextCursor()
    private var cachedFileLines: [String]?
    private var cachedDocumentText: String?
    private var cachedSerializedByteCount: Int?
    var highlightSession: LanguageHighlighter.Session?
    private var fileOpenTask: Task<Void, Never>?
    private var pendingOpenRequestID: UInt64 = 0
    var currentLineEnding: TextDocument.LineEnding = .lf {
        didSet {
            cachedSerializedByteCount = nil
        }
    }

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
            cachedMaxLineWidth = TextDocument.computeMaxLineWidth(for: normalizedLines, tabSize: config.editor.tabSize)
            cachedSerializedByteCount = TextDocument.computeSerializedByteCount(
                for: normalizedLines,
                lineEnding: currentLineEnding
            )
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
        cachedMaxLineWidth = nil
        cachedSerializedByteCount = nil
    }

    func invalidateHighlightSession() {
        highlightSession = nil
    }

    func textDidChange() {
        invalidateTextSnapshotCache()
        if let buf = bufferManager.activeBuffer {
            buf.postOpenProcessingTask?.cancel()
            buf.postOpenProcessingTask = nil
            buf.isDirty = true
            if buf.isPreview { buf.isPreview = false }
            buf.documentVersion += 1
            isLoadingGrammar = false
        }
        widenCachedMaxLineWidth(for: textCursor.row..<(textCursor.row + 1))
        refreshHighlights()
        gitDecorationManager?.scheduleRefreshForActiveBuffer()
    }

    func textDidChange(_ mutation: TextMutation) {
        invalidateTextSnapshotCache()
        if let buf = bufferManager.activeBuffer {
            buf.postOpenProcessingTask?.cancel()
            buf.postOpenProcessingTask = nil
            buf.isDirty = true
            if buf.isPreview { buf.isPreview = false }
            buf.documentVersion += 1
            isLoadingGrammar = false
        }
        widenCachedMaxLineWidth(for: mutation.updatedLineRange)
        refreshHighlights(after: mutation)
        gitDecorationManager?.scheduleRefreshForActiveBuffer()
    }

    func replaceDocumentText(with content: String) {
        let lines = TextBuffer.splitLines(from: content)
        textBuffer = TextBuffer(lines: lines)
        cachedFileLines = lines
        cachedDocumentText = content
        cachedMaxLineWidth = TextDocument.computeMaxLineWidth(for: lines, tabSize: config.editor.tabSize)
        cachedSerializedByteCount = TextDocument.computeSerializedByteCount(for: lines, lineEnding: currentLineEnding)
        highlightSession = nil
    }

    var serializedByteCount: Int {
        if let cachedSerializedByteCount {
            return cachedSerializedByteCount
        }

        let count = TextDocument.computeSerializedByteCount(in: textBuffer, lineEnding: currentLineEnding)
        cachedSerializedByteCount = count
        return count
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

    // MARK: - Active buffer synchronization

    /// Save current editor state to the active DocumentBuffer.
    func saveStateToActiveBuffer() {
        guard let buf = bufferManager.activeBuffer else { return }
        buf.textBuffer = textBuffer
        buf.textCursor = textCursor
        buf.highlightedLines = highlightedLines
        buf.highlightSession = highlightSession
        buf.cachedFileLines = cachedFileLines
        buf.cachedDocumentText = cachedDocumentText
        buf.cachedMaxLineWidth = cachedMaxLineWidth
        buf.cachedSerializedByteCount = cachedSerializedByteCount
        buf.language = currentLanguage
        buf.lineEnding = currentLineEnding
    }

    /// Restore editor state from the active DocumentBuffer.
    func restoreStateFromActiveBuffer() {
        guard let buf = bufferManager.activeBuffer else { return }
        textBuffer = buf.textBuffer
        textCursor = buf.textCursor
        highlightedLines = buf.highlightedLines
        highlightSession = buf.highlightSession
        currentLanguage = buf.language
        fileName = buf.fileName
        filePath = buf.filePath
        cachedFileLines = buf.cachedFileLines
        cachedDocumentText = buf.cachedDocumentText
        cachedMaxLineWidth = buf.cachedMaxLineWidth
        cachedSerializedByteCount = buf.cachedSerializedByteCount
        currentLineEnding = buf.lineEnding
    }

    /// Switch to a different tab by index, saving/restoring state.
    func switchToTab(_ index: Int) {
        guard index != bufferManager.activeIndex, index >= 0, index < bufferManager.count else { return }
        saveStateToActiveBuffer()
        bufferManager.switchTo(index: index)
        restoreStateFromActiveBuffer()
        gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
    }

    /// Adjust `tabScrollOffset` so the active tab is visible within the given ribbon width.
    func ensureActiveTabVisible(ribbonWidth: Int) {
        let tabs = bufferManager.buffers.map { TabRibbon.Tab(name: $0.fileName, isDirty: $0.isDirty) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: bufferManager.activeIndex, scrollOffset: tabScrollOffset)
        tabScrollOffset = ribbon.clampedScrollOffset(activeIndex: bufferManager.activeIndex, ribbonWidth: ribbonWidth)
    }

    // MARK: - File tree (backed by KittyFileTree)

    var treeNodes: [FileNode] = []
    var cachedFlatTree: [(depth: Int, node: FileNode)] = []
    var selectedTreeIndex = 0
    var treeScrollOffset = 0
    var lastSelectedDirectoryPath: String?

    // MARK: - Activity bar & sidebar

    enum SidebarPanel {
        case explorer
        case openDocuments
    }

    var activeSidebarPanel: SidebarPanel = .explorer
    var sidebarCollapsed: Bool = false
    var openFilesScrollOffset: Int = 0
    var openFilesSelectedIndex: Int = 0

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

    private var syntaxHighlightingEnabled: Bool {
        guard config.syntaxHighlighting else { return false }
        if let lang = currentLanguage, config.disabledLanguages.contains(lang) {
            return false
        }
        return true
    }

    func refreshHighlights() {
        guard syntaxHighlightingEnabled else {
            highlightedLines = fileContent.map { line in
                [StyledSpan(text: line, style: colorScheme.editorText)]
            }
            return
        }
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
            theme: syntaxTheme,
            preferGrammar: false
        )
        highlightSession = newSession
        return newSession
    }

    private func refreshHighlights(after mutation: TextMutation) {
        guard syntaxHighlightingEnabled else {
            refreshHighlights()
            return
        }
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
    var prompt: EditorPrompt?
    var contextMenu: ContextMenuState?
    var mode: Mode = .tree
    var vimMode: VimMode = .normal
    var symbolTheme: TerminalSymbolTheme
    var lastClickTime: Date = .distantPast
    var lastClickIndex = -1
    var isScrolling = false
    var scrollDragState: ScrollDragState?
    var isLoadingGrammar = false
    var cachedMaxLineWidth: Int?

    var maxLineWidth: Int {
        cachedMaxLineWidth ?? 0
    }

    init(rootPath: String, config: KittyConfig) {
        self.rootPath = rootPath
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        let catalog = config.useSFSymbolsInTerminal ? SymbolCatalogLoader.loadOrDiscover() : nil
        self.symbolTheme = TerminalSymbolTheme.make(symbolsEnabled: config.useSFSymbolsInTerminal, catalog: catalog)
        self.treeNodes = DirectoryScanner.scan(rootPath, maxDepth: 1)
        self.cachedFlatTree = FileTreeNavigator.flatten(treeNodes)
        self.lastSelectedDirectoryPath = rootPath
        self.statusMessage = "Opened \(rootPath) | ^O Save | ^X Quit"
        refreshHighlights()
    }

    deinit {
        fileOpenTask?.cancel()
    }

    func nextOpenRequestID() -> UInt64 {
        pendingOpenRequestID &+= 1
        return pendingOpenRequestID
    }

    func replaceFileOpenTask(with task: Task<Void, Never>) {
        fileOpenTask?.cancel()
        fileOpenTask = task
    }

    func cancelPendingFileOpen() {
        fileOpenTask?.cancel()
        fileOpenTask = nil
    }

    func isCurrentOpenRequest(_ requestID: UInt64) -> Bool {
        pendingOpenRequestID == requestID
    }

    private func widenCachedMaxLineWidth(for range: Range<Int>) {
        let lowerBound = max(0, range.lowerBound)
        let upperBound = min(fileLineCount, range.upperBound)
        guard lowerBound < upperBound else { return }

        let widenedWidth = (lowerBound..<upperBound).reduce(0) { partial, lineIndex in
            max(partial, UnicodeWidth.displayWidth(of: textBuffer.line(at: lineIndex)))
        }

        cachedMaxLineWidth = max(cachedMaxLineWidth ?? 0, widenedWidth)
    }

    func noteSelectedPath(_ path: String, isDirectory: Bool) {
        let directoryPath: String
        if isDirectory {
            directoryPath = path
        } else {
            directoryPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        }

        lastSelectedDirectoryPath = directoryPath
    }
}
