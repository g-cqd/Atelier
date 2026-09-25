import AemiRuntime
import AtelierProcess
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// A probe against the machine's own `sourcekit-lsp`, run only with `ATELIER_LSP_INTEGRATION=1`: it spawns a real
/// server and exercises the SDK tier end to end.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_LSP_INTEGRATION"] == "1"))
struct SDKDocumentationProviderIntegrationTests {
    @Test
    func `resolves NSVisualEffectView Material hudWindow against the real toolchain`() async throws {
        guard let serverExecutable = Self.resolveSourceKitLSP() else {
            Issue.record("sourcekit-lsp not found on PATH or via xcrun; skipping")
            return
        }

        let probeDirectory = try SDKDocumentationProvider.makeProbeDirectory()
        let provider = SDKDocumentationProvider.scratch(
            serverExecutable: serverExecutable, probeDirectory: probeDirectory, locateSDK: { _ in nil })

        let content = "import AppKit\nlet material = NSVisualEffectView.Material.hudWindow"
        // Inside "hudWindow", counted on the hovered line alone.
        let column = "let material = NSVisualEffectView.Material.hudWindow".utf16.count - 1
        let query = HoverQuery(documentURI: "file:///probe.swift", content: content, line: 1, utf16Column: column)

        let result = try await provider.hover(query)
        await provider.shutdown()
        try FileManager.default.removeItem(at: probeDirectory)

        let markdown = try #require(result?.markdown)
        #expect(markdown.lowercased().contains("material"))
    }

    @Test(.timeLimit(.minutes(3)))
    func `a system symbol's page is filed under the module of its chain's first type`() async throws {
        let serverExecutable = try #require(Self.resolveSourceKitLSP(), "sourcekit-lsp not found")
        let probeDirectory = try SDKDocumentationProvider.makeProbeDirectory()
        let provider = SDKDocumentationProvider.scratch(
            serverExecutable: serverExecutable, probeDirectory: probeDirectory, locateSDK: { _ in nil },
            resolvesDocumentationPages: true)

        func page(of line: String) async throws -> HoverContent.DocumentationPage? {
            let query = HoverQuery(
                documentURI: "file:///probe.swift", content: "import Foundation\n" + line, line: 1,
                utf16Column: line.utf16.count - 1)
            return try await provider.hover(query)?.documentationPage
        }
        let utf8 = try await page(of: "let encoding = String.Encoding.utf8")
        let manager = try await page(of: "let manager = FileManager.default")
        await provider.shutdown()
        try FileManager.default.removeItem(at: probeDirectory)

        // Foundation declares the encoding; Apple's documentation files it under Swift's String.
        #expect(utf8 == HoverContent.DocumentationPage(module: "Swift", path: ["String", "Encoding", "utf8"]))
        #expect(manager == HoverContent.DocumentationPage(module: "Foundation", path: ["FileManager", "default"]))
    }

    @Test(.timeLimit(.minutes(3)))
    func `resolves UIView against the iOS simulator SDK`() async throws {
        let serverExecutable = try #require(Self.resolveSourceKitLSP(), "sourcekit-lsp not found")
        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let probeDirectory = try SDKDocumentationProvider.makeProbeDirectory()
        // A cold module cache takes a quarter of a minute to load UIKit here.
        let provider = SDKDocumentationProvider.scratch(
            serverExecutable: serverExecutable, probeDirectory: probeDirectory,
            locateSDK: { platform in await SDKLocation.locate(platform, runner: runner) }, requestTimeout: .seconds(120)
        )

        let content = "import UIKit\nlet view = UIView()"
        let query = HoverQuery(
            documentURI: "file:///probe.swift", content: content, line: 1, utf16Column: "let view = UIV".utf16.count)
        let result = try await provider.hover(query)
        await provider.shutdown()
        try FileManager.default.removeItem(at: probeDirectory)

        let markdown = try #require(result?.markdown)
        #expect(markdown.contains("class UIView"))
    }

    private static func resolveSourceKitLSP() -> URL? {
        let candidates = [
            "/usr/bin/sourcekit-lsp",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }
}
