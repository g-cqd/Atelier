import Foundation
import Testing

@testable import AtelierLSP

@Suite
struct LSPTypesTests {
    @Test
    func `Hover contents as MarkupContent`() throws {
        let payload = Data(##"{"contents":{"kind":"markdown","value":"# Title"}}"##.utf8)
        let hover = try JSONDecoder().decode(Hover.self, from: payload)
        #expect(hover.markdown == "# Title")
        #expect(hover.range == nil)
    }

    @Test
    func `Hover contents as a bare string`() throws {
        let payload = Data(#"{"contents":"plain text"}"#.utf8)
        let hover = try JSONDecoder().decode(Hover.self, from: payload)
        #expect(hover.markdown == "plain text")
    }

    @Test
    func `Hover contents as a language value object`() throws {
        let payload = Data(#"{"contents":{"language":"swift","value":"func f()"}}"#.utf8)
        let hover = try JSONDecoder().decode(Hover.self, from: payload)
        #expect(hover.markdown == "```swift\nfunc f()\n```")
    }

    @Test
    func `Hover contents as an array of marked strings`() throws {
        let payload = Data(
            #"{"contents":["plain text",{"language":"swift","value":"func f()"}]}"#.utf8)
        let hover = try JSONDecoder().decode(Hover.self, from: payload)
        #expect(hover.markdown == "plain text\n\n```swift\nfunc f()\n```")
    }

    @Test
    func `Hover decodes an optional range`() throws {
        let payload = Data(
            #"{"contents":"x","range":{"start":{"line":1,"character":2},"end":{"line":1,"character":5}}}"#.utf8)
        let hover = try JSONDecoder().decode(Hover.self, from: payload)
        #expect(hover.range == HoverRange(start: Position(line: 1, character: 2), end: Position(line: 1, character: 5)))
    }

    @Test
    func `Realistic sourcekit-lsp hover response decodes`() throws {
        let payload = Data(
            ##"{"contents":{"kind":"markdown","value":"```swift\nfunc f()\n```\n\ndocs"}}"##.utf8)
        let hover = try JSONDecoder().decode(Hover.self, from: payload)
        #expect(hover.markdown == "```swift\nfunc f()\n```\n\ndocs")
    }

    @Test
    func `InitializeParams encodes contentFormat markdown first`() throws {
        let params = InitializeParams(processId: 123, rootUri: "file:///repo")
        let data = try JSONEncoder().encode(params)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let capabilities = try #require(json["capabilities"] as? [String: Any])
        let textDocument = try #require(capabilities["textDocument"] as? [String: Any])
        let hover = try #require(textDocument["hover"] as? [String: Any])
        let contentFormat = try #require(hover["contentFormat"] as? [String])

        #expect(contentFormat == ["markdown", "plaintext"])
        #expect(json["processId"] as? Int == 123)
        #expect(json["rootUri"] as? String == "file:///repo")
        #expect(json["initializationOptions"] == nil)
        #expect(json["workspaceFolders"] == nil)
    }

    @Test
    func `InitializeParams encodes its options and workspace folders when given`() throws {
        let params = InitializeParams(
            processId: nil, rootUri: "file:///repo/", initializationOptions: .object(["a": .bool(true)]),
            workspaceFolders: [WorkspaceFolder(uri: "file:///repo/", name: "repo")])
        let data = try JSONEncoder().encode(params)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect((json["initializationOptions"] as? [String: Any])?["a"] as? Bool == true)
        let folders = try #require(json["workspaceFolders"] as? [[String: Any]])
        #expect(folders.count == 1)
        #expect(folders.first?["uri"] as? String == "file:///repo/")
        #expect(folders.first?["name"] as? String == "repo")
    }
}
