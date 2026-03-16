/// Shared text-display measurements used by widgets and editor logic.
public enum TextDisplayMetrics {
    /// Converts a character offset within a line to a terminal display column.
    public static func displayColumn(
        forCharacterOffset targetOffset: Int, in line: String, tabSize: Int = 4
    ) -> Int {
        guard targetOffset > 0 else { return 0 }

        var column = 0
        for (offset, char) in line.enumerated() {
            if offset >= targetOffset { break }
            if char == "\t" {
                let tabSpan = max(1, tabSize)
                column += tabSpan - (column % tabSpan)
            } else {
                column += UnicodeWidth.displayWidth(of: char)
            }
        }
        return column
    }

    /// Converts a terminal display column to the nearest character offset within a line.
    public static func characterOffset(
        forDisplayColumn targetColumn: Int, in line: String, tabSize: Int = 4
    ) -> Int {
        guard targetColumn > 0 else { return 0 }

        var column = 0
        for (offset, char) in line.enumerated() {
            let nextColumn: Int
            if char == "\t" {
                let tabSpan = max(1, tabSize)
                nextColumn = column + tabSpan - (column % tabSpan)
            } else {
                nextColumn = column + UnicodeWidth.displayWidth(of: char)
            }
            if targetColumn < nextColumn { return offset }
            column = nextColumn
        }
        return line.count
    }

    /// Computes the display width of a line accounting for tab stops.
    public static func displayWidth(of line: String, tabSize: Int = 4) -> Int {
        var column = 0
        for char in line {
            if char == "\t" {
                let tabSpan = max(1, tabSize)
                column += tabSpan - (column % tabSpan)
            } else {
                column += UnicodeWidth.displayWidth(of: char)
            }
        }
        return column
    }

    /// Returns the number of decimal digits required to render line numbers.
    public static func lineNumberDigits(forLineCount lineCount: Int) -> Int {
        let clampedCount = max(1, lineCount)
        if clampedCount < 10 { return 1 }
        if clampedCount < 100 { return 2 }
        if clampedCount < 1000 { return 3 }
        if clampedCount < 10_000 { return 4 }
        if clampedCount < 100_000 { return 5 }
        return String(clampedCount).count
    }
}

extension Character {
    public var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return !scalar.isASCII || (scalar.value >= 32 && scalar.value < 127)
    }
}
