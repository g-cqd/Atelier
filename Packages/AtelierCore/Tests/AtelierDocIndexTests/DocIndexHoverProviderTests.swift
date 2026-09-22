import AtelierSyntaxModel
import Testing

@testable import AtelierDocIndex

struct DocIndexHoverProviderTests {
    private static let calleeFile = """
        /// Loads the configuration.
        func loadConfig() -> Config {
            fatalError()
        }
        """

    private static let callerFile = """
        func run() {
            loadConfig()
        }
        """

    private func makeIndex() async -> DocCommentIndex {
        let index = DocCommentIndex()
        await index.update(files: [
            DocIndexFile(uri: "file:///callee.swift", content: Self.calleeFile),
            DocIndexFile(uri: "file:///caller.swift", content: Self.callerFile)
        ])
        return index
    }

    @Test
    func `resolves documentation for a call site from another file`() async throws {
        let index = await makeIndex()
        let provider = DocIndexHoverProvider(index: index)
        // "    loadConfig()" -> "loadConfig" starts at utf16 column 4.
        let query = HoverQuery(documentURI: "file:///caller.swift", content: Self.callerFile, line: 1, utf16Column: 6)
        let hover = try await provider.hover(query)
        #expect(hover?.source == .docIndex)
        #expect(hover?.markdown.contains("Loads the configuration.") == true)
        #expect(hover?.markdown.contains("func loadConfig() -> Config") == true)
    }

    @Test
    func `prefers the same file declaration when both declare the name`() async throws {
        let index = DocCommentIndex()
        let sameFile = """
            /// Local doc.
            func shared() {}

            func use() {
                shared()
            }
            """
        await index.update(files: [
            DocIndexFile(uri: "file:///a.swift", content: sameFile),
            DocIndexFile(uri: "file:///b.swift", content: "/// Other doc.\nfunc shared() {}")
        ])
        let provider = DocIndexHoverProvider(index: index)
        let query = HoverQuery(documentURI: "file:///a.swift", content: sameFile, line: 4, utf16Column: 5)
        let hover = try await provider.hover(query)
        #expect(hover?.markdown.contains("Local doc.") == true)
        #expect(hover?.markdown.contains("Other doc.") == false)
    }

    @Test
    func `caps at three entries when many files declare the name`() async throws {
        let index = DocCommentIndex()
        var files: [DocIndexFile] = []
        for index in 0 ..< 5 {
            files.append(DocIndexFile(uri: "file:///f\(index).swift", content: "/// Doc \(index).\nfunc shared() {}"))
        }
        await index.update(files: files)
        let provider = DocIndexHoverProvider(index: index)
        let content = "shared()"
        let query = HoverQuery(documentURI: "file:///caller.swift", content: content, line: 0, utf16Column: 2)
        let hover = try await provider.hover(query)
        let markdown = try #require(hover?.markdown)
        var blockCount = 1
        var remainder = markdown[...]
        while let range = remainder.firstRange(of: "\n\n---\n\n") {
            blockCount += 1
            remainder = remainder[range.upperBound...]
        }
        #expect(blockCount == 3)
    }

    @Test
    func `unknown identifier resolves to nil`() async throws {
        let index = await makeIndex()
        let provider = DocIndexHoverProvider(index: index)
        let content = "unknownName()"
        let query = HoverQuery(documentURI: "file:///caller.swift", content: content, line: 0, utf16Column: 2)
        let hover = try await provider.hover(query)
        #expect(hover == nil)
    }

    @Test
    func `position on a keyword resolves to nil`() async throws {
        let index = await makeIndex()
        let provider = DocIndexHoverProvider(index: index)
        let query = HoverQuery(documentURI: "file:///caller.swift", content: Self.callerFile, line: 0, utf16Column: 1)
        let hover = try await provider.hover(query)
        #expect(hover == nil)
    }
}

extension DocIndexHoverProviderTests {
    /// A focused repro at the hover-provider layer, one level up from `DocCommentIndexTests`' own repro of the
    /// same shape: hovering the property's own *name*, on its declaration line, inside an `extension`, with an
    /// explicit `get` accessor block -- exactly the position a user hovering `displayName` in
    /// `var displayName: String { get { ... } }` lands on.
    @Test
    func `hovering a computed property's own name on its declaration line resolves its doc comment`() async throws {
        let content = """
            extension ClearableSettingReference {
                /// The name shown in the picker for this option.
                var displayName: String {
                    get {
                        name
                    }
                }
            }
            """
        let index = DocCommentIndex()
        await index.update(files: [DocIndexFile(uri: "file:///a.swift", content: content)])
        let provider = DocIndexHoverProvider(index: index)
        // Line 2 (zero-based) is "    var displayName: String {"; "displayName" starts right after "    var ".
        let column = "    var ".utf16.count
        let query = HoverQuery(documentURI: "file:///a.swift", content: content, line: 2, utf16Column: column)
        let hover = try await provider.hover(query)
        #expect(hover?.markdown.contains("The name shown in the picker for this option.") == true)
    }
}
