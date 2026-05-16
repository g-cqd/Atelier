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
import Observation
import System
import os

/// Signpost emitter for editor hot paths — wraps `textDidChange` and the
/// wrap-cache rebuild so Instruments traces can attribute frame-budget
/// overruns to specific subsystems. Audit D10 (mirrors the pattern in
/// `RenderPipeline.swift`).
private let editorSignposter = OSSignposter(
    subsystem: "com.kittytui.editor", category: "edit")

@Observable
@MainActor
public final class EditorState {
    public enum AcceleratedScrollTarget: Sendable {
        case tree
        case editor
    }

    public struct WrapCache: Sendable {
        public var contentWidth: Int = -1
        public var tabSize: Int = -1
        public var documentVersion: Int = 0
        public var totalRowCount: Int = 0
        public var lineWrapCounts: [Int] = []
        public var visualOffsets: [Int] = []

        mutating func invalidate() {
            contentWidth = -1
            tabSize = -1
            documentVersion = 0
            totalRowCount = 0
            lineWrapCounts.removeAll(keepingCapacity: true)
            visualOffsets.removeAll(keepingCapacity: true)
        }

        public func isValid(contentWidth: Int, tabSize: Int, documentVersion: Int, lineCount: Int) -> Bool
        {
            self.contentWidth == contentWidth && self.tabSize == tabSize
                && self.documentVersion == documentVersion && lineWrapCounts.count == lineCount
        }

        /// Pure helper: how many wrapped rows does `line` produce at the given
        /// `contentWidth` and `tabSize`? Used both by the full rebuild path in
        /// `buildWrapCache` and the incremental patch path in `invalidateLines`.
        public static func wrapCount(of line: String, contentWidth: Int, tabSize: Int) -> Int {
            var rowCount = 1
            var currentRowWidth = 0
            for char in line {
                let width: Int =
                    char == "\t"
                    ? tabSize - (currentRowWidth % tabSize)
                    : UnicodeWidth.displayWidth(of: char)
                guard width > 0 else { continue }
                if currentRowWidth > 0, currentRowWidth + width > contentWidth {
                    rowCount += 1
                    currentRowWidth = 0
                }
                currentRowWidth += width
            }
            return rowCount
        }

        /// Incrementally re-wraps only the lines affected by `mutation` instead
        /// of clearing the entire cache and forcing a full rebuild on the next
        /// frame. Falls back to `invalidate()` when an invariant (contentWidth /
        /// tabSize / array length) doesn't match — those cases need a full
        /// rebuild anyway. Called from `textDidChange(_ mutation:)`; the wholesale
        /// `invalidate()` is kept for the no-mutation `textDidChange()` overload
        /// where the mutation footprint is unknown.
        mutating func invalidateLines(
            mutation: TextMutation,
            newDocumentVersion: Int,
            tabSize: Int,
            computeWrapCount: (Int) -> Int
        ) {
            guard contentWidth > 0, self.tabSize == tabSize else {
                invalidate()
                return
            }
            let original = mutation.originalLineRange
            let updated = mutation.updatedLineRange
            guard original.upperBound <= lineWrapCounts.count else {
                invalidate()
                return
            }

            // Delta on the row total is `newSum - oldSum` over the spliced range.
            var oldSum = 0
            for index in original { oldSum += lineWrapCounts[index] }
            let newWraps = updated.map(computeWrapCount)
            let newSum = newWraps.reduce(0, +)

            lineWrapCounts.replaceSubrange(original, with: newWraps)
            totalRowCount += newSum - oldSum

            // Visual offsets are a prefix sum of `lineWrapCounts`. Lines below
            // `original.lowerBound` are unchanged; the rest are recomputed.
            let startLine = original.lowerBound
            if visualOffsets.count < startLine {
                invalidate()
                return
            }
            if visualOffsets.count > startLine {
                visualOffsets.removeLast(visualOffsets.count - startLine)
            }
            if startLine == 0 {
                visualOffsets.append(0)
            }
            let newLineCount = lineWrapCounts.count
            while visualOffsets.count < newLineCount {
                let prev = visualOffsets.count - 1
                visualOffsets.append(visualOffsets[prev] + lineWrapCounts[prev])
            }

            documentVersion = newDocumentVersion
        }
    }

    public struct ColorScheme {
        public var bg: Style
        public var treeBg: Style
        public var treeSelected: Style
        public var treeDir: Style
        public var lineNumber: Style
        public var editorText: Style
        public var editorCursorLine: Style
        public var gitModifiedLine: TextStyleOverlay
        public var gitAddedLine: TextStyleOverlay
        public var gitUntrackedLine: TextStyleOverlay
        public var gitDeletedLine: TextStyleOverlay
        public var gitConflictedLine: TextStyleOverlay
        public var statusBar: Style
        public var titleBar: Style
        public var separator: Style
        public var syntaxKeyword: Style
        public var syntaxType: Style
        public var syntaxComment: Style
        public var syntaxString: Style
        public var syntaxNumber: Style
        public var syntaxAttribute: Style
        public var gitModified: Style
        public var gitAdded: Style
        public var gitUntracked: Style
        public var gitDeleted: Style
        public var gitConflicted: Style
        public var whitespaceIndentation: Style
        public var whitespaceSpace: Style
        public var whitespaceLineBreak: Style
        public var whitespaceUnexpected: Style
        public var verticalScrollIndicator: VerticalScrollIndicatorStyle
        public var horizontalScrollIndicator: HorizontalScrollIndicatorStyle
        public var emptyEditorMessage: Style
        public var selection: Style
        public var searchMatch: Style
        public var activeSearchMatch: Style
        public var commandFeedback: Style

        public func gitStatusStyle(for color: FileStatusColor) -> Style {
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

        public func gitLineOverlay(for color: FileStatusColor) -> TextStyleOverlay {
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

    public enum Mode {
        case tree
        case editor
        case searchPanel
    }

    public enum VimMode {
        case normal
        case insert
        case visual
        case visualLine
    }

    public enum ContextMenuTarget: Equatable {
        case editor
        case treeNode(index: Int)
    }

    public enum ContextMenuAction: Equatable {
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

    public struct ContextMenuItem: Equatable {
        public var title: String
        public var shortcut: String
        public var action: ContextMenuAction
    }

    public struct ContextMenuState: Equatable {
        public var title: String
        public var subtitle: String?
        public var target: ContextMenuTarget
        public var items: [ContextMenuItem]
        public var selectedIndex: Int = 0
    }

    public enum ScrollDragTarget: Equatable {
        case tree
        case editor
        case editorHorizontal
    }

    public struct ScrollDragState: Equatable {
        public var target: ScrollDragTarget
        public var gripOffset: Int
    }

    public enum SearchTarget: Sendable {
        case currentFile
        case workspace
    }

    public enum SearchPanelFocus: Sendable {
        case findField
        case replaceField
        case resultsList
    }

    public struct InFileSearch {
        public var query: String
        public var pattern: SearchPattern?
        public var matches: [SearchMatch]
        public var activeMatchIndex: Int
        public var isCaseSensitive: Bool
        public var isRegex: Bool
        public var isWholeWord: Bool
        public var replaceText: String = ""
        public var showReplace: Bool = false

        public var totalCount: Int { matches.count }
        public var activeMatch: SearchMatch? {
            guard activeMatchIndex >= 0, activeMatchIndex < matches.count else { return nil }
            return matches[activeMatchIndex]
        }
    }

    // MARK: - Workspace (domain state)

    public let workspace: WorkspaceSession

    // MARK: - Shell state

    public var config: KittyConfig
    @ObservationIgnored public var fileStatusProvider: (any FileStatusProvider)?
    @ObservationIgnored public var gitLineDecorationProvider: (any GitLineDecorationProvider)?
    @ObservationIgnored public var gitDecorationManager: GitDecorationManager?
    @ObservationIgnored public var renderRefreshSource: RenderRefreshSource?
    /// Observation-aware tick source. When non-nil, every `mark*Dirty` call
    /// advances it; an observation-listener task in `ApplicationRuntime` then
    /// injects an `.refresh` input event so the existing event loop renders
    /// the next frame. Lets us drop ad-hoc `renderRefreshSource.invalidate()`
    /// calls from async completion sites — the dirty marker that already
    /// runs there is enough.
    @ObservationIgnored public var renderClock: RenderClock?
    @ObservationIgnored public weak var fileWatcherIntegration: FileWatcherIntegration?
    public var colorScheme: ColorScheme {
        didSet {
            highlightSession = nil
            cachedSyntaxTheme = nil
        }
    }
    public var tabScrollOffset: Int = 0 {
        didSet { if tabScrollOffset != oldValue { markChromeDirty() } }
    }

    // MARK: - Forwarding properties to workspace

    public var rootPath: String {
        get { workspace.rootPath }
        set { workspace.rootPath = newValue }
    }

    public let bufferManager: BufferManager

    public var textBuffer: TextBuffer {
        get { workspace.textBuffer }
        set { workspace.textBuffer = newValue }
    }

    public var textCursor: TextCursor {
        get { workspace.textCursor }
        set { workspace.textCursor = newValue }
    }

    public var currentLanguage: String? {
        get { workspace.currentLanguage }
        set {
            if workspace.currentLanguage != newValue {
                workspace.highlightSession = nil
            }
            workspace.currentLanguage = newValue
        }
    }

    public var highlightedLines: [[StyledSpan]] {
        get { workspace.highlightedLines }
        // No didSet here: in-place mutations via `replaceSubrange` (see
        // `refreshPlainHighlights`) also route through this setter and would
        // wrongly escalate per-line dirty marks to contentAll. Wholesale
        // reassignment sites (async post-load, full-document highlight,
        // file watcher reload) mark dirty explicitly.
        set { workspace.highlightedLines = newValue }
    }

    public var highlightSession: LanguageHighlighter.Session? {
        get { workspace.highlightSession }
        set { workspace.highlightSession = newValue }
    }

    public var currentLineEnding: TextDocument.LineEnding {
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

    public var cachedMaxLineWidth: Int? {
        get { workspace.cachedMaxLineWidth }
        set { workspace.cachedMaxLineWidth = newValue }
    }

    public var fileName: String {
        get { workspace.fileName }
        set { workspace.fileName = newValue }
    }

    public var filePath: String {
        get { workspace.filePath }
        set { workspace.filePath = newValue }
    }

    // MARK: - Tree state forwarding

    public let treeState: WorkspaceTreeState

    public var treeNodes: [FileNode] {
        get { treeState.treeNodes }
        set {
            treeState.treeNodes = newValue
            markChromeDirty()
        }
    }
    public var cachedFlatTree: [(depth: Int, node: FileNode)] {
        get { treeState.cachedFlatTree }
        set {
            treeState.cachedFlatTree = newValue
            markChromeDirty()
        }
    }
    public var selectedTreeIndex: Int {
        get { treeState.selectedTreeIndex }
        set {
            guard treeState.selectedTreeIndex != newValue else { return }
            treeState.selectedTreeIndex = newValue
            markChromeDirty()
        }
    }
    public var treeScrollOffset: Int {
        get { treeState.treeScrollOffset }
        set {
            guard treeState.treeScrollOffset != newValue else { return }
            treeState.treeScrollOffset = newValue
            // Tree lives in the sidebar (chrome rect).
            markChromeDirty()
        }
    }
    public var lastSelectedDirectoryPath: String? {
        get { treeState.lastSelectedDirectoryPath }
        set { treeState.lastSelectedDirectoryPath = newValue }
    }

    // MARK: - Activity bar & sidebar

    public enum SidebarPanel {
        case explorer
        case openDocuments
        case search
    }

    public var activeSidebarPanel: SidebarPanel = .explorer {
        didSet { if activeSidebarPanel != oldValue { markChromeDirty() } }
    }
    public var sidebarCollapsed: Bool = false {
        // Collapsing/expanding the sidebar shifts the editor's horizontal
        // origin, so both chrome and content layout change.
        didSet { if sidebarCollapsed != oldValue { markEverythingDirty() } }
    }
    public var openFilesScrollOffset: Int = 0 {
        didSet { if openFilesScrollOffset != oldValue { markChromeDirty() } }
    }
    public var openFilesSelectedIndex: Int = 0 {
        didSet { if openFilesSelectedIndex != oldValue { markChromeDirty() } }
    }
    public var searchPanelScrollOffset: Int = 0 {
        didSet { if searchPanelScrollOffset != oldValue { markChromeDirty() } }
    }
    public var searchPanelSelectedIndex: Int = -1 {  // -1 = query field focused
        didSet { if searchPanelSelectedIndex != oldValue { markChromeDirty() } }
    }
    public var searchPanelFocus: SearchPanelFocus = .findField {
        didSet { if searchPanelFocus != oldValue { markChromeDirty() } }
    }
    public var searchTarget: SearchTarget = .currentFile {
        didSet { if searchTarget != oldValue { markChromeDirty() } }
    }
    public var workspaceSearchResults: [SearchFileResult] = [] {
        didSet { markChromeDirty() }
    }
    @ObservationIgnored public var workspaceSearchTask: Task<Void, Never>?
    /// Long-lived consumer that debounces workspace-search-as-you-type
    /// signals. The producer (`triggerWorkspaceSearchDebounced`) yields a
    /// tick on every find-field keystroke; the consumer sleeps the
    /// configured debounce window and then runs `triggerWorkspaceSearch`.
    /// `bufferingNewest(1)` collapses bursts of keystrokes into a single
    /// work cycle. Mirrors `GitDecorationManager.debouncedConsumer`
    /// (audit NF12 / A9).
    @ObservationIgnored public var workspaceSearchDebounceTask: Task<Void, Never>?
    @ObservationIgnored public let workspaceSearchDebounceSignal: AsyncStream<Void>
    @ObservationIgnored public let workspaceSearchDebounceContinuation:
        AsyncStream<Void>.Continuation
    public var workspaceSearchSummary: String = "" {
        didSet { if workspaceSearchSummary != oldValue { markChromeDirty() } }
    }
    public var isSearchingWorkspace: Bool = false {
        didSet { if isSearchingWorkspace != oldValue { markChromeDirty() } }
    }

    // MARK: - Highlighted document

    public func highlightedLine(at index: Int) -> [StyledSpan] {
        guard index >= 0 && index < highlightedLines.count else {
            return [StyledSpan(text: "", style: syntaxTheme.defaultStyle)]
        }
        return highlightedLines[index]
    }

    /// Cached syntax theme. The 22-call `setStyle` build is non-trivial and
    /// `syntaxTheme` is read once per render line plus per edit — without
    /// caching we'd rebuild ~1 000 themes per frame on a 1 000-line file.
    /// Recomputed when `colorScheme.didSet` fires (theme switch / config
    /// reload) — see init and `applyConfig`.
    @ObservationIgnored private var cachedSyntaxTheme: Theme?

    public var syntaxTheme: Theme {
        if let cached = cachedSyntaxTheme { return cached }
        let theme = Self.makeSyntaxTheme(from: colorScheme)
        cachedSyntaxTheme = theme
        return theme
    }

    private static func makeSyntaxTheme(from colorScheme: ColorScheme) -> Theme {
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

    public func refreshHighlights() {
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

        // Schedule the background full-document highlight via the
        // long-lived consumer. The producer doesn't spawn anything; the
        // consumer re-reads MainActor state at work time, so a burst of
        // keystrokes coalesces into at most one full-highlight pass.
        fullHighlightContinuation.yield(())
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

    public var fileContent: [String] {
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

    public var documentText: String {
        if let cachedDocumentText {
            return cachedDocumentText
        }

        let text = textBuffer.text
        cachedDocumentText = text
        return text
    }

    public var fileLineCount: Int {
        textBuffer.lineCount
    }

    public var isFileEmpty: Bool {
        textBuffer.isEmpty
    }

    public func fileLine(at index: Int) -> String {
        textBuffer.line(at: index)
    }

    public func invalidateTextSnapshotCache() {
        workspace.invalidateTextSnapshotCache()
    }

    public func invalidateHighlightSession() {
        workspace.invalidateHighlightSession()
    }

    public func activeBufferSnapshot() -> BufferEditSnapshot? {
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

    public func textDidChange(previousSnapshot: BufferEditSnapshot? = nil) {
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

    public func textDidChange(_ mutation: TextMutation, previousSnapshot: BufferEditSnapshot? = nil) {
        let interval = editorSignposter.beginInterval("textDidChange")
        defer { editorSignposter.endInterval("textDidChange", interval) }

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
        // Patch only the affected lines in the wrap cache. Falls back to a
        // full invalidation when the cache invariants don't match (e.g. the
        // first edit before a viewport has computed `contentWidth`).
        let tabSize = config.editor.tabSize
        let contentWidth = wrapCache.contentWidth
        let nextDocVersion = bufferManager.activeBuffer?.documentVersion ?? 0
        wrapCache.invalidateLines(
            mutation: mutation,
            newDocumentVersion: nextDocVersion,
            tabSize: tabSize
        ) { lineIndex in
            WrapCache.wrapCount(
                of: fileLine(at: lineIndex),
                contentWidth: contentWidth,
                tabSize: tabSize)
        }
        // If the mutation kept the line count stable, only the affected lines
        // need a repaint. Anything that shifts line count downstream requires
        // a full content repaint because line→screen-row mapping changes.
        if mutation.originalLineRange.count == mutation.updatedLineRange.count {
            markLinesDirty(mutation.updatedLineRange)
        } else {
            markContentAllDirty()
        }
    }

    public func replaceDocumentText(with content: String) {
        workspace.replaceDocumentText(
            with: content, tabSize: config.editor.tabSize, lineEnding: currentLineEnding)
    }

    public var serializedByteCount: Int {
        workspace.serializedByteCount
    }

    public var cursorRow: Int {
        get { textCursor.row }
        set { textCursor.row = newValue }
    }

    public var cursorCol: Int {
        get { textCursor.col }
        set { textCursor.col = newValue }
    }

    public var scrollOffset: Int {
        get { textCursor.scrollRow }
        set {
            let oldValue = textCursor.scrollRow
            guard oldValue != newValue else { return }
            textCursor.scrollRow = newValue
            wrapRowOffset = 0
            markScrollDirty(from: oldValue, to: newValue)
        }
    }

    /// Marks only the newly exposed buffer lines when scrolling vertically.
    /// Falls back to a full content repaint when the delta is larger than the
    /// estimated visible area (in which case sliding offers no win).
    private func markScrollDirty(from oldOffset: Int, to newOffset: Int) {
        let visibleRows = max(0, lastRenderRows - 2)
        let delta = newOffset - oldOffset
        guard visibleRows > 0, delta != 0, abs(delta) < visibleRows else {
            markContentAllDirty()
            return
        }
        let exposed: Range<Int>
        if delta > 0 {
            // Scrolling down: the new bottom strip exposes [old+visible, new+visible).
            exposed = (oldOffset + visibleRows)..<(newOffset + visibleRows)
        } else {
            // Scrolling up: the new top strip exposes [new, old).
            exposed = newOffset..<oldOffset
        }
        markLinesDirty(exposed)
    }

    public var wrapRowOffset: Int = 0 {
        didSet {
            if wrapRowOffset != oldValue { markContentAllDirty() }
        }
    }

    public var hScrollOffset: Int {
        get { textCursor.scrollCol }
        set {
            guard textCursor.scrollCol != newValue else { return }
            textCursor.scrollCol = newValue
            markContentAllDirty()
        }
    }

    // MARK: - Active buffer synchronization

    public func saveStateToActiveBuffer() {
        workspace.saveStateToActiveBuffer()
    }

    public func restoreStateFromActiveBuffer() {
        workspace.restoreStateFromActiveBuffer()
    }

    public func switchToTab(_ index: Int) {
        workspace.switchToTab(index)
        markEverythingDirty()
    }

    public func ensureActiveTabVisible(ribbonWidth: Int) {
        let tabs = tabRibbonTabs()
        let ribbon = TabRibbon(
            tabs: tabs, activeIndex: bufferManager.activeIndex, scrollOffset: tabScrollOffset)
        tabScrollOffset = ribbon.clampedScrollOffset(
            activeIndex: bufferManager.activeIndex, ribbonWidth: ribbonWidth)
    }

    public func buildWrapCache(contentWidth: Int) {
        let interval = editorSignposter.beginInterval("buildWrapCache")
        defer { editorSignposter.endInterval("buildWrapCache", interval) }

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
            WrapCache.wrapCount(
                of: fileLine(at: lineIndex), contentWidth: contentWidth, tabSize: tabSize)
        }
        wrapCache.totalRowCount = wrapCache.lineWrapCounts.reduce(0, +)

        var offset = 0
        wrapCache.visualOffsets = [0]
        for i in 1..<lineCount {
            offset += wrapCache.lineWrapCounts[i - 1]
            wrapCache.visualOffsets.append(offset)
        }
    }

    public func visualRowOffset(forLine lineIndex: Int) -> Int {
        guard lineIndex >= 0 && lineIndex < fileLineCount else { return 0 }
        guard lineIndex < wrapCache.visualOffsets.count else { return 0 }
        return wrapCache.visualOffsets[lineIndex]
    }

    public func totalWrappedRowCount() -> Int {
        wrapCache.totalRowCount
    }

    public func lineAndWrapRowOffset(forVisualRowOffset visualRowOffset: Int) -> (line: Int, wrapRow: Int) {
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

    public func wrapLayoutCacheSnapshot() -> TextEditor.WrapLayoutCache? {
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

    public func resolvedWrapContentWidth(columns: Int, rows: Int) -> Int {
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

    public func tabRibbonTabs() -> [TabRibbon.Tab] {
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

    public var treePanelWidth = 30
    public var fileVisibility: FileVisibility = .defaultHidden
    public var statusMessage = "" {
        didSet { if statusMessage != oldValue { markChromeDirty() } }
    }
    public var prompt: EditorPrompt? {
        didSet { markEverythingDirty() }
    }
    public var vimCommandLine: VimCommandLine? {
        didSet { markChromeDirty() }
    }
    public var inFileSearch: InFileSearch? {
        didSet { markEverythingDirty() }
    }
    public var contextMenu: ContextMenuState? {
        didSet { markEverythingDirty() }
    }
    public var mode: Mode = .tree {
        didSet {
            if mode != oldValue {
                markChromeDirty()
                // Cursor presence depends on mode, so the content area also
                // needs a repaint to remove or add the cursor cell.
                markContentAllDirty()
            }
        }
    }
    public var vimMode: VimMode = .normal {
        // Status bar surfaces the vim mode label; mode changes also re-style
        // the cursor cell so a content repaint is needed alongside chrome.
        didSet {
            if vimMode != oldValue {
                markChromeDirty()
                markContentAllDirty()
            }
        }
    }
    @ObservationIgnored public var vimVisualAnchor: (line: Int, col: Int)?
    public var symbolTheme: TerminalSymbolTheme
    @ObservationIgnored public var lastClickTime: ContinuousClock.Instant?
    @ObservationIgnored public var lastClickIndex = -1
    @ObservationIgnored public var isScrolling = false
    @ObservationIgnored public var scrollDragState: ScrollDragState?
    @ObservationIgnored public var focusMap: FocusMap?
    @ObservationIgnored public var lastRenderColumns = 80
    @ObservationIgnored public var lastRenderRows = 24
    @ObservationIgnored public var lastScrollDirection: MouseButton?
    @ObservationIgnored public var blockedMomentumDirection: MouseButton?
    @ObservationIgnored public var blockedMomentumDeadline: ContinuousClock.Instant?
    @ObservationIgnored public var scrollAccelerationDirection: MouseButton?
    @ObservationIgnored public var scrollAccelerationTarget: AcceleratedScrollTarget?
    @ObservationIgnored public var scrollAccelerationBurstCount = 0
    @ObservationIgnored public var scrollAccelerationLastEventAt: ContinuousClock.Instant?
    @ObservationIgnored public var pendingAcceleratedScrollLines = 0
    @ObservationIgnored public var pendingAcceleratedScrollTarget: AcceleratedScrollTarget?
    @ObservationIgnored public var scrollAccelerationTask: Task<Void, Never>?
    public var isLoadingGrammar = false {
        didSet { if isLoadingGrammar != oldValue { markChromeDirty() } }
    }
    @ObservationIgnored public var marqueeTickOffset: Int = 0
    @ObservationIgnored public var marqueeTimer: Task<Void, Never>?
    @ObservationIgnored public var marqueeTargetLabel: String?
    @ObservationIgnored public var wrapCache = WrapCache()

    // MARK: - Dirty tracking (Phase 2)
    //
    // Logical-coordinate dirty state. Drained at the start of each render
    // frame and translated into pipeline-level `DirtyRegions`. Phase 2 just
    // collects the markers; Phase 3 makes the renderer act on them. These
    // are `@ObservationIgnored` because the public observation surface is
    // `RenderClock.tick` (advanced by `mark*Dirty`) — letting consumers
    // observe these directly would have the registrar fire per-set during
    // hot edit loops with no benefit.

    /// Buffer-line indices whose content has changed and need repaint.
    @ObservationIgnored public var dirtyContentLines = Set<Int>()
    /// Whole editor content area must be repainted (e.g. scroll, file switch).
    @ObservationIgnored public var dirtyContentAll = true
    /// Sidebar / status bar / tab ribbon must be repainted.
    @ObservationIgnored public var dirtyChrome = true

    /// Marks every logical line in `range` as dirty.
    public func markLinesDirty(_ range: Range<Int>) {
        guard !dirtyContentAll else { return }
        let before = dirtyContentLines.count
        for line in range { dirtyContentLines.insert(line) }
        if dirtyContentLines.count != before {
            renderClock?.advance()
        }
    }

    /// Marks the entire editor content area as dirty. Supersedes per-line marks.
    public func markContentAllDirty() {
        let wasClean = !dirtyContentAll
        dirtyContentAll = true
        dirtyContentLines.removeAll(keepingCapacity: true)
        if wasClean {
            renderClock?.advance()
        }
    }

    /// Marks the chrome (sidebar, status bar, tabs) as dirty.
    public func markChromeDirty() {
        let wasClean = !dirtyChrome
        dirtyChrome = true
        if wasClean {
            renderClock?.advance()
        }
    }

    /// Marks both content and chrome as fully dirty (resize, theme change).
    public func markEverythingDirty() {
        markContentAllDirty()
        markChromeDirty()
    }

    /// Snapshots and clears the dirty markers. Called by the render frame
    /// once it has translated logical dirty state into pipeline rects.
    public func drainDirtyState() -> (contentAll: Bool, contentLines: Set<Int>, chrome: Bool) {
        let snapshot = (dirtyContentAll, dirtyContentLines, dirtyChrome)
        dirtyContentLines.removeAll(keepingCapacity: true)
        dirtyContentAll = false
        dirtyChrome = false
        return snapshot
    }

    public var selection: TextSelection? {
        get { bufferManager.activeBuffer?.selection }
        set {
            bufferManager.activeBuffer?.selection = newValue
            // Selection cells render differently from non-selected cells; any
            // change must invalidate content so the new highlight (or its
            // removal) is painted on the next frame.
            markContentAllDirty()
        }
    }
    @ObservationIgnored public var terminalWriter: (([UInt8]) -> Void)?
    public var readOnly: Bool = false
    public var commandFeedback: String? {
        didSet { if commandFeedback != oldValue { markChromeDirty() } }
    }
    @ObservationIgnored public var commandFeedbackExpiry: ContinuousClock.Instant?
    @ObservationIgnored public var lastKeyRepeatProcessedAt: ContinuousClock.Instant?
    @ObservationIgnored public var pendingKeySequence: [KeyStroke] = []
    @ObservationIgnored public var pendingKeySequenceTime: ContinuousClock.Instant?
    /// Long-lived consumer task that handles background full-document
    /// highlights. `refreshHighlights()` yields into `fullHighlightSignal`
    /// instead of spawning a fresh Task per call — eliminating the
    /// per-keystroke Task allocation + cancellation overhead (audit NF12).
    /// `bufferingNewest(1)` collapses a burst of keystrokes into a single
    /// work cycle. Started lazily on first signal so EditorState's `init`
    /// stays synchronous-only.
    @ObservationIgnored public var fullHighlightTask: Task<Void, Never>?
    @ObservationIgnored public let fullHighlightSignal: AsyncStream<Void>
    @ObservationIgnored public let fullHighlightContinuation: AsyncStream<Void>.Continuation
    public var fileTreeHistory = FileTreeOperationHistory()

    public var maxLineWidth: Int {
        if let cachedMaxLineWidth {
            return cachedMaxLineWidth
        }

        let computed = TextDocument.computeMaxLineWidth(
            in: textBuffer, tabSize: config.editor.tabSize)
        cachedMaxLineWidth = computed
        return computed
    }

    public var hasActiveSelection: Bool {
        selection.map { !$0.isCollapsed } ?? false
    }

    public func clearSelection() {
        selection = nil
    }

    public init(rootPath: String, config: KittyConfig) {
        self.workspace = WorkspaceSession(rootPath: rootPath)
        self.bufferManager = workspace.bufferManager
        self.treeState = workspace.treeState
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        let catalog = config.useSFSymbolsInTerminal ? SymbolCatalogLoader.loadOrDiscover() : nil
        self.symbolTheme = TerminalSymbolTheme.make(
            symbolsEnabled: config.useSFSymbolsInTerminal, catalog: catalog)
        let (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.fullHighlightSignal = stream
        self.fullHighlightContinuation = cont
        let (searchStream, searchCont) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        self.workspaceSearchDebounceSignal = searchStream
        self.workspaceSearchDebounceContinuation = searchCont
        self.fileTreeHistory.maxOperationSteps = config.editor.maxTreeUndoSteps
        let resolver = KeymapResolver(config: config)
        self.statusMessage = "Opened \(rootPath) | \(resolver.openedStatusHints())"

        // Wire up workspace callbacks
        workspace.onTabSwitched = { [weak self] in
            self?.gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
        }

        startFullHighlightConsumer()
        startWorkspaceSearchDebounceConsumer()
        refreshHighlights()
    }

    private func startFullHighlightConsumer() {
        guard fullHighlightTask == nil else { return }
        fullHighlightTask = Task { @MainActor [weak self, fullHighlightSignal] in
            for await _ in fullHighlightSignal {
                guard let self else { return }
                await self.performFullHighlight()
            }
        }
    }

    /// Long-lived consumer for workspace-search-as-you-type debouncing.
    /// One per `EditorState`; reads from the `bufferingNewest(1)` signal so
    /// a burst of find-field keystrokes coalesces into a single search
    /// after the debounce window elapses. The actual heavy work
    /// (`triggerWorkspaceSearch`) keeps its own cancel-and-respawn
    /// `workspaceSearchTask` since the search itself is preemptible and
    /// benefits from explicit cancellation when the query changes.
    private func startWorkspaceSearchDebounceConsumer() {
        guard workspaceSearchDebounceTask == nil else { return }
        workspaceSearchDebounceTask = Task {
            @MainActor [weak self, workspaceSearchDebounceSignal] in
            for await _ in workspaceSearchDebounceSignal {
                guard let strong = self else { return }
                let debounceMs = strong.config.search.debounceMilliseconds
                try? await Task.sleep(for: .milliseconds(debounceMs))
                // Audit B.2/F4 — `Task.sleep` swallows cancellation via
                // `try?`, so check explicitly before running the search
                // body. Without this, `shutdown()` racing with a pending
                // debounce wakeup would invoke `triggerWorkspaceSearch`
                // against a half-torn-down state graph (observed
                // properties firing during shutdown, etc.).
                if Task.isCancelled { return }
                guard let strong = self else { return }
                triggerWorkspaceSearch(state: strong)
            }
        }
    }

    /// Cleanly stops the long-lived full-highlight consumer task. Symmetric
    /// to `GitDecorationManager.stop()`; `AppMain` calls both during
    /// shutdown so neither leaves an orphaned task running against a
    /// deallocating state graph.
    public func shutdown() {
        fullHighlightContinuation.finish()
        fullHighlightTask?.cancel()
        workspaceSearchDebounceContinuation.finish()
        workspaceSearchDebounceTask?.cancel()
        workspaceSearchDebounceTask = nil
        fullHighlightTask = nil
    }

    /// Background-highlight body invoked by the long-lived consumer task.
    /// Re-reads session and document text on the main actor so a stale
    /// signal arrives running against the current state, not the state at
    /// signal-emit time. The `documentText == source` staleness gate
    /// ensures a highlight pass that finishes after the user has moved on
    /// is silently dropped.
    private func performFullHighlight() async {
        guard syntaxHighlightingEnabled else { return }
        let session = currentHighlightSession()
        guard !session.prefersLineInput else { return }

        let lineCount = fileLineCount
        guard lineCount > Self.viewportHighlightThreshold else { return }

        let source = documentText
        let fullHighlights = session.highlightDocument(source: source)

        // Only apply if the document hasn't moved on while we worked.
        guard documentText == source else { return }
        highlightedLines = fullHighlights
        markContentAllDirty()
        renderRefreshSource?.invalidate()
    }

    public func nextOpenRequestID() -> UInt64 {
        workspace.nextOpenRequestID()
    }

    public func replaceFileOpenTask(with task: Task<Void, Never>) {
        workspace.replaceFileOpenTask(with: task)
    }

    public func cancelPendingFileOpen() {
        workspace.cancelPendingFileOpen()
    }

    public func isCurrentOpenRequest(_ requestID: UInt64) -> Bool {
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

    public func noteSelectedPath(_ path: String, isDirectory: Bool) {
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
        // Undo/redo swaps the whole buffer; chrome (status, tab dirty marker)
        // and content (cursor, highlights, selection) all change.
        markEverythingDirty()
        renderRefreshSource?.invalidate()
    }

    public func undoActiveBuffer() {
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

    public func redoActiveBuffer() {
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

    public var isGitIgnoreFilterAvailable: Bool {
        guard config.git.enabled, fileStatusProvider != nil else { return false }
        return FileManager.default.fileExists(
            atPath: FilePath(rootPath).appending(".gitignore").string)
    }

    public func cycleFileVisibility() async {
        switch fileVisibility {
        case .defaultHidden:
            if isGitIgnoreFilterAvailable {
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

    public func applyConfig(_ newConfig: KittyConfig) {
        cancelPendingAcceleratedScroll(state: self, resetBurst: true)
        config = newConfig
        colorScheme = Self.makeColorScheme(config: newConfig)
        treePanelWidth = newConfig.treeWidth
        let catalog = newConfig.useSFSymbolsInTerminal ? SymbolCatalogLoader.loadOrDiscover() : nil
        symbolTheme = TerminalSymbolTheme.make(
            symbolsEnabled: newConfig.useSFSymbolsInTerminal, catalog: catalog)
        refreshHighlights()
        // Theme / config / symbol-theme swap touches every visible cell.
        markEverythingDirty()
    }
}
