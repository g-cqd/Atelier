import Foundation
import Testing

@testable import AtelierDiagnostics

/// The argv and exit-code contracts ``ToolCommand`` builds for each tool.
struct ToolCommandTests {
    private static let root = URL(filePath: "/repo")

    @Test(arguments: [
        (DiagnosticTool.swiftlint, ["lint", "--reporter", "sarif", "--quiet", "A.swift"]),
        (.swiftFormat, ["lint", "A.swift"]),
        (.arcleak, ["analyze", "A.swift", "--format", "sarif"]),
        (.dolly, ["analyze", "/repo", "--format", "sarif"]),
        (.deadwood, ["analyze", "/repo", "--format", "sarif"])
    ])
    func `analyze builds the expected argv for each tool`(tool: DiagnosticTool, expected: [String]) {
        #expect(ToolCommand.analyze(tool, files: ["A.swift"], root: Self.root) == expected)
    }

    @Test(arguments: DiagnosticTool.allCases)
    func `version is dash-dash-version for every tool`(tool: DiagnosticTool) {
        #expect(ToolCommand.version(tool) == ["--version"])
    }

    @Test(arguments: [
        (DiagnosticTool.swiftlint, Set<Int32>([0, 1, 2, 3])),
        (.swiftFormat, Set<Int32>([0, 1])),
        (.arcleak, Set<Int32>([0, 1])),
        (.dolly, Set<Int32>([0, 1])),
        (.deadwood, Set<Int32>([0, 1]))
    ])
    func `acceptable exit codes match each tool's meaning of nonzero`(tool: DiagnosticTool, expected: Set<Int32>) {
        #expect(ToolCommand.acceptableExitCodes(tool) == expected)
    }
}
