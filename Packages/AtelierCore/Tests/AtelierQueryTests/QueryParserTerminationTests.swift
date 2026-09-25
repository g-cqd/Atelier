import Foundation
import Synchronization
import Testing

@testable import AtelierQuery

/// Every parse ends: a malformed query throws, and none loops forever. Each parse runs under
/// `parseWithinTimeLimit(_:seconds:)`, so a parse that stops advancing fails its test instead of blocking the suite.
@Suite
struct QueryParserTerminationTests {
    @Test(arguments: [
        #"((identifier) @a (#eq? @a $))"#,
        #"((identifier) @a (#eq? @a (b)))"#,
        #"((identifier) @a (#eq? @a [x]))"#,
        #"((identifier) @a (#eq? @a ,))"#,
        #"((identifier) @a (#any-of? @a "x" ?))"#,
        #"((identifier) @a (#eq? @a "x" }))"#,
        #"(identifier) @a #eq? @a "x" (other)"#,
        #"((identifier) @a (#match? @a "unterminated))"#,
        #"((identifier) @a (#eq? @a "x""#,
        #"((identifier) @a (#))"#,
        #"((identifier) @a (# eq? @a "x"))"#,
        "#",
        "(#",
        #"((identifier) @a (#eq @a "x"))"#,
        #"((identifier) @a (#eq? @ "x"))"#,
        #"((identifier) @a (#eq? @a @))"#,
        "(identifier) @",
        "(pair : (value))",
        "(pair !)"
    ])
    func `A malformed query throws promptly`(source: String) async {
        let outcome = await parseWithinTimeLimit(source)
        guard let outcome else {
            Issue.record("parsing \(source) did not end")
            return
        }
        #expect(throws: QueryError.self) { try outcome.get() }
    }

    @Test
    func `A predicate argument the parser cannot read is an error at its line and column`() {
        #expect(throws: QueryError.syntaxError(#"Unexpected character "$" in a predicate at line 2, column 10"#)) {
            try QueryParser.parse("(identifier) @a\n(#eq? @a $)")
        }
    }

    @Test
    func `Every single-character mutation of a bundled query ends its parse`() async throws {
        let queries = try BundledHighlightQueries.all()
        #expect(queries.count > 10)
        var generator = SplitMix64(seed: 0x51E5_A7E1)
        var parses = 0
        for (language, source) in queries {
            for mutation in QueryMutation.sample(of: source, count: 48, using: &generator) {
                let mutated = mutation.applied(to: source)
                guard await parseWithinTimeLimit(mutated) != nil else {
                    Issue.record("parsing \(language)'s query with \(mutation) did not end")
                    return
                }
                parses += 1
            }
        }
        #expect(parses == queries.count * 48)
    }
}

// MARK: - A bounded parse

/// The outcome of parsing `source` on its own thread, or nil when the parse has not ended within `seconds`. The
/// thread of a parse that has not ended is left running: a loop that never advances cannot be interrupted.
private func parseWithinTimeLimit(_ source: String, seconds: Int = 10) async -> Result<Query, QueryError>? {
    await withCheckedContinuation { continuation in
        let once = ResumeOnce(continuation)
        let thread = Thread {
            once.resume(returning: Result { () throws(QueryError) in try QueryParser.parse(source) })
        }
        thread.stackSize = poolThreadStackSize
        thread.start()
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) { once.resume(returning: nil) }
    }
}

/// Resumes a continuation with the first result it is given and ignores the rest.
private final class ResumeOnce<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(returning value: Value) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }
}

// MARK: - Mutations of the bundled queries

/// KittyCode's bundled highlight queries, read from this checkout.
private enum BundledHighlightQueries {
    /// Each bundled language's name and its `highlights.scm`, in name order.
    static func all() throws -> [(language: String, source: String)] {
        // Tests/AtelierQueryTests/ → the repository root, four levels up from this file's directory.
        let grammars = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Apps/KittyCode/Sources/KittySyntax/Grammars")
        let languages = try FileManager.default.contentsOfDirectory(atPath: grammars.path()).sorted()
        return try languages.compactMap { language in
            let file = grammars.appending(path: language).appending(path: "highlights.scm")
            guard FileManager.default.fileExists(atPath: file.path()) else { return nil }
            return (language, try String(contentsOf: file, encoding: .utf8))
        }
    }
}

/// One character of a query deleted, replaced, or inserted before.
private struct QueryMutation: CustomStringConvertible {
    enum Kind {
        case delete
        case replace(Character)
        case insert(Character)
    }

    /// The characters a mutation writes: the query syntax's punctuation and a few others.
    private static let alphabet = Array(#"()[]{}"@#!?:_.;\ ,$*+-x"#) + ["\n"]

    var offset: Int
    var kind: Kind

    var description: String {
        switch kind {
            case .delete: "the character at \(offset) deleted"
            case .replace(let character): "the character at \(offset) replaced by \(character.debugDescription)"
            case .insert(let character): "\(character.debugDescription) inserted at \(offset)"
        }
    }

    func applied(to source: String) -> String {
        var characters = Array(source)
        switch kind {
            case .delete: characters.remove(at: offset)
            case .replace(let character): characters[offset] = character
            case .insert(let character): characters.insert(character, at: offset)
        }
        return String(characters)
    }

    /// `count` mutations of `source`: half near its predicates, where an argument the parser cannot read used to stop
    /// it advancing, and half anywhere.
    static func sample(of source: String, count: Int, using generator: inout SplitMix64) -> [QueryMutation] {
        let characters = Array(source)
        guard !characters.isEmpty else { return [] }
        let predicateStarts = characters.indices.filter { characters[$0] == "#" }
        return (0 ..< count)
            .map { index in
                var offset = Int.random(in: characters.indices, using: &generator)
                if index.isMultiple(of: 2), let start = predicateStarts.randomElement(using: &generator) {
                    offset = min(start + Int.random(in: -2 ... 24, using: &generator), characters.count - 1)
                    offset = max(offset, 0)
                }
                let character = alphabet.randomElement(using: &generator) ?? "x"
                let kind: Kind =
                    switch Int.random(in: 0 ..< 3, using: &generator) {
                        case 0: .delete
                        case 1: .replace(character)
                        default: .insert(character)
                    }
                return QueryMutation(offset: offset, kind: kind)
            }
    }
}

/// A seeded generator, so the sweep tries the same mutations on every run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
