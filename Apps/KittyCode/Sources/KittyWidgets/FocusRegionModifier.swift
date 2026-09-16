public struct FocusRegionModifier: ViewModifier, Sendable {
    let region: FocusRegion

    public func body(content: Content) -> some View { content }
}

extension View {
    public func focusRegion(_ region: FocusRegion) -> some View {
        ModifiedView(content: self, modifier: FocusRegionModifier(region: region))
    }
}
