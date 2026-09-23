public import AtelierSyntaxModel
import os

/// Composes several ``HoverProvider`` tiers into one, preferring prose: the first answer becomes the base and wins at
/// once if it has prose (``HoverContentQuality/hasProse(_:)``); otherwise the first later answer with prose wins,
/// behind the base's leading declaration fence when it has none of its own. With no prose from any tier, the base is
/// the answer. ``HoverContent/source`` names the tier that supplied the prose, or the base's tier.
///
/// A tier's `CancellationError` ends the composite; any other error from a tier is logged and counts as no answer.
public struct TieredHoverProviders: HoverProvider {
    private static let logger = Logger(subsystem: "Atelier.LSP", category: "TieredHoverProviders")

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
                let reason = String(describing: error)
                Self.logger.info("A hover tier failed; asking the next: \(reason, privacy: .public)")
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
