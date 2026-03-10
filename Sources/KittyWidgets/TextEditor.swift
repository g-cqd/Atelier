import KittyCodecs
import KittySyntax

/// Scrollable syntax-highlighted text display widget.
public struct TextEditor: View, Sendable {
    public var lines: [String]
    public var spans: [StyledSpan]
    public var scrollOffset: Int
    public var cursorRow: Int
    public var cursorCol: Int
    public var showLineNumbers: Bool

    public init(
        content: String = "",
        spans: [StyledSpan] = [],
        scrollOffset: Int = 0,
        cursorRow: Int = 0,
        cursorCol: Int = 0,
        showLineNumbers: Bool = true
    ) {
        self.lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.spans = spans
        self.scrollOffset = scrollOffset
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.showLineNumbers = showLineNumbers
    }

    public var body: Never { fatalError() }

    /// Number of digits needed for line numbers.
    public var lineNumberWidth: Int {
        let count = lines.count
        if count < 10 { return 1 }
        if count < 100 { return 2 }
        if count < 1000 { return 3 }
        if count < 10000 { return 4 }
        return 5
    }
}
