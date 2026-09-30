public import CoreGraphics

/// One row's typeset geometry (text-renderer.md §3.11): its height and the visual lines it wrapped onto, one unless
/// it wrapped.
public struct RowGeometry: Sendable {
    public var height: Float
    public var lines: [VisualLine]

    public init(height: Float, lines: [VisualLine]) {
        self.height = height
        self.lines = lines
    }
}

/// One visual (wrapped) line of a row.
public struct VisualLine: Sendable {
    /// The row-relative byte range this line covers.
    public var bytes: Range<ByteOffset>
    /// The x position of every UTF-16 boundary in the line, in visual (left-to-right on screen) order resolved.
    public var carets: [Float]
    /// Baseline y from the top of the line's own box.
    public var baseline: Float
    /// The line's width, glyph advance only.
    public var width: Float

    public init(bytes: Range<ByteOffset>, carets: [Float], baseline: Float, width: Float) {
        self.bytes = bytes
        self.carets = carets
        self.baseline = baseline
        self.width = width
    }
}

/// One rasterized tile: an image and the geometry of the rows drawn into it (text-renderer.md §3.5).
public struct RenderedTile: Sendable {
    public var rows: Range<RowIndex>
    public var image: CGImage
    public var geometry: [RowGeometry]

    public init(rows: Range<RowIndex>, image: CGImage, geometry: [RowGeometry]) {
        self.rows = rows
        self.image = image
        self.geometry = geometry
    }
}
