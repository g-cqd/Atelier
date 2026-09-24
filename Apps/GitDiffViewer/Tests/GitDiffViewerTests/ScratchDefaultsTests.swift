import Foundation
import Testing

/// The suites the tests write leave nothing on disk. cfprefsd writes a suite's changes lazily, seconds after them, and
/// puts a plist deleted in between back, so the only plist that cannot come back to the user's preferences is one
/// that never went there: these check where a scratch suite's plist goes, and that nothing of it is left once the
/// suite is released.
@MainActor
struct ScratchDefaultsTests {
    private static let preferences = URL.libraryDirectory.appending(path: "Preferences", directoryHint: .isDirectory)

    @Test
    func `a scratch suite keeps its plist out of the user's preferences`() throws {
        let scratch = ScratchDefaults(tag: "kept")

        scratch.defaults.set(true, forKey: "written")

        let inPreferences = try Self.entries(in: Self.preferences, containing: scratch.name)
        #expect(FileManager.default.fileExists(atPath: scratch.plist.path(percentEncoded: false)))
        #expect(inPreferences == [])
    }

    @Test
    func `a released scratch suite leaves no plist of its name behind`() throws {
        var scratch: ScratchDefaults? = ScratchDefaults(tag: "released")
        let name = try #require(scratch?.name)
        let plist = try #require(scratch?.plist)
        scratch?.defaults.set(true, forKey: "written")
        // A suite's first write reaches the disk at once, so there is a plist to leave behind.
        try #require(FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)))

        scratch = nil

        let leftovers = try Self.leftovers(of: name)
        #expect(!FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)))
        #expect(leftovers == [])
    }

    /// Everything named after `name` in the user's preferences or in the temporary directory.
    private static func leftovers(of name: String) throws -> [String] {
        try entries(in: preferences, containing: name)
            + entries(in: FileManager.default.temporaryDirectory, containing: name)
    }

    private static func entries(in directory: URL, containing name: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.contains(name) }
    }
}
