import KittyCodecs

/// Compares front and back buffers and emits minimal escape bytes for the diff.
public enum DiffRenderer: Sendable {

    /// Produces the minimal escape sequence bytes needed to update `front` so that it matches `back`.
    ///
    /// Only cells marked dirty in `back` are included in the output. Cursor movement sequences are
    /// emitted only when the current position differs from the target position. The caller is
    /// responsible for copying `back` into `front` and clearing the dirty tracker after this call.
    ///
    /// - Parameters:
    ///   - front: The buffer representing what is currently rendered on the terminal.
    ///   - back: The buffer containing the desired new state, with a populated dirty tracker.
    /// - Returns: A byte array of ANSI/VT escape sequences that transition the terminal from
    ///   `front` to `back`. Returns an empty array when no cells are dirty.
    public static func render(front: ScreenBuffer, back: ScreenBuffer) -> ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>()
        render(front: front, back: back, into: &bytes)
        return bytes
    }

    /// Renders diff into a caller-provided buffer (avoids allocation when reused).
    public static func render(front: ScreenBuffer, back: ScreenBuffer, into bytes: inout ContiguousArray<UInt8>) {
        let columns = back.columns
        let ranges = back.dirty.dirtyRanges(columns: columns)
        guard !ranges.isEmpty else { return }

        var lastRow = -1
        var lastCol = -1
        var lastStyle = Style.default

        for range in ranges {
            let row = range.row

            // Move cursor if needed
            if row != lastRow || range.colStart != lastCol {
                KittySequences.appendMoveCursor(
                    row: row + 1,
                    col: range.colStart + 1,
                    to: &bytes
                )
            }

            for col in range.colStart..<range.colEnd {
                let cell = back[row, col]

                // Skip continuation cells — the terminal fills the 2nd column of wide chars automatically
                if cell.isContinuation { continue }

                // Emit style change
                SGREncoder.encodeDiff(from: lastStyle, to: cell.style, into: &bytes)
                lastStyle = cell.style

                // Emit character
                appendUTF8(cell.character, to: &bytes)
            }

            lastRow = row
            lastCol = range.colEnd
        }

        // Reset style at end
        if lastStyle != .default {
            SGREncoder.appendReset(to: &bytes)
        }
    }

    /// Renders the entire buffer unconditionally, ignoring the dirty tracker.
    ///
    /// Use this for the initial paint or after an event (such as a terminal resize) that
    /// invalidates the previous render state entirely.
    ///
    /// - Parameter buffer: The buffer whose full contents should be rendered.
    /// - Returns: A byte array of ANSI/VT escape sequences representing every cell in `buffer`.
    public static func renderFull(_ buffer: ScreenBuffer) -> ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>()
        renderFull(buffer, into: &bytes)
        return bytes
    }

    /// Renders the entire buffer into a caller-provided buffer.
    public static func renderFull(_ buffer: ScreenBuffer, into bytes: inout ContiguousArray<UInt8>) {
        var lastStyle = Style.default

        for row in 0..<buffer.rows {
            KittySequences.appendMoveCursor(row: row + 1, col: 1, to: &bytes)
            for col in 0..<buffer.columns {
                let cell = buffer[row, col]

                // Skip continuation cells
                if cell.isContinuation { continue }

                SGREncoder.encodeDiff(from: lastStyle, to: cell.style, into: &bytes)
                lastStyle = cell.style

                appendUTF8(cell.character, to: &bytes)
            }
        }

        if lastStyle != .default {
            SGREncoder.appendReset(to: &bytes)
        }
    }

    @inline(__always)
    private static func appendUTF8(_ char: Character, to bytes: inout ContiguousArray<UInt8>) {
        for byte in char.utf8 {
            bytes.append(byte)
        }
    }
}
