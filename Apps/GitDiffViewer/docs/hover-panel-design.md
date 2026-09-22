# Rich hover panel design (validated 2026-09)

Verdict: replace NSPopover with an arrow-less anchored NSPanel child window (Xcode Quick Help
style). NSPopover's chrome is a hard ceiling (hasFullSizeContent only extends into the arrow
region; verified). Panel: [.borderless, .nonactivatingPanel], floating, clear/soft-shadow,
NSVisualEffectView .popover material, 8pt continuous corners, appearance matched to the pane.
Content stack: symbol header row · token-colored declaration chip · doc body (NSTextView,
selectable, links) · parameter NSGridView · diagnostics slot (reserved) · provenance footer.
Sizing: fixed width 440, measure via NSTextLayoutManager.usageBoundsForTextContainer, clamp
height 420 then inner-scroll body only. Anchor at HoverHit.anchorRect converted to screen,
below the identifier, flip at screen edges; addChildWindow(.above). DocHoverController's
debounce/generation/tracking untouched — only show/close swap.

Coloring: CodeAttributedBuilder (DiffRendering) = LexicalHighlightEngine tokens →
DiffPalette.color(for:), same palette instance as the hovered pane (RenderedText.palette).

Structure: HoverDocument {declaration, summary, discussion, parameters, returns, provenance,
extraCandidates, diagnostics(reserved)} + HoverMarkdownStructurer parsing sourcekit-lsp's
observed shapes (fenced decl + abstract; "## Multiple results" ---‑separated; - Parameters:/
Returns: list items) and docIndex's signature+markdown.

SDK tier (on-device Xcode docs, apple-docs declined): SDKDocumentationProvider (AtelierLSP)
drives the existing SourceKitLSPService against a scratch root with a synthetic document
mirroring the hovered file's imports (default Foundation/AppKit/SwiftUI) + a probe expression;
LIVE-VERIFIED payloads: declarations always, doc comments when .swiftdoc carries them,
overload lists; init 0.04s, first hover ~0.5s, reusable process; LRU(256) keyed
(identifier, sortedImports), nil results cached; tier order LSP → docIndex → SDK;
HoverContent.Source gains .sdk. Limits (honest): member names without receiver don't resolve;
availability + online-only long-form discussion absent; old plain-comment ObjC headers give
declaration only.

Phases: 1 presentation swap · 2 coloring · 3 structure · 4 SDK tier.
