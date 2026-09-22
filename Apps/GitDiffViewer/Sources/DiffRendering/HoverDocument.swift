package import AppKit
package import AtelierSyntaxModel
import Foundation

/// Xcode Quick-Help-shaped documentation for one hover: a colored declaration, prose summary and discussion,
/// per-parameter and return descriptions, any secondary overloads, where the content came from, and a diagnostics
/// slot reserved for a later unification with the diagnostics squiggle popover.
///
/// Lives in `DiffRendering` rather than `DiffComparison` (where the design that named it first put it) so that
/// `DiffTextKit`, which owns `DocHoverController` and needs the type for its resolver seam, can see it without a
/// dependency edge onto `DiffComparison` -- which does not exist today and adding it would mean touching
/// `Package.swift`. `DiffRendering` is already a dependency of both `DiffTextKit` and `DiffComparison`, so this
/// keeps the seam a pure Swift-file change.
///
/// `@unchecked Sendable`: every stored `NSAttributedString` here is built once, off whatever actor resolved the
/// hover, and never mutated again -- the same immutable-after-construction shape ``RenderedText`` and
/// ``DiffPalette`` already use for the same reason.
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

    /// Where the content came from, kept separate from ``AtelierSyntaxModel/HoverContent/Source`` so this module
    /// compiles whether or not that enum already carries the SDK tier's `.sdk` case: ``init(_:)`` maps any case it
    /// does not yet know about to ``unknown`` rather than failing to build.
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
    /// Further declarations from an overload list sourcekit-lsp answered with (at most two, Quick Help's own
    /// limit); their prose is shown, their bodies are not, to keep the panel from growing unbounded.
    package let extraCandidates: [Candidate]
    /// Reserved for the diagnostics-hover unification: always empty today.
    package let diagnostics: [DiagnosticEntry]
    /// The background a declaration chip (the main declaration, and any ``extraCandidates``' own) should be drawn
    /// against: the same ``DiffPalette/background`` the pane the hover came from renders its own text on, so a
    /// theme's role colors -- picked to read against *that* background -- stay legible regardless of the panel's
    /// own vibrancy material, which may land on either a light or a dark system appearance independent of the
    /// diff theme. `nil` only when there is no declaration to chip (``build(from:palette:)`` always sets it
    /// otherwise; ``HoverDocument/init`` defaults it to `nil` for callers, mostly tests, that build a document by
    /// hand with no theme to speak of).
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

    /// Parses and colors `content` for the hover panel: ``HoverMarkdownStructurer`` splits its markdown into
    /// plain-text pieces, then the declaration and any candidate declarations are colored with `palette` -- the
    /// same palette instance as the pane the hover came from, so the panel's declaration matches the identifier it
    /// documents exactly. Prose pieces go through Foundation's own markdown parser, falling back to plain text for
    /// anything it rejects, the same policy `DiffComparison`'s `renderHoverMarkdown` already uses.
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
            // Blended just short of fully opaque rather than the palette's raw background: the chip should read
            // as the theme's own surface, but a hairline of the panel's vibrancy showing through at the edges
            // keeps it looking like a chip set into the glass rather than a flat, unrelated rectangle pasted over
            // it.
            chipBackground: palette.background.withAlphaComponent(0.94)
        )
    }

    /// A minimal markdown-to-`NSAttributedString` pass for the plain-prose pieces a structured document carries
    /// (no fences expected in a summary, a discussion or a parameter's own description): Foundation's own parser,
    /// falling back to plain text for a fragment it rejects rather than showing nothing.
    ///
    /// `AttributedString(markdown:)` leaves `.foregroundColor` unset wherever the source markdown never asked for
    /// one, which is every plain run of prose; shown on an `NSVisualEffectView`'s vibrant material (the panel's
    /// own `.popover` material, `.behindWindow` blended), text with no explicit color draws blended into the glass
    /// rather than opaque -- readable as blank in front of a light backdrop. `labelColor` is stamped over the
    /// whole run afterward so prose is always opaque, the same way ``CodeAttributedBuilder`` already stamps
    /// explicit palette colors on the declaration (which is why the declaration alone was ever visible).
    private static func renderProse(_ text: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        var parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        Self.materializeFonts(in: &parsed)
        let result = NSMutableAttributedString(parsed)
        // Stamped only where nothing already set a color: markdown source text never specifies one for plain
        // prose, but this stays additive rather than a blanket overwrite in case a future syntax ever does.
        result.enumerateAttribute(
            .foregroundColor, in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            guard value == nil else { return }
            result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        return result
    }

    /// Stamps an explicit `NSFont` on every run of `text` from Foundation's own `inlinePresentationIntent`
    /// (bold/italic/inline-code), which `AttributedString(markdown:)` records as *intent* and never as a font.
    /// The bridge to `NSAttributedString` in ``renderProse(_:)`` has nothing of its own to fall back to for a run
    /// with no font attribute -- `NSTextView` draws it in its hardcoded default, Helvetica 12, not the system
    /// font, silently losing the bold/italic/code styling along with it. Walked here, on the `AttributedString`
    /// side, while the intent is still a readable value rather than whatever the bridge chose to encode it into;
    /// every run leaves with a font, intent or not, so nothing downstream can ever bridge fontless.
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
