import KittyCodecs
import KittySyntax
import KittyText

/// Scrollable syntax-highlighted text display widget.
public struct TextEditor: View, Sendable {
    private enum LineStorage: Sendable {
        case lines([String])
        case buffer(TextBuffer)
    }

    public struct GutterDecoration: Sendable, Equatable {
        public var symbol: Character
        public var style: Style

        public init(symbol: Character, style: Style) {
            self.symbol = symbol
            self.style = style
        }
    }

    private var lineStorage: LineStorage
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
    public var lineStyleOverlays: [Int: TextStyleOverlay]
    public var editorStyle: Style
    public var lineNumberStyle: Style
    public var currentLineStyle: Style
    public var verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle
    public var horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle
    public var modeShowsCursor: Bool
    public var maxLineWidth: Int
    public var whitespaceConfig: WhitespaceRenderer.Config

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
        lineStyleOverlays: [Int: TextStyleOverlay] = [:],
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle = HorizontalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true,
        maxLineWidth: Int = 0,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled
    ) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.lineStorage = .lines(lines)
        self.lineSpans = lines.map { _ in spans }
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
        self.lineStyleOverlays = lineStyleOverlays
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.horizontalScrollIndicatorStyle = horizontalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
        self.maxLineWidth = maxLineWidth
        self.whitespaceConfig = whitespaceConfig
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
        lineStyleOverlays: [Int: TextStyleOverlay] = [:],
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle = HorizontalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true,
        maxLineWidth: Int = 0,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled
    ) {
        self.lineStorage = .lines(lines.isEmpty ? [""] : lines)
        self.lineSpans = lineSpans
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
        self.lineStyleOverlays = lineStyleOverlays
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.horizontalScrollIndicatorStyle = horizontalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
        self.maxLineWidth = maxLineWidth
        self.whitespaceConfig = whitespaceConfig
    }

    public init(
        buffer: TextBuffer,
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
        lineStyleOverlays: [Int: TextStyleOverlay] = [:],
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle = HorizontalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true,
        maxLineWidth: Int = 0,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled
    ) {
        self.lineStorage = .buffer(buffer.lineCount == 0 ? TextBuffer(lines: [""]) : buffer)
        self.lineSpans = lineSpans
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
        self.lineStyleOverlays = lineStyleOverlays
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.horizontalScrollIndicatorStyle = horizontalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
        self.maxLineWidth = maxLineWidth
        self.whitespaceConfig = whitespaceConfig
    }

    public var body: Never { fatalError() }

    public var lines: [String] {
        switch lineStorage {
        case .lines(let lines):
            lines
        case .buffer(let buffer):
            buffer.lines
        }
    }

    public var lineCount: Int {
        switch lineStorage {
        case .lines(let lines):
            lines.count
        case .buffer(let buffer):
            max(1, buffer.lineCount)
        }
    }

    public func line(at index: Int) -> String {
        switch lineStorage {
        case .lines(let lines):
            guard index >= 0, index < lines.count else { return "" }
            return lines[index]
        case .buffer(let buffer):
            return buffer.line(at: index)
        }
    }

    public func spans(at index: Int) -> [StyledSpan] {
        guard index >= 0 && index < lineCount else {
            return [StyledSpan(text: "", style: editorStyle)]
        }

        if index < lineSpans.count {
            return lineSpans[index]
        }

        return [StyledSpan(text: line(at: index), style: editorStyle)]
    }

    /// Number of digits needed for line numbers.
    public var lineNumberWidth: Int {
        TextDisplayMetrics.lineNumberDigits(forLineCount: lineCount)
    }
}
