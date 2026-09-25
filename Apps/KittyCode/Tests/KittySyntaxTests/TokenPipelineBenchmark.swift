import AtelierGrammar
import AtelierGrammarCorpus
import AtelierLexers
import AtelierParser
import AtelierQuery
import AtelierSyntaxModel
import Foundation
import Testing

@testable import KittySyntax

/// Opt-in timing of the token steps between a scan or a parse and the styled lines, in a release build: splitting a
/// document's tokens per line, matching the JSON highlight query, and resolving each capture to a role.
///
/// `GDV_BENCH=1 swift test -c release --filter TokenPipelineBenchmark`. Every input is generated, so two builds time
/// the same work; the checksums cover every per-line token and every match, so two builds that print the same
/// checksums produce the same tokens and matches.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
struct TokenPipelineBenchmark {
    private static let iterations = 13
    private static let warmUps = 2

    /// The lexical tokens of a 100,000-line Swift document, split per line the way the renderers read them.
    @Test
    func `splits a hundred thousand lines of tokens per line`() {
        let text = Self.swiftDocument(lines: 100_000)
        let bytes = Array(text.utf8)
        var lineStarts = [0]
        for (offset, byte) in bytes.enumerated() where byte == 0x0A { lineStarts.append(offset + 1) }
        let tokens = LexicalHighlightEngine().highlight(utf8: bytes, language: .swift)
        var samples: [Double] = []
        var checksum: UInt64 = 0
        for iteration in 0 ..< Self.iterations {
            // Each result is released before the next timed call, so no call pays for freeing another's.
            var byLine: [[HighlightToken]] = []
            let elapsed = Self.milliseconds {
                byLine = HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: bytes.count)
            }
            if iteration == 0 { checksum = Self.checksum(of: byLine) }
            if iteration >= Self.warmUps { samples.append(elapsed) }
        }
        print("BENCH tokens-per-line lines \(lineStarts.count) tokens \(tokens.count) checksum \(checksum)")
        Self.report("tokens-per-line byLine", samples)

        var flatSamples: [Double] = []
        var flatChecksum: UInt64 = 0
        for iteration in 0 ..< Self.iterations {
            var lines = LineTokens(emptyLines: 0)
            let elapsed = Self.milliseconds {
                lines = LineTokens(tokens, lineStarts: lineStarts, textLength: bytes.count)
            }
            // The lexer's tokens all have priority 0, which a line token leaves out.
            if iteration == 0 {
                flatChecksum = Self.checksum(
                    of: lines.map { line in
                        line.map { HighlightToken(byteRange: $0.range, role: $0.role, modifiers: $0.modifiers) }
                    })
            }
            if iteration >= Self.warmUps { flatSamples.append(elapsed) }
        }
        #expect(flatChecksum == checksum)
        print("BENCH tokens-per-line LineTokens checksum \(flatChecksum)")
        Self.report("tokens-per-line LineTokens", flatSamples)
    }

    /// The JSON highlight query over a generated document: the match, the role of each capture, and the tokens and
    /// spans the highlighter builds from the matches.
    @Test
    func `matches the json query and resolves its capture roles`() throws {
        let resources = try #require(KittySyntaxResources.resourcePath)
        let grammar = try GrammarLoader.load(from: "\(resources)/Grammars/json/grammar.json")
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let query = try QueryParser.parse(
            String(contentsOfFile: "\(resources)/Grammars/json/highlights.scm", encoding: .utf8))
        let source = Self.jsonDocument(bytes: 40_000)
        let parseStart = ContinuousClock.now
        let tree = try parser.parse(source)
        print("BENCH json bytes \(source.utf8.count) parse \(ContinuousClock.now - parseStart)")

        var matchSamples: [Double] = []
        var matches: [QueryMatch] = []
        for iteration in 0 ..< Self.iterations {
            var result: [QueryMatch] = []
            let elapsed = Self.milliseconds { result = QueryMatcher.execute(query: query, tree: tree) }
            if iteration >= Self.warmUps { matchSamples.append(elapsed) }
            matches = result
        }
        let captureCount = matches.reduce(0) { $0 + $1.captures.count }
        print(
            "BENCH json matches \(matches.count) captures \(captureCount) checksum \(Self.checksum(of: matches))")
        Self.report("json match", matchSamples)

        // What `buildTokens` did per capture before the roles were resolved once per query: two lookups by name.
        var byName: [Double] = []
        var byNameSum = 0
        for iteration in 0 ..< Self.iterations {
            var sum = 0
            let elapsed = Self.milliseconds {
                for match in matches {
                    for capture in match.captures where CaptureRoleMapper.colorsText(capture.name) {
                        let (role, modifiers) = CaptureRoleMapper.map(capture.name)
                        sum &+= Int(role.rawValue) &+ Int(modifiers.rawValue)
                    }
                }
            }
            #expect(sum > 0)
            byNameSum = sum
            if iteration >= Self.warmUps { byName.append(elapsed * 1e6 / Double(captureCount)) }
        }
        Self.report("json capture-role by-name (ns per capture)", byName, unit: "ns")

        // What it does since: one read of the query's roles by the capture's index.
        let roles = CaptureRoles(captureNames: query.captureNames)
        var byIndex: [Double] = []
        for iteration in 0 ..< Self.iterations {
            var sum = 0
            let elapsed = Self.milliseconds {
                for match in matches {
                    for capture in match.captures {
                        guard let resolved = roles[capture.index] else { continue }
                        sum &+= Int(resolved.role.rawValue) &+ Int(resolved.modifiers.rawValue)
                    }
                }
            }
            #expect(sum == byNameSum)
            if iteration >= Self.warmUps { byIndex.append(elapsed * 1e6 / Double(captureCount)) }
        }
        Self.report("json capture-role by-index (ns per capture)", byIndex, unit: "ns")

        let highlighter = Highlighter(theme: .monokai)
        var tokenSamples: [Double] = []
        var tokenChecksum: UInt64 = 0
        for iteration in 0 ..< Self.iterations {
            var tokens: [HighlightToken] = []
            let elapsed = Self.milliseconds { tokens = highlighter.buildTokens(matches: matches, roles: roles) }
            if iteration == 0 { tokenChecksum = Self.checksum(of: [tokens]) }
            if iteration >= Self.warmUps { tokenSamples.append(elapsed) }
        }
        print("BENCH json buildTokens checksum \(tokenChecksum)")
        Self.report("json buildTokens", tokenSamples)

        var spanSamples: [Double] = []
        var spanCount = 0
        for iteration in 0 ..< Self.iterations {
            var spans: [StyledSpan] = []
            let elapsed = Self.milliseconds {
                spans = highlighter.highlight(source: source, tree: tree, query: query)
            }
            spanCount = spans.count
            if iteration >= Self.warmUps { spanSamples.append(elapsed) }
        }
        print("BENCH json highlight spans \(spanCount)")
        Self.report("json highlight (match + spans)", spanSamples)
    }

    /// Every capture name of every bundled query that parses, in pattern order, repeated to 100,000 captures: the
    /// names of all the languages, most of them dotted, rather than JSON's few.
    @Test
    func `resolves the capture roles of every bundled query`() throws {
        let resources = try #require(KittySyntaxResources.resourcePath)
        var names: [String] = []
        // Each query's roles, and its captures' indices in the order `names` lists their names.
        var queries: [(roles: CaptureRoles, indices: [Int])] = []
        for entry in BundledLanguageManifest.entries {
            let path = "\(resources)/Grammars/\(entry.path)/highlights.scm"
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                let query = try? QueryParser.parse(text)
            else { continue }
            var captures: [QueryPattern.Capture] = []
            for pattern in query.patterns { Self.collectCaptures(pattern, into: &captures) }
            names.append(contentsOf: captures.map(\.name))
            queries.append((CaptureRoles(captureNames: query.captureNames), captures.map(\.index)))
        }
        try #require(!names.isEmpty)
        var stream: [String] = []
        while stream.count < 100_000 { stream.append(contentsOf: names) }
        var byName: [Double] = []
        var byNameSum = 0
        for iteration in 0 ..< Self.iterations {
            var sum = 0
            let elapsed = Self.milliseconds {
                for name in stream where CaptureRoleMapper.colorsText(name) {
                    let (role, modifiers) = CaptureRoleMapper.map(name)
                    sum &+= Int(role.rawValue) &+ Int(modifiers.rawValue)
                }
            }
            #expect(sum > 0)
            byNameSum = sum
            if iteration >= Self.warmUps { byName.append(elapsed * 1e6 / Double(stream.count)) }
        }
        print("BENCH bundled capture names \(names.count) stream \(stream.count)")
        Self.report("bundled capture-role by-name (ns per capture)", byName, unit: "ns")

        // The same captures, the same number of times, each read by index from its own query's roles.
        let repeats = stream.count / names.count
        var byIndex: [Double] = []
        for iteration in 0 ..< Self.iterations {
            var sum = 0
            let elapsed = Self.milliseconds {
                for _ in 0 ..< repeats {
                    for query in queries {
                        for index in query.indices {
                            guard let resolved = query.roles[index] else { continue }
                            sum &+= Int(resolved.role.rawValue) &+ Int(resolved.modifiers.rawValue)
                        }
                    }
                }
            }
            #expect(sum == byNameSum)
            if iteration >= Self.warmUps { byIndex.append(elapsed * 1e6 / Double(stream.count)) }
        }
        Self.report("bundled capture-role by-index (ns per capture)", byIndex, unit: "ns")
    }

    // MARK: - Inputs

    private static func swiftDocument(lines: Int) -> String {
        let templates = [
            "    let value# = compute(index: #, name: \"item # ✓\") // trailing note",
            "    /* block */ @MainActor func f#() async throws -> Int { 0x1F + 1.5e3 }",
            "/// Returns the value at `index`, or nil past the end.",
            "}"
        ]
        var text = ""
        for index in 0 ..< lines {
            text += templates[index % templates.count].replacingOccurrences(of: "#", with: String(index))
            text += "\n"
        }
        return text
    }

    /// Records of strings with escapes, numbers, literals and nested arrays, to about `bytes` bytes.
    private static func jsonDocument(bytes: Int) -> String {
        var records: [String] = []
        var size = 0
        var index = 0
        while size < bytes {
            let record =
                "  {\"id\": \(index), \"name\": \"item \\\"\(index)\\\"\\n\", \"ok\": \(index % 2 == 0), "
                + "\"none\": null, \"tags\": [\"a\", \"b\\t\", \(index).5e3], \"nested\": {\"k\": [1, 2, {\"x\": false}]}}"
            records.append(record)
            size += record.utf8.count + 2
            index += 1
        }
        return "[\n" + records.joined(separator: ",\n") + "\n]\n"
    }

    /// The captures of `pattern` in the order the name stream has always listed them: a node's before its children's.
    private static func collectCaptures(_ pattern: QueryPattern, into captures: inout [QueryPattern.Capture]) {
        switch pattern {
            case .nodeMatch(_, let children, let capture):
                if let capture { captures.append(capture) }
                for child in children { collectCaptures(child, into: &captures) }
            case .literal(_, let capture), .wildcard(let capture):
                if let capture { captures.append(capture) }
            case .fieldMatch(_, let inner), .quantified(let inner, _):
                collectCaptures(inner, into: &captures)
            case .alternation(let patterns), .sequence(let patterns):
                for inner in patterns { collectCaptures(inner, into: &captures) }
            case .negatedField, .predicate, .anchor:
                break
        }
    }

    // MARK: - Checksums and reporting

    /// FNV-1a over each line's tokens: the line, each range, role and modifiers.
    private static func checksum(of lines: [[HighlightToken]]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for (line, tokens) in lines.enumerated() {
            for token in tokens {
                let fields = [
                    UInt64(line), UInt64(token.byteRange.lowerBound), UInt64(token.byteRange.upperBound),
                    UInt64(token.role.rawValue), UInt64(token.modifiers.rawValue),
                    UInt64(bitPattern: Int64(token.priority))
                ]
                for field in fields { hash = (hash ^ field) &* 1_099_511_628_211 }
            }
        }
        return hash
    }

    /// FNV-1a over each match: its pattern, and each capture's name and range.
    private static func checksum(of matches: [QueryMatch]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for match in matches {
            hash = (hash ^ UInt64(match.patternIndex)) &* 1_099_511_628_211
            for capture in match.captures {
                for byte in capture.name.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
                for field in [capture.node.byteRange.lowerBound, capture.node.byteRange.upperBound] {
                    hash = (hash ^ UInt64(field)) &* 1_099_511_628_211
                }
            }
        }
        return hash
    }

    private static func report(_ name: String, _ samples: [Double], unit: String = "ms") {
        let sorted = samples.sorted()
        let rounded = sorted.map { ($0 * 1_000).rounded() / 1_000 }
        print("BENCH \(name) median \(sorted[sorted.count / 2]) \(unit) samples \(rounded)")
    }

    private static func milliseconds(_ body: () -> Void) -> Double {
        let elapsed = ContinuousClock().measure(body)
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
}
