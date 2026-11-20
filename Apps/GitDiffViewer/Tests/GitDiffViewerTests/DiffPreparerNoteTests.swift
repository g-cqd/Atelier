import AemiTesting
import DiffCore
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A prepared file carries what differs between its sides that its lines do not show, and a single file's render
/// passes it on to the change summary.
@MainActor
@Suite(.mainActorLane)
struct DiffPreparerNoteTests {
    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()

    private func prepare(_ pair: FilePair) async throws -> PreparedDiff {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        let prepared = try await preparer.prepare(
            [pair],
            left: .directory(ModelTestHarness.leftURL),
            right: .directory(ModelTestHarness.rightURL),
            granularity: .word,
            heuristics: DiffHeuristics()
        )
        return try #require(prepared.first)
    }

    @Test
    func `a file converted to CRLF that lost its final newline carries both notes, and its render too`() async throws {
        reader.blobContents["lf"] = "a\nb\n"
        reader.blobContents["crlf"] = "a\r\nb"
        let pair = FilePair(
            path: "a.txt",
            old: SourceEntry(relativePath: "a.txt", blobID: "lf", size: 4),
            new: SourceEntry(relativePath: "a.txt", blobID: "crlf", size: 4)
        )

        let prepared = try await prepare(pair)
        let rendered = DiffRenderer.render(
            prepared: [prepared],
            options: DiffRenderer.Options(sides: [.unified]),
            layout: .full,
            withHeaders: false
        )

        #expect(prepared.notes == [.lineEndings(old: .lf, new: .crlf), .finalNewline(old: true, new: false)])
        #expect(rendered.notes == prepared.notes)
    }

    @Test
    func `the same blobs under two modes are prepared apart, each with its own note`() async throws {
        reader.blobContents["script"] = "echo hi\n"
        let plain = FilePair(
            path: "run.sh",
            old: SourceEntry(relativePath: "run.sh", blobID: "script", size: 8, mode: "100644"),
            new: SourceEntry(relativePath: "run.sh", blobID: "script", size: 8, mode: "100644")
        )
        let executable = FilePair(
            path: "run.sh",
            old: SourceEntry(relativePath: "run.sh", blobID: "script", size: 8, mode: "100644"),
            new: SourceEntry(relativePath: "run.sh", blobID: "script", size: 8, mode: "100755")
        )
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        let sides = (
            left: ComparisonSource.directory(ModelTestHarness.leftURL),
            right: ComparisonSource.directory(ModelTestHarness.rightURL)
        )

        let first = try await preparer.prepare(
            [plain],
            left: sides.left,
            right: sides.right,
            granularity: .word,
            heuristics: DiffHeuristics()
        )
        let second = try await preparer.prepare(
            [executable],
            left: sides.left,
            right: sides.right,
            granularity: .word,
            heuristics: DiffHeuristics()
        )

        #expect(first.first?.notes == [])
        #expect(second.first?.notes == [.mode(old: "100644", new: "100755")])
    }
}
