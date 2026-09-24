# Rich hover panel design (validated 2026-09)

Verdict: replace NSPopover with an arrow-less anchored NSPanel child window (Xcode Quick Help
style). NSPopover's chrome is a hard ceiling (hasFullSizeContent only extends into the arrow
region; verified). Panel: [.borderless, .nonactivatingPanel], floating, clear/soft-shadow,
NSVisualEffectView .popover material, 8pt continuous corners, appearance matched to the pane.
Content stack (HOVER-20, Quick Help's order): the symbol's name as a title (HoverDeclarationName,
from the declaration) · the abstract · token-colored declaration chip · divider · doc body, a
flipped document view holding one view per markdown block under an "Overview" heading
(HoverMarkdownBlock reads Foundation's PresentationIntents: paragraphs and headings as selectable
NSTextViews, code blocks as chips colored like the declaration, lists, quotes, rules) · parameter
NSGridView · diagnostics slot (reserved). A declaration with nothing else shows the chip alone:
no title, no divider, no "No documentation" line.
Sizing: fixed width 440, measure via NSTextLayoutManager.usageBoundsForTextContainer, clamp
height 420 then inner-scroll body only. Anchor at HoverHit.anchorRect converted to screen,
below the identifier, flip at screen edges; addChildWindow(.above). DocHoverController's
debounce/generation/tracking untouched — only show/close swap. Staying open (HOVER-20): a
corridor (HoverCorridor) spans the identifier's middle to the panel's near edge across the
panel's width; leaving identifier, corridor and panel closes after closeGraceDelay (300 ms),
which coming back cancels; Escape, a click off the panel and the pane's window resigning key
close at once; another identifier replaces the panel when its own lookup lands.

Coloring: CodeAttributedBuilder (DiffRendering) = LexicalHighlightEngine tokens →
DiffPalette.color(for:), same palette instance as the hovered pane (RenderedText.palette).

Structure: HoverDocument {declaration, summary, discussion, parameters, returns, provenance,
extraCandidates, diagnostics(reserved)} + HoverMarkdownStructurer parsing sourcekit-lsp's
observed shapes (fenced decl + abstract; "## Multiple results" ---‑separated; - Parameters:/
Returns: list items) and docIndex's signature+markdown.

SDK tier (on-device Xcode docs, apple-docs declined): SDKDocumentationProvider (AtelierLSP)
drives one SourceKitLSPService per platform against a private scratch root with a synthetic
document mirroring the hovered file's imports (defaults Foundation/SwiftUI + AppKit or UIKit) + a
probe expression; the platform is the file's own (UIKit → iOS, AppKit → macOS), else its project's
(Package.swift platforms, .xcodeproj SDKROOT), else macOS; iOS resolves against the iPhone simulator
SDK that xcrun finds, through sourcekit-lsp's fallback build settings; LIVE-VERIFIED payloads:
declarations always, doc comments when .swiftdoc carries them, overload lists; init 0.04s, first
hover ~0.5s (UIKit from a cold module cache ~16s), reusable process; LRU(256) keyed (platform,
identifier, sortedImports), answered misses cached, unanswered probes (timeouts) not; tier order
LSP → docIndex → SDK; HoverContent.Source gains .sdk. Limits (honest): member names without
receiver don't resolve; availability + online-only long-form discussion absent; old
plain-comment ObjC headers give declaration only; a git blob's file has no project, so only its
imports choose its platform.

Phases: 1 presentation swap · 2 coloring · 3 structure · 4 SDK tier.
