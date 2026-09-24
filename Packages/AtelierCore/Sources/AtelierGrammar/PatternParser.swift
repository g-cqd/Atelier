/// A token pattern, parsed.
indirect enum PatternNode: Sendable, Equatable {
    /// One scalar from the set.
    case characters(ScalarRanges)
    /// Each node in turn; empty, it matches the empty string.
    case sequence([PatternNode])
    /// Any one of the nodes.
    case alternation([PatternNode])
    /// `node` at least `min` times, and at most `max` when `max` is not nil.
    case repetition(PatternNode, min: Int, max: Int?)
}

/// Parses the regular expressions of tree-sitter's `PATTERN` rules: the JavaScript source of a grammar's regex
/// literals, which tree-sitter compiles with Rust's regex syntax.
///
/// It takes what token rules use: literals, `.`, classes with ranges and negation, the ASCII `\d \w \s` classes and
/// their negations, character escapes, `\p{…}` general categories and identifier properties, groups, alternation, and the
/// `* + ? {n} {n,} {n,m}` quantifiers, lazy or not, since the lexer takes the longest match regardless. Anchors, word
/// boundaries, backreferences, lookaround and inline flags have no meaning for a token and are rejected.
struct PatternParser {
    /// The largest count a `{n,m}` quantifier may give: each repetition is a copy of its operand in the automaton.
    static let maxRepetitionCount = 1_000

    private let pattern: String
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var classDepth = 0

    private init(_ pattern: String) {
        self.pattern = pattern
        self.scalars = Array(pattern.unicodeScalars)
    }

    /// - Throws: `GrammarError.invalidRuleType` when `pattern` is malformed or uses a construct a token can't.
    static func parse(_ pattern: String) throws(GrammarError) -> PatternNode {
        var parser = PatternParser(pattern)
        let node = try parser.parseAlternation()
        guard parser.index == parser.scalars.count else { throw parser.failure("unbalanced `)`") }
        return node
    }

    // MARK: - Structure

    private mutating func parseAlternation() throws(GrammarError) -> PatternNode {
        var branches = [try parseSequence()]
        while peek() == "|" {
            index += 1
            branches.append(try parseSequence())
        }
        return branches.count == 1 ? branches[0] : .alternation(branches)
    }

    private mutating func parseSequence() throws(GrammarError) -> PatternNode {
        var items: [PatternNode] = []
        while let scalar = peek(), scalar != "|", scalar != ")" {
            let atom = try parseAtom()
            items.append(try parseQuantifiers(of: atom))
        }
        return items.count == 1 ? items[0] : .sequence(items)
    }

    private mutating func parseQuantifiers(of atom: PatternNode) throws(GrammarError) -> PatternNode {
        var node = atom
        while let scalar = peek() {
            let bounds: (min: Int, max: Int?)
            switch scalar {
                case "*":
                    index += 1
                    bounds = (0, nil)
                case "+":
                    index += 1
                    bounds = (1, nil)
                case "?":
                    index += 1
                    bounds = (0, 1)
                case "{":
                    // A brace that does not open a count is a literal, which the next atom reads.
                    guard let counted = try parseCount() else { return node }
                    bounds = counted
                default:
                    return node
            }
            if peek() == "?" { index += 1 }
            node = .repetition(node, min: bounds.min, max: bounds.max)
        }
        return node
    }

    /// The bounds of a `{n}`, `{n,}` or `{n,m}` quantifier at the current `{`, consumed; nil, consuming nothing, when
    /// the brace opens no count.
    private mutating func parseCount() throws(GrammarError) -> (min: Int, max: Int?)? {
        var cursor = index + 1
        func number() -> Int? {
            var value: Int?
            while cursor < scalars.count, ("0" ... "9").contains(scalars[cursor]) {
                let digit = Int(scalars[cursor].value - 0x30)
                value = min((value ?? 0) * 10 + digit, Self.maxRepetitionCount + 1)
                cursor += 1
            }
            return value
        }
        guard let low = number() else { return nil }
        var high: Int? = low
        if cursor < scalars.count, scalars[cursor] == "," {
            cursor += 1
            high = number()
        }
        guard cursor < scalars.count, scalars[cursor] == "}" else { return nil }
        guard low <= Self.maxRepetitionCount, (high ?? low) <= Self.maxRepetitionCount else {
            throw .resourceLimitExceeded(
                "Pattern `\(pattern)` repeats more than \(Self.maxRepetitionCount) times")
        }
        guard low <= high ?? low else { throw failure("a count's minimum exceeds its maximum") }
        index = cursor + 1
        return (low, high)
    }

    private mutating func parseAtom() throws(GrammarError) -> PatternNode {
        guard let scalar = next() else { throw failure("unexpected end") }
        switch scalar {
            case "(":
                try skipGroupPrefix()
                let inner = try parseAlternation()
                guard next() == ")" else { throw failure("unclosed group") }
                return inner
            case "[":
                return .characters(try parseClass())
            case ".":
                return .characters(Self.anyButNewline)
            case "\\":
                return .characters(try parseEscape(inClass: false).ranges)
            case "^", "$":
                throw failure("anchors are not supported")
            case "*", "+", "?":
                throw failure("a quantifier has nothing to repeat")
            default:
                return .characters(ScalarRanges(scalar: scalar.value))
        }
    }

    /// Consumes the `?:` or `?<name>` that may follow a group's `(`; a lookaround or an inline flag throws.
    private mutating func skipGroupPrefix() throws(GrammarError) {
        guard peek() == "?" else { return }
        index += 1
        switch next() {
            case ":":
                return
            case "<" where peek() != "=" && peek() != "!", "P" where peek() == "<":
                skip(through: ">")
            default:
                throw failure("lookaround and inline flags are not supported")
        }
    }

    /// Consumes scalars up to and including the next `terminator`, or to the end.
    private mutating func skip(through terminator: Unicode.Scalar) {
        while let scalar = next(), scalar != terminator {
            continue
        }
    }

    // MARK: - Classes and escapes

    /// One element of a bracketed class: a scalar, which may start a range, or a set such as `\d`.
    private enum ClassItem {
        case scalar(UInt32)
        case set(ScalarRanges)

        var ranges: ScalarRanges {
            switch self {
                case .scalar(let value): ScalarRanges(scalar: value)
                case .set(let set): set
            }
        }
    }

    /// The set of a `[…]` class, its `[` already read. A `]` first in the class is a literal, as in Rust's syntax,
    /// and so is a `-` that cannot form a range.
    private mutating func parseClass() throws(GrammarError) -> ScalarRanges {
        guard classDepth < 64 else { throw failure("class nesting exceeds 64 levels") }
        classDepth += 1
        defer { classDepth -= 1 }
        var negated = false
        if peek() == "^" {
            index += 1
            negated = true
        }
        var members: [ClosedRange<UInt32>] = []
        var isFirst = true
        while true {
            guard let scalar = peek() else { throw failure("unclosed class") }
            if scalar == "]", !isFirst {
                index += 1
                break
            }
            if scalar == "&", peek(offset: 1) == "&" {
                index += 2
                guard peek() == "[" else { throw failure("class intersection requires a nested class") }
                index += 1
                let shared = try ScalarRanges(members).intersection(parseClass())
                members = shared.ranges
                isFirst = false
                continue
            }
            isFirst = false
            let item = try parseClassItem()
            if case .scalar(let low) = item, peek() == "-", let after = peek(offset: 1), after != "]" {
                index += 1
                guard case .scalar(let high) = try parseClassItem(), low <= high else {
                    throw failure("invalid class range")
                }
                members.append(low ... high)
            } else {
                members.append(contentsOf: item.ranges.ranges)
            }
        }
        let set = ScalarRanges(members)
        return negated ? set.inverted() : set
    }

    private mutating func parseClassItem() throws(GrammarError) -> ClassItem {
        guard let scalar = next() else { throw failure("unclosed class") }
        switch scalar {
            case "\\":
                return try parseEscape(inClass: true)
            case "[" where peek() == ":":
                throw failure("POSIX classes are not supported")
            default:
                return .scalar(scalar.value)
        }
    }

    /// The scalar or set an escape stands for, its backslash already read.
    private mutating func parseEscape(inClass: Bool) throws(GrammarError) -> ClassItem {
        guard let scalar = next() else { throw failure("a trailing backslash") }
        switch scalar {
            case "d": return .set(Self.digits)
            case "D": return .set(Self.digits.inverted())
            case "w": return .set(Self.wordCharacters)
            case "W": return .set(Self.wordCharacters.inverted())
            case "s": return .set(Self.whitespace)
            case "S": return .set(Self.whitespace.inverted())
            case "n": return .scalar(0x0A)
            case "r": return .scalar(0x0D)
            case "t": return .scalar(0x09)
            case "f": return .scalar(0x0C)
            case "v": return .scalar(0x0B)
            case "0": return .scalar(0x00)
            case "b" where inClass: return .scalar(0x08)
            case "b", "B": throw failure("word boundaries are not supported")
            case "1" ... "9": throw failure("backreferences are not supported")
            case "x": return .scalar(try parseHexScalar(digits: 2))
            case "u": return .scalar(try parseHexScalar(digits: 4))
            case "c":
                guard let letter = next(), letter.properties.isAlphabetic, letter.isASCII else {
                    throw failure("an invalid control escape")
                }
                return .scalar(letter.value % 32)
            case "p", "P":
                let set = try UnicodeProperties.set(named: parsePropertyName(), in: pattern)
                return .set(scalar == "p" ? set : set.inverted())
            default:
                return .scalar(scalar.value)
        }
    }

    /// A scalar written as `digits` hexadecimal digits, or as any number of them in braces.
    private mutating func parseHexScalar(digits: Int) throws(GrammarError) -> UInt32 {
        var hex = ""
        if peek() == "{" {
            index += 1
            while let scalar = next(), scalar != "}" { hex.unicodeScalars.append(scalar) }
        } else {
            for _ in 0 ..< digits {
                guard let scalar = next() else { break }
                hex.unicodeScalars.append(scalar)
            }
        }
        guard let value = UInt32(hex, radix: 16), Unicode.Scalar(value) != nil else {
            throw failure("an invalid code point escape")
        }
        return value
    }

    /// The name in `\p{Name}` or the letter in `\pL`, the `p` already read.
    private mutating func parsePropertyName() throws(GrammarError) -> String {
        guard let scalar = next() else { throw failure("an unterminated property") }
        guard scalar == "{" else { return String(scalar) }
        var name = ""
        while let scalar = next(), scalar != "}" { name.unicodeScalars.append(scalar) }
        return name
    }

    // MARK: - Cursor

    private func peek(offset: Int = 0) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    private mutating func next() -> Unicode.Scalar? {
        guard index < scalars.count else { return nil }
        defer { index += 1 }
        return scalars[index]
    }

    private func failure(_ reason: String) -> GrammarError {
        .invalidRuleType("Pattern `\(pattern)`: \(reason)")
    }

    // MARK: - Sets

    // `\d`, `\w` and `\s` are ASCII, as tree-sitter rewrites them before it compiles a pattern: Unicode's classes
    // would let a JSON separator skip a no-break space, which JSON does not allow between tokens.
    static let anyButNewline = ScalarRanges(scalar: 0x0A).inverted()
    static let digits = ScalarRanges([0x30 ... 0x39])
    static let wordCharacters = ScalarRanges([0x30 ... 0x39, 0x41 ... 0x5A, 0x5F ... 0x5F, 0x61 ... 0x7A])
    /// Tab, line feed, vertical tab, form feed, carriage return and space: tree-sitter's `[\t-\r ]`.
    static let whitespace = ScalarRanges([0x09 ... 0x0D, 0x20 ... 0x20])
}
