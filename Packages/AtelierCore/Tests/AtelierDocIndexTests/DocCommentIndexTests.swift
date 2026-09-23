import Testing

@testable import AtelierDocIndex

struct DocCommentIndexTests {
    private func firstEntry(_ entries: [DocEntry], named name: String) -> DocEntry? {
        entries.first { $0.name == name }
    }

    @Test
    func `extracts a documented function`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    /// Loads data from a URL.
                    func load(_ url: URL) async throws -> Data {
                        fatalError()
                    }
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "load", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.markdown == "Loads data from a URL.")
        #expect(entries.first?.signature == "func load(_ url: URL) async throws -> Data")
    }

    @Test
    func `extracts a documented initializer`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    struct Foo {
                        /// Creates a Foo.
                        init(x: Int) {}
                    }
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "init", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.signature == "init(x: Int)")
        #expect(entries.first?.markdown == "Creates a Foo.")
    }

    @Test
    func `extracts a documented subscript`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    struct Foo {
                        /// Element access.
                        subscript(index: Int) -> Int { 0 }
                    }
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "subscript", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.signature == "subscript(index: Int) -> Int")
        #expect(entries.first?.markdown == "Element access.")
    }

    @Test
    func `extracts documented properties`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    struct Foo {
                        /// The count.
                        var count: Int = 0
                        /// A constant.
                        let name: String = "x"
                    }
                    """)
        ])
        let countEntries = await index.documentation(forIdentifier: "count", preferringURI: nil)
        let nameEntries = await index.documentation(forIdentifier: "name", preferringURI: nil)
        #expect(countEntries.first?.markdown == "The count.")
        #expect(nameEntries.first?.markdown == "A constant.")
    }

    @Test(
        arguments: [
            ("struct", "Foo"), ("class", "Foo"), ("enum", "Foo"), ("actor", "Foo"), ("protocol", "Foo")
        ])
    func `extracts documented type declarations`(kind: String, name: String) async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    /// A type.
                    \(kind) \(name) {}
                    """)
        ])
        let entries = await index.documentation(forIdentifier: name, preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.markdown == "A type.")
    }

    @Test
    func `extracts a documented typealias`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    /// An alias.
                    typealias ID = Int
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "ID", preferringURI: nil)
        #expect(entries.first?.markdown == "An alias.")
        #expect(entries.first?.signature == "typealias ID = Int")
    }

    @Test
    func `extracts a documented macro`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    /// A macro.
                    macro Stringify<T>(_ value: T) = #externalMacro(module: "M", type: "S")
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "Stringify", preferringURI: nil)
        #expect(entries.first?.markdown == "A macro.")
    }

    @Test
    func `extracts a documented enum case`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    enum Foo {
                        /// The first case.
                        case first
                    }
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "first", preferringURI: nil)
        #expect(entries.first?.markdown == "The first case.")
    }

    @Test
    func `normalizes a block doc comment`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    /**
                     * Summary line.
                     *
                     * More detail.
                     */
                    func run() {}
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "run", preferringURI: nil)
        #expect(entries.first?.markdown == "Summary line.\n\nMore detail.")
    }

    @Test
    func `undocumented declarations produce no entry`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "file:///a.swift", content: "func undocumented() {}")
        ])
        let entries = await index.documentation(forIdentifier: "undocumented", preferringURI: nil)
        #expect(entries.isEmpty)
    }

    @Test
    func `signature has no body and collapses whitespace`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    /// Runs.
                    func run(
                        x: Int,
                        y: Int
                    ) -> Int {
                        x + y
                    }
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "run", preferringURI: nil)
        #expect(entries.first?.signature == "func run( x: Int, y: Int ) -> Int")
    }

    @Test
    func `update with changed content replaces entries`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "file:///a.swift", content: "/// Old.\nfunc run() {}")
        ])
        await index.update(files: [
            DocIndexFile(uri: "file:///a.swift", content: "/// New.\nfunc run() {}")
        ])
        let entries = await index.documentation(forIdentifier: "run", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.markdown == "New.")
    }

    @Test
    func `unchanged content is not re-parsed into duplicates`() async {
        let index = DocCommentIndex()
        let file = DocIndexFile(uri: "file:///a.swift", content: "/// Doc.\nfunc run() {}")
        await index.update(files: [file])
        await index.update(files: [file])
        let entries = await index.documentation(forIdentifier: "run", preferringURI: nil)
        #expect(entries.count == 1)
    }

    @Test
    func `preferringURI sorts that file's entries first`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "file:///a.swift", content: "/// From A.\nfunc run() {}"),
            DocIndexFile(uri: "file:///b.swift", content: "/// From B.\nfunc run() {}")
        ])
        let entries = await index.documentation(forIdentifier: "run", preferringURI: "file:///b.swift")
        #expect(entries.count == 2)
        #expect(entries.first?.uri == "file:///b.swift")
        #expect(entries.first?.markdown == "From B.")
    }

    @Test
    func `blob and file entries with the same signature collapse to the file entry`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "atelier-blob://deadbeef/Sources/Foo.swift", content: "/// Foo.\nstruct Foo {}"),
            DocIndexFile(uri: "file:///repo/Sources/Foo.swift", content: "/// Foo.\nstruct Foo {}")
        ])
        let entries = await index.documentation(forIdentifier: "Foo", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.uri == "file:///repo/Sources/Foo.swift")
    }

    @Test
    func `blob and file entries at the same path with different signatures keep only the file entry`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "atelier-blob://deadbeef/Sources/Foo.swift", content: "/// Foo.\nstruct Foo {}"),
            DocIndexFile(
                uri: "file:///repo/Sources/Foo.swift", content: "/// Foo.\nstruct Foo: Sendable {}")
        ])
        let entries = await index.documentation(forIdentifier: "Foo", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.uri == "file:///repo/Sources/Foo.swift")
        #expect(entries.first?.signature == "struct Foo: Sendable")
    }

    @Test
    func `same-named declarations at genuinely different paths both remain candidates`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "atelier-blob://deadbeef/Sources/Foo.swift", content: "/// Foo A.\nstruct Foo {}"),
            DocIndexFile(uri: "file:///repo/Sources/Bar.swift", content: "/// Foo B.\nstruct Foo {}")
        ])
        let entries = await index.documentation(forIdentifier: "Foo", preferringURI: nil)
        #expect(entries.count == 2)
    }

    @Test
    func `hovering the old blob side itself shows the old side's own documentation, not the new one's`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "atelier-blob://deadbeef/Sources/Foo.swift", content: "/// Old doc, no conformance.\nstruct Foo {}"
            ),
            DocIndexFile(
                uri: "file:///repo/Sources/Foo.swift",
                content: "/// New doc, now Sendable.\nstruct Foo: Sendable {}")
        ])
        // The query's own blob entry survives the dedupe and sorts first, despite a newer `file://` entry at its path.
        let entries = await index.documentation(
            forIdentifier: "Foo", preferringURI: "atelier-blob://deadbeef/Sources/Foo.swift")
        #expect(entries.count == 2)
        #expect(entries.first?.uri == "atelier-blob://deadbeef/Sources/Foo.swift")
        #expect(entries.first?.markdown == "Old doc, no conformance.")
        #expect(entries.first?.signature == "struct Foo")
    }
}

extension DocCommentIndexTests {
    @Test
    func `a documented computed property inside an extension with an explicit get block is indexed`() async {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(
                uri: "file:///a.swift",
                content: """
                    extension ClearableSettingReference {
                        /// The name shown in the picker for this option.
                        var displayName: String {
                            get {
                                name
                            }
                        }
                    }
                    """)
        ])
        let entries = await index.documentation(forIdentifier: "displayName", preferringURI: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.markdown == "The name shown in the picker for this option.")
    }
}
