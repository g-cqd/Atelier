// Re-exports the diff (aemi's AemiDiff), AtelierCore's lexing and language vocabulary to every app target that imports DiffCore. The
// swift-syntax provider is deliberately not re-exported: only the renderer links it.
@_exported public import AemiDiff
@_exported public import AtelierLexers
@_exported public import AtelierSyntaxModel
