import KittyInput

/// Manages focus state for view hierarchies.
/// Tab/Shift-Tab cycles focus; the focused view receives input events first.
public struct FocusEngine: Sendable {
    public var focusedIndex: Int
    public var focusableCount: Int

    public init(focusedIndex: Int = 0, focusableCount: Int = 1) {
        self.focusedIndex = max(0, focusedIndex)
        self.focusableCount = max(1, focusableCount)
    }

    /// Move focus forward (Tab).
    public mutating func focusNext() {
        focusedIndex = (focusedIndex + 1) % focusableCount
    }

    /// Move focus backward (Shift-Tab).
    public mutating func focusPrevious() {
        focusedIndex = (focusedIndex - 1 + focusableCount) % focusableCount
    }

    /// Check if a given index is focused.
    public func isFocused(_ index: Int) -> Bool {
        index == focusedIndex
    }
}
