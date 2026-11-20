import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSources

struct PatchSourceTests {
    @Test
    func `binary content becomes a one line size marker and binary extensions are skipped`() {
        #expect(SourceLoader.text(from: Data([0x68, 0x69, 0x00, 0x01])).hasPrefix("(binary file, 4 bytes, blob "))
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
        let loader = TestProcesses.loader
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

    @Test
    func `a patch with a byte that is not UTF-8 opens`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PatchSourceTests-\(UUID().uuidString).patch")
        defer { try? FileManager.default.removeItem(at: url) }
        var patch = Data("diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-caf\n+caf".utf8)
        patch.append(contentsOf: [0xE9, 0x0A])
        try patch.write(to: url)

        let entries = try await TestProcesses.loader.entries(of: .patch(url, side: .new))

        #expect(entries.map(\.relativePath) == ["a.txt"])
    }

    @Test
    func `a binary file of a patch is listed, its two sides told apart`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PatchSourceTests-\(UUID().uuidString).patch")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        diff --git a/logo.dat b/logo.dat
        index 1111111..2222222 100644
        Binary files a/logo.dat and b/logo.dat differ
        diff --git a/added.dat b/added.dat
        new file mode 100644
        index 0000000..3333333
        Binary files /dev/null and b/added.dat differ

        """
        .write(to: url, atomically: true, encoding: .utf8)

        let old = try await TestProcesses.loader.entries(of: .patch(url, side: .old))
        let new = try await TestProcesses.loader.entries(of: .patch(url, side: .new))
        let oldLogo = try #require(old.first { $0.relativePath == "logo.dat" })
        let newLogo = try #require(new.first { $0.relativePath == "logo.dat" })

        #expect(old.map(\.relativePath) == ["logo.dat"])
        #expect(new.map(\.relativePath).sorted() == ["added.dat", "logo.dat"])
        #expect(oldLogo.blobID != newLogo.blobID)
    }

    @Test
    func `a mode-only change of a patch lists the file with each side's mode`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PatchSourceTests-\(UUID().uuidString).patch")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        diff --git a/run.sh b/run.sh
        old mode 100644
        new mode 100755

        """
        .write(to: url, atomically: true, encoding: .utf8)

        let old = try await TestProcesses.loader.entries(of: .patch(url, side: .old))
        let new = try await TestProcesses.loader.entries(of: .patch(url, side: .new))

        #expect(old.map(\.mode) == ["100644"])
        #expect(new.map(\.mode) == ["100755"])
        #expect(old.map(\.blobID) == new.map(\.blobID))
    }

    @Test
    func `a patch path git quoted with C escapes is listed decoded`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PatchSourceTests-\(UUID().uuidString).patch")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"""
        diff --git "a/caf\303\251.txt" "b/caf\303\251.txt"
        --- "a/caf\303\251.txt"
        +++ "b/caf\303\251.txt"
        @@ -1 +1 @@
        -a
        +b

        """#
        .write(to: url, atomically: true, encoding: .utf8)

        let entries = try await TestProcesses.loader.entries(of: .patch(url, side: .new))

        #expect(entries.map(\.relativePath) == ["café.txt"])
    }
}
