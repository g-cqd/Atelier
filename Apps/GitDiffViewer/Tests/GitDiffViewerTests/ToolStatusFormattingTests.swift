import AtelierDiagnostics
import Foundation
import Testing

@testable import DiffComparison

/// ``toolStatusDescription(_:pinned:)``'s pure formatting: every origin's wording, the version-less case, and the
/// missing/pinned-broken distinction that lets a status row tell "never installed" from "the pinned path broke".
struct ToolStatusFormattingTests {
    private static let url = URL(filePath: "/opt/homebrew/bin/swiftlint")

    @Test("Shows the executable, version and place for every origin")
    func availableWithVersion() {
        let expectations: [(ToolOrigin, String)] = [
            (.environment, "environment override"),
            (.custom, "pinned path"),
            (.bundled, "bundled"),
            (.toolchain, "toolchain"),
            (.wellKnown, "well-known directory"),
            (.shellPath, "shell PATH")
        ]
        for (origin, name) in expectations {
            let status = ToolStatus(tool: .swiftlint, url: Self.url, origin: origin, version: "0.59.1")
            #expect(
                toolStatusDescription(status, pinned: false)
                    == "swiftlint 0.59.1 — /opt/homebrew/bin (\(name))")
        }
    }

    @Test("Drops the version when none could be probed")
    func availableWithoutVersion() {
        let status = ToolStatus(tool: .swiftlint, url: Self.url, origin: .wellKnown, version: nil)
        #expect(toolStatusDescription(status, pinned: false) == "swiftlint — /opt/homebrew/bin (well-known directory)")
    }

    @Test("Reports a tool that was never found, and unset")
    func missing() {
        let status = ToolStatus(tool: .swiftlint, url: nil, origin: nil, version: nil)
        #expect(toolStatusDescription(status, pinned: false) == "Not found")
        #expect(toolStatusDescription(nil, pinned: false) == "Checking…")
    }

    @Test("Distinguishes a pinned path that does not resolve from a plain miss")
    func pinnedBroken() {
        let status = ToolStatus(tool: .swiftlint, url: nil, origin: nil, version: nil)
        #expect(toolStatusDescription(status, pinned: true) == "Pinned path is missing or not executable")
    }
}
