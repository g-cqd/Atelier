import KittyCodecs
import KittyTerminal

/// Describes a terminal-level scroll operation to apply before diffing.
///
/// The pipeline uses DECSTBM to restrict scrolling to the given row region,
/// then SU or SD to physically scroll the terminal display. The front buffer
/// is shifted to match so the subsequent diff only covers newly exposed rows
/// and any cells (e.g. sidebar) that were incorrectly scrolled.
public struct ScrollHint: Sendable {
    /// Zero-based row index of the top of the scroll region.
    public var regionTop: Int
    /// Number of rows in the scroll region.
    public var regionHeight: Int
    /// Number of rows to scroll. Positive = content moves up (scroll down);
    /// negative = content moves down (scroll up).
    public var delta: Int

    public init(regionTop: Int, regionHeight: Int, delta: Int) {
        self.regionTop = regionTop
        self.regionHeight = regionHeight
        self.delta = delta
    }
}

/// Double-buffered render pipeline with synchronized output.
@MainActor
public final class RenderPipeline: Sendable {
    private let connection: any TerminalConnection
    private var front: ScreenBuffer
    private var back: ScreenBuffer

    /// Persistent output buffer reused across frames to avoid allocation.
    private var outputBuffer = ContiguousArray<UInt8>()

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

    /// Optional hint for terminal-level scrolling via DECSTBM + SU/SD.
    ///
    /// When set, `flush()` emits scroll region commands to physically scroll the
    /// terminal display and shifts the front buffer to match, so DiffRenderer only
    /// needs to emit newly exposed rows and any sidebar cells that were incorrectly
    /// scrolled by the full-width terminal scroll.
    public var scrollHint: ScrollHint?

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

    /// Prepares for composing a new frame.
    ///
    /// The back buffer retains the previous frame's content so that renderers
    /// that overwrite their entire area only mark truly changed cells as dirty.
    /// This dramatically reduces diff output during scrolling.
    public func beginFrame() {
        cursorRow = nil
        cursorCol = nil
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
        outputBuffer.removeAll(keepingCapacity: true)

        KittySequences.appendBeginSyncUpdate(to: &outputBuffer)

        // Apply terminal scroll region optimization before diffing.
        // This physically scrolls the terminal display, then shifts the front
        // buffer to match, so DiffRenderer only emits the delta.
        if let hint = scrollHint, hint.delta != 0,
            abs(hint.delta) < hint.regionHeight, hint.regionHeight > 0
        {
            let top1 = hint.regionTop + 1  // 1-based
            let bottom1 = hint.regionTop + hint.regionHeight  // 1-based inclusive
            KittySequences.appendSetScrollRegion(top: top1, bottom: bottom1, to: &outputBuffer)
            if hint.delta > 0 {
                KittySequences.appendScrollUp(lines: hint.delta, to: &outputBuffer)
            } else {
                KittySequences.appendScrollDown(lines: -hint.delta, to: &outputBuffer)
            }
            KittySequences.appendResetScrollRegion(to: &outputBuffer)

            // Shift front buffer rows (full width) to mirror the terminal scroll.
            front.shiftRows(
                regionY: hint.regionTop,
                regionHeight: hint.regionHeight,
                regionX: 0,
                regionWidth: front.columns,
                delta: hint.delta
            )
            // Terminal fills vacated rows with blank cells — do the same in front.
            if hint.delta > 0 {
                let blankStart = hint.regionTop + hint.regionHeight - hint.delta
                front.fill(
                    row: blankStart, col: 0, width: front.columns, height: hint.delta, cell: .empty)
            } else {
                front.fill(
                    row: hint.regionTop, col: 0, width: front.columns, height: -hint.delta,
                    cell: .empty)
            }

            // The terminal scroll moved ALL columns, but non-editor columns
            // (sidebar, separators) weren't written to the back buffer this frame
            // and thus aren't dirty. Mark any cell where shifted-front differs
            // from back so DiffRenderer will re-emit it.
            let cols = back.columns
            let regionEnd = hint.regionTop + hint.regionHeight
            for row in hint.regionTop..<regionEnd {
                let base = row &* cols
                for col in 0..<cols {
                    let idx = base &+ col
                    if front.cells[idx] != back.cells[idx] {
                        back.dirty.mark(idx)
                    }
                }
            }

            scrollHint = nil
        }

        // Render diff directly into our persistent buffer
        let hasDirty = !back.dirty.isEmpty
        if hasDirty {
            KittySequences.appendHideCursor(to: &outputBuffer)
            DiffRenderer.render(front: front, back: back, into: &outputBuffer)
        }

        if let r = cursorRow, let c = cursorCol {
            KittySequences.appendMoveCursor(row: r + 1, col: c + 1, to: &outputBuffer)
            KittySequences.appendShowCursor(to: &outputBuffer)
        } else {
            KittySequences.appendHideCursor(to: &outputBuffer)
        }

        KittySequences.appendEndSyncUpdate(to: &outputBuffer)

        if !outputBuffer.isEmpty {
            try connection.writeContiguous(outputBuffer)
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
        outputBuffer.removeAll(keepingCapacity: true)

        KittySequences.appendBeginSyncUpdate(to: &outputBuffer)
        KittySequences.appendHideCursor(to: &outputBuffer)
        DiffRenderer.renderFull(back, into: &outputBuffer)

        if let r = cursorRow, let c = cursorCol {
            KittySequences.appendMoveCursor(row: r + 1, col: c + 1, to: &outputBuffer)
            KittySequences.appendShowCursor(to: &outputBuffer)
        }

        KittySequences.appendEndSyncUpdate(to: &outputBuffer)
        try connection.writeContiguous(outputBuffer)
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
