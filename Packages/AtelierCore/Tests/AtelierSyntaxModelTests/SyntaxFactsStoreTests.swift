import AtelierSyntaxModel
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
}
