import Testing

@testable import AtelierDiagnostics

/// The properties ``DiagnosticTool`` reports for each tool.
struct DiagnosticToolTests {
    @Test(arguments: [
        (DiagnosticTool.swiftlint, false),
        (.swiftFormat, false),
        (.swiftformat, false),
        (.arcleak, true),
        (.dolly, true),
        (.deadwood, true)
    ])
    func `only the analyzers scope their own report to the files they are given`(
        tool: DiagnosticTool, expected: Bool
    ) {
        #expect(tool.scopesItsOwnReport == expected)
    }
}
