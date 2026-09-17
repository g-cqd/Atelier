public import KittyCodecs
public import KittyTerminal

/// A one-pixel line drawn under the cells with the kitty graphics protocol: a pane separator, a ribbon underline
/// or a gutter rule that costs no cell column or row.
public struct ChromeLine: Sendable, Equatable, Hashable {
    public enum Axis: Sendable, Hashable {
        case vertical
        case horizontal
    }

    public var axis: Axis
    /// The cell the line starts in.
    public var row: Int
    public var column: Int
    /// How many cells the line spans along its axis.
    public var length: Int
    public var color: ColorRGB
    /// Where in the starting cell the line sits, in pixels from its left (vertical) or top (horizontal) edge.
    public var offset: Int

    public init(axis: Axis, row: Int, column: Int, length: Int, color: ColorRGB, offset: Int = 0) {
        self.axis = axis
        self.row = row
        self.column = column
        self.length = length
        self.color = color
        self.offset = offset
    }
}

/// Draws ``ChromeLine``s as image placements below the text (`z=-1`), transmitting each distinct line image
/// once and re-placing lines only when the set of lines changes or the terminal moved them.
///
/// Image ids live in a range of their own (`1 << 20` upwards) so they cannot collide with any other image the
/// app places. Every command is quiet, so nothing comes back on the input stream.
public struct PixelChrome: Sendable, Equatable {
    public let cell: TerminalCapabilities.CellPixelSize
    private var imageIDs: [ImageKey: UInt32] = [:]
    private var nextImageID: UInt32 = 1 << 20
    private var placed: [ChromeLine] = []
    private var pendingDelete: Deletion?

    private enum Deletion {
        case placements
        case everything
    }

    private struct ImageKey: Hashable {
        var axis: ChromeLine.Axis
        var pixels: Int
        var color: ColorRGB
    }

    public init(cell: TerminalCapabilities.CellPixelSize) {
        self.cell = cell
    }

    /// Whether `lines` are the ones already on screen.
    public func isCurrent(_ lines: [ChromeLine]) -> Bool {
        placed == lines
    }

    /// The placements on screen moved or were painted over (a scroll, a full redraw): the next ``render``
    /// deletes them and places every line again, keeping the transmitted images.
    public mutating func invalidate() {
        placed = []
        if pendingDelete == nil { pendingDelete = .placements }
    }

    /// The cell size or the screen changed: the next ``render`` deletes every placement and image and
    /// transmits afresh.
    public mutating func reset() {
        placed = []
        imageIDs = [:]
        pendingDelete = .everything
    }

    /// Appends the commands that make `lines` the lines on screen: nothing when they already are, otherwise a
    /// delete of the previous placements, any image not yet transmitted, and one placement per line.
    /// - Complexity: O(lines)
    public mutating func render(_ lines: [ChromeLine], into bytes: inout ContiguousArray<UInt8>) {
        guard placed != lines || pendingDelete != nil else { return }
        switch pendingDelete {
            case .everything:
                bytes.append(contentsOf: Self.deleteAllBytes)
            case .placements:
                bytes.append(contentsOf: Self.deletePlacementsBytes)
            case nil:
                if !placed.isEmpty { bytes.append(contentsOf: Self.deletePlacementsBytes) }
        }
        pendingDelete = nil
        for (index, line) in lines.enumerated() where line.length > 0 {
            let id = imageID(for: line, into: &bytes)
            KittySequences.appendMoveCursor(row: line.row + 1, col: line.column + 1, to: &bytes)
            let placement = GraphicsCommand.Placement(
                id: UInt32(index + 1), zIndex: -1,
                xOffset: line.axis == .vertical ? UInt32(max(0, line.offset)) : 0,
                yOffset: line.axis == .horizontal ? UInt32(max(0, line.offset)) : 0)
            bytes.append(
                contentsOf: GraphicsEncoder.encode(
                    GraphicsCommand(action: .placement, id: id, placement: placement, isQuiet: true)))
        }
        placed = lines
    }

    /// The command deleting every placement and its image data, for teardown or a resize.
    public static let deleteAllBytes: [UInt8] = GraphicsEncoder.encode(
        GraphicsCommand(action: .delete, deletion: .allPlacements(freeingData: true), isQuiet: true))

    /// The command deleting every placement while keeping the image data for re-placing.
    public static let deletePlacementsBytes: [UInt8] = GraphicsEncoder.encode(
        GraphicsCommand(action: .delete, deletion: .allPlacements(freeingData: false), isQuiet: true))

    private mutating func imageID(for line: ChromeLine, into bytes: inout ContiguousArray<UInt8>) -> UInt32 {
        let pixels = line.length * (line.axis == .vertical ? cell.height : cell.width)
        let key = ImageKey(axis: line.axis, pixels: pixels, color: line.color)
        if let id = imageIDs[key] { return id }
        let id = nextImageID
        nextImageID += 1
        imageIDs[key] = id
        let alpha = UInt8((min(max(line.color.alpha, 0), 1) * 255).rounded())
        var payload: [UInt8] = []
        payload.reserveCapacity(pixels * 4)
        for _ in 0 ..< pixels {
            payload.append(contentsOf: [line.color.r, line.color.g, line.color.b, alpha])
        }
        let (width, height) = line.axis == .vertical ? (1, pixels) : (pixels, 1)
        bytes.append(
            contentsOf: GraphicsEncoder.encode(
                GraphicsCommand(
                    action: .transmit, format: .rgba, transmission: .direct, id: id, width: UInt32(width),
                    height: UInt32(height), payload: payload, isQuiet: true)))
        return id
    }
}
