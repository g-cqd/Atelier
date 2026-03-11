import KittyGit
import KittySyntax
import KittyText

/// Read-only view of the active document for renderers.
@MainActor
public protocol ActiveDocumentView: AnyObject {
    var textBuffer: TextBuffer { get }
    var textCursor: TextCursor { get }
    var fileName: String { get }
    var filePath: String { get }
    var currentLanguage: String? { get }
    var currentLineEnding: TextDocument.LineEnding { get }
    var highlightedLines: [[StyledSpan]] { get }
    var fileLineCount: Int { get }
    var isFileEmpty: Bool { get }
    var serializedByteCount: Int { get }
    var maxLineWidth: Int { get }
    func fileLine(at index: Int) -> String
    func highlightedLine(at index: Int) -> [StyledSpan]
}

/// Read-only view of the tab ribbon for renderers.
@MainActor
public protocol TabRibbonView: AnyObject {
    var bufferManager: BufferManager { get }
    var tabScrollOffset: Int { get }
}

/// Read-only view of the tree panel for renderers.
@MainActor
public protocol TreePanelView: AnyObject {
    var treeState: WorkspaceTreeState { get }
}

/// Commands for workspace operations.
@MainActor
public protocol WorkspaceCommands: AnyObject {
    func switchToTab(_ index: Int)
    func saveStateToActiveBuffer()
    func restoreStateFromActiveBuffer()
}
