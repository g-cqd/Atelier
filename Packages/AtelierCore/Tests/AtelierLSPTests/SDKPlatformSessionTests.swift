import AemiTestKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// Makes one scripted session per platform, whose server answers every hover with the platform's name, and records
/// every platform a session was asked for.
private actor PlatformSessions {
    private(set) var asked: [SDKPlatform] = []
    private var factories: [SDKPlatform: ScriptedConnectionFactory] = [:]
    private let available: Set<SDKPlatform>
    private let gate: AsyncGate?

    /// - Parameters:
    ///   - available: The platforms that have a session; the others, as iOS without Xcode, have none.
    ///   - gate: Holds every session's making until it opens, when given.
    init(available: Set<SDKPlatform> = Set(SDKPlatform.allCases), gate: AsyncGate? = nil) {
        self.available = available
        self.gate = gate
    }

    func make(_ platform: SDKPlatform) async -> SourceKitLSPService? {
        asked.append(platform)
        if let gate {
            do {
                try await gate.waitUntilOpen()
            } catch {
                Issue.record("The session gate never opened: \(error)")
            }
        }
        guard available.contains(platform) else { return nil }
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": .object([:]), "shutdown": .null,
            "textDocument/hover": .object([
                "contents": .object([
                    "kind": .string("markdown"), "value": .string("Documented on \(platform.rawValue).")
                ])
            ])
        ])
        factories[platform] = factory
        return SourceKitLSPService(
            configuration: SourceKitLSPService.Configuration(
                serverExecutable: URL(filePath: "/usr/bin/true"),
                workspaceRoot: URL(filePath: "/probe-\(platform.rawValue)", directoryHint: .isDirectory)),
            clock: TestClock()
        ) { _ in await factory.make() }
    }

    /// The text of every document `platform`'s server was sent.
    func openedTexts(on platform: SDKPlatform) async -> [String] {
        guard let factory = factories[platform] else { return [] }
        var texts: [String] = []
        for index in 0 ..< (await factory.generationCount) {
            for frame in await factory.transport(at: index).sink.all {
                let sent = try? JSONDecoder().decode(SentOpen.self, from: unframe(frame))
                if let text = sent?.params?.textDocument.text { texts.append(text) }
            }
        }
        return texts
    }

    /// How many times `platform`'s server was closed.
    func closeCount(on platform: SDKPlatform) async -> Int {
        guard let factory = factories[platform] else { return 0 }
        var count = 0
        for index in 0 ..< (await factory.generationCount) {
            count += await factory.transport(at: index).closeCount.count
        }
        return count
    }
}

/// A sent frame, reduced to a `didOpen`'s document text.
private struct SentOpen: Decodable {
    struct Params: Decodable {
        struct Document: Decodable { let text: String? }
        let textDocument: Document
    }

    let params: Params?
}

private func query(_ content: String, hovering token: String, documentURI: String = "file:///a.swift") -> HoverQuery {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
    let line = lines.lastIndex { $0.contains(token) } ?? 0
    let column = lines[line].range(of: token)
        .map { lines[line].utf16.distance(from: lines[line].startIndex, to: $0.lowerBound) }
    return HoverQuery(documentURI: documentURI, content: content, line: line, utf16Column: (column ?? 0) + 1)
}

@Suite
struct SDKPlatformSessionTests {
    @Test
    func `a UIKit file's probe goes to the iOS session and imports UIKit`() async throws {
        let sessions = PlatformSessions()
        let provider = SDKDocumentationProvider(sessions: { await sessions.make($0) })

        let answer = try await provider.hover(query("import UIKit\nlet view = UIView()", hovering: "UIView"))

        #expect(answer?.markdown == "Documented on iOS.")
        #expect(await sessions.asked == [.iOS])
        let opened = try #require(await sessions.openedTexts(on: .iOS).first)
        #expect(opened.contains("import UIKit"))
        #expect(!opened.contains("import AppKit"))
        await provider.shutdown()
    }

    @Test
    func `each platform's session is made once`() async throws {
        let sessions = PlatformSessions()
        let provider = SDKDocumentationProvider(sessions: { await sessions.make($0) })

        _ = try await provider.hover(query("import UIKit\nlet view = UIView()", hovering: "UIView"))
        _ = try await provider.hover(query("import UIKit\nlet color = UIColor.red", hovering: "red"))
        _ = try await provider.hover(query("import AppKit\nlet view = NSView()", hovering: "NSView"))

        #expect(await sessions.asked == [.iOS, .macOS])
        await provider.shutdown()
    }

    @Test
    func `concurrent first hovers of one platform share its one session`() async throws {
        let gate = AsyncGate()
        let sessions = PlatformSessions(gate: gate)
        let provider = SDKDocumentationProvider(sessions: { await sessions.make($0) })

        async let first = provider.hover(query("import UIKit\nlet view = UIView()", hovering: "UIView"))
        async let second = provider.hover(query("import UIKit\nlet color = UIColor.red", hovering: "red"))
        gate.open()
        let answers = try await [first, second]

        #expect(answers.map { $0?.markdown } == ["Documented on iOS.", "Documented on iOS."])
        #expect(await sessions.asked == [.iOS])
        await provider.shutdown()
    }

    @Test
    func `without an iOS session, an iOS file's probe falls back to the Mac's`() async throws {
        let sessions = PlatformSessions(available: [.macOS])
        let provider = SDKDocumentationProvider(sessions: { await sessions.make($0) })

        let answer = try await provider.hover(
            query("import UIKit\nlet url = URL.homeDirectory", hovering: "homeDirectory"))

        #expect(answer?.markdown == "Documented on macOS.")
        #expect(await sessions.asked == [.iOS, .macOS])
        let opened = try #require(await sessions.openedTexts(on: .macOS).first)
        #expect(!opened.contains("import UIKit"))
        await provider.shutdown()
    }

    @Test
    func `a file on disk that imports no platform framework follows its project`() async throws {
        let repository = TemporaryDirectory(prefix: "atelier-sdk-project")
        defer { repository.cleanup() }
        let root = URL(filePath: repository.path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "App.xcodeproj"), withIntermediateDirectories: true)
        try Data("SDKROOT = iphoneos;".utf8).write(to: root.appending(path: "App.xcodeproj/project.pbxproj"))
        let sessions = PlatformSessions()
        let provider = SDKDocumentationProvider(sessions: { await sessions.make($0) })

        let answer = try await provider.hover(
            query(
                "import SwiftUI\nlet host: UIHostingController<Text>? = nil", hovering: "UIHostingController",
                documentURI: root.appending(path: "App/Sources/Screen.swift").absoluteString))

        #expect(answer?.markdown == "Documented on iOS.")
        #expect(await sessions.asked == [.iOS])
        await provider.shutdown()
    }

    @Test
    func `shutting the provider down shuts every session it made down`() async throws {
        let sessions = PlatformSessions()
        let provider = SDKDocumentationProvider(sessions: { await sessions.make($0) })
        _ = try await provider.hover(query("import UIKit\nlet view = UIView()", hovering: "UIView"))
        _ = try await provider.hover(query("import AppKit\nlet view = NSView()", hovering: "NSView"))

        await provider.shutdown()

        #expect(await sessions.closeCount(on: .iOS) == 1)
        #expect(await sessions.closeCount(on: .macOS) == 1)
        #expect(try await provider.hover(query("import UIKit\nlet image = UIImage()", hovering: "UIImage")) == nil)
    }
}
