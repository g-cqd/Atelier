import KittyCodecs

// MARK: - View Modifier Protocol

public protocol ViewModifier: Sendable {
    associatedtype Body: View
    @ViewBuilder func body(content: Content) -> Body
}

extension ViewModifier {
    public typealias Content = AnyViewContent
}

/// Placeholder for content passed to modifiers.
public struct AnyViewContent: View, Sendable {
    public var body: Never { fatalError() }
}

// MARK: - Modified View

public struct ModifiedView<Content: View, Modifier: ViewModifier>: View, Sendable {
    public let content: Content
    public let modifier: Modifier

    public var body: some View {
        modifier.body(content: AnyViewContent())
    }
}

// MARK: - Style Modifiers

extension View {
    public func foreground(_ color: Color) -> some View {
        ModifiedView(content: self, modifier: ForegroundModifier(color: color))
    }

    public func background(_ color: Color) -> some View {
        ModifiedView(content: self, modifier: BackgroundModifier(color: color))
    }

    public func bold() -> some View {
        ModifiedView(content: self, modifier: BoldModifier())
    }

    public func italic() -> some View {
        ModifiedView(content: self, modifier: ItalicModifier())
    }
}

// MARK: - Concrete Modifiers

public struct ForegroundModifier: ViewModifier, Sendable {
    let color: Color
    public func body(content: Content) -> some View { content }
}

public struct BackgroundModifier: ViewModifier, Sendable {
    let color: Color
    public func body(content: Content) -> some View { content }
}

public struct BoldModifier: ViewModifier, Sendable {
    public func body(content: Content) -> some View { content }
}

public struct ItalicModifier: ViewModifier, Sendable {
    public func body(content: Content) -> some View { content }
}
