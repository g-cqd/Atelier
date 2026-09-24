import Testing

@testable import AtelierGrammar

/// The regular expressions of `PATTERN` rules, as the lexer compiles them.
@Suite
struct PatternParserTests {
    @Test
    func `A negated class holds every scalar but the ones it lists`() throws {
        let set = try Self.characters(#"[^\\"\n]"#)

        #expect(set.contains(Self.value("a")))
        #expect(set.contains(Self.value("é")))
        #expect(!set.contains(Self.value("\\")))
        #expect(!set.contains(Self.value("\"")))
        #expect(!set.contains(Self.value("\n")))
    }

    @Test
    func `A hyphen that cannot form a range is a literal`() throws {
        let set = try Self.characters("[a-z0-9-_]")

        #expect(set.contains(Self.value("-")))
        #expect(set.contains(Self.value("_")))
        #expect(!set.contains(Self.value(":")))
    }

    @Test
    func `Escapes name the characters they stand for`() throws {
        #expect(try Self.characters(#"\d"#) == ScalarRanges([48 ... 57]))
        #expect(try Self.characters(#"\x41"#) == ScalarRanges(scalar: 0x41))
        #expect(try Self.characters(#"é"#) == ScalarRanges(scalar: 0xE9))
        #expect(try Self.characters(#"\/"#) == ScalarRanges(scalar: 0x2F))
    }

    @Test
    func `The whitespace class is ASCII whitespace, as tree-sitter reads it`() throws {
        #expect(try Self.characters(#"\s"#) == ScalarRanges([0x09 ... 0x0D, 0x20 ... 0x20]))
    }

    @Test
    func `Quantifiers parse to their bounds, lazy or not`() throws {
        let letter = PatternNode.characters(ScalarRanges(scalar: Self.value("a")))

        #expect(try PatternParser.parse("a{2,4}") == .repetition(letter, min: 2, max: 4))
        #expect(try PatternParser.parse("a{3,}") == .repetition(letter, min: 3, max: nil))
        #expect(try PatternParser.parse("a*?") == .repetition(letter, min: 0, max: nil))
    }

    @Test
    func `A brace that opens no count is a literal`() throws {
        let node = try PatternParser.parse("a{b")

        #expect(node == .sequence(["a", "{", "b"].map { .characters(ScalarRanges(scalar: Self.value($0))) }))
    }

    @Test
    func `An identifier property holds the scalars that start identifiers`() throws {
        let set = try Self.characters(#"\p{XID_Start}"#)

        #expect(set.contains(Self.value("é")))
        #expect(set.contains(Self.value("Ж")))
        #expect(!set.contains(Self.value("1")))
    }

    @Test
    func `A nested class intersection excludes unwanted scalars`() throws {
        let set = try Self.characters(#"[a-z0-9&&[^0-9]]"#)

        #expect(set.contains(Self.value("a")))
        #expect(!set.contains(Self.value("1")))
        #expect(!set.contains(Self.value("#")))
    }

    @Test(arguments: ["^a", #"a\b"#, "(?=a)", #"\p{Klingon}"#, "a)", "[a"])
    func `A construct a token cannot use is rejected`(pattern: String) {
        #expect(throws: GrammarError.self) { try PatternParser.parse(pattern) }
    }

    private static func characters(_ pattern: String) throws -> ScalarRanges {
        guard case .characters(let set) = try PatternParser.parse(pattern) else {
            Issue.record("`\(pattern)` is not a single character class")
            return .empty
        }
        return set
    }

    private static func value(_ character: Character) -> UInt32 {
        character.unicodeScalars.first?.value ?? 0
    }
}
