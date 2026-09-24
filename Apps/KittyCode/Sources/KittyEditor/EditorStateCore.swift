public import AemiCore
import AtelierGit
public import AtelierProcess
public import AtelierText
public import AtelierTheme
// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable file_length type_body_length
import Foundation
public import KittyApp
public import KittyCodecs
public import KittyFileTree
public import KittyGit
public import KittySearch
public import KittySymbols
public import KittySyntax
public import KittyWidgets
public import KittyWorkspace
public import Observation
import System
import os

public import class AemiRuntime.BlockingOffloadPool

/// Editor signposts around `textDidChange` and the wrap-cache rebuild, so Instruments can attribute frame time.
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

        public func isValid(contentWidth: Int, tabSize: Int, documentVersion: Int, lineCount: Int) -> Bool {
            self.contentWidth == contentWidth && self.tabSize == tabSize
                && self.documentVersion == documentVersion && lineWrapCounts.count == lineCount
        }

        /// The rows `line` wraps into at `contentWidth` columns, tabs reaching the next multiple of `tabSize`; at
        /// least one.
        /// - Complexity: O(n), where n is the length of `line`.
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

        /// Re-wraps only the lines `mutation` touched, patching the row total and offsets; invalidates the whole cache
        /// instead when its width, tab size or line count doesn't match.
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
        var isSearching = false
        var isComplete = false
        var didHitLimit = false
        var resultRequest: InFileSearchRequest? = nil

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
    /// How git is spawned for one-off queries such as the gitignore filter; nil when git
    /// integration is disabled. Set by the composition root alongside `fileStatusProvider`.
    @ObservationIgnored public var processRunner: (any ProcessRunner)?
    @ObservationIgnored public var gitDecorationManager: GitDecorationManager?
    @ObservationIgnored public var renderRefreshSource: RenderRefreshSource?
    /// Advanced by the `mark*Dirty` calls that dirty something new, so the runtime renders the next frame.
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

    // `textBuffer`, `textCursor` and `highlightedLines` yield the workspace's own storage to a mutation. Through `get`
    // and `set` alone, `&state.textBuffer` or `state.highlightedLines.replaceSubrange(…)` mutates a copy that shares
    // the storage, so every edit copies a whole document's worth of lines. SE-0474's `yielding mutate` still needs an
    // experimental feature in Swift 6.4, hence `_modify`.

    public var textBuffer: TextBuffer {
        get { workspace.textBuffer }
        set { workspace.textBuffer = newValue }
        _modify { yield &workspace.textBuffer }
    }

    public var textCursor: TextCursor {
        get { workspace.textCursor }
        set { workspace.textCursor = newValue }
        _modify { yield &workspace.textCursor }
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
        // Marks nothing: per-line `replaceSubrange` edits pass through here too, so wholesale assignments mark dirty
        // themselves.
        set { workspace.highlightedLines = newValue }
        _modify { yield &workspace.highlightedLines }
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
    /// The in-file search running on `searchPool`; a newer search, `cancelInFileSearch(state:)` and `shutdown()`
    /// cancel it.
    @ObservationIgnored var inFileSearchTask: Task<Void, Never>?
    /// Advanced by every in-file search started or cancelled: a search applies its result only while it is current.
    @ObservationIgnored var inFileSearchGeneration: UInt64 = 0
    /// The consumer debouncing search as you type: each find-field keystroke signals it, and `bufferingNewest(1)`
    /// turns a burst into one `triggerWorkspaceSearch` after the debounce window.
    @ObservationIgnored public var workspaceSearchDebounceTask: Task<Void, Never>?
    @ObservationIgnored public let workspaceSearchDebounceSignal: AsyncStream<Void>
    @ObservationIgnored public let workspaceSearchDebounceContinuation: AsyncStream<Void>.Continuation
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

    /// The built `syntaxTheme`, read once per rendered line; cleared by a colour scheme change and by
    /// `replaceConfiguredSyntaxTheme(_:)`.
    @ObservationIgnored private var cachedSyntaxTheme: Theme?
    /// The theme `syntax.xcodeTheme` names, loaded when the config is applied; nil when none is configured or
    /// the file could not be read, in which case the colour scheme's syntax colours apply.
    @ObservationIgnored private var configuredSyntaxTheme: Theme?
    /// The colours the terminal answered for its palette, as `receiveTerminalReply` gathers them.
    @ObservationIgnored public var terminalPalette = TerminalPalette()
    /// Paste requests sent to the terminal whose clipboard reply has not come; a reply none waits for is ignored.
    @ObservationIgnored var pendingClipboardReplies = 0

    public var syntaxTheme: Theme {
        if let cached = cachedSyntaxTheme { return cached }
        let theme = configuredSyntaxTheme ?? Self.makeSyntaxTheme(from: colorScheme)
        cachedSyntaxTheme = theme
        return theme
    }

    /// Loads the configured Xcode theme, if any, else the terminal-derived one when asked for and the palette
    /// has arrived, and reports a failure in the status bar.
    private func loadConfiguredSyntaxTheme(_ config: KittyConfig) {
        do {
            configuredSyntaxTheme = try Self.resolveConfiguredSyntaxTheme(config: config, palette: terminalPalette)
        } catch {
            configuredSyntaxTheme = nil
            statusMessage = "Could not load syntax.xcodeTheme: \(error.localizedDescription)"
        }
    }

    /// Replaces the configured syntax theme and re-highlights every open buffer with it.
    func replaceConfiguredSyntaxTheme(_ theme: Theme?) {
        configuredSyntaxTheme = theme
        cachedSyntaxTheme = nil
        highlightSession = nil
        for buffer in bufferManager.buffers {
            buffer.highlightSession = nil
        }
        refreshHighlights()
        markEverythingDirty()
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

    /// The lines below the screen that a refresh also highlights at once, so a short scroll finds them styled.
    private static let viewportHighlightMargin = 20

    /// Highlights the lines on screen from the rope, reading no other line, and hands the rest of the document to the
    /// background full pass. Until that pass lands, every other line holds no spans, which the editor draws as plain
    /// text, so the text itself never waits for highlighting.
    /// - Complexity: O(bytes on screen) to highlight, plus an O(line count) array of empty placeholders.
    public func refreshHighlights() {
        highlightGeneration &+= 1
        let lineCount = fileLineCount
        let viewport = highlightViewportRange(lineCount: lineCount)
        var lines = Array(repeating: [StyledSpan](), count: lineCount)
        let viewportHighlights = highlightViewport(of: textBuffer, in: viewport)
        if viewportHighlights.count == viewport.count {
            lines.replaceSubrange(viewport, with: viewportHighlights)
        }
        replaceHighlightedLines(with: lines)
        // Plain text needs no highlighting pass, as a line without spans draws plain; an unknown width needs measuring.
        let leavesLinesUnhighlighted = syntaxHighlightingEnabled && viewport != 0 ..< lineCount
        if leavesLinesUnhighlighted || cachedMaxLineWidth == nil {
            requestFullHighlight()
        }
    }

    /// The lines on screen and a margin below them.
    private func highlightViewportRange(lineCount: Int) -> Range<Int> {
        let start = min(max(0, scrollOffset), lineCount - 1)
        return start ..< min(lineCount, start + lastRenderRows + Self.viewportHighlightMargin)
    }

    /// The spans of `viewport`'s lines, read from `document` alone: a comment or string opened above the viewport
    /// is not seen, so the full pass restyles those lines.
    /// - Complexity: O(bytes of the viewport's lines), plus an O(log n) seek in a rope.
    func highlightViewport(of document: some DocumentSource, in viewport: Range<Int>) -> [[StyledSpan]] {
        let lines = document.lines(in: viewport)
        guard syntaxHighlightingEnabled else {
            let style = colorScheme.editorText
            return lines.map { [StyledSpan(text: $0, style: style)] }
        }
        return currentHighlightSession().highlightLines(lines)
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

        // Lines come straight from the buffer: `fileContent` would materialise the whole document per keystroke.
        let lineCount = fileLineCount
        guard isMutationApplicable(mutation, lineCount: lineCount) else {
            refreshHighlights()
            return
        }

        let updatedHighlights = session.highlightLines(textBuffer.lines(in: mutation.updatedLineRange))
        highlightedLines.replaceSubrange(mutation.originalLineRange, with: updatedHighlights)

        // A comment or string the edit opened or closed restyles what follows it: re-scan the visible window with
        // some lookback so the screen is right at once, and hand the rest of the document to the full pass when the
        // window's last line changed style, which is the sign of a construct running past it.
        let window = highlightWindow(around: mutation.updatedLineRange, lineCount: lineCount)
        guard window != mutation.updatedLineRange, window.upperBound <= highlightedLines.count else { return }
        let before = highlightedLines[window.upperBound - 1]
        let windowHighlights = session.highlightLines(textBuffer.lines(in: window))
        guard windowHighlights.count == window.count else { return }
        highlightedLines.replaceSubrange(window, with: windowHighlights)
        if windowHighlights[windowHighlights.count - 1] != before, window.upperBound < lineCount {
            requestFullHighlight()
        }
    }

    /// The visible lines with lookback, widened to include `edited`; `edited` alone when it lies off screen.
    private func highlightWindow(around edited: Range<Int>, lineCount: Int) -> Range<Int> {
        let visible = max(0, scrollOffset - 200) ..< min(lineCount, max(scrollOffset, 0) + lastRenderRows + 50)
        guard visible.overlaps(edited) || visible.contains(edited.lowerBound) else { return edited }
        return min(visible.lowerBound, edited.lowerBound) ..< max(visible.upperBound, edited.upperBound)
    }

    /// Restyles only the lines `mutation` covers as plain text, for when syntax highlighting is off.
    private func refreshPlainHighlights(after mutation: TextMutation) {
        guard isMutationApplicable(mutation, lineCount: fileLineCount) else {
            refreshHighlights()
            return
        }
        let style = colorScheme.editorText
        let replacement = textBuffer.lines(in: mutation.updatedLineRange)
            .map { line in
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

    // MARK: - Text access

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

    private var bufferUndoCoalescingWindow: Duration? {
        guard config.editor.undoCoalescingEnabled else { return nil }
        return .milliseconds(max(0, config.editor.undoCoalescingMilliseconds))
    }

    public func textDidChange(previousSnapshot: BufferEditSnapshot? = nil) {
        guard !readOnly else {
            statusMessage = "Read-only mode"
            return
        }
        invalidateTextSnapshotCache()
        if let buf = bufferManager.activeBuffer {
            cancelPostOpenProcessing(of: buf)
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
        widenCachedMaxLineWidth(for: textCursor.row ..< (textCursor.row + 1))
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
        // An edit can only widen the widest line through its own lines, so the cached width outlives the other caches.
        let knownMaxLineWidth = cachedMaxLineWidth
        invalidateTextSnapshotCache()
        cachedMaxLineWidth = knownMaxLineWidth
        if let buf = bufferManager.activeBuffer {
            cancelPostOpenProcessing(of: buf)
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
        // A changed line count moves every row below the edit, so only a stable count repaints just its lines.
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

    /// Marks only the lines a vertical scroll exposes; a jump of a screen or more repaints the whole content.
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
            exposed = (oldOffset + visibleRows) ..< (newOffset + visibleRows)
        } else {
            // Scrolling up: the new top strip exposes [new, old).
            exposed = newOffset ..< oldOffset
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
        refreshHighlightsIfIncomplete()
    }

    public func switchToTab(_ index: Int) {
        // The outgoing document's highlights and caches: the switch evicts the buffer's copy and the restore lets go
        // of the workspace's, so they are retired once it has, below. Its rope stays with its buffer.
        let retired = RetiredStorage(
            highlights: highlightedLines, fileLines: cachedFileLines, documentText: cachedDocumentText)
        workspace.switchToTab(index)
        refreshHighlightsIfIncomplete()
        markEverythingDirty()
        retire(consume retired)
    }

    /// Refreshes the highlights of an active buffer brought back without them or without its width, as a tab is once
    /// evicted while inactive; the width is then measured by the full pass, never here.
    private func refreshHighlightsIfIncomplete() {
        guard bufferManager.activeBuffer != nil,
            highlightedLines.count != fileLineCount || cachedMaxLineWidth == nil
        else { return }
        refreshHighlights()
    }

    /// Cancels `buffer`'s post-load pass, if it has one pending, and hands its whole-document highlight and
    /// measurement to the full pass, since nothing else may ask for them.
    private func cancelPostOpenProcessing(of buffer: DocumentBuffer) {
        guard let pending = buffer.postOpenProcessingTask else { return }
        pending.cancel()
        buffer.postOpenProcessingTask = nil
        requestFullHighlight()
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
        wrapCache.lineWrapCounts = (0 ..< lineCount)
            .map { lineIndex in
                WrapCache.wrapCount(
                    of: fileLine(at: lineIndex), contentWidth: contentWidth, tabSize: tabSize)
            }
        wrapCache.totalRowCount = wrapCache.lineWrapCounts.reduce(0, +)

        var offset = 0
        wrapCache.visualOffsets = [0]
        for i in 1 ..< lineCount {
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
    @ObservationIgnored public var lastClickTime: ClockInstant?
    @ObservationIgnored public var lastClickIndex = -1
    @ObservationIgnored public var isScrolling = false
    @ObservationIgnored public var scrollDragState: ScrollDragState?
    @ObservationIgnored public var focusMap: FocusMap?
    /// Whether the frame is drawn with pixel chrome: the pane separator and ribbon underline are one-pixel
    /// placements under the cells instead of a cell column and glyphs. Set by the shell from the pipeline
    /// before each layout, so hit testing and rendering agree.
    @ObservationIgnored public var usesPixelChrome = false
    @ObservationIgnored public var lastRenderColumns = 80
    @ObservationIgnored public var lastRenderRows = 24
    @ObservationIgnored public var lastScrollDirection: MouseButton?
    @ObservationIgnored public var blockedMomentumDirection: MouseButton?
    @ObservationIgnored public var blockedMomentumDeadline: ClockInstant?
    @ObservationIgnored public var scrollAccelerationDirection: MouseButton?
    @ObservationIgnored public var scrollAccelerationTarget: AcceleratedScrollTarget?
    @ObservationIgnored public var scrollAccelerationBurstCount = 0
    @ObservationIgnored public var scrollAccelerationLastEventAt: ClockInstant?
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

    // MARK: - Dirty tracking
    //
    // Logical dirty state, drained each frame into the pipeline's `DirtyRegions`. `RenderClock.tick` is the observable
    // surface, so these stay observation-ignored and hot edit loops don't fire the registrar on every set.

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
            // Selected cells render differently, so any selection change repaints the content.
            markContentAllDirty()
        }
    }
    @ObservationIgnored public var terminalWriter: (([UInt8]) -> Void)?
    public var readOnly: Bool = false
    public var commandFeedback: String? {
        didSet { if commandFeedback != oldValue { markChromeDirty() } }
    }
    @ObservationIgnored public var commandFeedbackExpiry: ClockInstant?
    @ObservationIgnored public var lastKeyRepeatProcessedAt: ClockInstant?
    @ObservationIgnored public var pendingKeySequence: [KeyStroke] = []
    @ObservationIgnored public var pendingKeySequenceTime: ClockInstant?
    /// The consumer of `fullHighlightSignal`, started by `init`. It waits for each full pass before taking the next
    /// request, so passes never overlap, and `bufferingNewest(1)` turns the requests of a burst into one pass.
    @ObservationIgnored public var fullHighlightTask: Task<Void, Never>?
    @ObservationIgnored public let fullHighlightSignal: AsyncStream<Void>
    @ObservationIgnored public let fullHighlightContinuation: AsyncStream<Void>.Continuation
    /// The detached task running the current full pass; `shutdown()` cancels it.
    @ObservationIgnored private var fullHighlightWorkTask: Task<Void, Never>?
    /// Advanced by every `refreshHighlights()`: a pass that read the document before it may style it with a theme, a
    /// language or a setting that no longer holds.
    @ObservationIgnored private(set) var highlightGeneration: UInt64 = 0
    /// Hands storage the state no longer shows to a consumer `init` starts and `shutdown()` ends, which frees it off the
    /// main actor; a test substitutes it to see what a close or a reload lets go of.
    @ObservationIgnored var retire: @Sendable (consuming RetiredStorage) -> Void
    @ObservationIgnored private let retiredStorage: AsyncStream<RetiredStorage>.Continuation
    /// The full pass itself, run on a detached task; a test substitutes it to see where and when a pass runs.
    @ObservationIgnored var fullHighlightCompute: @Sendable (FullHighlightInput) async -> FullHighlightResult = {
        EditorState.computeFullHighlight($0)
    }
    public var fileTreeHistory = FileTreeOperationHistory()

    /// The widest line's display width, or 0 while the post-load or full pass is still measuring it: a document is
    /// never measured on the main actor.
    public var maxLineWidth: Int {
        cachedMaxLineWidth ?? 0
    }

    public var hasActiveSelection: Bool {
        selection.map { !$0.isCollapsed } ?? false
    }

    public func clearSelection() {
        selection = nil
    }

    @ObservationIgnored public let taskProvider: any TaskProvider
    @ObservationIgnored public let clock: any Clock<Duration>
    /// The pool the editor's blocking file work runs on, so it never parks a cooperative thread: workspace search's
    /// walk and reads, file loads and reloads, and tree scans. The app's injected pool, or else a one-worker pool of
    /// its own, which `shutdown()` must stop as `deinit` doesn't.
    @ObservationIgnored public let searchPool: BlockingOffloadPool
    /// Whether `searchPool` is this instance's own; an injected pool is stopped by its creator.
    @ObservationIgnored private let ownsSearchPool: Bool

    public init(
        rootPath: String, config: KittyConfig,
        taskProvider: any TaskProvider = .default, clock: any Clock<Duration> = ContinuousClock(),
        searchPool: BlockingOffloadPool? = nil
    ) {
        self.taskProvider = taskProvider
        self.clock = clock
        if let searchPool {
            self.searchPool = searchPool
            self.ownsSearchPool = false
        } else {
            self.searchPool = BlockingOffloadPool(width: 1)
            self.ownsSearchPool = true
        }
        self.workspace = WorkspaceSession(rootPath: rootPath)
        self.bufferManager = workspace.bufferManager
        self.treeState = workspace.treeState
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        self.configuredSyntaxTheme = try? Self.resolveConfiguredSyntaxTheme(config: config, palette: TerminalPalette())
        self.symbolTheme = TerminalSymbolTheme.make(symbolsEnabled: config.useSFSymbolsInTerminal) {
            SymbolCatalogLoader.loadOrDiscover()
        }
        let (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.fullHighlightSignal = stream
        self.fullHighlightContinuation = cont
        let (retiredStream, retired) = AsyncStream<RetiredStorage>.makeStream()
        self.retiredStorage = retired
        self.retire = { retired.yield($0) }
        let (searchStream, searchCont) = AsyncStream<Void>
            .makeStream(
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
        taskProvider.detachedTask(role: .observation, priority: .utility) {
            // Each array is freed here, on this task's thread, when the loop lets go of it.
            for await _ in retiredStream {}
        }
        startWorkspaceSearchDebounceConsumer()
        refreshHighlights()
    }

    private func startFullHighlightConsumer() {
        guard fullHighlightTask == nil else { return }
        fullHighlightTask = taskProvider.task(role: .observation) { @MainActor [weak self, fullHighlightSignal] in
            for await _ in fullHighlightSignal {
                guard let self else { return }
                await self.performFullHighlight()
            }
        }
    }

    /// Starts `workspaceSearchDebounceTask`; each search it triggers keeps its own cancellable `workspaceSearchTask`.
    private func startWorkspaceSearchDebounceConsumer() {
        guard workspaceSearchDebounceTask == nil else { return }
        let clock = clock
        workspaceSearchDebounceTask = taskProvider.task(role: .observation) {
            @MainActor [weak self, workspaceSearchDebounceSignal] in
            for await _ in workspaceSearchDebounceSignal {
                guard let strong = self else { return }
                let debounceMs = strong.config.search.debounceMilliseconds
                try? await clock.sleep(for: .milliseconds(debounceMs))
                // `try?` swallows the sleep's cancellation; no search may run on a state `shutdown()` tears down.
                if Task.isCancelled { return }
                guard let strong = self else { return }
                triggerWorkspaceSearch(state: strong)
            }
        }
    }

    /// Stops the full-highlight and search-debounce consumers, a full pass and an in-file search in flight and an owned
    /// search pool, so no task outlives the state; `AppMain` calls it alongside `GitDecorationManager.stop()`.
    public func shutdown() {
        fullHighlightContinuation.finish()
        fullHighlightTask?.cancel()
        fullHighlightWorkTask?.cancel()
        fullHighlightWorkTask = nil
        retiredStorage.finish()
        workspaceSearchDebounceContinuation.finish()
        workspaceSearchDebounceTask?.cancel()
        workspaceSearchDebounceTask = nil
        fullHighlightTask = nil
        cancelInFileSearch(state: self)
        if ownsSearchPool { searchPool.shutdown() }
    }

    /// Runs one full pass over a snapshot of the document on a detached task, which installs the result on the main
    /// actor, and waits for it. A buffer whose post-load pass is still running is left to that pass, which highlights
    /// and measures it too.
    private func performFullHighlight() async {
        let highlightsSyntax = syntaxHighlightingEnabled
        guard highlightsSyntax || cachedMaxLineWidth == nil,
            bufferManager.activeBuffer?.postOpenProcessingTask == nil
        else { return }
        let request = currentHighlightRequest
        let input = FullHighlightInput(
            textBuffer: textBuffer, language: currentLanguage, theme: syntaxTheme, highlightsSyntax: highlightsSyntax,
            tabSize: config.editor.tabSize)
        let compute = fullHighlightCompute
        let work = taskProvider.detachedTask(role: .work) { [weak self] in
            let result = await compute(input)
            guard !Task.isCancelled else { return }
            await self?.installFullHighlight(result, for: request)
        }
        fullHighlightWorkTask = work
        await work.value
        if fullHighlightWorkTask == work { fullHighlightWorkTask = nil }
    }

    /// Installs a finished pass while the buffer, its version, its text and the refresh the pass followed are still
    /// the ones it read. A pass its own document has outrun asks for another, since the edits that outran it may not.
    private func installFullHighlight(_ result: FullHighlightResult, for request: HighlightRequest) {
        let current = currentHighlightRequest
        guard request == current, result.highlightedLines.map({ $0.count == fileLineCount }) ?? true else {
            if request.bufferID == current.bufferID { requestFullHighlight() }
            return
        }
        if let highlightedLines = result.highlightedLines {
            replaceHighlightedLines(with: highlightedLines)
        }
        cachedMaxLineWidth = result.maxLineWidth
        markContentAllDirty()
        renderRefreshSource?.invalidate()
    }

    /// Installs `lines` and retires the previous highlights: freeing a large document's spans one heap object at a
    /// time held the main actor for 75 ms at a million lines.
    private func replaceHighlightedLines(with lines: [[StyledSpan]]) {
        let previous = RetiredStorage(highlights: highlightedLines)
        highlightedLines = lines
        retire(consume previous)
    }

    /// The active document's highlights, rope and line and text caches, `closedBuffer` and what a reload's buffer let
    /// go of, to hand to `retire` once the state has replaced them, so that the last reference to each goes with the
    /// consumer.
    func activeDocumentStorage(
        closing closedBuffer: DocumentBuffer? = nil, replaced: consuming DocumentBuffer.ReplacedContents? = nil
    ) -> RetiredStorage {
        RetiredStorage(
            highlights: highlightedLines, textBuffer: textBuffer, fileLines: cachedFileLines,
            documentText: cachedDocumentText, buffer: closedBuffer, replaced: replaced)
    }

    /// The preview buffer an open in preview mode replaces, and the active document's storage when it is that buffer.
    func replacedPreviewStorage() -> RetiredStorage {
        guard config.tabRibbon.persistence == .preview, let index = bufferManager.previewIndex else {
            return RetiredStorage()
        }
        let preview = bufferManager.buffers[index]
        return index == bufferManager.activeIndex
            ? activeDocumentStorage(closing: preview) : RetiredStorage(buffer: preview)
    }

    private var currentHighlightRequest: HighlightRequest {
        let buffer = bufferManager.activeBuffer
        return HighlightRequest(
            bufferID: buffer.map(ObjectIdentifier.init), documentVersion: buffer?.documentVersion ?? 0,
            contentHash: textBuffer.contentHash, generation: highlightGeneration)
    }

    /// Asks the consumer for a full pass; the requests of a burst make one pass.
    func requestFullHighlight() {
        fullHighlightContinuation.yield(())
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

    /// Grows a known width to cover the lines in `range`; an unknown width stays unknown, left to the pass measuring it.
    private func widenCachedMaxLineWidth(for range: Range<Int>) {
        guard let cachedWidth = cachedMaxLineWidth else { return }

        let lowerBound = max(0, range.lowerBound)
        let upperBound = min(fileLineCount, range.upperBound)
        guard lowerBound < upperBound else { return }

        let widenedWidth = (lowerBound ..< upperBound)
            .reduce(0) { partial, lineIndex in
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
        // Clears the width too, which the full pass the refresh below asks for measures.
        invalidateTextSnapshotCache()
        highlightSession = nil
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
            let replaced = RetiredStorage(highlights: buffer.highlightedLines)
            buffer.highlightedLines = []
            retire(consume replaced)
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
                if isGitIgnoreFilterAvailable, let processRunner {
                    let ignored = await GitIgnoreChecker.ignoredPaths(in: rootPath, runner: processRunner)
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
        loadConfiguredSyntaxTheme(newConfig)
        colorScheme = Self.makeColorScheme(config: newConfig)
        treePanelWidth = newConfig.treeWidth
        symbolTheme = TerminalSymbolTheme.make(symbolsEnabled: newConfig.useSFSymbolsInTerminal) {
            SymbolCatalogLoader.loadOrDiscover()
        }
        refreshHighlights()
        // Theme / config / symbol-theme swap touches every visible cell.
        markEverythingDirty()
    }
}

// MARK: - Full-document highlighting

extension EditorState {
    /// What a full pass reads: a snapshot of the rope, O(1) to take, and the settings to highlight and measure with.
    struct FullHighlightInput: Sendable {
        let textBuffer: TextBuffer
        let language: String?
        let theme: Theme
        /// False when syntax highlighting is off: the pass then only measures, as a line without spans draws plain.
        let highlightsSyntax: Bool
        let tabSize: Int
    }

    /// A full pass's product: the spans of every line, unless it only measured, and the widest line's display width.
    struct FullHighlightResult: Sendable {
        let highlightedLines: [[StyledSpan]]?
        let maxLineWidth: Int
    }

    /// Storage the state has let go of, which the consumer `init` starts frees off the main actor. A large document's
    /// storage frees one heap object at a time: a million lines of spans held the main actor for 70-110 ms when a
    /// close or a reload let go of them there.
    struct RetiredStorage: Sendable {
        var highlights: [[StyledSpan]] = []
        var textBuffer: TextBuffer?
        var fileLines: [String]?
        var documentText: String?
        /// A closed tab's buffer, with its undo history and its own copy of the highlights.
        var buffer: DocumentBuffer?
        /// What a reload's buffer let go of: an inactive tab's highlights are held there alone.
        var replaced: DocumentBuffer.ReplacedContents?
    }

    /// The state a full pass starts from; its result is installed only while the state is unchanged.
    struct HighlightRequest: Equatable, Sendable {
        /// The active buffer, so a pass started in another tab never lands in this one.
        let bufferID: ObjectIdentifier?
        /// The buffer's version, which every edit, undo and redo advances.
        let documentVersion: Int
        /// The rope's O(1) hash, for text replaced without a buffer or a version.
        let contentHash: Int
        /// The refresh the pass follows, for a theme, language or setting changed since.
        let generation: UInt64
    }

    /// The widest line of the document, and the document highlighted lexically in one scan, so that a comment or
    /// string spanning lines is styled as one. Reads the rope's bytes without caching its text, since the live buffer
    /// and the undo history share the storage.
    /// - Complexity: O(document bytes).
    nonisolated private static func computeFullHighlight(_ input: FullHighlightInput) -> FullHighlightResult {
        let maxLineWidth = TextDocument.computeMaxLineWidth(in: input.textBuffer, tabSize: input.tabSize)
        guard input.highlightsSyntax else {
            return FullHighlightResult(highlightedLines: nil, maxLineWidth: maxLineWidth)
        }
        let rope = input.textBuffer.ropeSnapshot
        let source = String(decoding: rope.bytes(in: 0 ..< rope.byteCount), as: UTF8.self)
        let session = LanguageHighlighter.makeSession(
            language: input.language, theme: input.theme, preferGrammar: false)
        return FullHighlightResult(
            highlightedLines: session.highlightDocument(source: source), maxLineWidth: maxLineWidth)
    }
}
