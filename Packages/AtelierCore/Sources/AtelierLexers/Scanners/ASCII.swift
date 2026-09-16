enum ASCII {
    static let newline = UInt16(10)
    static let carriageReturn = UInt16(13)
    static let quote = UInt16(34)
    static let hash = UInt16(35)
    static let ampersand = UInt16(38)
    static let apostrophe = UInt16(39)
    static let asterisk = UInt16(42)
    static let hyphen = UInt16(45)
    static let dot = UInt16(46)
    static let slash = UInt16(47)
    static let colon = UInt16(58)
    static let semicolon = UInt16(59)
    static let lessThan = UInt16(60)
    static let equals = UInt16(61)
    static let greaterThan = UInt16(62)
    static let at = UInt16(64)
    static let backslash = UInt16(92)
    static let underscore = UInt16(95)
    static let exclamation = UInt16(33)
    static let dollar = UInt16(36)
    static let percent = UInt16(37)
    static let openBrace = UInt16(123)
    static let closeBrace = UInt16(125)
    static let openBracket = UInt16(91)
    static let closeBracket = UInt16(93)
    static let backtick = UInt16(96)
    static let comma = UInt16(44)
    static let plus = UInt16(43)

    static func isDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
    static func isUpper(_ unit: UInt16) -> Bool { unit >= 65 && unit <= 90 }
    static func isLower(_ unit: UInt16) -> Bool { unit >= 97 && unit <= 122 }
    static func isAlpha(_ unit: UInt16) -> Bool { isUpper(unit) || isLower(unit) }
    static func isIdentifierStart(_ unit: UInt16) -> Bool { isAlpha(unit) || unit == underscore || unit >= 128 }
    static func isIdentifier(_ unit: UInt16) -> Bool { isIdentifierStart(unit) || isDigit(unit) }
    static func isSpace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == newline || unit == carriageReturn }
}
