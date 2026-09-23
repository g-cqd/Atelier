import Foundation
import Testing

@testable import AtelierSources

/// A listing tells a supported file by its extension without building a URL, which cost a `getcwd` per path; the
/// extension must stay the one URL gives.
struct SupportedPathTests {
    @Test(arguments: [
        "a.swift", "Sources/a.swift", "archive.tar.gz", ".gitignore", ".env.local", "Makefile", "file.", "dir.d/file",
        "a..b", "..x", "...x", "..a.b", ".a.b", "UPPER.PNG", "x.y.z/", "a.b//", "/abs/path/file.swift", "é/ü.ÄÖ",
        "a/..b", "weird name.with space", "a. b", "a.b\tc", " .b", "a .b", "x/.", "x/.."
    ])
    func `a path's extension is the one URL gives it`(path: String) {
        #expect(String(SourceLoader.pathExtension(of: path)) == URL(filePath: path).pathExtension)
    }

    @Test
    func `a file with a binary extension is not supported, whatever its case`() {
        #expect(!SourceLoader.isSupported(path: "Assets/icon.PNG"))
        #expect(SourceLoader.isSupported(path: "Sources/..png"))
        #expect(SourceLoader.isSupported(path: "Sources/App.swift"))
    }
}
