// Re-exports AtelierCore's diff, lexing and language vocabulary to every app target that imports DiffCore. The
// swift-syntax provider is deliberately not re-exported: only the renderer links it.
@_exported public import AtelierDiff
@_exported public import AtelierLexers
@_exported public import AtelierSyntaxModel
