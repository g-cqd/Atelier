import Synchronization

/// The scalar sets of the Unicode properties a token pattern may name with `\p{…}`: the general categories, by
/// short or long name, and the identifier and case properties grammars use.
enum UnicodeProperties {
    /// Each set is built once per process by testing every scalar, about 1.1 million, which takes some milliseconds.
    private static let cache = Mutex<[String: ScalarRanges]>([:])

    /// - Throws: `GrammarError.invalidRuleType` for a property it does not know.
    static func set(named name: String, in pattern: String) throws(GrammarError) -> ScalarRanges {
        if let cached = cache.withLock({ $0[name] }) {
            return cached
        }
        guard let isMember = membership(named: name) else {
            throw .invalidRuleType("Pattern `\(pattern)`: unsupported property `\(name)`")
        }
        let set = scalars(where: isMember)
        cache.withLock { $0[name] = set }
        return set
    }

    private static func membership(named name: String) -> ((Unicode.Scalar.Properties) -> Bool)? {
        switch name {
            case "XID_Start", "XIDS": return { $0.isXIDStart }
            case "XID_Continue", "XIDC": return { $0.isXIDContinue }
            case "ID_Start", "IDS": return { $0.isIDStart }
            case "ID_Continue", "IDC": return { $0.isIDContinue }
            case "Alphabetic", "Alpha": return { $0.isAlphabetic }
            case "White_Space", "WSpace": return { $0.isWhitespace }
            case "Uppercase", "Upper": return { $0.isUppercase }
            case "Lowercase", "Lower": return { $0.isLowercase }
            default:
                guard let categories = generalCategories(named: name) else { return nil }
                return { categories.contains($0.generalCategory) }
        }
    }

    private static func generalCategories(named name: String) -> [Unicode.GeneralCategory]? {
        switch name {
            case "L", "Letter": [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter]
            case "LC", "L&", "Cased_Letter": [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter]
            case "Lu", "Uppercase_Letter": [.uppercaseLetter]
            case "Ll", "Lowercase_Letter": [.lowercaseLetter]
            case "Lt", "Titlecase_Letter": [.titlecaseLetter]
            case "Lm", "Modifier_Letter": [.modifierLetter]
            case "Lo", "Other_Letter": [.otherLetter]
            case "M", "Mark": [.nonspacingMark, .spacingMark, .enclosingMark]
            case "Mn", "Nonspacing_Mark": [.nonspacingMark]
            case "Mc", "Spacing_Mark": [.spacingMark]
            case "Me", "Enclosing_Mark": [.enclosingMark]
            case "N", "Number": [.decimalNumber, .letterNumber, .otherNumber]
            case "Nd", "Decimal_Number": [.decimalNumber]
            case "Nl", "Letter_Number": [.letterNumber]
            case "No", "Other_Number": [.otherNumber]
            case "P", "Punctuation":
                [
                    .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                    .initialPunctuation, .finalPunctuation, .otherPunctuation
                ]
            case "Pc", "Connector_Punctuation": [.connectorPunctuation]
            case "Pd", "Dash_Punctuation": [.dashPunctuation]
            case "S", "Symbol": [.mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol]
            case "Sm", "Math_Symbol": [.mathSymbol]
            case "Sc", "Currency_Symbol": [.currencySymbol]
            case "Z", "Separator": [.spaceSeparator, .lineSeparator, .paragraphSeparator]
            case "Zs", "Space_Separator": [.spaceSeparator]
            case "Cc", "Control": [.control]
            case "Cf", "Format": [.format]
            case "Co", "Private_Use": [.privateUse]
            default: nil
        }
    }

    private static func scalars(where isMember: (Unicode.Scalar.Properties) -> Bool) -> ScalarRanges {
        var ranges: [ClosedRange<UInt32>] = []
        var start: UInt32?
        for value in 0 ... ScalarRanges.maxScalar {
            let member = Unicode.Scalar(value).map { isMember($0.properties) } ?? false
            if member, start == nil {
                start = value
            } else if !member, let first = start {
                ranges.append(first ... value - 1)
                start = nil
            }
        }
        if let first = start {
            ranges.append(first ... ScalarRanges.maxScalar)
        }
        return ScalarRanges(ranges)
    }
}
