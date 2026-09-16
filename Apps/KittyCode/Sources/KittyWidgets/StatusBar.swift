import AtelierText
public import KittyCodecs

/// Status bar with left/center/right aligned segments.
public struct StatusBar: View, Sendable {
    public var left: String
    public var center: String
    public var right: String
    public var style: Style

    public init(
        left: String = "",
        center: String = "",
        right: String = "",
        style: Style = Style(fg: .rgb(r: 0, g: 0, b: 0), bg: .rgb(r: 200, g: 200, b: 200))
    ) {
        self.left = left
        self.center = center
        self.right = right
        self.style = style
    }

    public var body: Never { fatalError() }

    /// Render the status bar into a fixed-width string.
    public func render(width: Int) -> String {
        guard width > 0 else { return "" }
        if center.isEmpty {
            return renderEdgeAligned(width: width)
        }
        return renderCentered(width: width)
    }

    private func renderEdgeAligned(width: Int) -> String {
        let rightPart = suffixFitting(right, width: width)
        let leftPart = prefixFitting(
            left, width: max(0, width - UnicodeWidth.displayWidth(of: rightPart)))
        return leftPart
            + String(
                repeating: " ",
                count: max(
                    0,
                    width - UnicodeWidth.displayWidth(of: leftPart)
                        - UnicodeWidth.displayWidth(of: rightPart))
            )
            + rightPart
    }

    private func renderCentered(width: Int) -> String {
        let leftPart = String(left.prefix(width))
        let rightPart = String(right.suffix(width))
        let centerStart = min(width, leftPart.count)
        let centerEnd = max(centerStart, width - rightPart.count)
        let availableCenterWidth = max(0, centerEnd - centerStart)
        let centerPart = String(center.prefix(availableCenterWidth))

        var result = Array(repeating: Character(" "), count: width)
        write(leftPart, into: &result, at: 0)
        write(rightPart, into: &result, at: max(0, width - rightPart.count))
        write(
            centerPart, into: &result,
            at: centerStart + max(0, (availableCenterWidth - centerPart.count) / 2))
        return String(result)
    }

    private func write(_ text: String, into result: inout [Character], at start: Int) {
        guard start < result.count else { return }
        for (offset, char) in text.enumerated() {
            let index = start + offset
            guard index < result.count else { break }
            result[index] = char
        }
    }

    private func prefixFitting(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }

        var result = ""
        var usedWidth = 0
        for char in text {
            let charWidth = UnicodeWidth.displayWidth(of: char)
            guard charWidth > 0 else { continue }
            guard usedWidth + charWidth <= width else { break }
            result.append(char)
            usedWidth += charWidth
        }
        return result
    }

    private func suffixFitting(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }

        var reversed: [Character] = []
        var usedWidth = 0
        for char in text.reversed() {
            let charWidth = UnicodeWidth.displayWidth(of: char)
            guard charWidth > 0 else { continue }
            guard usedWidth + charWidth <= width else { break }
            reversed.append(char)
            usedWidth += charWidth
        }
        return String(reversed.reversed())
    }
}
