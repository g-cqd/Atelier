import KittyTerminal
import KittyCodecs

/// Double-buffered render pipeline with synchronized output.
@MainActor
public final class RenderPipeline: Sendable {
    private let connection: any TerminalConnection
    private var front: ScreenBuffer
    private var back: ScreenBuffer

    /// The current number of columns in the render viewport.
    public var columns: Int { back.columns }

    /// The current number of rows in the render viewport.
    public var rows: Int { back.rows }

    /// The zero-based row at which the cursor should be positioned after each flush.
    ///
    /// When `nil`, the cursor is hidden at the end of the flush sequence.
    public var cursorRow: Int?

    /// The zero-based column at which the cursor should be positioned after each flush.
    ///
    /// When `nil`, the cursor is hidden at the end of the flush sequence.
    public var cursorCol: Int?

    /// Creates a pipeline backed by the given terminal connection and initial viewport dimensions.
    ///
    /// - Parameters:
    ///   - connection: The terminal connection used to write escape sequences.
    ///   - columns: The initial number of columns in the viewport.
    ///   - rows: The initial number of rows in the viewport.
    public init(connection: any TerminalConnection, columns: Int, rows: Int) {
        self.connection = connection
        self.front = ScreenBuffer(columns: columns, rows: rows)
        self.back = ScreenBuffer(columns: columns, rows: rows)
    }

    /// The back buffer used for compositing the next frame.
    ///
    /// Write to this buffer to stage changes. They become visible on the terminal after the next
    /// call to `flush()` or `forceRedraw()`.
    public var buffer: ScreenBuffer {
        get { back }
        set { back = newValue }
    }

    /// Flushes the diff between the front and back buffers to the terminal.
    ///
    /// The output is wrapped in synchronized-update markers to prevent tearing. When there are
    /// dirty cells, the cursor is hidden during the update and then repositioned according to
    /// `cursorRow`/`cursorCol`. After writing, `back` is copied into `front` and the dirty
    /// tracker is cleared.
    ///
    /// - Throws: `TerminalError` if the underlying connection write fails.
    public func flush() throws(TerminalError) {
        let diffBytes = DiffRenderer.render(front: front, back: back)
        
        var output: [UInt8] = []
        output.append(contentsOf: KittySequences.beginSyncUpdate)
        
        if !diffBytes.isEmpty {
            output.append(contentsOf: KittySequences.hideCursor)
            output.append(contentsOf: diffBytes)
        }

        if let r = cursorRow, let c = cursorCol {
            output.append(contentsOf: KittySequences.moveCursor(row: r + 1, col: c + 1))
            output.append(contentsOf: KittySequences.showCursor)
        } else {
            output.append(contentsOf: KittySequences.hideCursor)
        }

        output.append(contentsOf: KittySequences.endSyncUpdate)

        if !output.isEmpty {
            try connection.write(output)
        }

        // Swap: copy back → front, clear dirty bits
        front = back
        back.dirty.clear()
    }

    /// Redraws every cell in the back buffer unconditionally and writes the result to the terminal.
    ///
    /// Use this after a resize event or any situation where the terminal display may be in an
    /// unknown state. The dirty tracker is cleared and `back` is copied into `front` on success.
    ///
    /// - Throws: `TerminalError` if the underlying connection write fails.
    public func forceRedraw() throws(TerminalError) {
        let fullBytes = DiffRenderer.renderFull(back)
        var output: [UInt8] = []
        output.append(contentsOf: KittySequences.beginSyncUpdate)
        output.append(contentsOf: KittySequences.hideCursor)
        output.append(contentsOf: fullBytes)

        if let r = cursorRow, let c = cursorCol {
            output.append(contentsOf: KittySequences.moveCursor(row: r + 1, col: c + 1))
            output.append(contentsOf: KittySequences.showCursor)
        }

        output.append(contentsOf: KittySequences.endSyncUpdate)
        try connection.write(output)
        front = back
        back.dirty.clear()
    }

    /// Resizes both the front and back buffers to the new viewport dimensions.
    ///
    /// Content within the intersection of the old and new dimensions is preserved. All cells in
    /// the resized back buffer are marked dirty so the next `flush()` redraws the full viewport.
    ///
    /// - Parameters:
    ///   - columns: The new number of columns.
    ///   - rows: The new number of rows.
    public func resize(columns: Int, rows: Int) {
        front.resize(columns: columns, rows: rows)
        back.resize(columns: columns, rows: rows)
    }
}
