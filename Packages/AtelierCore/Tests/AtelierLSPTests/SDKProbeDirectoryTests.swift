import AemiTestKit
import AtelierSyntaxModel
import Darwin
import Foundation
import Testing

@testable import AtelierLSP

/// One frame the client sent, reduced to what these tests read.
private struct SentFrame: Decodable {
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?

    /// The `textDocument.uri` of a `didOpen` or `hover`, or nil for any other frame.
    var documentURI: String? {
        guard case .object(let params) = params, case .object(let document) = params["textDocument"],
            case .string(let uri) = document["uri"]
        else { return nil }
        return uri
    }
}

private func sentFrames(_ transport: PipeTransport) async throws -> [SentFrame] {
    try await transport.sink.all.map { try JSONDecoder().decode(SentFrame.self, from: unframe($0)) }
}

private func respond(_ transport: PipeTransport, to frame: SentFrame, with result: JSONValue) throws {
    let id = try #require(frame.id)
    transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: result)))
}

private func hoverResult(_ markdown: String) -> JSONValue {
    .object(["contents": .object(["kind": .string("markdown"), "value": .string(markdown)])])
}

@Suite
struct SDKProbeDirectoryTests {
    @Test
    func `the probe directory is new, lies under its parent and only its owner can enter it`() throws {
        let parent = TemporaryDirectory(prefix: "atelier-sdk-parent")
        defer { parent.cleanup() }
        let parentURL = URL(filePath: parent.path, directoryHint: .isDirectory)

        let probeDirectory = try SDKDocumentationProvider.makeProbeDirectory(in: parentURL)

        #expect(probeDirectory.deletingLastPathComponent().standardizedFileURL == parentURL.standardizedFileURL)
        #expect(probeDirectory.lastPathComponent.hasPrefix("atelier-sdk-probe."))
        var status = stat()
        #expect(stat(probeDirectory.path(percentEncoded: false), &status) == 0)
        #expect(status.st_mode & S_IFMT == S_IFDIR)
        #expect(status.st_mode & 0o777 == 0o700)
    }

    @Test
    func `a probe directory that cannot be created surfaces an error`() throws {
        let parent = TemporaryDirectory(prefix: "atelier-sdk-parent")
        defer { parent.cleanup() }
        let missingParent = URL(filePath: parent.path, directoryHint: .isDirectory)
            .appending(path: "missing", directoryHint: .isDirectory)

        #expect(
            throws: SDKProbeDirectoryError.creationFailed(
                parentPath: missingParent.path(percentEncoded: false), code: ENOENT)
        ) {
            try SDKDocumentationProvider.makeProbeDirectory(in: missingParent)
        }
    }

    @Test
    func `every probe document is named under the scratch session's probe directory`() async throws {
        let parent = TemporaryDirectory(prefix: "atelier-sdk-parent")
        defer { parent.cleanup() }
        let probeDirectory = try SDKDocumentationProvider.makeProbeDirectory(
            in: URL(filePath: parent.path, directoryHint: .isDirectory))
        let transport = PipeTransport()
        let service = LanguageServerSession(
            configuration: LanguageServerSession.Configuration(
                serverExecutable: URL(filePath: "/usr/bin/true"), workspaceRoot: probeDirectory),
            clock: TestClock()
        ) { _ in LSPConnection(transport: transport) }
        let provider = SDKDocumentationProvider(service: service)
        // An uppercase chain whose first answer has no prose sends a second, type-position probe.
        let content = "import SwiftUI\nlet x = StateObject"
        let query = HoverQuery(
            documentURI: "file:///repository/a.swift", content: content, line: 1,
            utf16Column: "let x = StateObject".utf16.count - 3)

        async let answer = provider.hover(query)
        await transport.sink.waitForCount(1)
        try respond(transport, to: try await sentFrames(transport)[0], with: .object([:]))
        await transport.sink.waitForCount(4)
        try respond(transport, to: try await sentFrames(transport)[3], with: hoverResult("```swift\nstruct S\n```"))
        await transport.sink.waitForCount(6)
        try respond(transport, to: try await sentFrames(transport)[5], with: hoverResult("Prose."))
        _ = try await answer

        let documentURIs = try await sentFrames(transport).compactMap(\.documentURI)
        #expect(documentURIs.count == 4)
        for uri in documentURIs {
            #expect(uri.hasPrefix(probeDirectory.absoluteString))
        }
        transport.endIncoming()
        await service.shutdown()
    }
}
