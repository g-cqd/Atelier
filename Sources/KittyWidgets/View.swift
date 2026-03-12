import KittyCodecs
import KittyInput
import KittyRenderer

// MARK: - Size

public struct Size: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public static let zero = Size(width: 0, height: 0)

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

// MARK: - ProposedSize

public struct ProposedSize: Sendable, Equatable {
    public var width: Int?
    public var height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }
}

// MARK: - Event Result

public enum EventResult: Sendable {
    case handled
    case ignored
}

// MARK: - View Protocol

public protocol View: Sendable {
    associatedtype Body: View

    @ViewBuilder var body: Body { get }
}

extension View {
    /// Compute the size this view needs.
    public func size(proposed: ProposedSize) -> Size {
        Size(width: proposed.width ?? 0, height: proposed.height ?? 0)
    }

    /// Render this view into a buffer. Default dispatches to ViewRenderer.
    public func render(
        to buffer: inout ScreenBuffer, in rect: Rect, context: RenderContext = RenderContext()
    ) {
        ViewRenderer.render(self, into: &buffer, in: rect, context: context)
    }

    /// Handle an input event. Default returns .ignored.
    public func handleEvent(_ event: InputEvent) -> EventResult {
        .ignored
    }
}

// MARK: - Never View (leaf terminator)

extension Never: View {
    public var body: Never { fatalError() }
}

// MARK: - EmptyView

public struct EmptyView: View, Sendable {
    public init() {}
    public var body: Never { fatalError() }
}

// MARK: - Text

public struct Text: View, Sendable {
    public let content: String
    public var style: Style

    public init(_ content: String, style: Style = .default) {
        self.content = content
        self.style = style
    }

    public var body: Never { fatalError() }
}

// MARK: - StyledText

public struct StyledTextView: View, Sendable {
    public let spans: [StyledTextSpan]

    public struct StyledTextSpan: Sendable {
        public var text: String
        public var style: Style
        public init(text: String, style: Style) {
            self.text = text
            self.style = style
        }
    }

    public init(_ spans: [StyledTextSpan]) {
        self.spans = spans
    }

    public var body: Never { fatalError() }
}
