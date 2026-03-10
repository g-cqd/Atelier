import KittyTerminal
import KittyCodecs

/// Double-buffered render pipeline with synchronized output.
public final class RenderPipeline: @unchecked Sendable {
    private let connection: any TerminalConnection
    private var front: ScreenBuffer
    private var back: ScreenBuffer

    public var columns: Int { back.columns }
    public var rows: Int { back.rows }

    public init(connection: any TerminalConnection, columns: Int, rows: Int) {
        self.connection = connection
        self.front = ScreenBuffer(columns: columns, rows: rows)
        self.back = ScreenBuffer(columns: columns, rows: rows)
    }

    /// Access the back buffer for writing.
    public var buffer: ScreenBuffer {
        get { back }
        set { back = newValue }
    }

    /// Flush the diff between front and back buffers to the terminal,
    /// wrapped in synchronized output markers.
    public func flush() throws(TerminalError) {
        let diffBytes = DiffRenderer.render(front: front, back: back)
        guard !diffBytes.isEmpty else { return }

        var output: [UInt8] = []
        output.append(contentsOf: KittySequences.beginSyncUpdate)
        output.append(contentsOf: KittySequences.hideCursor)
        output.append(contentsOf: diffBytes)
        output.append(contentsOf: KittySequences.showCursor)
        output.append(contentsOf: KittySequences.endSyncUpdate)

        try connection.write(output)

        // Swap: copy back → front, clear dirty bits
        front = back
        back.dirty.clear()
    }

    /// Force a full redraw.
    public func forceRedraw() throws(TerminalError) {
        let fullBytes = DiffRenderer.renderFull(back)
        var output: [UInt8] = []
        output.append(contentsOf: KittySequences.beginSyncUpdate)
        output.append(contentsOf: KittySequences.hideCursor)
        output.append(contentsOf: fullBytes)
        output.append(contentsOf: KittySequences.showCursor)
        output.append(contentsOf: KittySequences.endSyncUpdate)
        try connection.write(output)
        front = back
        back.dirty.clear()
    }

    /// Resize both buffers.
    public func resize(columns: Int, rows: Int) {
        front.resize(columns: columns, rows: rows)
        back.resize(columns: columns, rows: rows)
    }
}
