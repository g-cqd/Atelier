import Testing

@testable import DiffComparison

/// ``WorkingTreeWrites``: which working-tree writes a reload can show, which only git can judge, and which never show
/// (GDV S2, PERF-03).
struct WorkingTreeWritesTests {
    private static let listed: Set<String> = ["Sources/a.swift", "Sources", ".swiftlint.yml"]

    private static func writes(_ paths: String...) -> WorkingTreeWrites {
        WorkingTreeWrites(paths) { listed.contains($0) }
    }

    @Test
    func `a write to a listed file settles it without asking git`() {
        let writes = Self.writes("build/out.o", "Sources/a.swift")

        #expect(writes.touchesListing)
        #expect(writes.unlisted.isEmpty)
    }

    @Test
    func `a listed folder, as a folder rename reports it, settles it too`() {
        #expect(Self.writes("Sources").touchesListing)
    }

    @Test
    func `a listed dotfile counts like any listed file`() {
        #expect(Self.writes(".swiftlint.yml").touchesListing)
    }

    @Test
    func `new paths go to git, sorted, when a later listing could show them`() {
        let writes = Self.writes("new.swift", "App.xcodeproj/xcuserdata/me.xcuserdatad/UserInterfaceState.xcuserstate")

        #expect(!writes.touchesListing)
        #expect(
            writes.unlisted == ["App.xcodeproj/xcuserdata/me.xcuserdatad/UserInterfaceState.xcuserstate", "new.swift"])
    }

    @Test
    func `a new dotfile, or a new path in a hidden folder, goes to git like any other`() {
        let writes = Self.writes(".github/workflows/ci.yml", ".env.example")

        #expect(!writes.touchesListing)
        #expect(writes.unlisted == [".env.example", ".github/workflows/ci.yml"])
    }

    @Test
    func `nothing under .build, where the app's own tools write, reaches git or reloads, even a listed file`() {
        let writes = WorkingTreeWrites(
            [
                ".build/index-build/Index/v5/records/AB/a.swift-1Q2W3E", "Packages/Core/.build/debug/x.json",
                ".build/b.swift"
            ]
        ) { $0 == ".build/b.swift" }

        #expect(!writes.touchesListing)
        #expect(writes.unlisted.isEmpty)
    }

    @Test
    func `a path the listing always skips never reaches git`() {
        let writes = Self.writes("node_modules/left-pad/index.js", "Pods", "Sources/Assets/logo.png")

        #expect(!writes.touchesListing)
        #expect(writes.unlisted.isEmpty)
    }
}
