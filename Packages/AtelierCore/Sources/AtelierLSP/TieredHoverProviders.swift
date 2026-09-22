public import AtelierSyntaxModel

/// Composes several ``HoverProvider`` tiers into one, quality-aware: a tier that answers with only a bare
/// declaration and no prose (``HoverContentQuality/hasProse(_:)``) does not win outright -- later tiers still get
/// a chance to supply the prose a build-context-only language server has no way to know (a project's own `///`
/// comments, or Apple's own SDK documentation).
///
/// The first tier to answer at all becomes the base: its answer is what is shown if nothing better turns up.
/// If the base already has prose, it wins immediately -- first tier with prose, whole answer, no merge. Otherwise
/// later tiers are tried in order; the first later answer that has prose wins, merged with the base's own leading
/// fenced declaration when that later answer has no declaration fence of its own (a doc-comment index entry keeps
/// its own declaration; a hand-written prose-only fallback would not). If no later tier ever supplies prose, the
/// declaration-only base is still returned -- some answer beats none.
///
/// Provenance (``HoverContent/source``) reports whichever tier actually contributed the prose, or the base's own
/// tier when nothing ever did.
///
/// A tier that throws ``CancellationError`` aborts the whole composite immediately (the caller itself was
/// cancelled, so no later tier should run either); any other error from a tier is treated the same as a `nil`
/// result -- move on to the next tier -- since a ``HoverProvider`` is documented to prefer `nil` over throwing
/// when it simply has nothing to show, and a misbehaving tier shouldn't take the whole composite down.
public struct TieredHoverProviders: HoverProvider {
    private let providers: [any HoverProvider]

    public init(_ providers: [any HoverProvider]) {
        self.providers = providers
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        var base: HoverContent?
        for provider in providers {
            try Task.checkCancellation()
            let content: HoverContent?
            do {
                content = try await provider.hover(query)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            guard let content else { continue }

            guard let existingBase = base else {
                base = content
                if HoverContentQuality.hasProse(content.markdown) { return content }
                continue
            }

            guard HoverContentQuality.hasProse(content.markdown) else { continue }
            if HoverContentQuality.leadingFencedBlock(content.markdown) != nil {
                return content
            }
            guard let baseDeclaration = HoverContentQuality.leadingFencedBlock(existingBase.markdown) else {
                return content
            }
            return HoverContent(markdown: baseDeclaration + "\n\n" + content.markdown, source: content.source)
        }
        return base
    }
}
