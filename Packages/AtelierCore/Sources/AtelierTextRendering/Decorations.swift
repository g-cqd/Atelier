/// Row-level and range-level paint, layered above the text model (text-renderer.md §3.2). A layer can change without
/// touching text: diff row backgrounds, intraline emphasis and squiggles each land as their own layer, progressively,
/// and text never waits for one to arrive.
public struct LayerID: Hashable, Sendable {
    public var rawValue: Int

    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

/// The shape a squiggle or a plain underline draws.
public enum UnderlineShape: Hashable, Sendable {
    case single
    case squiggle
    case double
}

public struct DecorationLayer: Sendable, Identifiable {
    public enum Paint: Hashable, Sendable {
        /// Fills the row's full width, gutter to trailing edge, e.g. a diff row background.
        case rowFill(ColorRef)
        /// Fills one byte range of the row, e.g. intraline emphasis.
        case rangeFill(Range<ByteOffset>, ColorRef)
        /// `nil` range underlines the whole row.
        case underline(Range<ByteOffset>?, UnderlineShape, ColorRef)
    }

    public let id: LayerID
    public var zIndex: Int
    /// Sparse: only the rows that changed need be present.
    public var paints: [RowIndex: [Paint]]

    public init(id: LayerID, zIndex: Int, paints: [RowIndex: [Paint]]) {
        self.id = id
        self.zIndex = zIndex
        self.paints = paints
    }
}
