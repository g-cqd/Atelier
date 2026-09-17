import AtelierSyntaxModel

extension SyntaxTheme {
    /// The Monokai palette on the role hierarchy: the default theme of the terminal editor, and a dark theme any
    /// consumer can start from when no Xcode or terminal-derived theme is configured.
    public static let monokai: SyntaxTheme = {
        let pink = ThemeColor(byteRed: 249, green: 38, blue: 114)
        let green = ThemeColor(byteRed: 166, green: 226, blue: 46)
        let cyan = ThemeColor(byteRed: 102, green: 217, blue: 239)
        let yellow = ThemeColor(byteRed: 230, green: 219, blue: 116)
        let purple = ThemeColor(byteRed: 174, green: 129, blue: 255)
        let orange = ThemeColor(byteRed: 253, green: 151, blue: 31)
        let grey = ThemeColor(byteRed: 117, green: 113, blue: 94)
        let text = ThemeColor(byteRed: 248, green: 248, blue: 242)
        return SyntaxTheme(
            name: "Monokai",
            plainText: ThemeStyle(foreground: text),
            background: ThemeColor(byteRed: 39, green: 40, blue: 34),
            selection: ThemeColor(byteRed: 73, green: 72, blue: 62),
            roles: [
                .keyword: ThemeStyle(foreground: pink, isBold: true),
                .function: ThemeStyle(foreground: green),
                .functionBuiltin: ThemeStyle(foreground: cyan),
                .functionMacro: ThemeStyle(foreground: green, isBold: true),
                .functionSpecial: ThemeStyle(foreground: green, isItalic: true),
                .type: ThemeStyle(foreground: cyan, isItalic: true),
                .string: ThemeStyle(foreground: yellow),
                .stringEscape: ThemeStyle(foreground: purple),
                .number: ThemeStyle(foreground: purple),
                .comment: ThemeStyle(foreground: grey, isItalic: true),
                .commentDocumentation: ThemeStyle(foreground: grey, isItalic: true, isUnderlined: true),
                .variable: ThemeStyle(foreground: text),
                .variableBuiltin: ThemeStyle(foreground: purple, isItalic: true),
                .variableParameter: ThemeStyle(foreground: orange, isItalic: true),
                .constant: ThemeStyle(foreground: purple),
                .boolean: ThemeStyle(foreground: purple),
                .operator: ThemeStyle(foreground: pink),
                .punctuationBracket: ThemeStyle(foreground: text),
                .punctuationDelimiter: ThemeStyle(foreground: text),
                .punctuationSpecial: ThemeStyle(foreground: pink),
                .property: ThemeStyle(foreground: green),
                .tag: ThemeStyle(foreground: pink),
                .attribute: ThemeStyle(foreground: green),
                .namespace: ThemeStyle(foreground: cyan),
                .label: ThemeStyle(foreground: yellow),
                .constructor: ThemeStyle(foreground: cyan),
                .embedded: ThemeStyle(foreground: text),
                .escape: ThemeStyle(foreground: purple)
            ])
    }()
}

extension ThemeColor {
    /// A colour from 8-bit channels, the form terminal palettes and most theme files use.
    public init(byteRed red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        self.init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: alpha)
    }

    /// The channels quantised to 8 bits, for a terminal or an RGB bitmap.
    public var byteChannels: (red: UInt8, green: UInt8, blue: UInt8) {
        func byte(_ channel: Double) -> UInt8 {
            UInt8((channel.clamped(to: 0 ... 1) * 255).rounded())
        }
        return (byte(red), byte(green), byte(blue))
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
