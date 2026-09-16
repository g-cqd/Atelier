import Testing

@testable import DiffCore

struct UnifiedPatchTests {
    static let gitPatch = """
        From 1234 Mon Sep 17 00:00:00 2001
        Subject: [PATCH] Example

        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111..2222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -3,4 +3,4 @@ import Foundation
         let a = 1
        -let b = 2
        +let b = 3
         let c = 4
        \\ No newline at end of file
        diff --git a/New.swift b/New.swift
        new file mode 100644
        --- /dev/null
        +++ b/New.swift
        @@ -0,0 +1,2 @@
        +line one
        +line two
        diff --git a/Old.swift b/Old.swift
        deleted file mode 100644
        --- a/Old.swift
        +++ /dev/null
        @@ -1 +0,0 @@
        -gone
        diff --git a/Was.swift b/Is.swift
        similarity index 90%
        rename from Was.swift
        rename to Is.swift
        --- a/Was.swift
        +++ b/Is.swift
        @@ -10,2 +10,2 @@
         keep
        -old
        +new
        diff --git a/Image.png b/Image.png
        Binary files a/Image.png and b/Image.png differ
        """

    @Test
    func `git patches parse into per-file hunks with added, deleted, renamed and binary files`() {
        let patch = UnifiedPatch(parsing: Self.gitPatch)

        #expect(patch.files.map(\.oldPath) == ["Sources/App.swift", nil, "Old.swift", "Was.swift", "Image.png"])
        #expect(patch.files.map(\.newPath) == ["Sources/App.swift", "New.swift", nil, "Is.swift", "Image.png"])
        #expect(patch.files.map(\.isBinary) == [false, false, false, false, true])
        #expect(patch.files[3].isRename)
        let hunk = patch.files[0].hunks[0]
        #expect((hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount) == (3, 4, 3, 4))
        #expect(hunk.lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(hunk.lines.map(\.text) == ["let a = 1", "let b = 2", "let b = 3", "let c = 4"])
    }

    @Test
    func `reconstructed texts place hunks at their line numbers and omit missing sides`() {
        let patch = UnifiedPatch(parsing: Self.gitPatch)

        let modified = patch.files[0].reconstructedTexts
        #expect(modified.old == "\n\nlet a = 1\nlet b = 2\nlet c = 4\n")
        #expect(modified.new == "\n\nlet a = 1\nlet b = 3\nlet c = 4\n")
        let added = patch.files[1].reconstructedTexts
        #expect(added.old == nil)
        #expect(added.new == "line one\nline two\n")
        let deleted = patch.files[2].reconstructedTexts
        #expect(deleted.old == "gone\n")
        #expect(deleted.new == nil)
        #expect(
            patch.files[3].reconstructedTexts.new?.split(separator: "\n", omittingEmptySubsequences: false).count == 12)
    }

    @Test
    func `plain unified diffs without git headers parse too`() {
        let text = """
            --- before.txt\t2024-01-01 10:00:00
            +++ after.txt\t2024-01-02 10:00:00
            @@ -1,2 +1,2 @@
             same
            -a
            +b
            --- other.txt
            +++ other.txt
            @@ -1 +1 @@
            -x
            +y
            """
        let patch = UnifiedPatch(parsing: text)

        #expect(patch.files.map(\.oldPath) == ["before.txt", "other.txt"])
        #expect(patch.files.map(\.newPath) == ["after.txt", "other.txt"])
        #expect(patch.files[0].hunks[0].lines.map(\.text) == ["same", "a", "b"])
        #expect(patch.files[1].hunks[0].lines.map(\.kind) == [.removed, .added])
    }

    @Test
    func `blank lines inside a hunk are context and CRLF endings are stripped`() {
        let patch = UnifiedPatch(
            parsing: "--- a/x.txt\r\n+++ b/x.txt\r\n@@ -1,3 +1,3 @@\r\n one\r\n\r\n-two\r\n+deux\r\n")

        #expect(
            patch.files[0].hunks[0].lines == [
                .init(kind: .context, text: "one"), .init(kind: .context, text: ""),
                .init(kind: .removed, text: "two"), .init(kind: .added, text: "deux")
            ])
    }
}
