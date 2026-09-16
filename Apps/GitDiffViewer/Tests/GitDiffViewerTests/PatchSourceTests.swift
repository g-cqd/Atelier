import AemiCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

struct PatchSourceTests {
    @Test
    func `binary content becomes a one line size marker and binary extensions are skipped`() {
        #expect(SourceLoader.text(from: Data([0x68, 0x69, 0x00, 0x01])) == "(binary file, 4 bytes)\n")
        #expect(SourceLoader.text(from: Data("hi\n".utf8)) == "hi\n")
        #expect(!SourceLoader.isSupported(path: "Assets.xcassets/icon.png"))
        #expect(SourceLoader.isSupported(path: "Makefile"))
        #expect(SourceLoader.isSupported(path: "notes.md"))
    }

    @Test
    func `a patch file lists its files per side, serves their reconstructed text and reports renames`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PatchSourceTests-\(UUID().uuidString).patch")
        try """
        diff --git a/Keep.swift b/Keep.swift
        --- a/Keep.swift
        +++ b/Keep.swift
        @@ -2,2 +2,2 @@
         same
        -old
        +new
        diff --git a/Was.swift b/Is.swift
        rename from Was.swift
        rename to Is.swift
        diff --git a/Gone.swift b/Gone.swift
        deleted file mode 100644
        --- a/Gone.swift
        +++ /dev/null
        @@ -1 +0,0 @@
        -bye
        """
        .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let loader = SourceLoader()
        let old = ComparisonSource.patch(url, side: .old)
        let new = ComparisonSource.patch(url, side: .new)

        let oldEntries = try await loader.entries(of: old)
        let newEntries = try await loader.entries(of: new)

        #expect(oldEntries.map(\.relativePath) == ["Keep.swift", "Was.swift", "Gone.swift"])
        #expect(newEntries.map(\.relativePath) == ["Keep.swift", "Is.swift"])
        #expect(oldEntries[0].blobID != newEntries[0].blobID)
        #expect(oldEntries[1].blobID != oldEntries[2].blobID)
        #expect(try await loader.content(of: oldEntries[0], in: old) == "\nsame\nold\n")
        #expect(try await loader.content(of: newEntries[0], in: new) == "\nsame\nnew\n")
        #expect(await loader.renames(from: old, to: new) == ["Was.swift": "Is.swift"])
    }
}
