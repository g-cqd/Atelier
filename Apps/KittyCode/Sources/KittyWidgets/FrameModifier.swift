public struct FrameModifier: ViewModifier, Sendable {
    let width: LayoutDimension?
    let height: LayoutDimension?

    public func body(content: Content) -> some View { content }
}

extension View {
    public func frame(width: Int) -> some View {
        ModifiedView(content: self, modifier: FrameModifier(width: .fixed(width), height: nil))
    }

    public func frame(minWidth: Int) -> some View {
        ModifiedView(content: self, modifier: FrameModifier(width: .flexible(min: minWidth), height: nil))
    }

    public func frame(height: Int) -> some View {
        ModifiedView(content: self, modifier: FrameModifier(width: nil, height: .fixed(height)))
    }

    public func frame(width: Int, height: Int) -> some View {
        ModifiedView(content: self, modifier: FrameModifier(width: .fixed(width), height: .fixed(height)))
    }

    public func frame(minWidth: Int, height: Int) -> some View {
        ModifiedView(content: self, modifier: FrameModifier(width: .flexible(min: minWidth), height: .fixed(height)))
    }
}
