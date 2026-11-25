import AtelierDiagnostics
import DiffGit
import Testing

@testable import DiffComparison

/// ``DiagnosticFileIndex``'s mapping from a render target's file order to the path findings are keyed under.
struct DiagnosticFileIndexTests {
    private func entry(_ path: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: "blob", size: 1)
    }

    @Test
    func `a file present on both sides maps to its new (right) path`() {
        let pairs = [FilePair(path: "A.swift", old: entry("A.swift"), new: entry("A.swift"))]

        let paths = DiagnosticFileIndex.paths(for: pairs)

        #expect(paths == [0: "A.swift"])
    }

    @Test
    func `a renamed file maps to its destination path, not its source`() {
        let pairs = [FilePair(path: "Old.swift", old: entry("Old.swift"), new: entry("New.swift"))]

        let paths = DiagnosticFileIndex.paths(for: pairs)

        #expect(paths == [0: "New.swift"])
    }

    @Test
    func `a file deleted on the right falls back to its own (left) path`() {
        let pairs = [FilePair(path: "Gone.swift", old: entry("Gone.swift"), new: nil)]

        let paths = DiagnosticFileIndex.paths(for: pairs)

        #expect(paths == [0: "Gone.swift"])
    }

    @Test
    func `every pair keeps the render order's own index`() {
        let pairs = [
            FilePair(path: "A.swift", old: entry("A.swift"), new: entry("A.swift")),
            FilePair(path: "B.swift", old: nil, new: entry("B.swift")),
            FilePair(path: "C.swift", old: entry("C.swift"), new: nil)
        ]

        let paths = DiagnosticFileIndex.paths(for: pairs)

        #expect(paths == [0: "A.swift", 1: "B.swift", 2: "C.swift"])
    }
}
