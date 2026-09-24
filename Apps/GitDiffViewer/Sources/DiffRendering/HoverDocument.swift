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

    /// The symbol's name, as Quick Help titles it, read from the declaration; nil when it names none.
    package let title: String?
    package let declaration: NSAttributedString?
    /// The abstract: the documentation's opening paragraph.
    package let summary: NSAttributedString?
    /// Everything after the abstract, block by block.
    package let discussion: [Block]
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
        title: String? = nil, declaration: NSAttributedString? = nil, summary: NSAttributedString? = nil,
        discussion: [Block] = [], parameters: [Field] = [], returns: NSAttributedString? = nil,
        provenance: Provenance = .unknown, extraCandidates: [Candidate] = [], diagnostics: [DiagnosticEntry] = [],
        chipBackground: NSColor? = nil
    ) {
        self.title = title
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

    /// This document with `diagnostics` after its own, every other field kept as it is, ``chipBackground``
    /// included, so a row with findings shows its declaration on the same chip as any other row.
    package func adding(diagnostics: [DiagnosticEntry]) -> HoverDocument {
        HoverDocument(
            title: title, declaration: declaration, summary: summary, discussion: discussion, parameters: parameters,
            returns: returns, provenance: provenance, extraCandidates: extraCandidates,
            diagnostics: self.diagnostics + diagnostics, chipBackground: chipBackground)
    }

    /// Structures and styles `content` for the hover panel: declarations colored with the hovered pane's `palette`,
    /// prose through Foundation's markdown parser with a plain-text fallback.
    package static func build(from content: HoverContent, palette: DiffPalette) -> HoverDocument {
        let parsed = HoverMarkdownStructurer.structure(content.markdown)
        func declaration(_ text: String?) -> NSAttributedString? {
            text.map {
                CodeAttributedBuilder.attributedString(
                    for: HoverDeclarationName.withAttributesOnTheirOwnLines($0), palette: palette)
            }
        }
        func prose(_ text: String?) -> NSAttributedString? {
            text.map { Self.renderProse($0) }
        }
        return HoverDocument(
            title: parsed.declaration.flatMap(HoverDeclarationName.name(fromDeclaration:)),
            declaration: declaration(parsed.declaration),
            summary: prose(parsed.summary),
            discussion: parsed.discussion.map { Self.blocks(fromMarkdown: $0, palette: palette) } ?? [],
            parameters: parsed.parameters.map { field in
                Field(name: field.name, text: prose(field.text) ?? NSAttributedString())
            },
            returns: prose(parsed.returns),
            provenance: Provenance(content.source),
            extraCandidates: parsed.extraCandidates.map { candidate in
                Candidate(declaration: declaration(candidate.declaration), summary: prose(candidate.summary))
            },
            diagnostics: [],
            // Just short of opaque, so a trace of the panel's material keeps the chip set into the glass.
            chipBackground: chipColor(for: palette.background)
        )
    }

    /// Preserves a system background's light and dark variants when giving the declaration chip its translucency.
    private static func chipColor(for background: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = background
            appearance.performAsCurrentDrawingAppearance {
                resolved = (background.usingColorSpace(.sRGB) ?? background).withAlphaComponent(0.94)
            }
            return resolved
        }
    }

    /// Renders a prose piece through Foundation's markdown parser, as plain text where it fails. Runs without a color
    /// get `labelColor`: on the panel's vibrant material, uncolored text blends into the glass. A link
    /// ``openableURL(forLink:)`` refuses loses its link and keeps its text.
    private static func renderProse(_ text: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        return styledInline(parsed, size: HoverTypography.bodySize, weight: .regular)
    }

    /// `text`'s inline runs with explicit fonts at `size` and `weight`, `labelColor` where no color is set, and only
    /// openable links, as ``renderProse(_:)`` describes.
    static func styledInline(_ text: AttributedString, size: CGFloat, weight: NSFont.Weight) -> NSAttributedString {
        let result = NSMutableAttributedString(text)
        let whole = NSRange(location: 0, length: result.length)
        Self.materializeFonts(in: result, range: whole, base: .systemFont(ofSize: size, weight: weight))
        result.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            guard value == nil else { return }
            result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        result.enumerateAttribute(.link, in: whole) { value, range, _ in
            guard let value, Self.openableURL(forLink: value) == nil else { return }
            result.removeAttribute(.link, range: range)
        }
        return result
    }

    /// The URL the hover panel may open for a link, or nil to refuse it. `link` is an `NSAttributedString.Key.link`
    /// value, a `URL` or a string, and only an absolute `https` URL is openable: a doc comment comes from the
    /// repository under review, and every other scheme reaches something local, such as a file opened in its default
    /// app, a mounted share, or whichever app claims a custom scheme.
    package static func openableURL(forLink link: Any) -> URL? {
        let url: URL? =
            switch link {
                case let url as URL: url
                case let string as String: URL(string: string)
                default: nil
            }
        guard let url, url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// Gives every run an explicit font from its inline presentation intent: the markdown parser records bold,
    /// italic and code only as intent, and a fontless run draws in `NSTextView`'s default Helvetica 12. Set on the
    /// `NSAttributedString`, whose attribute values need not be `Sendable` the way `AttributedString`'s typed font
    /// attribute requires.
    private static func materializeFonts(in text: NSMutableAttributedString, range: NSRange, base: NSFont) {
        let code = NSFont.monospacedSystemFont(ofSize: base.pointSize - 1, weight: .regular)
        text.enumerateAttribute(.inlinePresentationIntent, in: range) { value, runRange, _ in
            let intent = (value as? NSNumber).map { InlinePresentationIntent(rawValue: $0.uintValue) } ?? []
            guard !intent.contains(.code) else {
                text.addAttribute(.font, value: code, range: runRange)
                return
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            let font =
                traits.isEmpty
                ? base : NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize)
            text.addAttribute(.font, value: font ?? base, range: runRange)
        }
    }
}
