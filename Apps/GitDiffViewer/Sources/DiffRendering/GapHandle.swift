package import CoreGraphics

/// Which neighbouring change a gap handle extends into the rows the gap hides (book DIFF-02).
package enum GapHandle: Sendable, Hashable {
    /// Extends the change above the gap downwards, revealing the rows after it; dragged down.
    case extendsChangeAbove
    /// Extends the change below the gap upwards, revealing the rows before it; dragged up.
    case extendsChangeBelow

    /// The sign of the vertical travel that reveals rows: down for the change above, up for the change below.
    package var revealDirection: CGFloat {
        switch self {
            case .extendsChangeAbove: 1
            case .extendsChangeBelow: -1
        }
    }
}

extension GapMarker {
    /// The handles this gap offers, one per neighbouring change, so a run between two changes grows from either side.
    /// A gap with no change on either side, a whole file without one, offers none.
    package var handles: [GapHandle] {
        switch (isLeading, isTrailing) {
            case (false, false): [.extendsChangeAbove, .extendsChangeBelow]
            case (true, false): [.extendsChangeBelow]
            case (false, true): [.extendsChangeAbove]
            case (true, true): []
        }
    }

    /// What a handle's tooltip says: how many lines the gap hides, which no row shows, and how to reveal them.
    package var handleHelp: String {
        "\(hiddenRows) hidden \(hiddenRows == 1 ? "line" : "lines"). Drag to reveal; double-click to reveal all"
    }
}

/// What the view tracking a gap handle reports to the model that owns the drag. The view only measures the pointer;
/// which rows that reveals is the model's to decide.
package enum GapDragEvent: Sendable, Equatable {
    /// The pointer went down on `handle` of the gap `marker`, in a pane whose rows are `lineHeight` points tall.
    case began(GapMarker, GapHandle, lineHeight: CGFloat)
    /// The pointer is `offset` points below where it went down, negative above, and `edgeOvershoot` points into the
    /// edge zone of the viewport or the card in the handle's direction; zero or less while clear of it.
    case moved(offset: CGFloat, edgeOvershoot: CGFloat)
    /// The pointer went up.
    case ended
    /// A double click on `handle`: every row the gap hides, revealed from that side.
    case revealedAll(GapMarker, GapHandle)
}
