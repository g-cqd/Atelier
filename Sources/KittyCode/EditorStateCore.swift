import Foundation
import KittyApp
import KittyCodecs
import KittyFileTree
import KittyGit
import KittySearch
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

        func isValid(contentWidth: Int, tabSize: Int, documentVersion: Int, lineCount: Int) -> Bool
        {
            self.contentWidth == contentWidth && self.tabSize == tabSize
                && self.documentVersion == documentVersion && lineWrapCounts.count == lineCount
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
        var searchMatch: Style
        var activeSearchMatch: Style
        var commandFeedback: Style

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
        case searchPanel
    }

    enum VimMode {
        case normal
        case insert
        case visual
        case visualLine
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
        case undo
        case redo
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

    enum SearchTarget: Sendable {
        case currentFile
        case workspace
    }

    enum SearchPanelFocus: Sendable {
        case findField
        case replaceField
        case resultsList
    }

    struct InFileSearch {
        var query: String
        var pattern: SearchPattern?
        var matches: [SearchMatch]
        var activeMatchIndex: Int
        var isCaseSensitive: Bool
        var isRegex: Bool
        var isWholeWord: Bool
        var replaceText: String = ""
        var showReplace: Bool = false

        var totalCount: Int { matches.count }
        var activeMatch: SearchMatch? {
            guard activeMatchIndex >= 0, activeMatchIndex < matches.count else { return nil }
            return matches[activeMatchIndex]
        }
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
        case search
    }

    var activeSidebarPanel: SidebarPanel = .explorer
    var sidebarCollapsed: Bool = false
    var openFilesScrollOffset: Int = 0
    var openFilesSelectedIndex: Int = 0
    var searchPanelScrollOffset: Int = 0
    var searchPanelSelectedIndex: Int = -1  // -1 = query field focused
    var searchPanelFocus: SearchPanelFocus = .findField
    var searchTarget: SearchTarget = .currentFile
    var workspaceSearchResults: [SearchFileResult] = []
    var workspaceSearchTask: Task<Void, Never>?
    var workspaceSearchSummary: String = ""
    var isSearchingWorkspace: Bool = false

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

    private static let viewportHighlightThreshold = 1000

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
            return
        }

        let lineCount = fileLineCount
        let source = documentText

        // For small files, highlight everything synchronously
        guard lineCount > Self.viewportHighlightThreshold else {
            highlightedLines = session.highlightDocument(source: source)
            return
        }

        // Viewport-first: highlight only visible lines, then schedule full in background
        let visibleStart = max(0, scrollOffset)
        let visibleEnd = min(lineCount, visibleStart + lastRenderRows + 20)
        let visibleRange = visibleStart..<visibleEnd

        // Start with plain text for all lines
        let defaultStyle = colorScheme.editorText
        var lines = fileContent.map { line in
            [StyledSpan(text: line, style: defaultStyle)]
        }

        // Highlight the viewport synchronously
        let viewportHighlights = session.highlightViewport(
            source: source, visibleLineRange: visibleRange)
        for (i, highlight) in viewportHighlights.enumerated() {
            let lineIdx = visibleStart + i
            if lineIdx < lines.count {
                lines[lineIdx] = highlight
            }
        }
        highlightedLines = lines

        // Schedule full document highlight in background
        fullHighlightTask?.cancel()
        fullHighlightTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Yield to let the viewport render first
            await Task.yield()
            guard !Task.isCancelled else { return }

            let fullHighlights = session.highlightDocument(source: source)
            guard !Task.isCancelled else { return }

            // Only apply if we're still on the same document
            if self.documentText == source {
                self.highlightedLines = fullHighlights
                self.renderRefreshSource?.invalidate()
            }
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
        if !syntaxHighlightingEnabled {
            refreshPlainHighlights(after: mutation)
            return
        }
        let session = currentHighlightSession()
        guard session.prefersLineInput else {
            refreshHighlights()
            return
        }

        let lines = fileContent
        guard isMutationApplicable(mutation, lineCount: lines.count) else {
            refreshHighlights()
            return
        }

        let updatedHighlights = session.highlightLines(lines[mutation.updatedLineRange])
        highlightedLines.replaceSubrange(mutation.originalLineRange, with: updatedHighlights)
    }

    /// Plain-text refresh that only touches the lines covered by `mutation`.
    /// Avoids rebuilding the full `highlightedLines` array on every keystroke
    /// when syntax highlighting is off.
    private func refreshPlainHighlights(after mutation: TextMutation) {
        let lines = fileContent
        guard isMutationApplicable(mutation, lineCount: lines.count) else {
            refreshHighlights()
            return
        }
        let style = colorScheme.editorText
        let replacement = lines[mutation.updatedLineRange].map { line in
            [StyledSpan(text: line, style: style)]
        }
        highlightedLines.replaceSubrange(mutation.originalLineRange, with: replacement)
    }

    private func isMutationApplicable(_ mutation: TextMutation, lineCount: Int) -> Bool {
        mutation.originalLineRange.lowerBound >= 0
            && mutation.originalLineRange.upperBound <= highlightedLines.count
            && mutation.updatedLineRange.lowerBound >= 0
            && mutation.updatedLineRange.upperBound <= lineCount
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
            cachedMaxLineWidth = TextDocument.computeMaxLineWidth(
                for: normalizedLines, tabSize: config.editor.tabSize)
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
            lineEnding: currentLineEnding,
            selection: selection
        )
    }

    private var bufferUndoCoalescingWindow: TimeInterval? {
        guard config.editor.undoCoalescingEnabled else { return nil }
        return Double(max(0, config.editor.undoCoalescingMilliseconds)) / 1_000
    }

    func textDidChange(previousSnapshot: BufferEditSnapshot? = nil) {
        guard !readOnly else {
            statusMessage = "Read-only mode"
            return
        }
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
        // Unknown mutation footprint → conservative full content repaint.
        markContentAllDirty()
    }

    func textDidChange(_ mutation: TextMutation, previousSnapshot: BufferEditSnapshot? = nil) {
        guard !readOnly else {
            statusMessage = "Read-only mode"
            return
        }
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
        // If the mutation kept the line count stable, only the affected lines
        // need a repaint. Anything that shifts line count downstream requires
        // a full content repaint because line→screen-row mapping changes.
        if mutation.originalLineRange.count == mutation.updatedLineRange.count {
            markLinesDirty(mutation.updatedLineRange)
        } else {
            markContentAllDirty()
        }
    }

    func replaceDocumentText(with content: String) {
        workspace.replaceDocumentText(
            with: content, tabSize: config.editor.tabSize, lineEnding: currentLineEnding)
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
            guard textCursor.scrollRow != newValue else { return }
            textCursor.scrollRow = newValue
            wrapRowOffset = 0
            // A vertical scroll shifts every visible line; full content repaint
            // (until Phase 4 introduces the slide-via-ScrollHint fast path).
            markContentAllDirty()
        }
    }

    var wrapRowOffset: Int = 0 {
        didSet {
            if wrapRowOffset != oldValue { markContentAllDirty() }
        }
    }

    var hScrollOffset: Int {
        get { textCursor.scrollCol }
        set {
            guard textCursor.scrollCol != newValue else { return }
            textCursor.scrollCol = newValue
            markContentAllDirty()
        }
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
        let ribbon = TabRibbon(
            tabs: tabs, activeIndex: bufferManager.activeIndex, scrollOffset: tabScrollOffset)
        tabScrollOffset = ribbon.clampedScrollOffset(
            activeIndex: bufferManager.activeIndex, ribbonWidth: ribbonWidth)
    }

    func buildWrapCache(contentWidth: Int) {
        guard contentWidth > 0 else { return }

        let docVersion = bufferManager.activeBuffer?.documentVersion ?? 0
        let lineCount = fileLineCount
        let tabSize = config.editor.tabSize

        guard
            !wrapCache.isValid(
                contentWidth: contentWidth, tabSize: tabSize, documentVersion: docVersion,
                lineCount: lineCount)
        else {
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
                let width =
                    char == "\t"
                    ? tabSize - (currentRowWidth % tabSize) : UnicodeWidth.displayWidth(of: char)
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

    func lineAndWrapRowOffset(forVisualRowOffset visualRowOffset: Int) -> (line: Int, wrapRow: Int) {
        guard !wrapCache.visualOffsets.isEmpty else { return (0, 0) }

        let target = max(0, visualRowOffset)
        var low = 0
        var high = wrapCache.visualOffsets.count - 1

        while low <= high {
            let mid = (low + high) / 2
            if wrapCache.visualOffsets[mid] <= target {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let lineIndex = max(0, min(high, wrapCache.visualOffsets.count - 1))
        let lineStart = wrapCache.visualOffsets[lineIndex]
        let rowCount =
            wrapCache.lineWrapCounts.indices.contains(lineIndex)
            ? wrapCache.lineWrapCounts[lineIndex] : 1
        let wrapRow = min(max(0, target - lineStart), max(0, rowCount - 1))
        return (lineIndex, wrapRow)
    }

    func wrapLayoutCacheSnapshot() -> TextEditor.WrapLayoutCache? {
        guard wrapCache.contentWidth > 0 else { return nil }
        guard wrapCache.lineWrapCounts.count == fileLineCount else { return nil }
        guard wrapCache.visualOffsets.count == fileLineCount else { return nil }

        return TextEditor.WrapLayoutCache(
            contentWidth: wrapCache.contentWidth,
            tabSize: wrapCache.tabSize,
            lineCount: fileLineCount,
            totalRowCount: wrapCache.totalRowCount,
            lineWrapCounts: wrapCache.lineWrapCounts,
            visualOffsets: wrapCache.visualOffsets
        )
    }

    func resolvedWrapContentWidth(columns: Int, rows: Int) -> Int {
        let layout = LayoutMetrics(
            state: self,
            columns: max(1, columns),
            rows: max(2, rows)
        )
        let lineNumberWidth = max(
            3, TextDisplayMetrics.lineNumberDigits(forLineCount: fileLineCount) + 1)
        let gutterDecorationWidth =
            (config.git.enabled && config.git.decorations.showLineChanges
                && gitLineDecorationProvider != nil) ? 2 : 0
        let gutterWidth = gutterDecorationWidth + lineNumberWidth

        let pessimisticContentWidth = max(1, layout.editorWidth - gutterWidth - 1)
        buildWrapCache(contentWidth: pessimisticContentWidth)

        guard wrapCache.totalRowCount <= layout.contentRows else {
            return pessimisticContentWidth
        }

        let fullWidthContent = max(1, layout.editorWidth - gutterWidth)
        if fullWidthContent != pessimisticContentWidth {
            buildWrapCache(contentWidth: fullWidthContent)
        }
        return fullWidthContent
    }

    func tabRibbonTabs() -> [TabRibbon.Tab] {
        bufferManager.buffers.map { buf in
            let status =
                config.git.enabled && config.git.decorations.showTabRibbonStatus
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
    var vimCommandLine: VimCommandLine?
    var inFileSearch: InFileSearch?
    var contextMenu: ContextMenuState?
    var mode: Mode = .tree {
        didSet {
            if mode != oldValue {
                markChromeDirty()
                // Cursor presence depends on mode, so the content area also
                // needs a repaint to remove or add the cursor cell.
                markContentAllDirty()
            }
        }
    }
    var vimMode: VimMode = .normal
    var vimVisualAnchor: (line: Int, col: Int)?
    var symbolTheme: TerminalSymbolTheme
    var lastClickTime: ContinuousClock.Instant?
    var lastClickIndex = -1
    var isScrolling = false
    var scrollDragState: ScrollDragState?
    var focusMap: FocusMap?
    var lastRenderColumns = 80
    var lastRenderRows = 24
    var lastScrollDirection: MouseButton?
    var blockedMomentumDirection: MouseButton?
    var blockedMomentumDeadline: ContinuousClock.Instant?
    var scrollAccelerationDirection: MouseButton?
    var scrollAccelerationTarget: AcceleratedScrollTarget?
    var scrollAccelerationBurstCount = 0
    var scrollAccelerationLastEventAt: ContinuousClock.Instant?
    var pendingAcceleratedScrollLines = 0
    var pendingAcceleratedScrollTarget: AcceleratedScrollTarget?
    var scrollAccelerationTask: Task<Void, Never>?
    var isLoadingGrammar = false
    var marqueeTickOffset: Int = 0
    var marqueeTimer: Task<Void, Never>?
    var marqueeTargetLabel: String?
    var wrapCache = WrapCache()

    // MARK: - Dirty tracking (Phase 2)
    //
    // Logical-coordinate dirty state. Drained at the start of each render
    // frame and translated into pipeline-level `DirtyRegions`. Phase 2 just
    // collects the markers; Phase 3 makes the renderer act on them.

    /// Buffer-line indices whose content has changed and need repaint.
    var dirtyContentLines = Set<Int>()
    /// Whole editor content area must be repainted (e.g. scroll, file switch).
    var dirtyContentAll = true
    /// Sidebar / status bar / tab ribbon must be repainted.
    var dirtyChrome = true

    /// Marks every logical line in `range` as dirty.
    func markLinesDirty(_ range: Range<Int>) {
        guard !dirtyContentAll else { return }
        for line in range { dirtyContentLines.insert(line) }
    }

    /// Marks the entire editor content area as dirty. Supersedes per-line marks.
    func markContentAllDirty() {
        dirtyContentAll = true
        dirtyContentLines.removeAll(keepingCapacity: true)
    }

    /// Marks the chrome (sidebar, status bar, tabs) as dirty.
    func markChromeDirty() {
        dirtyChrome = true
    }

    /// Marks both content and chrome as fully dirty (resize, theme change).
    func markEverythingDirty() {
        markContentAllDirty()
        markChromeDirty()
    }

    /// Snapshots and clears the dirty markers. Called by the render frame
    /// once it has translated logical dirty state into pipeline rects.
    func drainDirtyState() -> (contentAll: Bool, contentLines: Set<Int>, chrome: Bool) {
        let snapshot = (dirtyContentAll, dirtyContentLines, dirtyChrome)
        dirtyContentLines.removeAll(keepingCapacity: true)
        dirtyContentAll = false
        dirtyChrome = false
        return snapshot
    }

    var selection: TextSelection? {
        get { bufferManager.activeBuffer?.selection }
        set { bufferManager.activeBuffer?.selection = newValue }
    }
    var terminalWriter: (([UInt8]) -> Void)?
    var readOnly: Bool = false
    var commandFeedback: String?
    var commandFeedbackExpiry: ContinuousClock.Instant?
    var lastKeyRepeatProcessedAt: ContinuousClock.Instant?
    var pendingKeySequence: [KeyStroke] = []
    var pendingKeySequenceTime: ContinuousClock.Instant?
    var fullHighlightTask: Task<Void, Never>?
    var fileTreeHistory = FileTreeOperationHistory()

    var maxLineWidth: Int {
        if let cachedMaxLineWidth {
            return cachedMaxLineWidth
        }

        let computed = TextDocument.computeMaxLineWidth(
            in: textBuffer, tabSize: config.editor.tabSize)
        cachedMaxLineWidth = computed
        return computed
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
        self.symbolTheme = TerminalSymbolTheme.make(
            symbolsEnabled: config.useSFSymbolsInTerminal, catalog: catalog)
        self.fileTreeHistory.maxOperationSteps = config.editor.maxTreeUndoSteps
        let resolver = KeymapResolver(config: config)
        self.statusMessage = "Opened \(rootPath) | \(resolver.openedStatusHints())"

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
        guard let cachedWidth = cachedMaxLineWidth else {
            cachedMaxLineWidth = TextDocument.computeMaxLineWidth(
                in: textBuffer, tabSize: config.editor.tabSize)
            return
        }

        let lowerBound = max(0, range.lowerBound)
        let upperBound = min(fileLineCount, range.upperBound)
        guard lowerBound < upperBound else { return }

        let widenedWidth = (lowerBound..<upperBound).reduce(0) { partial, lineIndex in
            max(partial, UnicodeWidth.displayWidth(of: textBuffer.line(at: lineIndex)))
        }

        cachedMaxLineWidth = max(cachedWidth, widenedWidth)
    }

    func noteSelectedPath(_ path: String, isDirectory: Bool) {
        treeState.noteSelectedPath(path, isDirectory: isDirectory)
    }

    private func applyActiveBufferSnapshot(_ snapshot: BufferEditSnapshot) {
        textBuffer = snapshot.textBuffer
        textCursor = snapshot.textCursor
        currentLineEnding = snapshot.lineEnding
        invalidateTextSnapshotCache()
        cachedMaxLineWidth = TextDocument.computeMaxLineWidth(
            in: snapshot.textBuffer, tabSize: config.editor.tabSize)
        highlightSession = nil
        highlightedLines = []
        selection = snapshot.selection
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
            switch buffer.editHistory.lastInvalidationReason {
            case .externalFileChange:
                statusMessage = "Undo history cleared after external file change"
            case .fingerprintMismatch:
                statusMessage = "Undo history cleared (buffer content diverged)"
            case nil:
                statusMessage = "Undo history cleared"
            }
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
            switch buffer.editHistory.lastInvalidationReason {
            case .externalFileChange:
                statusMessage = "Redo history cleared after external file change"
            case .fingerprintMismatch:
                statusMessage = "Redo history cleared (buffer content diverged)"
            case nil:
                statusMessage = "Redo history cleared"
            }
        }
    }

    var isGitFilterAvailable: Bool {
        guard config.git.enabled, fileStatusProvider != nil else { return false }
        return FileManager.default.fileExists(
            atPath: (rootPath as NSString).appendingPathComponent(".gitignore"))
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
        symbolTheme = TerminalSymbolTheme.make(
            symbolsEnabled: newConfig.useSFSymbolsInTerminal, catalog: catalog)
        refreshHighlights()
    }
}
