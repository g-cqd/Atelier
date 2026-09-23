package import AppKit
package import AtelierSyntaxModel
import Foundation

/// Xcode Quick-Help-shaped documentation for one hover: a colored declaration, prose summary and discussion,
/// per-parameter and return descriptions, any secondary overloads, and where the content came from.
///
/// `@unchecked Sendable`: every stored `NSAttributedString` is built once and never mutated.
package struct HoverDocument: @unchecked Sendable {
    package struct Field: @unchecked Sendable {
        package let name: String
        package let text: NSAttributedString

        package init(name: String, text: NSAttributedString) {
            self.name = name
            self.text = text
        }
    }

    package struct Candidate: @unchecked Sendable {
        package let declaration: NSAttributedString?
        package let summary: NSAttributedString?

        package init(declaration: NSAttributedString?, summary: NSAttributedString?) {
            self.declaration = declaration
            self.summary = summary
        }
    }

    package struct DiagnosticEntry: Sendable {
        package enum Severity: Sendable {
            case note
            case warning
            case error
        }

        package let severity: Severity
        package let message: String
        package let tool: String

        package init(severity: Severity, message: String, tool: String) {
            self.severity = severity
            self.message = message
            self.tool = tool
        }
    }

    /// Where the content came from; ``unknown`` for a document built by hand.
    package enum Provenance: Sendable, Equatable {
        case languageServer
        case docIndex
        case sdk
        case unknown

        package init(_ source: HoverContent.Source) {
            switch source {
                case .languageServer: self = .languageServer
                case .docIndex: self = .docIndex
                case .sdk: self = .sdk
            }
        }

        /// The footer text Quick Help shows for this tier; empty when there is nothing worth saying.
        package var label: String {
            switch self {
                case .languageServer: "sourcekit-lsp"
                case .docIndex: "doc comment"
                case .sdk: "Apple SDK"
                case .unknown: ""
            }
        }
    }

    package let declaration: NSAttributedString?
    package let summary: NSAttributedString?
    package let discussion: NSAttributedString?
    package let parameters: [Field]
    package let returns: NSAttributedString?
    package let provenance: Provenance
    /// Further declarations from an overload list, each with its summary; at most two when built from hover content.
    package let extraCandidates: [Candidate]
    /// Diagnostics shown with the hover; ``build(from:palette:)`` leaves it empty.
    package let diagnostics: [DiagnosticEntry]
    /// The background declarations are drawn against: the hovered pane's ``DiffPalette/background``, so the theme's
    /// colors stay legible over the panel's material; nil for a document built by hand.
    package let chipBackground: NSColor?

    package init(
        declaration: NSAttributedString? = nil, summary: NSAttributedString? = nil,
        discussion: NSAttributedString? = nil, parameters: [Field] = [], returns: NSAttributedString? = nil,
        provenance: Provenance = .unknown, extraCandidates: [Candidate] = [], diagnostics: [DiagnosticEntry] = [],
        chipBackground: NSColor? = nil
    ) {
        self.declaration = declaration
        self.summary = summary
        self.discussion = discussion
        self.parameters = parameters
        self.returns = returns
        self.provenance = provenance
        self.extraCandidates = extraCandidates
        self.diagnostics = diagnostics
        self.chipBackground = chipBackground
    }

    /// Structures and styles `content` for the hover panel: declarations colored with the hovered pane's `palette`,
    /// prose through Foundation's markdown parser with a plain-text fallback.
    package static func build(from content: HoverContent, palette: DiffPalette) -> HoverDocument {
        let parsed = HoverMarkdownStructurer.structure(content.markdown)
        func code(_ text: String?) -> NSAttributedString? {
            text.map { CodeAttributedBuilder.attributedString(for: $0, palette: palette) }
        }
        func prose(_ text: String?) -> NSAttributedString? {
            text.map { Self.renderProse($0) }
        }
        return HoverDocument(
            declaration: code(parsed.declaration),
            summary: prose(parsed.summary),
            discussion: prose(parsed.discussion),
            parameters: parsed.parameters.map { field in
                Field(name: field.name, text: prose(field.text) ?? NSAttributedString())
            },
            returns: prose(parsed.returns),
            provenance: Provenance(content.source),
            extraCandidates: parsed.extraCandidates.map { candidate in
                Candidate(declaration: code(candidate.declaration), summary: prose(candidate.summary))
            },
            diagnostics: [],
            // Just short of opaque, so a trace of the panel's material keeps the chip set into the glass.
            chipBackground: palette.background.withAlphaComponent(0.94)
        )
    }

    /// Renders a prose piece through Foundation's markdown parser, as plain text where it fails. Runs without a color
    /// get `labelColor`: on the panel's vibrant material, uncolored text blends into the glass.
    private static func renderProse(_ text: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        var parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        Self.materializeFonts(in: &parsed)
        let result = NSMutableAttributedString(parsed)
        result.enumerateAttribute(
            .foregroundColor, in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            guard value == nil else { return }
            result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        return result
    }

    /// Gives every run of `text` an explicit font from its `inlinePresentationIntent`: the markdown parser records
    /// bold, italic and code only as intent, and a fontless run draws in `NSTextView`'s default Helvetica 12.
    private static func materializeFonts(in text: inout AttributedString) {
        let base = NSFont.systemFont(ofSize: 12)
        for run in text.runs {
            let intent = run.inlinePresentationIntent
            if let intent, intent.contains(.code) {
                text[run.range].font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                continue
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if let intent, intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if let intent, intent.contains(.emphasized) { traits.insert(.italic) }
            guard !traits.isEmpty else {
                text[run.range].font = base
                continue
            }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            text[run.range].font = NSFont(descriptor: descriptor, size: 12) ?? base
        }
    }
}
