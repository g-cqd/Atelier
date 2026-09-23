import AemiRuntime
import Foundation
import Synchronization
import Testing

@testable import AtelierFileTree

/// ``DirectoryScanner/scanAsync(_:maxDepth:maxEntries:visibility:withinRoot:pool:)`` reads directories on the pool it
/// is given, a few at a time, and builds the tree the synchronous scan builds (Core S3).
@Suite(.tags(.scanner))
struct DirectoryScanAsyncTests {
    /// Every path of a tree, depth first, a directory's with a trailing slash.
    private static func outline(_ nodes: [FileNode], prefix: String = "") -> [String] {
        nodes.flatMap { node in
            node.isDirectory
                ? [prefix + node.name + "/"] + outline(node.children, prefix: prefix + node.name + "/")
                : [prefix + node.name]
        }
    }

    @Test func `a wide tree's scan lists at most a few directories at once`() async throws {
        let tree = try TempTree()
        for index in 0 ..< 40 {
            try tree.createDirectory(named: "dir\(index)")
            try tree.createFile(named: "dir\(index)/a.txt")
        }
        let pool = ListingSpy()
        defer { pool.shutdown() }

        let entries = try await DirectoryScanner.scanAsync(
            tree.root, maxDepth: 1, maxEntries: 1000, visibility: .defaultHidden, withinRoot: nil, offload: pool)

        #expect(entries.count == 40)
        #expect(entries.allSatisfy { $0.children.map(\.name) == ["a.txt"] })
        #expect(pool.listings == 41)
        #expect(pool.mostInFlight <= DirectoryScanner.listingConcurrency)
    }

    @Test func `an async scan builds the tree a synchronous scan builds`() async throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "Sources/App")
        try tree.createDirectory(named: "Sources/Core/Deep")
        try tree.createFile(named: "Sources/App/main.swift")
        try tree.createFile(named: "Sources/Core/b.swift")
        try tree.createFile(named: "Sources/Core/Deep/c.swift")
        try tree.createFile(named: "README.md")
        try tree.createFile(named: ".hidden")
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }

        let scanned = try await DirectoryScanner.scanAsync(tree.root, maxDepth: 2, pool: pool)

        #expect(Self.outline(scanned) == Self.outline(DirectoryScanner.scan(tree.root, maxDepth: 2)))
        #expect(Self.outline(scanned).contains("Sources/Core/Deep/"))
        #expect(!Self.outline(scanned).contains("Sources/Core/Deep/c.swift"))
    }

    @Test func `a capped scan keeps the shallow entries`() async throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "a/deep")
        try tree.createFile(named: "a/deep/x.txt")
        try tree.createFile(named: "a/y.txt")
        try tree.createFile(named: "b.txt")
        try tree.createFile(named: "c.txt")
        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }

        let scanned = try await DirectoryScanner.scanAsync(tree.root, maxDepth: 5, maxEntries: 3, pool: pool)

        #expect(Self.outline(scanned) == ["a/", "b.txt", "c.txt"])
    }

    @Test func `a cancelled scan throws instead of returning a partial tree`() async throws {
        let tree = try TempTree()
        try tree.createFile(named: "a.txt")
        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }

        let scan = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DirectoryScanner.scanAsync(tree.root, pool: pool)
        }

        await #expect(throws: CancellationError.self) { try await scan.value }
    }
}

/// A pool spy that hands every listing to a real pool, counting the listings and the most in flight at once, asked for
/// and not yet returned.
final class ListingSpy: BlockingOffload {
    private struct State {
        var listings = 0
        var inFlight = 0
        var most = 0
    }

    private let pool = BlockingOffloadPool(width: 1)
    private let state = Mutex(State())

    var listings: Int { state.withLock(\.listings) }
    var mostInFlight: Int { state.withLock(\.most) }

    /// Joins the spy's pool thread; call once every listing has returned.
    func shutdown() {
        pool.shutdown()
    }

    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        state.withLock { state in
            state.listings += 1
            state.inFlight += 1
            state.most = max(state.most, state.inFlight)
        }
        defer { state.withLock { $0.inFlight -= 1 } }
        return try await pool.run(body)
    }
}
