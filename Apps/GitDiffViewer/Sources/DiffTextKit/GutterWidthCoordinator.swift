package import Foundation

/// Shares one gutter width across a card list (book D43, "one gutter width across the card list"): each card's gutter
/// registers the width its own numbers, markers and ribbon need, and every registered gutter reads back the widest
/// any of them needs, so their trailing edges line up. A card appearing with more digits widens every card's gutter
/// together; a card leaving drops its own width from the shared one. Registering or updating a width that does not
/// move the shared one calls no gutter back, so a list settling on one width, or a card matching it already, causes no
/// storm of invalidation; only a card's own wrapped text re-measures, since a card that fits merely follows the clip
/// view it already tracks.
@MainActor
package final class GutterWidthCoordinator {
    private var widths: [ObjectIdentifier: CGFloat] = [:]
    private var observers: [ObjectIdentifier: () -> Void] = [:]

    package init() {}

    /// The widest width any registered gutter needs; zero when none is registered.
    package var sharedWidth: CGFloat { widths.values.max() ?? 0 }

    /// Registers `id` with its own natural width, and what to call whenever the shared width moves because of it or
    /// another gutter's; replaces an earlier registration under the same id. Tells every gutter, this one included,
    /// when the new width widens the shared one; a card matching the width already in force calls nothing back.
    package func register(_ id: ObjectIdentifier, width: CGFloat, onChange: @escaping () -> Void) {
        let before = sharedWidth
        observers[id] = onChange
        widths[id] = width
        guard sharedWidth != before else { return }
        notifyAll()
    }

    /// `id`'s own natural width changed; tells every registered gutter, `id`'s included, to invalidate its size when
    /// that moved the shared width, and nothing when it did not.
    package func update(_ id: ObjectIdentifier, width: CGFloat) {
        let before = sharedWidth
        widths[id] = width
        guard sharedWidth != before else { return }
        notifyAll()
    }

    /// A card left the list: its own width no longer counts towards the shared one, which may shrink back for the
    /// gutters that remain.
    package func unregister(_ id: ObjectIdentifier) {
        guard widths[id] != nil else { return }
        let before = sharedWidth
        widths[id] = nil
        observers[id] = nil
        guard sharedWidth != before else { return }
        notifyAll()
    }

    private func notifyAll() {
        for onChange in observers.values { onChange() }
    }
}
