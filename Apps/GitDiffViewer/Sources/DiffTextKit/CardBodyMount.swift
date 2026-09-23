/// Decides when a card's body is mounted. An unfolded card's body is mounted for its current inputs. A fold keeps the
/// body mounted, for the card's shrinking edge to clip away, until the card shows none of it. A folded card holds
/// none, and unfolding mounts the body again before the card grows to show it.
package struct CardBodyMount<Inputs: Equatable> {
    /// What the owner does to the body.
    package enum Change: Equatable {
        case none
        /// Builds the body from these inputs, replacing any body mounted before.
        case mount(Inputs)
        /// Removes the body's content, panes and all.
        case unmount
    }

    /// The inputs the mounted body was built from, or nil while none is mounted.
    package private(set) var mounted: Inputs?

    package init() {}

    /// Follows the card's inputs and fold state.
    /// - Parameters:
    ///   - inputs: What the body would be built from, or nil while the card cannot lay its panes out, such as before it
    ///     has a width. Nil leaves an unfolded card's body as it is.
    ///   - isCollapsed: Whether the card is folded, or folding.
    /// - Returns: `mount` for an unfolded card whose inputs changed, `unmount` for a folded card whose inputs changed
    ///   while its body was still mounted, `none` otherwise: a fold under way keeps its body.
    package mutating func update(to inputs: Inputs?, isCollapsed: Bool) -> Change {
        if isCollapsed {
            guard let mounted, mounted != inputs else { return .none }
            self.mounted = nil
            return .unmount
        }
        guard let inputs, inputs != mounted else { return .none }
        mounted = inputs
        return .mount(inputs)
    }

    /// Takes the report that the card shows none of its body.
    /// - Parameter isCollapsed: Whether the card is folded. An unfolded card can show no body for a moment, while it
    ///   has no size yet, and keeps it.
    /// - Returns: `unmount` once a folded card's fold has hidden its mounted body, `none` otherwise.
    package mutating func bodyHidden(isCollapsed: Bool) -> Change {
        guard isCollapsed, mounted != nil else { return .none }
        mounted = nil
        return .unmount
    }
}
