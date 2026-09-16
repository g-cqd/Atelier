// MARK: - EdgeInsets

public struct EdgeInsets: Sendable, Equatable {
    public var top: Int
    public var bottom: Int
    public var left: Int
    public var right: Int

    public init(top: Int = 0, bottom: Int = 0, left: Int = 0, right: Int = 0) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public init(all: Int) {
        self.top = all
        self.bottom = all
        self.left = all
        self.right = all
    }
}

// MARK: - PaddingModifier

public struct PaddingModifier: ViewModifier, Sendable {
    public let insets: EdgeInsets

    public func body(content: Content) -> some View { content }
}

// MARK: - View Extension

extension View {
    public func padding(_ amount: Int = 1) -> some View {
        ModifiedView(content: self, modifier: PaddingModifier(insets: EdgeInsets(all: amount)))
    }

    public func padding(top: Int = 0, bottom: Int = 0, left: Int = 0, right: Int = 0) -> some View
    {
        ModifiedView(
            content: self,
            modifier: PaddingModifier(
                insets: EdgeInsets(top: top, bottom: bottom, left: left, right: right)))
    }
}
