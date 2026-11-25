/// What the hover panel's background is made of (book HOVER-08): Liquid Glass by default, or the popover material
/// the panel had before it.
package enum HoverPanelMaterial: String, CaseIterable, Identifiable, Sendable {
    /// `NSGlassEffectView`'s regular glass, shaped to the panel's rounded corners.
    case liquidGlass
    /// `NSVisualEffectView`'s popover material, masked to the panel's rounded corners.
    case popover

    package var id: String { rawValue }
}
