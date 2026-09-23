public import AtelierParser

/// The external scanners ported from each bundled grammar's tree-sitter `scanner.c`, by grammar name (the `name` in
/// its `grammar.json`). A grammar with externals and no entry here parses without its external tokens.
public enum BundledScanners {
    /// Each ported scanner's type; add one line per port.
    public static let byGrammarName: [String: any GrammarExternalScanner.Type] = [:]
}
