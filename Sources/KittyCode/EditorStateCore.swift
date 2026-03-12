import Foundation
import KittyApp
import KittyCodecs
import KittyFileTree
import KittyGit
import KittySymbols
import KittySyntax
import KittyText
import KittyWidgets
import KittyWorkspace

@MainActor
final class EditorState {
    enum AcceleratedScrollTarget: Sendable {
        case tree
        case editor
    }

    struct WrapCache: Sendable {
        var contentWidth: Int = -1
        var tabSize: Int = -1
        var documentVersion: Int = 0
        var totalRowCount: Int = 0
        var lineWrapCounts: [Int] = []
        var visualOffsets: [Int] = []

        mutating func invalidate() {
            contentWidth = -1
            tabSize = -1
            documentVersion = 0
            totalRowCount = 0
            lineWrapCounts.removeAll(keepingCapacity: true)
            visualOffsets.removeAll(keepingCapacity: true)
        }

        func isValid(contentWidth: Int, tabSize: Int, documentVersion: Int, lineCount: Int) -> Bool {
            self.contentWidth == contentWidth &&
            self.tabSize == tabSize &&
            self.documentVersion == documentVersion &&
            lineWrapCounts.count == lineCount
        }
    }

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
        var selection: Style

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
        case beginCreateFile(inDirectory: String)
        case beginCreateDirectory(inDirectory: String)
        case beginSavePrompt(inDirectory: String)
        case beginRename(path: String)
        case beginDuplicate(path: String)
        case beginMove(path: String)
        case beginDelete(path: String)
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

    // MARK: - Workspace (domain state)

    let workspace: WorkspaceSession

    // MARK: - Shell state

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
    var tabScrollOffset: Int = 0

    // MARK: - Forwarding properties to workspace

    var rootPath: String {
        get { workspace.rootPath }
        set { workspace.rootPath = newValue }
    }

    let bufferManager: BufferManager

    var textBuffer: TextBuffer {
        get { workspace.textBuffer }
        set { workspace.textBuffer = newValue }
    }

    var textCursor: TextCursor {
        get { workspace.textCursor }
        set { workspace.textCursor = newValue }
    }

    var currentLanguage: String? {
        get { workspace.currentLanguage }
        set {
            if workspace.currentLanguage != newValue {
                workspace.highlightSession = nil
            }
            workspace.currentLanguage = newValue
        }
    }

    var highlightedLines: [[StyledSpan]] {
        get { workspace.highlightedLines }
        set { workspace.highlightedLines = newValue }
    }

    var highlightSession: LanguageHighlighter.Session? {
        get { workspace.highlightSession }
        set { workspace.highlightSession = newValue }
    }

    var currentLineEnding: TextDocument.LineEnding {
        get { workspace.currentLineEnding }
        set {
            workspace.currentLineEnding = newValue
            workspace.cachedSerializedByteCount = nil
        }
    }

    private var cachedFileLines: [String]? {
        get { workspace.cachedFileLines }
        set { workspace.cachedFileLines = newValue }
    }

    private var cachedDocumentText: String? {
        get { workspace.cachedDocumentText }
        set { workspace.cachedDocumentText = newValue }
    }

    private var cachedSerializedByteCount: Int? {
        get { workspace.cachedSerializedByteCount }
        set { workspace.cachedSerializedByteCount = newValue }
    }

    var cachedMaxLineWidth: Int? {
        get { workspace.cachedMaxLineWidth }
        set { workspace.cachedMaxLineWidth = newValue }
    }

    var fileName: String {
        get { workspace.fileName }
        set { workspace.fileName = newValue }
    }

    var filePath: String {
        get { workspace.filePath }
        set { workspace.filePath = newValue }
    }

    // MARK: - Tree state forwarding

    let treeState: WorkspaceTreeState

    var treeNodes: [FileNode] {
        get { treeState.treeNodes }
        set { treeState.treeNodes = newValue }
    }
    var cachedFlatTree: [(depth: Int, node: FileNode)] {
        get { treeState.cachedFlatTree }
        set { treeState.cachedFlatTree = newValue }
    }
    var selectedTreeIndex: Int {
        get { treeState.selectedTreeIndex }
        set { treeState.selectedTreeIndex = newValue }
    }
    var treeScrollOffset: Int {
        get { treeState.treeScrollOffset }
        set { treeState.treeScrollOffset = newValue }
    }
    var lastSelectedDirectoryPath: String? {
        get { treeState.lastSelectedDirectoryPath }
        set { treeState.lastSelectedDirectoryPath = newValue }
    }

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
        guard config.syntax.enabled else { return false }
        if let lang = currentLanguage, config.syntax.disabledLanguages.contains(lang) {
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

    // MARK: - Backward-compatible text access

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
        workspace.invalidateTextSnapshotCache()
    }

    func invalidateHighlightSession() {
        workspace.invalidateHighlightSession()
    }

    func activeBufferSnapshot() -> BufferEditSnapshot? {
        guard bufferManager.activeBuffer != nil else { return nil }
        return BufferEditSnapshot(
            textBuffer: textBuffer,
            textCursor: textCursor,
            lineEnding: currentLineEnding
        )
    }

    private var bufferUndoCoalescingWindow: TimeInterval? {
        guard config.editor.undoCoalescingEnabled else { return nil }
        return Double(max(0, config.editor.undoCoalescingMilliseconds)) / 1_000
    }

    func textDidChange(previousSnapshot: BufferEditSnapshot? = nil) {
        invalidateTextSnapshotCache()
        if let buf = bufferManager.activeBuffer {
            buf.postOpenProcessingTask?.cancel()
            buf.postOpenProcessingTask = nil
            if buf.isPreview { buf.isPreview = false }
            buf.documentVersion += 1
            isLoadingGrammar = false
            if let previousSnapshot,
               let currentSnapshot = activeBufferSnapshot()
            {
                buf.editHistory.recordChange(
                    from: previousSnapshot,
                    to: currentSnapshot,
                    coalescingWindow: bufferUndoCoalescingWindow
                )
                buf.isDirty = buf.editHistory.isDirty(current: currentSnapshot)
            } else {
                buf.isDirty = true
            }
        }
        widenCachedMaxLineWidth(for: textCursor.row..<(textCursor.row + 1))
        refreshHighlights()
        gitDecorationManager?.scheduleRefreshForActiveBuffer()
        wrapCache.invalidate()
    }

    func textDidChange(_ mutation: TextMutation, previousSnapshot: BufferEditSnapshot? = nil) {
        invalidateTextSnapshotCache()
        if let buf = bufferManager.activeBuffer {
            buf.postOpenProcessingTask?.cancel()
            buf.postOpenProcessingTask = nil
            if buf.isPreview { buf.isPreview = false }
            buf.documentVersion += 1
            isLoadingGrammar = false
            if let previousSnapshot,
               let currentSnapshot = activeBufferSnapshot()
            {
                buf.editHistory.recordChange(
                    from: previousSnapshot,
                    to: currentSnapshot,
                    coalescingWindow: bufferUndoCoalescingWindow
                )
                buf.isDirty = buf.editHistory.isDirty(current: currentSnapshot)
            } else {
                buf.isDirty = true
            }
        }
        widenCachedMaxLineWidth(for: mutation.updatedLineRange)
        refreshHighlights(after: mutation)
        gitDecorationManager?.scheduleRefreshForActiveBuffer()
        wrapCache.invalidate()
    }

    func replaceDocumentText(with content: String) {
        workspace.replaceDocumentText(with: content, tabSize: config.editor.tabSize, lineEnding: currentLineEnding)
    }

    var serializedByteCount: Int {
        workspace.serializedByteCount
    }

    var cursorRow: Int {
        get { textCursor.row }
        set { textCursor.row = newValue }
    }

    var cursorCol: Int {
        get { textCursor.col }
        set { textCursor.col = newValue }
    }

    var scrollOffset: Int {
        get { textCursor.scrollRow }
        set {
            textCursor.scrollRow = newValue
            wrapRowOffset = 0
        }
    }

    var wrapRowOffset: Int = 0

    var hScrollOffset: Int {
        get { textCursor.scrollCol }
        set { textCursor.scrollCol = newValue }
    }

    // MARK: - Active buffer synchronization

    func saveStateToActiveBuffer() {
        workspace.saveStateToActiveBuffer()
    }

    func restoreStateFromActiveBuffer() {
        workspace.restoreStateFromActiveBuffer()
    }

    func switchToTab(_ index: Int) {
        workspace.switchToTab(index)
    }

    func ensureActiveTabVisible(ribbonWidth: Int) {
        let tabs = tabRibbonTabs()
        let ribbon = TabRibbon(tabs: tabs, activeIndex: bufferManager.activeIndex, scrollOffset: tabScrollOffset)
        tabScrollOffset = ribbon.clampedScrollOffset(activeIndex: bufferManager.activeIndex, ribbonWidth: ribbonWidth)
    }

    func buildWrapCache(contentWidth: Int) {
        guard contentWidth > 0 else { return }

        let docVersion = bufferManager.activeBuffer?.documentVersion ?? 0
        let lineCount = fileLineCount
        let tabSize = config.editor.tabSize

        guard !wrapCache.isValid(contentWidth: contentWidth, tabSize: tabSize, documentVersion: docVersion, lineCount: lineCount) else {
            return
        }

        wrapCache.contentWidth = contentWidth
        wrapCache.tabSize = tabSize
        wrapCache.documentVersion = docVersion
        wrapCache.lineWrapCounts = (0..<lineCount).map { lineIndex in
            let line = fileLine(at: lineIndex)
            var rowCount = 1
            var currentRowWidth = 0
            for char in line {
                let width = char == "\t" ? tabSize - (currentRowWidth % tabSize) : UnicodeWidth.displayWidth(of: char)
                guard width > 0 else { continue }
                if currentRowWidth > 0, currentRowWidth + width > contentWidth {
                    rowCount += 1
                    currentRowWidth = 0
                }
                currentRowWidth += width
            }
            return rowCount
        }
        wrapCache.totalRowCount = wrapCache.lineWrapCounts.reduce(0, +)

        var offset = 0
        wrapCache.visualOffsets = [0]
        for i in 1..<lineCount {
            offset += wrapCache.lineWrapCounts[i - 1]
            wrapCache.visualOffsets.append(offset)
        }
    }

    func visualRowOffset(forLine lineIndex: Int) -> Int {
        guard lineIndex >= 0 && lineIndex < fileLineCount else { return 0 }
        guard lineIndex < wrapCache.visualOffsets.count else { return 0 }
        return wrapCache.visualOffsets[lineIndex]
    }

    func totalWrappedRowCount() -> Int {
        wrapCache.totalRowCount
    }

    func tabRibbonTabs() -> [TabRibbon.Tab] {
        bufferManager.buffers.map { buf in
            let status = config.git.enabled && config.git.decorations.showTabRibbonStatus
                ? fileStatusProvider?.status(for: buf.filePath)
                : nil
            return TabRibbon.Tab(
                name: buf.fileName,
                isDirty: buf.isDirty,
                isPreview: buf.isPreview,
                statusIndicator: status?.indicator.isEmpty == false ? status?.indicator : nil,
                statusStyle: status.map { colorScheme.gitStatusStyle(for: $0.statusColor) }
            )
        }
    }

    // MARK: - Remaining shell state

    var treePanelWidth = 30
    var fileVisibility: FileVisibility = .defaultHidden
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
    var lastRenderColumns = 80
    var lastRenderRows = 24
    var lastScrollDirection: MouseButton?
    var blockedMomentumDirection: MouseButton?
    var blockedMomentumDeadline: Date = .distantPast
    var scrollAccelerationDirection: MouseButton?
    var scrollAccelerationTarget: AcceleratedScrollTarget?
    var scrollAccelerationBurstCount = 0
    var scrollAccelerationLastEventAt: Date = .distantPast
    var pendingAcceleratedScrollLines = 0
    var pendingAcceleratedScrollTarget: AcceleratedScrollTarget?
    var scrollAccelerationTask: Task<Void, Never>?
    var isLoadingGrammar = false
    var wrapCache = WrapCache()
    var selection: TextSelection? {
        get { bufferManager.activeBuffer?.selection }
        set { bufferManager.activeBuffer?.selection = newValue }
    }
    var terminalWriter: (([UInt8]) -> Void)?
    var fileTreeHistory = FileTreeOperationHistory()

    var maxLineWidth: Int {
        cachedMaxLineWidth ?? 0
    }

    var hasActiveSelection: Bool {
        selection.map { !$0.isCollapsed } ?? false
    }

    func clearSelection() {
        selection = nil
    }

    init(rootPath: String, config: KittyConfig) {
        self.workspace = WorkspaceSession(rootPath: rootPath)
        self.bufferManager = workspace.bufferManager
        self.treeState = workspace.treeState
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        let catalog = config.useSFSymbolsInTerminal ? SymbolCatalogLoader.loadOrDiscover() : nil
        self.symbolTheme = TerminalSymbolTheme.make(symbolsEnabled: config.useSFSymbolsInTerminal, catalog: catalog)
        self.statusMessage = "Opened \(rootPath) | ^O Save | ^X Quit"

        // Wire up workspace callbacks
        workspace.onTabSwitched = { [weak self] in
            self?.gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
        }

        refreshHighlights()
    }

    func nextOpenRequestID() -> UInt64 {
        workspace.nextOpenRequestID()
    }

    func replaceFileOpenTask(with task: Task<Void, Never>) {
        workspace.replaceFileOpenTask(with: task)
    }

    func cancelPendingFileOpen() {
        workspace.cancelPendingFileOpen()
    }

    func isCurrentOpenRequest(_ requestID: UInt64) -> Bool {
        workspace.isCurrentOpenRequest(requestID)
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
        treeState.noteSelectedPath(path, isDirectory: isDirectory)
    }

    private func applyActiveBufferSnapshot(_ snapshot: BufferEditSnapshot) {
        textBuffer = snapshot.textBuffer
        textCursor = snapshot.textCursor
        currentLineEnding = snapshot.lineEnding
        invalidateTextSnapshotCache()
        cachedMaxLineWidth = TextDocument.computeMaxLineWidth(in: snapshot.textBuffer, tabSize: config.editor.tabSize)
        highlightSession = nil
        highlightedLines = []
        selection = nil
        wrapCache.invalidate()

        if let buffer = bufferManager.activeBuffer {
            buffer.postOpenProcessingTask?.cancel()
            buffer.postOpenProcessingTask = nil
            buffer.textBuffer = snapshot.textBuffer
            buffer.textCursor = snapshot.textCursor
            buffer.lineEnding = snapshot.lineEnding
            buffer.cachedFileLines = nil
            buffer.cachedDocumentText = nil
            buffer.cachedMaxLineWidth = cachedMaxLineWidth
            buffer.cachedSerializedByteCount = nil
            buffer.highlightedLines = []
            buffer.highlightSession = nil
            buffer.documentVersion += 1
            buffer.isDirty = buffer.editHistory.isDirty(current: snapshot)
        }

        refreshHighlights()
        gitDecorationManager?.scheduleRefreshForActiveBuffer()
        renderRefreshSource?.invalidate()
    }

    func undoActiveBuffer() {
        guard let buffer = bufferManager.activeBuffer,
              let currentSnapshot = activeBufferSnapshot()
        else {
            statusMessage = "No active buffer"
            return
        }

        switch buffer.editHistory.undo(current: currentSnapshot) {
        case .applied(let snapshot):
            applyActiveBufferSnapshot(snapshot)
            statusMessage = "Undo \(activeFileDisplayName)"
        case .unavailable:
            statusMessage = "Nothing to undo"
        case .invalidated:
            statusMessage = "Undo history cleared after external refresh"
        }
    }

    func redoActiveBuffer() {
        guard let buffer = bufferManager.activeBuffer,
              let currentSnapshot = activeBufferSnapshot()
        else {
            statusMessage = "No active buffer"
            return
        }

        switch buffer.editHistory.redo(current: currentSnapshot) {
        case .applied(let snapshot):
            applyActiveBufferSnapshot(snapshot)
            statusMessage = "Redo \(activeFileDisplayName)"
        case .unavailable:
            statusMessage = "Nothing to redo"
        case .invalidated:
            statusMessage = "Redo history cleared after external refresh"
        }
    }

    var isGitFilterAvailable: Bool {
        guard config.git.enabled, fileStatusProvider != nil else { return false }
        return FileManager.default.fileExists(atPath: (rootPath as NSString).appendingPathComponent(".gitignore"))
    }

    func cycleFileVisibility() async {
        switch fileVisibility {
        case .defaultHidden:
            if isGitFilterAvailable {
                let ignored = await GitIgnoreChecker.ignoredPaths(in: rootPath)
                fileVisibility = .gitFiltered(ignoredPaths: ignored)
            } else {
                fileVisibility = .showAll
            }
        case .gitFiltered:
            fileVisibility = .showAll
        case .showAll:
            fileVisibility = .defaultHidden
        }
        await loadInitialTree()
    }

    func applyConfig(_ newConfig: KittyConfig) {
        cancelPendingAcceleratedScroll(state: self, resetBurst: true)
        config = newConfig
        colorScheme = Self.makeColorScheme(config: newConfig)
        treePanelWidth = newConfig.treeWidth
        let catalog = newConfig.useSFSymbolsInTerminal ? SymbolCatalogLoader.loadOrDiscover() : nil
        symbolTheme = TerminalSymbolTheme.make(symbolsEnabled: newConfig.useSFSymbolsInTerminal, catalog: catalog)
        refreshHighlights()
    }
}
