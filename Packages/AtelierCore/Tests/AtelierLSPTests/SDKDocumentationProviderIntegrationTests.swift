import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// Real-toolchain probe against the machine's own `sourcekit-lsp`, skipped by default. Set
/// `ATELIER_LSP_INTEGRATION=1` to run it -- it spawns an actual sourcekit-lsp process and exercises the SDK
/// tier end to end, the same shape as the manual verification this feature's design doc records.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_LSP_INTEGRATION"] == "1"))
struct SDKDocumentationProviderIntegrationTests {
    @Test
    func `resolves NSVisualEffectView Material hudWindow against the real toolchain`() async throws {
        guard let serverExecutable = Self.resolveSourceKitLSP() else {
            Issue.record("sourcekit-lsp not found on PATH or via xcrun; skipping")
            return
        }

        let service = SDKDocumentationProvider.makeScratchService(serverExecutable: serverExecutable)
        let provider = SDKDocumentationProvider(service: service)

        let content = "import AppKit\nlet material = NSVisualEffectView.Material.hudWindow"
        let column = content.utf16.count - 1  // inside "hudWindow"
        let query = HoverQuery(documentURI: "file:///probe.swift", content: content, line: 1, utf16Column: column)

        let result = try await provider.hover(query)
        await service.shutdown()

        let markdown = try #require(result?.markdown)
        #expect(markdown.lowercased().contains("material"))
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
