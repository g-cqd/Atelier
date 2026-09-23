import KittyCodecs
public import KittyTerminal
import os

/// A terminal-level scroll applied before diffing: DECSTBM confines it to the region and SU or SD moves the display,
/// then the front buffer shifts to match, so the diff covers only the exposed rows and the cells the scroll wrongly
/// moved, such as the sidebar's.
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

/// Frame-phase signposts, under the `com.kittytui.render` subsystem in Instruments.
private let signposter = OSSignposter(subsystem: "com.kittytui.render", category: "frame")

/// Double-buffered render pipeline with synchronized output.
@MainActor
public final class RenderPipeline {
    private let connection: any TerminalConnection
    private var front: ScreenBuffer
    private var back: ScreenBuffer

    /// Persistent output buffer reused across frames to avoid allocation.
    private var outputBuffer = ContiguousArray<UInt8>()

    /// Active signpost interval state — only one frame in flight at a time per
    /// pipeline, so a single optional is sufficient.
    private var activeFrameInterval: OSSignpostIntervalState?

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

    /// A scroll for the next `flush()` to perform in the terminal; the flush clears it once performed.
    public var scrollHint: ScrollHint?

    /// The regions marked dirty since the last `clearDirtyRegions()`.
    public private(set) var dirtyRegions = DirtyRegions()

    /// The pixel chrome layer, present when the terminal can draw under its cells; the shell sets
    /// ``chromeLines`` each frame and ``flush()`` places them after the cell diff.
    public var chrome: PixelChrome?
    /// The elements the shell wants under this frame's cells.
    public var chromeElements: [ChromeElement] = []

    /// The one-pixel lines among ``chromeElements``; setting replaces every element with lines.
    public var chromeLines: [ChromeLine] {
        get {
            chromeElements.compactMap { element in
                if case .line(let line) = element { return line }
                return nil
            }
        }
        set { chromeElements = newValue.map(ChromeElement.line) }
    }

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

    /// The back buffer staging the next frame, shown by the next `flush()` or `forceRedraw()`.
    public var buffer: ScreenBuffer {
        get { back }
        set { back = newValue }
    }

    /// Starts a frame with no cursor position, so the cursor stays hidden unless set again. The back buffer keeps
    /// the previous frame, so repainting an area dirties only the cells that change.
    public func beginFrame() {
        cursorRow = nil
        cursorCol = nil
        activeFrameInterval = signposter.beginInterval("frame")
    }

    /// Marks a screen region for repaint on the next frame; overlapping marks are fine.
    public func markDirty(_ rect: DirtyRect) {
        dirtyRegions.mark(rect)
    }

    /// Convenience for marking a single full-width row dirty.
    public func markDirtyRow(_ row: Int) {
        dirtyRegions.markRow(row, columns: columns)
    }

    /// Marks every cell as dirty (used after a resize or mode flip).
    public func markAllDirty() {
        dirtyRegions.markAll(columns: columns, rows: rows)
    }

    /// Drops the collected dirty regions, which `flush()` leaves for the caller to clear.
    public func clearDirtyRegions() {
        dirtyRegions.clear()
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
        let flushInterval = signposter.beginInterval("flush")
        defer {
            signposter.endInterval("flush", flushInterval)
            if let interval = activeFrameInterval {
                signposter.endInterval("frame", interval)
                activeFrameInterval = nil
            }
        }
        outputBuffer.removeAll(keepingCapacity: true)

        KittySequences.appendBeginSyncUpdate(to: &outputBuffer)

        if let hint = scrollHint, hint.delta != 0, hint.regionHeight > 0,
            hint.delta.magnitude < UInt(hint.regionHeight)
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

            // The scroll moved every column, including ones this frame never wrote (sidebar, separators): mark any
            // cell where the shifted front differs from back so the diff re-emits it.
            let cols = back.columns
            let regionEnd = hint.regionTop + hint.regionHeight
            for row in hint.regionTop ..< regionEnd {
                let base = row &* cols
                for col in 0 ..< cols {
                    let idx = base &+ col
                    if front.cells[idx] != back.cells[idx] {
                        back.dirty.mark(idx)
                    }
                }
            }

            scrollHint = nil
            // The terminal scrolled the placements along with the cells; put them back.
            chrome?.invalidate()
        }

        // Render diff directly into our persistent buffer
        let hasDirty = !back.dirty.isEmpty
        if hasDirty {
            KittySequences.appendHideCursor(to: &outputBuffer)
            DiffRenderer.render(front: front, back: back, into: &outputBuffer)
        }

        chrome?.render(chromeElements, into: &outputBuffer)

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
        let redrawInterval = signposter.beginInterval("forceRedraw")
        defer {
            signposter.endInterval("forceRedraw", redrawInterval)
            if let interval = activeFrameInterval {
                signposter.endInterval("frame", interval)
                activeFrameInterval = nil
            }
        }
        outputBuffer.removeAll(keepingCapacity: true)

        KittySequences.appendBeginSyncUpdate(to: &outputBuffer)
        KittySequences.appendHideCursor(to: &outputBuffer)
        DiffRenderer.renderFull(back, into: &outputBuffer)
        chrome?.invalidate()
        chrome?.render(chromeElements, into: &outputBuffer)

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
        chrome?.reset()
    }
}
