import Foundation
import Testing

@testable import KittyFileTree

extension Tag {
    @Tag static var fileNode: Self
    @Tag static var scanner: Self
    @Tag static var navigator: Self
    @Tag static var securePath: Self
}

/// Creates a temporary directory subtree for scanner tests and removes it on deinit.
final class TempTree: Sendable {
    let root: String

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("KittyFileTreeTests-\(Int.random(in: 100_000 ... 999_999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        root = tmp.path
    }

    /// Creates a file relative to `root` with the given name and optional content.
    func createFile(named name: String, content: String = "") throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Creates a subdirectory relative to `root`.
    func createDirectory(named name: String) throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }
}
