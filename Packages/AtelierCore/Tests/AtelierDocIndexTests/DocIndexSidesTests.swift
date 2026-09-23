import AtelierSyntaxModel
import Testing

@testable import AtelierDocIndex

/// A lookup answers from the files of the side being hovered, so the old version of a declaration never shows beside
/// the new one (HOVER-11).
struct DocIndexSidesTests {
    private static let oldFoo = "atelier-blob://foo1/Sources/Foo.swift"
    private static let newFoo = "atelier-blob://foo2/Sources/Foo.swift"
    private static let use = "let foo = Foo()\n"

    /// Both sides of a changed `Foo.swift`, as when both sides of a comparison are refs, and an unchanged file.
    private func makeIndex() async throws -> DocCommentIndex {
        let index = DocCommentIndex()
        try await index.upsert([
            DocIndexFile(uri: Self.oldFoo, content: "/// A foo.\nstruct Foo {}", sides: .old),
            DocIndexFile(uri: Self.newFoo, content: "/// A foo.\nstruct Foo: Sendable {}", sides: .new),
            DocIndexFile(uri: "file:///repo/Sources/Bar.swift", content: "/// A bar.\nstruct Bar {}", sides: .both)
        ])
        return index
    }

    private func signatures(of name: String, side: DocIndexSides, in index: DocCommentIndex) async -> [String] {
        await index.documentation(forIdentifier: name, preferringURI: nil, side: side).map(\.signature)
    }

    @Test
    func `a lookup from the new side lists only the new side's declaration`() async throws {
        let index = try await makeIndex()
        #expect(await signatures(of: "Foo", side: .new, in: index) == ["struct Foo: Sendable"])
    }

    @Test
    func `a lookup from the old side lists only the old side's declaration`() async throws {
        let index = try await makeIndex()
        #expect(await signatures(of: "Foo", side: .old, in: index) == ["struct Foo"])
    }

    @Test
    func `a file on both sides answers a lookup from either`() async throws {
        let index = try await makeIndex()
        #expect(await signatures(of: "Bar", side: .old, in: index) == ["struct Bar"])
        #expect(await signatures(of: "Bar", side: .new, in: index) == ["struct Bar"])
    }

    @Test
    func `a lookup from both sides lists every file`() async throws {
        let index = try await makeIndex()
        #expect(await signatures(of: "Foo", side: .both, in: index) == ["struct Foo", "struct Foo: Sendable"])
    }

    @Test
    func `distinct declarations of one name on the hovered side all remain listed`() async throws {
        let index = try await makeIndex()
        try await index.upsert([
            DocIndexFile(
                uri: "atelier-blob://baz/Sources/Other.swift", content: "/// Another foo.\nenum Foo {}", sides: .new)
        ])
        #expect(await signatures(of: "Foo", side: .new, in: index) == ["enum Foo", "struct Foo: Sendable"])
    }

    @Test
    func `an unchanged file takes the sides it is fed with, unparsed`() async throws {
        let index = try await makeIndex()
        try await index.upsert([
            DocIndexFile(uri: "file:///repo/Sources/Bar.swift", content: "/// A bar.\nstruct Bar {}", sides: .new)
        ])
        #expect(await signatures(of: "Bar", side: .old, in: index).isEmpty)
    }

    @Test
    func `keeping a file with other sides moves it to them`() async throws {
        let index = try await makeIndex()
        try await index.keepOnly([Self.oldFoo: .old, Self.newFoo: .both, "file:///repo/Sources/Bar.swift": .both])
        #expect(await signatures(of: "Foo", side: .old, in: index) == ["struct Foo", "struct Foo: Sendable"])
    }

    @Test
    func `a hover on the new side of a use lists only the new declaration`() async throws {
        let index = try await makeIndex()
        let provider = DocIndexHoverProvider(index: index, side: .new)
        // "Foo" sits at columns 10..<13 of "let foo = Foo()".
        let query = HoverQuery(
            documentURI: "atelier-blob://use2/Sources/Use.swift", content: Self.use, line: 0, utf16Column: 11)

        let markdown = try #require(try await provider.hover(query)?.markdown)

        #expect(markdown == "```swift\nstruct Foo: Sendable\n```\n\nA foo.")
    }

    @Test
    func `a hover on the old side of a use lists only the old declaration`() async throws {
        let index = try await makeIndex()
        let provider = DocIndexHoverProvider(index: index, side: .old)
        let query = HoverQuery(
            documentURI: "atelier-blob://use1/Sources/Use.swift", content: Self.use, line: 0, utf16Column: 11)

        let markdown = try #require(try await provider.hover(query)?.markdown)

        #expect(markdown == "```swift\nstruct Foo\n```\n\nA foo.")
    }
}
