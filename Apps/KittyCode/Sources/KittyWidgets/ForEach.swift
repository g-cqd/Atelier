// MARK: - ForEachProtocol

/// Type-erased protocol allowing the ViewRenderer to iterate ForEach children
/// without knowing the concrete generic parameters.
public protocol ForEachProtocol {
    var childViews: [any View & Sendable] { get }
}

// MARK: - ForEach

/// Renders a collection of elements as a vertical sequence of child views.
///
/// Identity tracking is not needed in this terminal UI framework, so elements
/// only require `Sendable` rather than `Identifiable`.
public struct ForEach<Data: RandomAccessCollection & Sendable, Content: View & Sendable>: View,
    Sendable
where Data.Element: Sendable {
    public let data: Data
    public let content: @Sendable (Data.Element) -> Content

    public init(
        _ data: Data,
        @ViewBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) {
        self.data = data
        self.content = content
    }

    public var body: Never { fatalError() }
}

extension ForEach: ForEachProtocol {
    public var childViews: [any View & Sendable] {
        data.map { content($0) }
    }
}
