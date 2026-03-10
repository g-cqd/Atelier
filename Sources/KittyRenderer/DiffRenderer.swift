import KittyCodecs

/// Compares front and back buffers and emits minimal escape bytes for the diff.
public enum DiffRenderer: Sendable {

    /// Produces the minimal escape sequence bytes to update `front` to match `back`.
    /// After calling, the caller should copy back → front.
    public static func render(front: ScreenBuffer, back: ScreenBuffer) -> [UInt8] {
        let columns = back.columns
        let ranges = back.dirty.dirtyRanges(columns: columns)
        guard !ranges.isEmpty else { return [] }

        var bytes: [UInt8] = []
        var lastRow = -1
        var lastCol = -1
        var lastStyle = Style.default

        for range in ranges {
            let row = range.row

            // Move cursor if needed
            if row != lastRow || range.colStart != lastCol {
                bytes.append(contentsOf: KittySequences.moveCursor(
                    row: row + 1,
                    col: range.colStart + 1
                ))
            }

            for col in range.colStart..<range.colEnd {
                let cell = back[row, col]

                // Emit style change
                let diffBytes = SGREncoder.encodeDiff(from: lastStyle, to: cell.style)
                bytes.append(contentsOf: diffBytes)
                lastStyle = cell.style

                // Emit character
                appendUTF8(cell.character, to: &bytes)
            }

            lastRow = row
            lastCol = range.colEnd
        }

        // Reset style at end
        if lastStyle != .default {
            bytes.append(contentsOf: SGREncoder.reset)
        }

        return bytes
    }

    /// Full redraw — renders entire back buffer.
    public static func renderFull(_ buffer: ScreenBuffer) -> [UInt8] {
        var bytes: [UInt8] = []
        var lastStyle = Style.default

        for row in 0..<buffer.rows {
            bytes.append(contentsOf: KittySequences.moveCursor(row: row + 1, col: 1))
            for col in 0..<buffer.columns {
                let cell = buffer[row, col]

                let diffBytes = SGREncoder.encodeDiff(from: lastStyle, to: cell.style)
                bytes.append(contentsOf: diffBytes)
                lastStyle = cell.style

                appendUTF8(cell.character, to: &bytes)
            }
        }

        if lastStyle != .default {
            bytes.append(contentsOf: SGREncoder.reset)
        }

        return bytes
    }

    private static func appendUTF8(_ char: Character, to bytes: inout [UInt8]) {
        for byte in String(char).utf8 {
            bytes.append(byte)
        }
    }
}
