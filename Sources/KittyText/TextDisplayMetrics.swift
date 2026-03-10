/// Shared text-display measurements used by widgets and editor logic.
public enum TextDisplayMetrics {
    /// Converts a character offset within a line to a terminal display column.
    public static func displayColumn(forCharacterOffset targetOffset: Int, in line: String) -> Int {
        guard targetOffset > 0 else { return 0 }

        var column = 0
        for (offset, char) in line.enumerated() {
            if offset >= targetOffset { break }
            column += UnicodeWidth.displayWidth(of: char)
        }
        return column
    }

    /// Converts a terminal display column to the nearest character offset within a line.
    public static func characterOffset(forDisplayColumn targetColumn: Int, in line: String) -> Int {
        guard targetColumn > 0 else { return 0 }

        var column = 0
        for (offset, char) in line.enumerated() {
            if column >= targetColumn { return offset }
            column += UnicodeWidth.displayWidth(of: char)
        }
        return line.count
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

public extension Character {
    var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return !scalar.isASCII || (scalar.value >= 32 && scalar.value < 127)
    }
}
