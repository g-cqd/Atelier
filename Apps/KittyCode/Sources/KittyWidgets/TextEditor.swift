public import AtelierText
public import KittyCodecs
public import KittySyntax

/// A highlighted range within a single line, carrying its own style.
public struct TextHighlight: Sendable, Equatable {
    public enum Role: Int, Sendable, Equatable, Comparable {
        case searchMatch = 0
        case userSelection = 1
        case activeSearchMatch = 2

        public static func < (lhs: Role, rhs: Role) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var range: ClosedRange<Int>
    public var role: Role
    public var style: Style

    public init(range: ClosedRange<Int>, role: Role, style: Style) {
        self.range = range
        self.role = role
        self.style = style
    }
}

/// Scrollable syntax-highlighted text display widget.
public struct TextEditor: View, Sendable {
    private var source: any DocumentSource

    public struct WrapLayoutCache: Sendable, Equatable {
        public var contentWidth: Int
        public var tabSize: Int
        public var lineCount: Int
        public var totalRowCount: Int
        public var lineWrapCounts: [Int]
        public var visualOffsets: [Int]

        public init(
            contentWidth: Int,
            tabSize: Int,
            lineCount: Int,
            totalRowCount: Int,
            lineWrapCounts: [Int],
            visualOffsets: [Int]
        ) {
            self.contentWidth = contentWidth
            self.tabSize = tabSize
            self.lineCount = lineCount
            self.totalRowCount = totalRowCount
            self.lineWrapCounts = lineWrapCounts
            self.visualOffsets = visualOffsets
        }
    }

    public struct GutterDecoration: Sendable, Equatable {
        public var symbol: Character
        public var style: Style

        public init(symbol: Character, style: Style) {
            self.symbol = symbol
            self.style = style
        }
    }

    public var lineSpans: [[StyledSpan]]
    public var scrollOffset: Int
    public var wrapRowOffset: Int
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
    public var highlights: [Int: [TextHighlight]]
    public var editorStyle: Style
    public var lineNumberStyle: Style
    public var currentLineStyle: Style
    public var verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle
    public var horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle
    public var modeShowsCursor: Bool
    public var maxLineWidth: Int
    public var tabSize: Int
    public var whitespaceConfig: WhitespaceRenderer.Config
    public var wrapLayoutCache: WrapLayoutCache?

    public init(
        content: String = "",
        spans: [StyledSpan] = [],
        scrollOffset: Int = 0,
        wrapRowOffset: Int = 0,
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
        highlights: [Int: [TextHighlight]] = [:],
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle =
            HorizontalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true,
        maxLineWidth: Int = 0,
        tabSize: Int = 4,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled,
        wrapLayoutCache: WrapLayoutCache? = nil
    ) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            .map(
                String.init)
        self.source = ArrayDocumentSource(lines)
        self.lineSpans = lines.map { _ in spans }
        self.scrollOffset = scrollOffset
        self.wrapRowOffset = wrapRowOffset
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
        self.highlights = highlights
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.horizontalScrollIndicatorStyle = horizontalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
        self.maxLineWidth = maxLineWidth
        self.tabSize = tabSize
        self.whitespaceConfig = whitespaceConfig
        self.wrapLayoutCache = wrapLayoutCache
    }

    public init(
        lines: [String],
        lineSpans: [[StyledSpan]],
        scrollOffset: Int = 0,
        wrapRowOffset: Int = 0,
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
        highlights: [Int: [TextHighlight]] = [:],
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle =
            HorizontalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true,
        maxLineWidth: Int = 0,
        tabSize: Int = 4,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled,
        wrapLayoutCache: WrapLayoutCache? = nil
    ) {
        self.source = ArrayDocumentSource(lines)
        self.lineSpans = lineSpans
        self.scrollOffset = scrollOffset
        self.wrapRowOffset = wrapRowOffset
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
        self.highlights = highlights
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.horizontalScrollIndicatorStyle = horizontalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
        self.maxLineWidth = maxLineWidth
        self.tabSize = tabSize
        self.whitespaceConfig = whitespaceConfig
        self.wrapLayoutCache = wrapLayoutCache
    }

    public init(
        buffer: TextBuffer,
        lineSpans: [[StyledSpan]],
        scrollOffset: Int = 0,
        wrapRowOffset: Int = 0,
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
        highlights: [Int: [TextHighlight]] = [:],
        editorStyle: Style = .default,
        lineNumberStyle: Style = .default,
        currentLineStyle: Style = .default,
        verticalScrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(),
        horizontalScrollIndicatorStyle: HorizontalScrollIndicatorStyle =
            HorizontalScrollIndicatorStyle(),
        modeShowsCursor: Bool = true,
        maxLineWidth: Int = 0,
        tabSize: Int = 4,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled,
        wrapLayoutCache: WrapLayoutCache? = nil
    ) {
        self.source = buffer.lineCount == 0 ? TextBuffer(lines: [""]) : buffer
        self.lineSpans = lineSpans
        self.scrollOffset = scrollOffset
        self.wrapRowOffset = wrapRowOffset
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
        self.highlights = highlights
        self.editorStyle = editorStyle
        self.lineNumberStyle = lineNumberStyle
        self.currentLineStyle = currentLineStyle
        self.verticalScrollIndicatorStyle = verticalScrollIndicatorStyle
        self.horizontalScrollIndicatorStyle = horizontalScrollIndicatorStyle
        self.modeShowsCursor = modeShowsCursor
        self.maxLineWidth = maxLineWidth
        self.tabSize = tabSize
        self.whitespaceConfig = whitespaceConfig
        self.wrapLayoutCache = wrapLayoutCache
    }

    public var body: Never { fatalError() }

    public var lines: [String] {
        source.lines(in: 0 ..< source.lineCount)
    }

    public var lineCount: Int {
        max(1, source.lineCount)
    }

    public func line(at index: Int) -> String {
        source.line(at: index)
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
