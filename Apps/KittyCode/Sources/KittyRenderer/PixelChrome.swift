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

/// One thing drawn in pixels under the cells.
public enum ChromeElement: Sendable, Hashable {
    /// A one-pixel line.
    case line(ChromeLine)
    /// A cell-aligned area filled with a colour: a one-pixel image scaled to `columns` by `rows` cells, so a
    /// selection, the current line, a search hit or a bar's band costs a placement and no payload.
    case fill(row: Int, column: Int, columns: Int, rows: Int, color: ColorRGB)
    /// A vertical bar of `widthPixels` by `heightPixels`, offset inside its first cell by pixels: gutter marks,
    /// scroll tracks and thumbs, placed to the pixel rather than the cell.
    case bar(row: Int, column: Int, widthPixels: Int, heightPixels: Int, color: ColorRGB, xOffset: Int, yOffset: Int)
}

/// Draws ``ChromeElement``s as image placements below the text (`z=-1`), transmitting each distinct image once
/// and re-placing elements only when the set changes or the terminal moved them.
///
/// Image ids live in a range of their own (`1 << 20` upwards) so they cannot collide with any other image the
/// app places. Every command is quiet, so nothing comes back on the input stream.
public struct PixelChrome: Sendable, Equatable {
    public let cell: TerminalCapabilities.CellPixelSize
    private var imageIDs: [ImageKey: UInt32] = [:]
    private var nextImageID: UInt32 = 1 << 20
    private var placed: [ChromeElement] = []
    private var pendingDelete: Deletion?

    private enum Deletion {
        case placements
        case everything
    }

    private struct ImageKey: Hashable {
        var width: Int
        var height: Int
        var color: ColorRGB
    }

    public init(cell: TerminalCapabilities.CellPixelSize) {
        self.cell = cell
    }

    /// Whether `lines` are the ones already on screen.
    public func isCurrent(_ lines: [ChromeLine]) -> Bool {
        placed == lines.map(ChromeElement.line)
    }

    /// The placements on screen moved or were painted over (a scroll, a full redraw): the next ``render``
    /// deletes them and places every element again, keeping the transmitted images.
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

    public mutating func render(_ lines: [ChromeLine], into bytes: inout ContiguousArray<UInt8>) {
        render(lines.map(ChromeElement.line), into: &bytes)
    }

    /// Appends the commands that make `elements` the elements on screen: nothing when they already are,
    /// otherwise a delete of the previous placements, any image not yet transmitted, and one placement each.
    /// - Complexity: O(elements)
    public mutating func render(_ elements: [ChromeElement], into bytes: inout ContiguousArray<UInt8>) {
        guard placed != elements || pendingDelete != nil else { return }
        switch pendingDelete {
            case .everything:
                bytes.append(contentsOf: Self.deleteAllBytes)
            case .placements:
                bytes.append(contentsOf: Self.deletePlacementsBytes)
            case nil:
                if !placed.isEmpty { bytes.append(contentsOf: Self.deletePlacementsBytes) }
        }
        pendingDelete = nil
        for (index, element) in elements.enumerated() {
            let placementID = UInt32(index + 1)
            switch element {
                case .line(let line):
                    guard line.length > 0 else { continue }
                    let pixels = line.length * (line.axis == .vertical ? cell.height : cell.width)
                    let (width, height) = line.axis == .vertical ? (1, pixels) : (pixels, 1)
                    let id = imageID(width: width, height: height, color: line.color, into: &bytes)
                    place(
                        id: id, placement: placementID, row: line.row, column: line.column,
                        xOffset: line.axis == .vertical ? line.offset : 0,
                        yOffset: line.axis == .horizontal ? line.offset : 0, into: &bytes)
                case .fill(let row, let column, let columns, let rows, let color):
                    guard columns > 0, rows > 0 else { continue }
                    let id = imageID(width: 1, height: 1, color: color, into: &bytes)
                    place(
                        id: id, placement: placementID, row: row, column: column, columns: columns, rows: rows,
                        into: &bytes)
                case .bar(let row, let column, let widthPixels, let heightPixels, let color, let xOffset, let yOffset):
                    guard heightPixels > 0, widthPixels > 0 else { continue }
                    let id = imageID(width: widthPixels, height: heightPixels, color: color, into: &bytes)
                    place(
                        id: id, placement: placementID, row: row, column: column, xOffset: xOffset, yOffset: yOffset,
                        into: &bytes)
            }
        }
        placed = elements
    }

    /// The command deleting every placement and its image data, for teardown or a resize.
    public static let deleteAllBytes: [UInt8] = GraphicsEncoder.encode(
        GraphicsCommand(action: .delete, deletion: .allPlacements(freeingData: true), isQuiet: true))

    /// The command deleting every placement while keeping the image data for re-placing.
    public static let deletePlacementsBytes: [UInt8] = GraphicsEncoder.encode(
        GraphicsCommand(action: .delete, deletion: .allPlacements(freeingData: false), isQuiet: true))

    private func place(
        id: UInt32, placement: UInt32, row: Int, column: Int, xOffset: Int = 0, yOffset: Int = 0, columns: Int = 0,
        rows: Int = 0, into bytes: inout ContiguousArray<UInt8>
    ) {
        KittySequences.appendMoveCursor(row: row + 1, col: column + 1, to: &bytes)
        let placement = GraphicsCommand.Placement(
            id: placement, zIndex: -1, xOffset: UInt32(max(0, xOffset)), yOffset: UInt32(max(0, yOffset)),
            columns: UInt32(max(0, columns)), rows: UInt32(max(0, rows)))
        bytes.append(
            contentsOf: GraphicsEncoder.encode(
                GraphicsCommand(action: .placement, id: id, placement: placement, isQuiet: true)))
    }

    private mutating func imageID(width: Int, height: Int, color: ColorRGB, into bytes: inout ContiguousArray<UInt8>)
        -> UInt32
    {
        let key = ImageKey(width: width, height: height, color: color)
        if let id = imageIDs[key] { return id }
        let id = nextImageID
        nextImageID += 1
        imageIDs[key] = id
        let alpha = UInt8((min(max(color.alpha, 0), 1) * 255).rounded())
        var payload: [UInt8] = []
        payload.reserveCapacity(width * height * 4)
        for _ in 0 ..< (width * height) {
            payload.append(contentsOf: [color.r, color.g, color.b, alpha])
        }
        bytes.append(
            contentsOf: GraphicsEncoder.encode(
                GraphicsCommand(
                    action: .transmit, format: .rgba, transmission: .direct, id: id, width: UInt32(width),
                    height: UInt32(height), payload: payload, isQuiet: true)))
        return id
    }
}
