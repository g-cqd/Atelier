import Synchronization
import Testing

@testable import AtelierDocIndex

/// Counts the files an index parses.
private final class ParseSpy: Sendable {
    private let parsed = Mutex<[String]>([])

    /// The URIs parsed so far, in order.
    var uris: [String] { parsed.withLock { $0 } }

    func extract(uri: String, content: String) -> [DocEntry] {
        parsed.withLock { $0.append(uri) }
        return DocCommentIndex.extractEntries(uri: uri, content: content)
    }
}

/// How an index takes files one comparison after another: incrementally, parsing only what changed, off the actor
/// and cancellably, with every name's entries in one bucket.
struct DocCommentIndexUpdateTests {
    private let spy = ParseSpy()

    private func makeIndex() -> DocCommentIndex {
        DocCommentIndex(extractor: { [spy] uri, content in spy.extract(uri: uri, content: content) })
    }

    private func markdown(of name: String, in index: DocCommentIndex) async -> [String] {
        await index.documentation(forIdentifier: name, preferringURI: nil).map(\.markdown)
    }

    @Test
    func `an upsert keeps every file it does not name`() async throws {
        let index = makeIndex()
        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// A.\nfunc a() {}")])

        try await index.upsert([DocIndexFile(uri: "file:///b.swift", content: "/// B.\nfunc b() {}")])

        #expect(await markdown(of: "a", in: index) == ["A."])
        #expect(await markdown(of: "b", in: index) == ["B."])
    }

    @Test
    func `a file already indexed at its blob id is not parsed again`() async throws {
        let index = makeIndex()
        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// A.\nfunc a() {}", blobID: "1")])

        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// A.\nfunc a() {}", blobID: "1")])

        #expect(spy.uris == ["file:///a.swift"])
    }

    @Test
    func `a file at a new blob id is parsed again`() async throws {
        let index = makeIndex()
        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// Old.\nfunc a() {}", blobID: "1")])

        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// New.\nfunc a() {}", blobID: "2")])

        #expect(await markdown(of: "a", in: index) == ["New."])
    }

    @Test
    func `a file without a blob id is parsed again only when its content changes`() async throws {
        let index = makeIndex()
        let old = DocIndexFile(uri: "file:///a.swift", content: "/// Old.\nfunc a() {}")
        try await index.upsert([old])
        try await index.upsert([old])
        #expect(spy.uris.count == 1)

        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// New.\nfunc a() {}")])

        #expect(spy.uris.count == 2)
        #expect(await markdown(of: "a", in: index) == ["New."])
    }

    @Test
    func `keeping only some files drops every other file with its entries`() async throws {
        let index = makeIndex()
        try await index.upsert([
            DocIndexFile(uri: "file:///a.swift", content: "/// A.\nfunc a() {}"),
            DocIndexFile(uri: "file:///b.swift", content: "/// B.\nfunc b() {}")
        ])

        try await index.keepOnly(["file:///a.swift"])

        #expect(await index.fileCount == 1)
        #expect(await markdown(of: "a", in: index) == ["A."])
        #expect(await markdown(of: "b", in: index).isEmpty)
    }

    @Test
    func `only files indexed at the blob id asked about count as indexed`() async throws {
        let index = makeIndex()
        try await index.upsert([
            DocIndexFile(uri: "file:///a.swift", content: "func a() {}", blobID: "1"),
            DocIndexFile(uri: "file:///b.swift", content: "func b() {}", blobID: "2"),
            DocIndexFile(uri: "file:///c.swift", content: "func c() {}")
        ])

        let indexed = await index.urisIndexed(atBlobIDs: [
            "file:///a.swift": "1", "file:///b.swift": "3", "file:///c.swift": "4", "file:///d.swift": "5"
        ])

        #expect(indexed == ["file:///a.swift"])
    }

    @Test
    func `an update cancelled before it starts parses nothing and changes nothing`() async throws {
        let index = makeIndex()
        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// Old.\nfunc a() {}")])

        let threwCancellation = await withTaskGroup(of: Bool.self) { group in
            group.cancelAll()
            // Added to a cancelled group, the task starts cancelled.
            group.addTask {
                do {
                    try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: "/// New.\nfunc a() {}")])
                    return false
                } catch {
                    return error is CancellationError
                }
            }
            return await group.next() ?? false
        }

        #expect(threwCancellation)
        #expect(spy.uris.count == 1)
        #expect(await markdown(of: "a", in: index) == ["Old."])
    }

    @Test
    func `the lookup by name lists what a scan of every file lists`() async throws {
        let index = makeIndex()
        let files = [
            "file:///a.swift": "/// A run.\nfunc run() {}\n/// A stop.\nfunc stop() {}",
            "file:///b.swift": "/// B run.\nfunc run() {}\n/// B size.\nvar size: Int",
            "file:///c.swift": "/// C stop.\nfunc stop() {}\nstruct Plain {}"
        ]
        var indexed = files
        try await index.upsert(files.map { DocIndexFile(uri: $0.key, content: $0.value) })
        indexed["file:///b.swift"] = "/// B run, again.\nfunc run() {}\n/// B stop.\nfunc stop() {}"
        try await index.upsert([DocIndexFile(uri: "file:///b.swift", content: indexed["file:///b.swift"] ?? "")])
        indexed["file:///a.swift"] = nil
        try await index.keepOnly(Set(indexed.keys))

        for name in ["run", "stop", "size", "Plain", "missing"] {
            let scanned = indexed.flatMap { DocCommentIndex.extractEntries(uri: $0.key, content: $0.value) }
                .filter { $0.name == name }
            #expect(sorted(await index.matches(named: name)) == sorted(scanned), "\(name)")
        }
    }

    private func sorted(_ entries: [DocEntry]) -> [DocEntry] {
        entries.sorted { ($0.uri, $0.signature, $0.markdown) < ($1.uri, $1.signature, $1.markdown) }
    }
}
