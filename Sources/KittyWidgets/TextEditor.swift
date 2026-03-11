import KittyCodecs
import KittySyntax
import KittyText

/// Scrollable syntax-highlighted text display widget.
public struct TextEditor: View, Sendable {
    public struct GutterDecoration: Sendable, Equatable {
        public var symbol: Character
        public var style: Style

        public init(symbol: Character, style: Style) {
            self.symbol = symbol
            self.style = style
        }
    }

    public var lines: [String]
    public var lineSpans: [[StyledSpan]]
    public var scrollOffset: Int
    public var horizontalScrollOffset: Int
    public var cursorRow: Int
    public var cursorCol: Int
    public var showLineNumbers: Bool
    public var showsGutterDecorations: Bool
    public var gutterDecorations: [Int: GutterDecoration]
    public var wrapLines: Bool
    public var showsVerticalScrollIndicator: Bool
    public var showsHorizontalScrollIndicator: Bool
    public var editorStyle: Style
    public var lineNumberStyle: Style
    public var currentLineStyle: Style
    public var verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle
    public var modeShowsCursor: Bool

    public init(
        content: String = "",
        spans: [StyledSpan] = [],
        scrollOffset: Int = 0,
        horizontalScrollOffset: Int = 0,
        cursorRow: Int = 0,
        cursorCol: Int = 0,
        showLineNumbers: Bool = true,
        showsGutterDecorations: Bool = false,
        gutterDecorations: [Int: GutterDecoration] = [:],
        wrapLines: Bool = false,
        showsVerticalScrollIndicator: Bool = false,
        showsHorizontalScrollIndicator: Bool = false,
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true
    ) {
        self.lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.lineSpans = self.lines.map { _ in spans }
        self.scrollOffset = scrollOffset
        self.horizontalScrollOffset = horizontalScrollOffset
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.showLineNumbers = showLineNumbers
        self.showsGutterDecorations = showsGutterDecorations
        self.gutterDecorations = gutterDecorations
        self.wrapLines = wrapLines
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.showsHorizontalScrollIndicator = showsHorizontalScrollIndicator
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
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
        showsGutterDecorations: Bool = false,
        gutterDecorations: [Int: GutterDecoration] = [:],
        wrapLines: Bool = false,
        showsVerticalScrollIndicator: Bool = false,
        showsHorizontalScrollIndicator: Bool = false,
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
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
        self.showsGutterDecorations = showsGutterDecorations
        self.gutterDecorations = gutterDecorations
        self.wrapLines = wrapLines
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.showsHorizontalScrollIndicator = showsHorizontalScrollIndicator
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
    }

    public var body: Never { fatalError() }

    /// Number of digits needed for line numbers.
    public var lineNumberWidth: Int {
        TextDisplayMetrics.lineNumberDigits(forLineCount: lines.count)
    }
}
