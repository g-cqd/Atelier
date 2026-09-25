import AtelierSyntaxModel
import Dispatch
import Synchronization
import Testing

/// The facts store keeps one parse's facts per revision within a byte budget (PERF-11 step 3).
struct SyntaxFactsStoreTests {
    /// Facts whose estimate grows with `lines`, each line holding one boundary.
    private static func facts(lines: Int) -> SyntaxFacts {
        SyntaxFacts(
            tokenBoundaries: Array(repeating: [0 ..< 1], count: lines), declarations: [], highlights: [],
            unexpectedShare: 0)
    }

    private static func revision(_ blob: String, document: String = "a.swift") -> SourceRevision {
        SourceRevision(documentID: document, language: .swift, key: .content(blob))
    }

    @Test
    func `a caller that misses a revision under extraction takes that extraction's facts`() {
        let store = SyntaxFactsStore()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchGroup()
        let results = Mutex([SyntaxFacts?]())
        DispatchQueue.global()
            .async(group: done) {
                let facts = store.facts(for: Self.revision("a")) {
                    started.signal()
                    release.wait()
                    return Self.facts(lines: 3)
                }
                results.withLock { $0.append(facts) }
            }
        started.wait()
        DispatchQueue.global()
            .async(group: done) {
                let facts = store.facts(for: Self.revision("a")) { Self.facts(lines: 7) }
                results.withLock { $0.append(facts) }
            }
        release.signal()
        done.wait()

        #expect(store.extractions == 1)
        #expect(results.withLock { $0 }.map { $0?.tokenBoundaries.count } == [3, 3])
    }

    @Test
    func `a store past its bound evicts the entry used least recently`() {
        let size = Self.facts(lines: 100).estimatedBytes
        let store = SyntaxFactsStore(byteLimit: size * 5 / 2)
        store.insert(Self.facts(lines: 100), for: Self.revision("a"))
        store.insert(Self.facts(lines: 100), for: Self.revision("b"))
        _ = store.facts(for: Self.revision("a"))

        store.insert(Self.facts(lines: 100), for: Self.revision("c"))

        #expect(store.facts(for: Self.revision("a")) != nil)
        #expect(store.facts(for: Self.revision("b")) == nil)
        #expect(store.facts(for: Self.revision("c")) != nil)
        #expect(store.byteCount <= store.byteLimit)
    }

    @Test
    func `content finds its facts from any document, a version only from its own`() {
        let store = SyntaxFactsStore()
        store.insert(Self.facts(lines: 1), for: Self.revision("blob", document: "old/a.swift"))
        let version = SourceRevision(documentID: "a.swift", language: .swift, key: .version(3))
        store.insert(Self.facts(lines: 1), for: version)

        #expect(store.facts(for: Self.revision("blob", document: "new/a.swift")) != nil)
        #expect(store.facts(for: SourceRevision(documentID: "b.swift", language: .swift, key: .version(3))) == nil)
        #expect(store.facts(for: SourceRevision(documentID: "a.swift", language: .json, key: .content("blob"))) == nil)
    }

    @Test
    func `a miss extracts once, a hit never, and a cancelled extraction keeps nothing`() {
        let store = SyntaxFactsStore()

        _ = store.facts(for: Self.revision("a")) { nil }
        _ = store.facts(for: Self.revision("a")) { Self.facts(lines: 2) }
        _ = store.facts(for: Self.revision("a")) { Self.facts(lines: 3) }

        #expect(store.extractions == 2)
        #expect(store.facts(for: Self.revision("a"))?.tokenBoundaries.count == 2)
    }

    @Test
    func `symbol kinds share the byte budget, the least recently used entry of either leaving first`() {
        let size = Self.facts(lines: 100).estimatedBytes
        let kinds = SymbolKinds(
            tokens: (0 ..< 200).map { HighlightToken(byteRange: $0 * 4 ..< $0 * 4 + 3, role: .variable) })
        let store = SyntaxFactsStore(byteLimit: size + kinds.estimatedBytes + size / 2)
        store.insert(kinds, for: Self.revision("a"))
        store.insert(Self.facts(lines: 100), for: Self.revision("b"))

        store.insert(Self.facts(lines: 100), for: Self.revision("c"))

        #expect(store.symbolKinds(for: Self.revision("a")) == nil)
        #expect(store.facts(for: Self.revision("b")) != nil)
        #expect(store.facts(for: Self.revision("c")) != nil)
        #expect(store.byteCount <= store.byteLimit)
    }

    @Test
    func `a symbol kind is found by the byte it covers`() {
        let kinds = SymbolKinds(tokens: [
            HighlightToken(byteRange: 0 ..< 3, role: .keyword), HighlightToken(byteRange: 3 ..< 4, role: .operator),
            HighlightToken(byteRange: 4 ..< 9, role: .variable), HighlightToken(byteRange: 12 ..< 14, role: .string),
            HighlightToken(byteRange: 15 ..< 20, role: .comment)
        ])

        #expect(
            [0, 2, 3, 4, 8, 10, 12, 16, 20].map(kinds.kind(atUTF8:)) == [
                .keyword, .keyword, nil, .symbol, .symbol, nil, .literal, .comment, nil
            ])
    }
}
