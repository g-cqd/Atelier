/// The highlight role of each capture name of a query, resolved once: entry `i` is what ``CaptureRoleMapper/map(_:)``
/// gives the query's capture name `i`, or nil when that capture colours no text (``CaptureRoleMapper/colorsText(_:)``).
/// A highlighter then reads each capture's role by the capture's index, with no lookup by name per capture.
public struct CaptureRoles: Sendable, Equatable {
    @usableFromInline
    struct Entry: Sendable, Equatable {
        @usableFromInline var role: HighlightRole
        @usableFromInline var modifiers: HighlightModifierSet
        @usableFromInline var colorsText: Bool
    }

    @usableFromInline let entries: [Entry]

    /// The roles of `captureNames`, a query's capture names in index order.
    public init(captureNames: [String]) {
        entries = captureNames.map { name in
            let (role, modifiers) = CaptureRoleMapper.map(name)
            return Entry(role: role, modifiers: modifiers, colorsText: CaptureRoleMapper.colorsText(name))
        }
    }

    /// The number of capture names.
    public var count: Int { entries.count }

    /// The role and modifiers of capture name `index`, or nil when that capture colours no text or no capture name has
    /// that index.
    /// - Complexity: O(1)
    @inlinable
    public subscript(index: Int) -> (role: HighlightRole, modifiers: HighlightModifierSet)? {
        guard entries.indices.contains(index) else { return nil }
        let entry = entries[index]
        return entry.colorsText ? (entry.role, entry.modifiers) : nil
    }
}
