import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// What the window model asks of the hover index as a comparison loads and is laid out again: the corpus pass reads
/// the right side's other Swift files only while hover documentation is on, and only once per comparison.
@MainActor
@Suite(.mainActorLane)
struct HoverIndexingTests {
    private let harness = ModelTestHarness()

    /// `a.swift` changed and calls `double`; `rest.swift` is unchanged and declares it, so only the hover corpus pass
    /// ever reads `rest.swift`. With `editsLineFifteen`, the new side of `a.swift` differs at line 15, so its gaps sit
    /// next to a change and offer drag handles.
    private func makeLoadedSUT(
        showsHover: Bool = true, isolatesChanges: Bool = false, editsLineFifteen: Bool = false
    ) async throws -> DiffViewerModel {
        let sut = harness.makeSUT()
        sut.settings.showsHoverDocumentation = showsHover
        sut.settings.isolatesChanges = isolatesChanges
        sut.attachHoverDocs(lspRegistry: nil)
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("rest.swift", "9")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "2"), harness.entry("rest.swift", "9")
        ]
        let lines = ["let value = double(3)"] + (1 ... 30).map { "let line\($0) = \($0)" }
        harness.reader.contents["a.swift"] = lines.joined(separator: "\n") + "\n"
        if editsLineFifteen {
            var edited = lines
            edited[15] = "let line15 = 150"
            harness.reader.blobContents["2"] = edited.joined(separator: "\n") + "\n"
        }
        harness.reader.contents["rest.swift"] = "/// Doubles a number.\nfunc double(_ x: Int) -> Int { x * 2 }\n"
        try await harness.load(sut)
        return sut
    }

    /// The next `count` reads, in the order they were asked for.
    private func reads(_ count: Int) async throws -> [String] {
        var paths: [String] = []
        for _ in 0 ..< count { paths.append(try #require(try await harness.reader.contentRequests.expectNext())) }
        return paths
    }

    @Test
    func `with hover documentation off, loading a comparison reads no corpus file`() async throws {
        _ = try await makeLoadedSUT(showsHover: false)

        #expect(try await reads(2) == ["a.swift", "a.swift"])
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `turning hover documentation on indexes the comparison already on screen`() async throws {
        let sut = try await makeLoadedSUT(showsHover: false)
        _ = try await reads(2)

        sut.settings.showsHoverDocumentation = true
        try await harness.taskProvider.waitForAllTasks()

        #expect(try await reads(1) == ["rest.swift"])
        // "double" sits at columns 12..<18 of "let value = double(3)".
        let content = await sut.hoverDocs?.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
        #expect(content?.markdown.contains("Doubles a number.") == true)
    }

    @Test
    func `laying the cards out again reads no corpus file`() async throws {
        let sut = try await makeLoadedSUT()
        #expect(try await reads(3).sorted() == ["a.swift", "a.swift", "rest.swift"])

        sut.settings.contextLines = 5
        try await harness.taskProvider.waitForAllTasks()

        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `dragging a gap reads no corpus file`() async throws {
        let sut = try await makeLoadedSUT(isolatesChanges: true, editsLineFifteen: true)
        #expect(try await reads(3).sorted() == ["a.swift", "a.swift", "rest.swift"])
        let gaps = try #require(sut.renderedFiles.first?.rendered.old?.gaps)
        let marker = try #require(gaps.lazy.map(\.marker).first { !$0.handles.isEmpty })

        harness.drag(sut, try #require(marker.handles.first), of: marker, rows: 4)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.expansion(of: marker.key) != GapExpansion())
        try harness.reader.contentRequests.expectNoBufferedElements()
    }
}
