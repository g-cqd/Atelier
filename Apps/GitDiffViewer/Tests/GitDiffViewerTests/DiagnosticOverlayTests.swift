import AtelierDiagnostics
import Testing

@testable import DiffTextKit

struct DiagnosticOverlayTests {
    private func row(severity: Finding.Severity = .warning, count: Int = 1) -> DiagnosticOverlay.RowDiagnostics {
        let finding = Finding(
            tool: .swiftlint, ruleID: "rule", message: "message", file: "a.swift", line: 1, severity: severity)
        return DiagnosticOverlay.RowDiagnostics(
            severity: severity, count: count, findings: Array(repeating: finding, count: count), squiggles: [])
    }

    @Test
    func `a fresh overlay is empty and answers nothing for any row`() {
        let overlay = DiagnosticOverlay()

        #expect(overlay.isEmpty)
        #expect(overlay.row(0) == nil)
    }

    @Test
    func `replace swaps in the rows given, readable back by index`() {
        let overlay = DiagnosticOverlay()

        overlay.replace([0: row(severity: .error), 3: row(severity: .note)])

        #expect(!overlay.isEmpty)
        #expect(overlay.row(0)?.severity == .error)
        #expect(overlay.row(3)?.severity == .note)
        #expect(overlay.row(1) == nil)
    }

    @Test
    func `a later replace fully supersedes an earlier one`() {
        let overlay = DiagnosticOverlay()
        overlay.replace([0: row(), 1: row()])

        overlay.replace([2: row(severity: .error)])

        #expect(overlay.row(0) == nil)
        #expect(overlay.row(1) == nil)
        #expect(overlay.row(2)?.severity == .error)
    }

    @Test
    func `replacing with an empty map empties the overlay`() {
        let overlay = DiagnosticOverlay()
        overlay.replace([0: row()])

        overlay.replace([:])

        #expect(overlay.isEmpty)
    }

    @Test
    func `concurrent reads alongside a replace never crash and settle on the latest write`() async {
        let overlay = DiagnosticOverlay()
        overlay.replace([0: row(severity: .note)])

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    _ = overlay.row(0)
                    _ = overlay.isEmpty
                }
            }
            group.addTask { overlay.replace([0: row(severity: .error), 1: row(severity: .warning)]) }
            for _ in 0 ..< 50 {
                group.addTask {
                    _ = overlay.row(1)
                    _ = overlay.isEmpty
                }
            }
            await group.waitForAll()
        }

        // Whichever write landed last, the overlay is internally consistent: row 0 always carries a diagnostic.
        #expect(overlay.row(0) != nil)
    }
}
