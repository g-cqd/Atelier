import AemiTestKit
import Foundation
import Testing

@testable import AtelierFileTree

extension Tag {
    @Tag static var fileNode: Self
    @Tag static var scanner: Self
    @Tag static var navigator: Self
    @Tag static var securePath: Self
}

/// A temporary directory subtree for scanner tests over `AemiTestKit.TemporaryDirectory`, removed on deinit.
final class TempTree: Sendable {
    private let directory: TemporaryDirectory
    var root: String { directory.path }

    init() throws {
        directory = TemporaryDirectory(prefix: "KittyFileTreeTests")
    }

    /// Creates a file relative to `root` with the given name and optional content.
    func createFile(named name: String, content: String = "") throws {
        try content.write(toFile: directory.file(name), atomically: true, encoding: .utf8)
    }

    /// Creates a subdirectory relative to `root`.
    func createDirectory(named name: String) throws {
        try FileManager.default.createDirectory(
            atPath: directory.file(name), withIntermediateDirectories: true)
    }

    deinit {
        directory.cleanup()
    }
}
