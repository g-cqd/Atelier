public import Foundation

/// A grammar corpus: a directory holding `languages.json` and, for each language, the directory its entry's `path`
/// names, with the language's `grammar.json` and `highlights.scm`.
public struct GrammarCorpus: Sendable, Equatable {
    /// The resource bundle SwiftPM builds for this target. An app that links the target copies it into its
    /// `Contents/Resources`.
    public static let bundleName = "AtelierCore_AtelierGrammarCorpus.bundle"

    /// The directory holding `languages.json` and the language directories.
    public let grammarsDirectory: URL

    public init(grammarsDirectory: URL) {
        self.grammarsDirectory = grammarsDirectory
    }

    /// The corpus this target bundles, from the first of `directories` that holds its resource bundle with a
    /// `Grammars/languages.json` inside.
    ///
    /// SwiftPM's generated `Bundle.module` traps when the bundle is missing, and it looks only beside the main bundle,
    /// not in an app's `Contents/Resources`; this lookup throws instead.
    /// - Throws: `GrammarCorpusError.bundleNotFound` with the directories searched.
    public static func bundled(
        searching directories: [URL] = defaultSearchDirectories
    ) throws(GrammarCorpusError) -> GrammarCorpus {
        for directory in directories {
            let bundleURL = directory.appending(path: bundleName, directoryHint: .isDirectory)
            // A macOS bundle keeps its resources in `Contents/Resources`; a flat one, at its root.
            for resources in [bundleURL.appending(path: "Contents/Resources", directoryHint: .isDirectory), bundleURL] {
                let corpus = GrammarCorpus(
                    grammarsDirectory: resources.appending(path: "Grammars", directoryHint: .isDirectory))
                if FileManager.default.fileExists(atPath: corpus.manifestURL.path) {
                    return corpus
                }
            }
        }
        throw .bundleNotFound(searched: directories.map(\.path))
    }

    /// Where the bundle is looked for, in order: the main bundle's resources, an app's `Contents/Resources`; the
    /// main bundle's own directory, beside a command-line executable; and the build products directory, beside the
    /// bundle this code is linked into, a test bundle for instance.
    public static var defaultSearchDirectories: [URL] {
        let linkedInto = Bundle(for: BundleToken.self)
        let candidates = [
            Bundle.main.resourceURL, Bundle.main.bundleURL, linkedInto.resourceURL,
            linkedInto.bundleURL.deletingLastPathComponent()
        ]
        var seen = Set<String>()
        return candidates.compactMap { $0?.standardizedFileURL }.filter { seen.insert($0.path).inserted }
    }

    /// The corpus's `languages.json`.
    public var manifestURL: URL {
        grammarsDirectory.appending(path: "languages.json")
    }

    /// The directory of `entry`'s grammar and highlight query.
    public func directory(for entry: GrammarRegistry.LanguageEntry) -> URL {
        grammarsDirectory.appending(path: entry.path, directoryHint: .isDirectory)
    }

    /// The `grammar.json` of `entry`, which may not exist.
    public func grammarURL(for entry: GrammarRegistry.LanguageEntry) -> URL {
        directory(for: entry).appending(path: "grammar.json")
    }

    /// The `highlights.scm` of `entry`, which may not exist.
    public func highlightsURL(for entry: GrammarRegistry.LanguageEntry) -> URL {
        directory(for: entry).appending(path: "highlights.scm")
    }

    /// The corpus's manifest.
    /// - Throws: `GrammarManifestError` when `languages.json` can't be read or is not a manifest.
    public func manifest() throws(GrammarManifestError) -> GrammarManifest {
        try GrammarManifest.load(from: manifestURL)
    }
}

/// Why the bundled grammar corpus is unavailable.
public enum GrammarCorpusError: Error, Sendable, Equatable {
    /// No searched directory holds the corpus's resource bundle with its manifest.
    case bundleNotFound(searched: [String])
}

/// A class of this module, so `Bundle(for:)` finds the bundle its code is linked into.
private final class BundleToken {}
