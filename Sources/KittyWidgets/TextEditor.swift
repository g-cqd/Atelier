import KittyCodecs
import KittySyntax
import KittyText

/// Scrollable syntax-highlighted text display widget.
public struct TextEditor: View, Sendable {
    public var lines: [String]
    public var lineSpans: [[StyledSpan]]
    public var scrollOffset: Int
    public var horizontalScrollOffset: Int
    public var cursorRow: Int
    public var cursorCol: Int
    public var showLineNumbers: Bool
    public var wrapLines: Bool
    public var editorStyle: Style
    public var lineNumberStyle: Style
    public var currentLineStyle: Style
    public var modeShowsCursor: Bool

    public init(
        content: String = "",
        spans: [StyledSpan] = [],
        scrollOffset: Int = 0,
        horizontalScrollOffset: Int = 0,
        cursorRow: Int = 0,
        cursorCol: Int = 0,
        showLineNumbers: Bool = true,
        wrapLines: Bool = false,
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        modeShowsCursor: Bool = true
    ) {
        self.lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.lineSpans = self.lines.map { _ in spans }
        self.scrollOffset = scrollOffset
        self.horizontalScrollOffset = horizontalScrollOffset
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.showLineNumbers = showLineNumbers
        self.wrapLines = wrapLines
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.modeShowsCursor = modeShowsCursor
    }

    public init(
        lines: [String],
        lineSpans: [[StyledSpan]],
        scrollOffset: Int = 0,
        horizontalScrollOffset: Int = 0,
        cursorRow: Int = 0,
        cursorCol: Int = 0,
        showLineNumbers: Bool = true,
        wrapLines: Bool = false,
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        modeShowsCursor: Bool = true
    ) {
        self.lines = lines.isEmpty ? [""] : lines
        if lineSpans.count == self.lines.count {
            self.lineSpans = lineSpans
        } else {
            self.lineSpans = self.lines.enumerated().map { index, line in
                if index < lineSpans.count {
                    return lineSpans[index]
                }
                return [StyledSpan(text: line, style: editorStyle)]
            }
        }
        self.scrollOffset = scrollOffset
        self.horizontalScrollOffset = horizontalScrollOffset
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.showLineNumbers = showLineNumbers
        self.wrapLines = wrapLines
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.modeShowsCursor = modeShowsCursor
    }

    public var body: Never { fatalError() }

    /// Number of digits needed for line numbers.
    public var lineNumberWidth: Int {
        TextDisplayMetrics.lineNumberDigits(forLineCount: lines.count)
    }
}
