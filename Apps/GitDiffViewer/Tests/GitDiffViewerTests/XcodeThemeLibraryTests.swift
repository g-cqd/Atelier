import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import DiffRendering

/// The theme listing asks `xcode-select` through the process runner and reads the bundled themes beside it.
struct XcodeThemeLibraryTests {
    @Test
    func `the bundled themes of the selected xcode are listed after the user's`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-xcode-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = root.appending(
            path: "Contents/SharedFrameworks/DVTUserInterfaceKit.framework/Versions/A/Resources/FontAndColorThemes")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<plist version=\"1.0\"><dict/></plist>".utf8).write(to: bundled.appending(path: "Zed.xccolortheme"))
        let developer = root.appending(path: "Contents/Developer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: developer, withIntermediateDirectories: true)
        let runner = FakeProcessRunner(always: .success(developer.path(percentEncoded: false) + "\n"))

        let entries = await XcodeThemeLibrary.entries(runner: runner)

        #expect(runner.specs.first?.arguments == ["-p"])
        #expect(entries.last?.name == "Zed")
        #expect(entries.contains { $0.url.lastPathComponent == "Zed.xccolortheme" })
    }

    @Test
    func `a failing xcode-select leaves only the user's themes`() async {
        let runner = FakeProcessRunner(always: .failure(2, error: "xcode-select: error"))
        let entries = await XcodeThemeLibrary.entries(runner: runner)
        #expect(
            entries.allSatisfy { $0.url.path(percentEncoded: false).contains("/Library/Developer/Xcode/UserData/") })
    }
}
