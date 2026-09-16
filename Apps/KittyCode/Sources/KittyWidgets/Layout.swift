// MARK: - VStack

public struct VStack<Content: View>: View, Sendable {
    public let content: Content
    public let spacing: Int

    public init(spacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never { fatalError() }
}

// MARK: - HStack

public struct HStack<Content: View>: View, Sendable {
    public let content: Content
    public let spacing: Int

    public init(spacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never { fatalError() }
}

// MARK: - ZStack

public struct ZStack<Content: View>: View, Sendable {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never { fatalError() }
}
