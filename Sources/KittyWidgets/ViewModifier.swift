import KittyCodecs

// MARK: - View Modifier Protocol

public protocol ViewModifier: Sendable {
    associatedtype Body: View
    @ViewBuilder func body(content: Content) -> Body

    /// Return the render context modifications this modifier applies.
    func modifyContext(_ context: RenderContext) -> RenderContext
}

extension ViewModifier {
    public typealias Content = AnyViewContent

    /// Default implementation: no context modification.
    public func modifyContext(_ context: RenderContext) -> RenderContext {
        context
    }
}

/// Placeholder for content passed to modifiers.
public struct AnyViewContent: View, Sendable {
    private let storage: any Sendable

    public init() {
        self.storage = EmptyView()
    }

    public init<Content: View>(_ content: Content) {
        self.storage = content
    }

    public func resolve<Content: View>(as type: Content.Type = Content.self) -> Content? {
        storage as? Content
    }

    public var body: Never { fatalError() }
}

// MARK: - Modified View

public struct ModifiedView<Content: View, Modifier: ViewModifier>: View, Sendable {
    public let content: Content
    public let modifier: Modifier

    public var modifierContent: AnyViewContent {
        AnyViewContent(content)
    }

    public var body: some View {
        modifier.body(content: modifierContent)
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

    public func modifyContext(_ context: RenderContext) -> RenderContext {
        var ctx = context
        ctx.foreground = color
        return ctx
    }
}

public struct BackgroundModifier: ViewModifier, Sendable {
    let color: Color

    public func body(content: Content) -> some View { content }

    public func modifyContext(_ context: RenderContext) -> RenderContext {
        var ctx = context
        ctx.background = color
        return ctx
    }
}

public struct BoldModifier: ViewModifier, Sendable {
    public func body(content: Content) -> some View { content }

    public func modifyContext(_ context: RenderContext) -> RenderContext {
        var ctx = context
        ctx.bold = true
        return ctx
    }
}

public struct ItalicModifier: ViewModifier, Sendable {
    public func body(content: Content) -> some View { content }

    public func modifyContext(_ context: RenderContext) -> RenderContext {
        var ctx = context
        ctx.italic = true
        return ctx
    }
}

public struct FocusedModifier: ViewModifier, Sendable {
    let isFocused: Bool

    public func body(content: Content) -> some View { content }

    public func modifyContext(_ context: RenderContext) -> RenderContext {
        var ctx = context
        ctx.isFocused = isFocused
        return ctx
    }
}

extension View {
    public func focused(_ isFocused: Bool) -> some View {
        ModifiedView(content: self, modifier: FocusedModifier(isFocused: isFocused))
    }
}
