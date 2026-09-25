package import AtelierLSP
package import AtelierSyntaxModel
package import DiffGit
package import Foundation

/// Which Swift sides take sourcekit-lsp's semantic colour (PERF-11 step 8, D35): a side whose text is a file on disk
/// in the side shown on the right, a working tree, while the setting is on and the user trusts the repository, which
/// the registry's admission checks. A side read from git history, and a commit's own change under the grouping by
/// commit, never ask.
///
/// The refinement job runs ``tier(store:)`` beside swift-syntax's tier on every displayed Swift side; the tier asks
/// here for the side's document, and asks the server nothing when there is none.
@MainActor
package final class SemanticColorSource {
    /// The language servers of trusted roots; nil until hover documentation attaches them, and then no side asks.
    package var registry: LanguageServerRegistry?
    /// Whether the setting is on.
    package var isEnabled = true
    /// The side shown on the right, a commit's own when the selection shows one, and the right side's files.
    private var shownRight: () -> (source: ComparisonSource?, entries: [SourceEntry]) = { (nil, []) }

    package init() {}

    /// Reads the right side through `shownRight` from now on.
    package func readShownRight(_ shownRight: @escaping () -> (source: ComparisonSource?, entries: [SourceEntry])) {
        self.shownRight = shownRight
    }

    /// The semantic tier, which keeps each side's symbol kinds in `store` for hover.
    package nonisolated func tier(store: SyntaxFactsStore) -> SemanticTokenTier {
        SemanticTokenTier(store: store) { [weak self] revision in await self?.document(for: revision) }
    }

    /// The on-disk document and sourcekit-lsp session of the side `revision` names; nil while the setting is off, when
    /// no registry is attached, when the side is not on disk, or when the registry admits no session there.
    package func document(for revision: SourceRevision) async -> SemanticTokenTier.Document? {
        guard isEnabled, let registry else { return nil }
        let shown = shownRight()
        guard let location = Self.onDiskLocation(of: revision, shownRight: shown.source, entries: shown.entries),
            let session = await registry.session(
                forDocumentAt: location.document, within: location.root, server: .sourceKitLSP)
        else { return nil }
        return SemanticTokenTier.Document(
            session: session, uri: location.document.absoluteString, languageID: Language.swift.lspLanguageID)
    }

    /// Where the Swift side `revision` names lies on disk: the file of `entries`, the files of `shownRight`, whose blob
    /// is the side's content key, the one at the revision's own path first, under `shownRight`'s canonical root. Nil
    /// when `shownRight` is not a directory, the revision has no blob, or no file of the right side holds it, as a side
    /// from history does.
    package nonisolated static func onDiskLocation(
        of revision: SourceRevision, shownRight: ComparisonSource?, entries: [SourceEntry]
    ) -> (root: URL, document: URL)? {
        guard revision.language == .swift, case .content(let blob) = revision.key,
            case .directory(let directory)? = shownRight,
            let root = LanguageServerRegistry.canonicalRoot(directory),
            let entry = entries.first(where: { $0.blobID == blob && $0.relativePath == revision.documentID })
                ?? entries.first(where: { $0.blobID == blob })
        else { return nil }
        return (root, root.appending(path: entry.relativePath))
    }
}

extension DiffViewerModel {
    /// Follows the semantic colour setting: turning it on or off refines the displayed Swift sides afresh, through the
    /// Swift colour refinement's own reset, so every side's colour matches the setting.
    func followSemanticColorSetting() {
        guard settings.semanticColor != semanticColor.isEnabled else { return }
        semanticColor.isEnabled = settings.semanticColor
        // The caller sets the refinement back from the setting right after, which refines what shows again.
        if pipeline.refinesSwiftColor { pipeline.refinesSwiftColor = false }
    }

    /// Refines the displayed Swift sides afresh once the user trusts `root`, a canonical repository root, when the
    /// right side shown is a folder in it, or holds it: a side refined while the repository was untrusted got no
    /// semantic colour, and its content, refined already, would not ask again until it changed. The refinement's own
    /// reset runs it, as the setting does; nothing happens while semantic colour or the refinement is off.
    func retrySemanticColor(afterTrusting root: URL) {
        guard semanticColor.isEnabled, settings.refinesSwiftColor, pipeline.refinesSwiftColor,
            case .directory(let directory)? = commitScope?.right ?? right.source,
            let shown = LanguageServerRegistry.canonicalRoot(directory),
            Self.nests(shown, root)
        else { return }
        pipeline.refinesSwiftColor = false
        pipeline.refinesSwiftColor = true
    }

    /// Whether one of two canonical directories is the other or lies inside it.
    private static func nests(_ first: URL, _ second: URL) -> Bool {
        let paths = [first, second]
            .map { url in
                let path = url.path(percentEncoded: false)
                return path.hasSuffix("/") ? path : path + "/"
            }
        return paths[0].hasPrefix(paths[1]) || paths[1].hasPrefix(paths[0])
    }
}
