import AemiTesting
import DiffCore
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A file's language comes from its name and its first line as well as its extension, so a dotfile and a script
/// without an extension are coloured as their language (`Language(path:firstLine:)`).
@MainActor
@Suite(.mainActorLane)
struct DiffPreparerLanguageTests {
    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()

    @Test
    func `a dotfile is prepared as shell by its file name`() async throws {
        reader.blobContents["zshrc"] = "export PATH=\"$HOME/bin:$PATH\"\n"
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        let pairs = [
            FilePair(path: ".zshrc", old: nil, new: SourceEntry(relativePath: ".zshrc", blobID: "zshrc", size: 1))
        ]

        let prepared = try await preparer.prepare(
            pairs, left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics())

        #expect(prepared.map(\.language) == [.shell])
    }

    @Test
    func `an extensionless shell script is prepared as shell by its shebang`() async throws {
        reader.blobContents["deploy"] = "#!/bin/sh\necho deploying\n"
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        let pairs = [
            FilePair(
                path: "bin/deploy", old: nil, new: SourceEntry(relativePath: "bin/deploy", blobID: "deploy", size: 1))
        ]

        let prepared = try await preparer.prepare(
            pairs, left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics())

        #expect(prepared.map(\.language) == [.shell])
    }

    @Test
    func `a deleted shell script is prepared as shell by the shebang of its old side`() async throws {
        reader.blobContents["deployOld"] = "#!/bin/sh\necho deploying\n"
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        let pairs = [
            FilePair(
                path: "bin/deploy", old: SourceEntry(relativePath: "bin/deploy", blobID: "deployOld", size: 1),
                new: nil)
        ]

        let prepared = try await preparer.prepare(
            pairs, left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics())

        #expect(prepared.map(\.language) == [.shell])
    }
}
