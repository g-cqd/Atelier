import KittyText

/// Converts a character index within a line to the display column offset,
/// accounting for wide characters.
func displayColumn(for charIndex: Int, in line: String) -> Int {
    var col = 0
    for (i, char) in line.enumerated() {
        if i >= charIndex { break }
        col += UnicodeWidth.displayWidth(of: char)
    }
    return col
}

/// Converts a display column offset to the character index, accounting for wide characters.
func charIndex(forDisplayColumn targetCol: Int, in line: String) -> Int {
    var col = 0
    for (i, char) in line.enumerated() {
        if col >= targetCol { return i }
        col += UnicodeWidth.displayWidth(of: char)
    }
    return line.count
}

extension Character {
    var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return !scalar.isASCII || (scalar.value >= 32 && scalar.value < 127)
    }
}
