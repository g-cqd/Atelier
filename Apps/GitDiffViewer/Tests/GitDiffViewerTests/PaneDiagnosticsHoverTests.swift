import AppKit
import AtelierDiagnostics
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit
@testable import GitDiffViewer

/// Hovering an underlined range shows that finding with the documentation, in one panel, in the single-file view and
/// in the card list alike, since both resolve a hover through ``PaneDiagnostics`` (book HOVER-14).
struct PaneDiagnosticsHoverTests {
    /// Which view's text the hover is over.
    enum View: CaseIterable, CustomTestStringConvertible {
        case singleFile
        case card

        var testDescription: String { self == .singleFile ? "the single-file view" : "a card" }

        /// The text `line` shows in: a file of its own, or the third file of a card list, whose rows carry file
        /// index 2.
        func rendered(_ text: String) throws -> RenderedText {
            switch self {
                case .singleFile:
                    return try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
                case .card:
                    let prepared = PreparedDiff(
                        FileDiffInput(title: "c.swift", oldText: text, newText: text, language: .plain),
                        granularity: .word)
                    return try #require(
                        DiffRenderer.render(
                            prepared: [prepared], options: DiffRenderer.Options(sides: [.new]), layout: .full,
                            withHeaders: false, firstFileIndex: 2
                        )
                        .new)
            }
        }

        var fileIndex: Int { self == .singleFile ? 0 : 2 }
    }

    private static let text = "let alphaValue = betaValue\n"

    private static func finding(rule: String, column: Int?, endColumn: Int?) -> Finding {
        Finding(
            tool: .swiftlint, ruleID: rule, message: "message \(rule)", file: "c.swift", line: 1, column: column,
            endLine: column == nil ? nil : 1, endColumn: endColumn, severity: .warning)
    }

    /// A resolver over `findings` on line 1, whose documentation is a document titled "doc".
    private static func resolver(_ view: View, findings: [Finding]) throws -> (
        resolve: @Sendable (HoverHit) async -> HoverDocument?, hit: (Int) -> HoverHit
    ) {
        let rendered = try view.rendered(text)
        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none,
            right: SideFindings(paths: [view.fileIndex: "c.swift"], findings: ["c.swift": findings]))
        let resolve = PaneDiagnostics.hoverResolver(
            overlay: DiagnosticOverlay(rows: rows), material: { .liquidGlass },
            documentation: { _ in HoverDocument(title: "doc") })
        let row = try #require(rendered.rows.firstIndex { $0.newNumber == 1 })
        let hit = { (column: Int) in
            HoverHit(
                fileIndex: view.fileIndex, side: .new, line: 0, utf16Column: column, row: row, anchorRect: .zero,
                identifierRange: NSRange(location: column, length: 1))
        }
        return (resolve, hit)
    }

    @Test(arguments: View.allCases)
    func `hovering an underlined range shows its finding with the documentation`(view: View) async throws {
        // "alphaValue" is columns 5 to 14, "betaValue" 18 to 26, one-based.
        let alpha = Self.finding(rule: "alpha", column: 5, endColumn: 15)
        let beta = Self.finding(rule: "beta", column: 18, endColumn: 27)
        let sut = try Self.resolver(view, findings: [alpha, beta])

        let document = try #require(await sut.resolve(sut.hit(8)))

        #expect(document.title == "doc")
        #expect(document.diagnostics.map(\.message) == ["alpha: message alpha"])
        #expect(document.diagnostics.map(\.tool) == [DiagnosticTool.swiftlint.displayName])
    }

    @Test(arguments: View.allCases)
    func `hovering off every underlined range of a row shows the documentation alone`(view: View) async throws {
        let beta = Self.finding(rule: "beta", column: 18, endColumn: 27)
        let sut = try Self.resolver(view, findings: [beta])

        let document = try #require(await sut.resolve(sut.hit(8)))

        #expect(document.title == "doc")
        #expect(document.diagnostics.isEmpty)
    }

    @Test(arguments: View.allCases)
    func `a finding without a column underlines its whole line, so any hover on it shows it`(view: View) async throws {
        let sut = try Self.resolver(view, findings: [Self.finding(rule: "line", column: nil, endColumn: nil)])

        let document = try #require(await sut.resolve(sut.hit(20)))

        #expect(document.diagnostics.map(\.message) == ["line: message line"])
    }
}
